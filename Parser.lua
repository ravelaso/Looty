-- Looty Parser
-- Parses CHAT_MSG_LOOT messages to extract roll choices.
-- The default Blizzard client prints detailed roll info
-- when "Detailed Loot Information" is enabled in Social
-- options. We parse those messages to track who rolled
-- what on each active roll.

local addon = Looty
local L = Looty_L

local Parser = {}
LootyParser = Parser

-- Normalized roll type strings to internal keys
local ROLL_TYPE_MAP = {
    ["Need"]       = "need",
    ["Greed"]      = "greed",
    ["Disenchant"] = "disenchant",
    ["Pass"]       = "pass",
}

-- Extract the raw item name from an item link for matching.
-- Item link format: |cffXXXXXX|Hitem:ITEMID:...|h[ItemName]|h|r
-- Use [^%]]+ to stop at the FIRST closing bracket.
local function ExtractItemName(text)
    local _, _, itemName = string.find(text, "%[([^%]]+)%]")
    if itemName then
        return itemName
    end
    return text
end

-- Match a roll RESULT message — the most important one.
-- Format: "Greed Roll - 24 for [Veteran Gloves] by Buenclima"
-- Returns: rollType (internal key), value, itemName, playerName
function Parser:ParseRollResult(message)
    for _, pattern in ipairs(L.ROLL_RESULT_PATTERNS) do
        local _, _, rollTypeRaw, valueStr, itemName, playerName = string.find(message, pattern)
        if rollTypeRaw and valueStr then
            local rollType = ROLL_TYPE_MAP[rollTypeRaw]
            if rollType then
                -- If no playerName captured (self-result without "by"), use unit name
                if not playerName then
                    playerName = UnitName("player")
                end
                return rollType, tonumber(valueStr), itemName, playerName
            end
        end
    end
    return nil, nil, nil, nil
end

-- Match a roll TYPE pattern (selection without value).
-- Returns: playerName (or nil for self), itemName, rollType (internal key)
function Parser:ParseMessageType(message)
    -- Self-selection MUST be checked first (most specific pattern)
    -- "You have selected Greed for: [Item]"
    for _, pattern in ipairs(L.ROLL_PATTERNS_SELF) do
        local _, _, rollTypeRaw, itemName = string.find(message, pattern)
        if rollTypeRaw and itemName then
            local mapped = ROLL_TYPE_MAP[rollTypeRaw]
            if mapped then
                return nil, itemName, mapped
            end
        end
    end

    -- Other players selection
    for pattern, rollType in pairs(L.ROLL_PATTERNS_OTHER) do
        if rollType == "other_selection" then
            local _, _, playerName, rollTypeRaw, itemName = string.find(message, pattern)
            if playerName and rollTypeRaw and itemName then
                local mapped = ROLL_TYPE_MAP[rollTypeRaw]
                if mapped then
                    return playerName, itemName, mapped
                end
            end
        elseif rollType == "other_selection_de" then
            local _, _, playerName, rollTypeRaw, itemName = string.find(message, pattern)
            if playerName and rollTypeRaw and itemName then
                return playerName, itemName, "disenchant"
            end
        else
            -- Pass patterns
            local _, _, playerName, itemName = string.find(message, pattern)
            if playerName and itemName then
                return playerName, itemName, rollType
            end
        end
    end

    return nil, nil, nil
end

-- Find active or completed roll by matching item name
local function FindRollByItem(itemName)
    local msgName = ExtractItemName(itemName)
    if not msgName or msgName == "" then return nil end

    -- Search active rolls first
    local activeRolls = addon:GetAllActiveRolls()
    for _, rollData in ipairs(activeRolls) do
        local linkName = ExtractItemName(rollData.link or "")
        if not linkName or linkName == "" then
            linkName = rollData.name
        end
        if linkName == msgName then
            return rollData.rollID
        end
    end

    -- Also search completed rolls (roll may have ended before chat messages arrived)
    local completedRolls = addon:GetCompletedRolls()
    for _, rollData in ipairs(completedRolls) do
        local linkName = ExtractItemName(rollData.link or "")
        if not linkName or linkName == "" then
            linkName = rollData.name
        end
        if linkName == msgName then
            return rollData.rollID
        end
    end

    return nil
end

