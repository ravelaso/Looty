-- Looty Core
-- Event registration, state management, and addon lifecycle.

local addon = CreateFrame("Frame", "LootyCore", UIParent)
Looty = addon

-- Default saved variables structure
local DEFAULT_SAVED = {
    windowPos = { x = nil, y = nil },
    windowSize = { w = nil, h = nil },
    locked = false,
}

-- Active rolls keyed by rollID
-- Each entry: {
--   rollID, name, link, texture, count, quality,
--   bindOnPickUp, canNeed, canGreed, canDisenchant,
--   startTime, duration,
--   rolls = { playerName = "need"|"greed"|"disenchant"|"pass" },
-- }
addon.activeRolls = {}

-- Completed rolls (for history mode)
addon.completedRolls = {}

-- Saved variables
addon.db = {}

-- ---- Lifecycle ----

function addon:OnEvent(event, ...)
    if self[event] then
        return self[event](self, event, ...)
    end
end

addon:SetScript("OnEvent", addon.OnEvent)

function addon:PLAYER_LOGIN()
    -- Load saved vars
    self.db = Looty_SavedVars or {}
    -- Merge defaults
    for k, v in pairs(DEFAULT_SAVED) do
        if self.db[k] == nil then
            self.db[k] = v
        end
    end

    -- Register loot events
    self:RegisterEvent("START_LOOT_ROLL")
    self:RegisterEvent("CANCEL_LOOT_ROLL")
    self:RegisterEvent("CHAT_MSG_LOOT")

    -- Create the UI window
    LootyUI:Create()

    -- Restore window position and size from saved vars
    if self.db.windowPos.x and self.db.windowPos.y then
        LootyFrame:SetPoint(
            "TOPLEFT", UIParent, "TOPLEFT",
            self.db.windowPos.x, self.db.windowPos.y
        )
    end
    if self.db.windowSize.w and self.db.windowSize.h then
        LootyFrame:SetSize(self.db.windowSize.w, self.db.windowSize.h)
    end

    self:Print("Loaded. Type /looty to toggle the window.")
end

function addon:PLAYER_LOGOUT()
    -- Save window position and size
    if LootyFrame then
        local x, y = LootyFrame:GetLeft(), LootyFrame:GetTop()
        if x and y then
            self.db.windowPos.x = x
            self.db.windowPos.y = y
        end
        local w, h = LootyFrame:GetWidth(), LootyFrame:GetHeight()
        if w and h then
            self.db.windowSize.w = w
            self.db.windowSize.h = h
        end
    end
    Looty_SavedVars = self.db
end

-- ---- Event Handlers ----

function addon:START_LOOT_ROLL(event, rollID, duration)
    -- Move completed rolls to history when a new roll appears
    local toRemove = {}
    for rid, rollData in pairs(self.activeRolls) do
        if rollData.completed then
            table.insert(self.completedRolls, 1, rollData)
            table.insert(toRemove, rid)
        end
    end
    for _, rid in ipairs(toRemove) do
        self.activeRolls[rid] = nil
    end

    local texture, name, count, quality, bindOnPickUp,
          canNeed, canGreed, canDisenchant = GetLootRollItemInfo(rollID)

    if not name then
        return
    end

    local link = GetLootRollItemLink(rollID)

    self.activeRolls[rollID] = {
        rollID = rollID,
        name = name,
        link = link,
        texture = texture,
        count = count,
        quality = quality,
        bindOnPickUp = bindOnPickUp,
        canNeed = canNeed,
        canGreed = canGreed,
        canDisenchant = canDisenchant,
        startTime = GetTime(),
        duration = duration or 90,
        rolls = {},
    }

    self:Print("New roll: " .. name)
    LootyUI:Refresh()

    -- Auto-show window if hidden
    if LootyFrame and not LootyFrame:IsShown() then
        LootyFrame:Show()
    end
end

function addon:CANCEL_LOOT_ROLL(event, rollID)
    if self.activeRolls[rollID] then
        -- Mark as completed but KEEP in active tab.
        -- Will be moved to history when a new roll starts.
        self.activeRolls[rollID].completed = true
        self.activeRolls[rollID].completedAt = GetTime()
        LootyUI:Refresh()
    end
end

function addon:CHAT_MSG_LOOT(event, message)
    -- Delegate to Parser module
    LootyParser:ProcessMessage(message)
end

-- ---- Public API ----

function addon:GetRoll(rollID)
    return self.activeRolls[rollID]
end

function addon:GetAllActiveRolls()
    local rolls = {}
    for k, v in pairs(self.activeRolls) do
        table.insert(rolls, v)
    end
    -- Sort by startTime descending (newest first)
    table.sort(rolls, function(a, b)
        return a.startTime > b.startTime
    end)
    return rolls
end

function addon:GetCompletedRolls()
    return self.completedRolls
end

function addon:RecordRoll(rollID, playerName, rollType, value)
    local roll = self.activeRolls[rollID]
    if not roll then
        return false
    end

    -- Don't overwrite existing rolls
    if roll.rolls[playerName] then
        return false
    end

    roll.rolls[playerName] = { type = rollType, value = value or nil }
    LootyUI:Refresh()
    return true
end

function addon:UpdateRollValue(rollID, playerName, value)
    local roll = self.activeRolls[rollID]
    if not roll then return end
    if roll.rolls[playerName] then
        local info = roll.rolls[playerName]
        -- Handle both old string format and new table format
        if type(info) == "table" then
            info.value = value
        else
            roll.rolls[playerName] = { type = info, value = value }
        end
        LootyUI:Refresh()
    end
end

function addon:FindRollByPlayer(playerName)
    -- Find the most recent active roll where this player has
    -- a type but no value yet
    local activeRolls = self:GetAllActiveRolls()
    for _, roll in ipairs(activeRolls) do
        if roll.rolls[playerName] then
            local info = roll.rolls[playerName]
            local rollType = type(info) == "table" and info.type or info
            local rollValue = type(info) == "table" and info.value or nil
            if rollType and not rollValue then
                return roll.rollID
            end
        end
    end
    return nil
end

-- ---- Utility ----

local function printPrefix()
    return "|cff7B2D8E[Looty]|r "
end

function addon:Print(...)
    DEFAULT_CHAT_FRAME:AddMessage(printPrefix() .. strjoin(" ", ...))
end

-- ---- Slash Commands ----

SLASH_LOOTY1 = "/looty"
SLASH_LOOTY2 = "/lr"

SlashCmdList["LOOTY"] = function(msg)
    msg = msg:lower():trim()

    if msg == "" then
        -- Toggle window
        if not LootyFrame then
            addon:Print("Window not created yet — check for errors with /framestack")
            return
        end
        if LootyFrame:IsShown() then
            LootyFrame:Hide()
        else
            LootyFrame:Show()
        end
    elseif msg == "lock" then
        addon.db.locked = not addon.db.locked
        addon:Print("Window " .. (addon.db.locked and "locked" or "unlocked"))
        LootyUI:UpdateMovable()
    elseif msg == "clear" then
        addon.completedRolls = {}
        addon:Print("Roll history cleared.")
        LootyUI:Refresh()
    else
        addon:Print("Commands:")
        addon:Print("  /looty        - Toggle window")
        addon:Print("  /looty lock   - Toggle window lock (dragging)")
        addon:Print("  /looty clear  - Clear completed roll history")
    end
end

addon:RegisterEvent("PLAYER_LOGIN")
