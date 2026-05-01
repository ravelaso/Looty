-- Looty Parser
-- Parses CHAT_MSG_LOOT and CHAT_MSG_SYSTEM messages.
-- Delegates results to GroupLoot (group roll choices/winners)
-- and MasterLoot (master loot /roll values).
-- No state of its own.

local addon = Looty
local L     = Looty_L

local Parser = {}
LootyParser  = Parser

-- Normalized roll type strings
local ROLL_TYPE_MAP = {
    ["Need"]       = "need",
    ["Greed"]      = "greed",
    ["Disenchant"] = "disenchant",
    ["Pass"]       = "pass",
}

-- Extract item name from a link or plain string.
local function ExtractItemName(text)
    local name = string.match(text, "%[([^%]]+)%]")
    return name or text
end

-- Find a Group Loot roll (active or completed) by item name.
local function FindRollByItem(itemName)
    local target = ExtractItemName(itemName)
    if not target or target == "" then return nil end

    for _, roll in ipairs(LootyGroupLoot:GetAllActiveRolls()) do
        local n = ExtractItemName(roll.link or "") 
        if n == "" then n = roll.name end
        if n == target then return roll.rollID end
    end

    for _, roll in ipairs(LootyGroupLoot:GetCompletedRolls()) do
        local n = ExtractItemName(roll.link or "")
        if n == "" then n = roll.name end
        if n == target then return roll.rollID end
    end

    return nil
end

-- ============================================================
-- ---- Roll result parsing ----
-- ============================================================

function Parser:ParseRollResult(message)
    for _, pattern in ipairs(L.ROLL_RESULT_PATTERNS) do
        local rollTypeRaw, valueStr, itemName, playerName =
            string.match(message, pattern)
        if rollTypeRaw and valueStr then
            local rollType = ROLL_TYPE_MAP[rollTypeRaw]
            if rollType then
                if not playerName then playerName = UnitName("player") end
                return rollType, tonumber(valueStr), itemName, playerName
            end
        end
    end
    return nil, nil, nil, nil
end

function Parser:ParseMessageType(message)
    for _, pattern in ipairs(L.ROLL_PATTERNS_SELF) do
        local rollTypeRaw, itemName = string.match(message, pattern)
        if rollTypeRaw and itemName then
            local mapped = ROLL_TYPE_MAP[rollTypeRaw]
            if mapped then return nil, itemName, mapped end
        end
    end

    for pattern, rollType in pairs(L.ROLL_PATTERNS_OTHER) do
        if rollType == "other_selection" then
            local playerName, rollTypeRaw, itemName = string.match(message, pattern)
            if playerName and rollTypeRaw and itemName then
                local mapped = ROLL_TYPE_MAP[rollTypeRaw]
                if mapped then return playerName, itemName, mapped end
            end
        elseif rollType == "other_selection_de" then
            local playerName, _, itemName = string.match(message, pattern)
            if playerName and itemName then
                return playerName, itemName, "disenchant"
            end
        else
            local playerName, itemName = string.match(message, pattern)
            if playerName and itemName then
                return playerName, itemName, rollType
            end
        end
    end

    return nil, nil, nil
end

-- ============================================================
-- ---- CHAT_MSG_LOOT processing (Group Loot) ----
-- ============================================================

