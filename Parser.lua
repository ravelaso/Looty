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
        if rollTypeRaw and valueStr and playerName then
            local rollType = ROLL_TYPE_MAP[rollTypeRaw]
            if rollType then
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

-- Find active roll by matching item name
local function FindRollByItem(itemName)
    local msgName = ExtractItemName(itemName)
    if not msgName or msgName == "" then return nil end

    for _, rollData in ipairs(addon:GetAllActiveRolls()) do
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

    -- 1. Try roll RESULT first (has everything: type + value + player + item)
    local rollType, value, itemName, playerName = self:ParseRollResult(message)
    if rollType and value and playerName then
        local targetRollID = FindRollByItem(itemName)
        if targetRollID then
            addon:RecordRoll(targetRollID, playerName, rollType, value)
        end
        return
    end

    -- 2. Try roll TYPE patterns (selection without value)
    local rawName, itemName, rollType = self:ParseMessageType(message)
    if itemName and rollType then
        if rawName == nil then
            -- Self-selection: "You have selected Greed for: [Item]"
            local targetRollID = FindRollByItem(itemName)
            if targetRollID then
                local myName = UnitName("player")
                addon:RecordRoll(targetRollID, myName, rollType)
            end
        else
            -- Pass messages or other selection without value
            local targetRollID = FindRollByItem(itemName)
            if targetRollID then
                addon:RecordRoll(targetRollID, rawName, rollType)
            end
        end
        return
    end
end