-- Process a CHAT_MSG_LOOT message.
function Parser:ProcessMessage(message)
    if not message then return end

    -- Debug: show incoming message
    if addon and addon.db and addon.db.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[LOOTY PARSE]|r " .. message)
    end

    -- 1. Try roll RESULT first
    local rollType, value, itemName, playerName = self:ParseRollResult(message)
    if rollType and value and playerName then
        local targetRollID = FindRollByItem(itemName)
        if addon and addon.db and addon.db.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[LOOTY PARSE]|r RESULT match: " .. rollType .. " val=" .. value .. " item=" .. tostring(itemName) .. " player=" .. playerName .. " rollID=" .. tostring(targetRollID))
        end
        if targetRollID then
            addon:RecordRoll(targetRollID, playerName, rollType, value)
        end
        return
    end

    -- 2. Try roll TYPE patterns
    local rawName, itemName, rollType = self:ParseMessageType(message)
    if itemName and rollType then
        if addon and addon.db and addon.db.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[LOOTY PARSE]|r TYPE match: " .. rollType .. " item=" .. tostring(itemName) .. " name=" .. tostring(rawName))
        end
        if rawName == nil then
            local targetRollID = FindRollByItem(itemName)
            if targetRollID then
                local myName = UnitName("player")
                addon:RecordRoll(targetRollID, myName, rollType)
            end
        else
            local targetRollID = FindRollByItem(itemName)
            if targetRollID then
                addon:RecordRoll(targetRollID, rawName, rollType)
            end
        end
        return
    end

    -- 3. "You won: [ItemName]" — mark winner and move to history
    local _, _, itemName = string.find(message, "^You won:%s*(.+)$")
    if itemName then
        if addon and addon.db and addon.db.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[LOOTY PARSE]|r WON match (self): " .. tostring(itemName))
        end
        local targetRollID = FindRollByItem(itemName)
        if targetRollID then
            local roll = addon:GetRoll(targetRollID)
            if roll then
                roll.wonByMe = true
                addon:FinalizeRoll(targetRollID)
            end
        end
        return
    end

    -- 4. "X won: [ItemName]" — mark winner and move to history
    local _, _, winnerName, itemName = string.find(message, "^(.-) won:%s*(.+)$")
    if winnerName and itemName then
        if addon and addon.db and addon.db.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[LOOTY PARSE]|r WON match (other): " .. winnerName .. " -> " .. tostring(itemName))
        end
        local targetRollID = FindRollByItem(itemName)
        if targetRollID then
            local roll = addon:GetRoll(targetRollID)
            if roll then
                roll.winner = winnerName
                addon:FinalizeRoll(targetRollID)
            end
        end
        return
    end

    -- 5. "Nobody won: [ItemName]" — move to history (no winner)
    local _, _, itemName = string.find(message, "^Nobody won:%s*(.+)$")
    if itemName then
        if addon and addon.db and addon.db.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[LOOTY PARSE]|r WON match (nobody): " .. tostring(itemName))
        end
        local targetRollID = FindRollByItem(itemName)
        if targetRollID then
            addon:FinalizeRoll(targetRollID)
        end
        return
    end

    if addon and addon.db and addon.db.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff666666[LOOTY PARSE]|r no match")
    end
end

-- ---- Master Loot: Process CHAT_MSG_SYSTEM for /roll messages ----

function Parser:ProcessSystemMessage(message)
    if not message then return end

    -- Debug
    if addon and addon.db and addon.db.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[LOOTY SYS]|r " .. message)
    end

    -- Try Master Loot /roll patterns
    for _, pattern in ipairs(L.MASTER_ROLL_PATTERNS) do
        local _, _, nameOrValue, valueStr, rangeMin, rangeMax = string.find(message, pattern)

        -- Self-roll pattern: "Your roll for [Item] is 85 (1-100)"
        if nameOrValue and rangeMin then
            local value = tonumber(valueStr)
            local rMin = tonumber(rangeMin)
            local rMax = tonumber(rangeMax)

            -- Validate range is 1-100 (standard roll)
            if value and rMin == 1 and rMax == 100 and value >= 1 and value <= 100 then
                if nameOrValue and not nameOrValue:find("^Your roll") then
                    -- Other player: "PlayerName rolls 85 (1-100)"
                    local playerName = nameOrValue
                    if addon.db and addon.db.debug then
                        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[LOOTY SYS]|r /roll match: " .. playerName .. " = " .. value)
                    end
                    if LootyMasterLoot then
                        LootyMasterLoot:RecordRoll(playerName, value, nil)
                    end
                    return
                elseif nameOrValue:find("^Your roll") then
                    -- Self roll
                    local playerName = UnitName("player")
                    if addon.db and addon.db.debug then
                        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[LOOTY SYS]|r /roll match (self): " .. playerName .. " = " .. value)
                    end
                    if LootyMasterLoot then
                        LootyMasterLoot:RecordRoll(playerName, value, nil)
                    end
                    return
                end
            end
        end
    end

    -- Not a roll message — check for "won" patterns in system chat
    -- (some servers use CHAT_MSG_SYSTEM instead of CHAT_MSG_LOOT for winner)
    -- 1. "X won: [ItemName]"
    local _, _, winnerName, itemName = string.find(message, "^(.-) won:%s*(.+)$")
    if winnerName and itemName then
        if addon and addon.db and addon.db.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[LOOTY SYS]|r WON match (system): " .. winnerName .. " -> " .. tostring(itemName))
        end
        local targetRollID = LootyParser:FindRollByItem(itemName)
        if targetRollID then
            local roll = addon:GetRoll(targetRollID)
            if roll then
                roll.winner = winnerName
                addon:FinalizeRoll(targetRollID)
            end
        end
        return
    end

    if addon and addon.db and addon.db.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff666666[LOOTY SYS]|r no match")
    end
end

-- Expose FindRollByItem for external use
function Parser:FindRollByItem(itemName)
    return FindRollByItem(itemName)
end
