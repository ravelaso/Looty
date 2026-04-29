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

-- Compiled regex cache
local compiledPatterns = {}

for pattern, rollType in pairs(L.ROLL_PATTERNS) do
    table.insert(compiledPatterns, { pattern = pattern, rollType = rollType })
end

-- Extract the raw item name from an item link for matching.
-- Item link format: |cffXXXXXX|Hitem:ITEMID:...|h[ItemName]|h|r
-- We extract the display name between the ] brackets.
local function ExtractItemName(text)
    -- Check if text is an item link
    local _, _, itemName = string.find(text, "%[(.+)%]")
    if itemName then
        return itemName
    end
    -- Not a link, return as-is
    return text
end

-- Match a roll message against known patterns.
-- Returns: playerName, itemName (raw), rollType or nil
function Parser:ParseMessage(message)
    for _, entry in ipairs(compiledPatterns) do
        local _, _, playerName, itemName = string.find(message, entry.pattern)
        if playerName and itemName then
            -- Ignore the system message where "Everyone" is the roller
            if playerName == "Everyone" then
                return nil, nil, nil
            end
            return playerName, itemName, entry.rollType
        end
    end
    return nil, nil, nil
end

-- Process a CHAT_MSG_LOOT message.
-- This is called from Core.lua on every CHAT_MSG_LOOT event.
function Parser:ProcessMessage(message)
    if not message then
        return
    end

    local playerName, itemName, rollType = self:ParseMessage(message)
    if not playerName then
        return
    end

    -- itemName here may or may not be a full link.
    -- We need to find which active roll this message
    -- belongs to by matching item names.
    local targetRollID = nil

    for _, rollData in ipairs(addon:GetAllActiveRolls()) do
        local linkName = ExtractItemName(rollData.link or "")
        local msgName = ExtractItemName(itemName)

        -- Fallback: compare raw names if link extraction fails
        if not linkName or linkName == "" then
            linkName = rollData.name
        end
        if not msgName or msgName == "" then
            msgName = itemName
        end

        if linkName == msgName then
            targetRollID = rollData.rollID
            break
        end
    end

    if targetRollID then
        if addon:RecordRoll(targetRollID, playerName, rollType) then
            -- Optional: debug print
            -- addon:Print(playerName .. " -> " .. (L.ROLL_LABELS[rollType] or rollType) .. " on " .. targetRollID)
        end
    end
end