function Parser:ProcessMessage(message)
    if not message then return end

    if addon.db and addon.db.debug then
        addon:Print("[PARSE] " .. message)
    end

    -- 1. Roll result (type + value + item + player)
    local rollType, value, itemName, playerName = self:ParseRollResult(message)
    if rollType and value and playerName then
        local rollID = FindRollByItem(itemName)
        if addon.db and addon.db.debug then
            addon:Print(string.format("[PARSE] RESULT type=%s val=%d item=%s player=%s rollID=%s",
                rollType, value, tostring(itemName), playerName, tostring(rollID)))
        end
        if rollID then
            LootyGroupLoot:RecordChoice(rollID, playerName, rollType, value)
        end
        return
    end

    -- 2. Roll type selection (no value yet)
    local rawName, iName, rType = self:ParseMessageType(message)
    if iName and rType then
        if addon.db and addon.db.debug then
            addon:Print(string.format("[PARSE] TYPE type=%s item=%s name=%s",
                rType, tostring(iName), tostring(rawName)))
        end
        local rollID = FindRollByItem(iName)
        if rollID then
            local who = rawName or UnitName("player")
            LootyGroupLoot:RecordChoice(rollID, who, rType, nil)
        end
        return
    end

    -- 3. "You won: [Item]"
    local wonItem = string.match(message, "^You won:%s*(.+)$")
    if wonItem then
        if addon.db and addon.db.debug then
            addon:Print("[PARSE] WON (self): " .. wonItem)
        end
        local rollID = FindRollByItem(wonItem)
        if rollID then
            local roll = LootyGroupLoot:GetRoll(rollID)
            if roll then
                roll.wonByMe = true
                LootyGroupLoot:FinalizeRoll(rollID)
            end
        end
        return
    end

    -- 4. "X won: [Item]"
    local winner, wonItem2 = string.match(message, "^(.-) won:%s*(.+)$")
    if winner and wonItem2 then
        if addon.db and addon.db.debug then
            addon:Print("[PARSE] WON (other): " .. winner .. " → " .. wonItem2)
        end
        local rollID = FindRollByItem(wonItem2)
        if rollID then
            local roll = LootyGroupLoot:GetRoll(rollID)
            if roll then
                roll.winner = winner
                LootyGroupLoot:FinalizeRoll(rollID)
            end
        end
        return
    end

    -- 5. "Nobody won: [Item]"
    local nobodyItem = string.match(message, "^Nobody won:%s*(.+)$")
    if nobodyItem then
        if addon.db and addon.db.debug then
            addon:Print("[PARSE] WON (nobody): " .. nobodyItem)
        end
        local rollID = FindRollByItem(nobodyItem)
        if rollID then LootyGroupLoot:FinalizeRoll(rollID) end
        return
    end

    if addon.db and addon.db.debug then
        addon:Print("[PARSE] no match")
    end
end

-- ============================================================
-- ---- CHAT_MSG_SYSTEM processing (Master Loot /roll) ----
-- ============================================================

function Parser:ProcessSystemMessage(message)
    if not message then return end

    if addon.db and addon.db.debug then
        addon:Print("[SYS] " .. message)
    end

    for _, pattern in ipairs(L.MASTER_ROLL_PATTERNS) do
        local nameOrValue, valueStr, rangeMin, rangeMax =
            string.match(message, pattern)

        if nameOrValue and rangeMin then
            local value = tonumber(valueStr)
            local rMin  = tonumber(rangeMin)
            local rMax  = tonumber(rangeMax)

            if value and rMin == 1 and rMax == 100 and value >= 1 and value <= 100 then
                local playerName
                if nameOrValue:find("^Your roll") then
                    playerName = UnitName("player")
                else
                    playerName = nameOrValue
                end
                if addon.db and addon.db.debug then
                    addon:Print(string.format("[SYS] /roll match: %s = %d", playerName, value))
                end
                LootyMasterLoot:RecordRoll(playerName, value)
                return
            end
        end
    end

    -- "X won" in system chat (some private servers route this here)
    local winner, wonItem = string.match(message, "^(.-) won:%s*(.+)$")
    if winner and wonItem then
        if addon.db and addon.db.debug then
            addon:Print("[SYS] WON (system): " .. winner .. " → " .. wonItem)
        end
        local rollID = self:FindRollByItem(wonItem)
        if rollID then
            local roll = LootyGroupLoot:GetRoll(rollID)
            if roll then
                roll.winner = winner
                LootyGroupLoot:FinalizeRoll(rollID)
            end
        end
        return
    end

    if addon.db and addon.db.debug then
        addon:Print("[SYS] no match")
    end
end

-- External access
function Parser:FindRollByItem(itemName)
    return FindRollByItem(itemName)
end
