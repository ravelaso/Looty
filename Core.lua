-- Looty Core
-- Event registration, state management, and addon lifecycle.

local addon = CreateFrame("Frame", "LootyCore", UIParent)
Looty = addon

-- Default saved variables structure
local DEFAULT_SAVED = {
    windowPos = { x = nil, y = nil },
    windowSize = { w = nil, h = nil },
    locked = false,
    debug = false,
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
        -- Move directly to history (completed rolls are always shown in history tab)
        table.insert(self.completedRolls, 1, self.activeRolls[rollID])
        self.activeRolls[rollID] = nil
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
        -- Also check completed rolls (chat messages may arrive after CANCEL_LOOT_ROLL)
        for _, cr in ipairs(self.completedRolls) do
            if cr.rollID == rollID then
                roll = cr
                break
            end
        end
        if not roll then
            if self.db and self.db.debug then
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[LOOTY CORE]|r RecordRoll FAILED — no roll " .. rollID)
            end
            return false
        end
    end

    -- If player already has an entry, only overwrite if it has no value yet
    local existing = roll.rolls[playerName]
    if existing then
        local existingInfo = type(existing) == "table" and existing or { type = existing, value = nil }
        if existingInfo.value then
            if self.db and self.db.debug then
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[LOOTY CORE]|r RecordRoll SKIPPED — " .. playerName .. " already has value")
            end
            return false
        end
    end

    roll.rolls[playerName] = { type = rollType, value = value or nil }
    if self.db and self.db.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[LOOTY CORE]|r RecordRoll OK — " .. playerName .. " type=" .. rollType .. " val=" .. tostring(value) .. " on roll " .. rollID .. " (" .. roll.name .. ")")
    end
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
    elseif msg == "test" then
        addon:InjectTestRolls()
    elseif msg == "debug" then
        addon.db.debug = not addon.db.debug
        addon:Print("Debug " .. (addon.db.debug and "ON" or "OFF"))
    else
        addon:Print("Commands:")
        addon:Print("  /looty        - Toggle window")
        addon:Print("  /looty lock   - Toggle window lock (dragging)")
        addon:Print("  /looty clear  - Clear completed roll history")
        addon:Print("  /looty test   - Inject mock rolls for testing")
        addon:Print("  /looty debug  - Toggle data debug")
    end
end

-- ---- Test Data Injection (100% local, no server interaction) ----

function addon:InjectTestRolls()
    -- Clear existing state
    self.activeRolls = {}
    self.completedRolls = {}

    local now = GetTime()

    -- ============================================================
    -- Active roll: Epic chest (raid scenario, many players rolling)
    -- ============================================================
    self.activeRolls[9001] = {
        rollID = 9001,
        name = "Vestments of the Devout",
        link = "|cffa335ee|Hitem:21345:0:0:0:0:0:0:0:0|h[Vestments of the Devout]|h|r",
        texture = "Interface\\Icons\\INV_Chest_Cloth_04",
        count = 1,
        quality = 4, -- Epic
        startTime = now,
        duration = 90,
        rolls = {
            -- Need
            Buenclima  = { type = "need",  value = 87 },
            ShadowMaw  = { type = "need",  value = 42 },
            HealMePlz  = { type = "need",  value = 63 },
            -- Greed
            TankJoe    = { type = "greed", value = 91 },
            DPSKing    = { type = "greed", value = 55 },
            AltRoller  = { type = "greed", value = 33 },
            -- Pass
            WarriorK   = { type = "pass" },
            MageBob    = { type = "pass" },
            LockDash   = { type = "pass" },
            RogueX     = { type = "pass" },
            HunterAim  = { type = "pass" },
        },
    }

    -- ============================================================
    -- Active roll: Rare weapon (fewer eligible players)
    -- ============================================================
    self.activeRolls[9002] = {
        rollID = 9002,
        name = "Blessed Claymore",
        link = "|cff0070dd|Hitem:16890:0:0:0:0:0:0:0:0|h[Blessed Claymore]|h|r",
        texture = "Interface\\Icons\\INV_Sword_25",
        count = 1,
        quality = 3, -- Rare
        startTime = now + 5,
        duration = 90,
        rolls = {
            TankJoe   = { type = "need",  value = 74 },
            Buenclima = { type = "greed", value = 48 },
            DPSKing   = { type = "greed", value = 22 },
            WarriorK  = { type = "need",  value = 66 },
        },
    }

    -- ============================================================
    -- Active roll: Epic ring (high demand)
    -- ============================================================
    self.activeRolls[9003] = {
        rollID = 9003,
        name = "Band of Forced Concentration",
        link = "|cffa335ee|Hitem:22734:0:0:0:0:0:0:0:0|h[Band of Forced Concentration]|h|r",
        texture = "Interface\\Icons\\INV_Jewelry_Ring_15",
        count = 1,
        quality = 4, -- Epic
        startTime = now + 10,
        duration = 90,
        rolls = {
            -- Need (all casters/healers)
            HealMePlz   = { type = "need",  value = 95 },
            ShadowMaw   = { type = "need",  value = 34 },
            MageBob     = { type = "need",  value = 78 },
            LockDash    = { type = "need",  value = 67 },
            -- Greed (everyone else hoping)
            TankJoe     = { type = "greed", value = 82 },
            WarriorK    = { type = "greed", value = 44 },
            DPSKing     = { type = "greed", value = 19 },
            RogueX      = { type = "greed", value = 71 },
            -- Disenchant
            AltRoller   = { type = "disenchant", value = 50 },
        },
    }

    -- ============================================================
    -- Completed rolls (history)
    -- ============================================================

    -- Epic weapon
    table.insert(self.completedRolls, {
        rollID = 8001,
        name = "Spinal Crusher",
        link = "|cffa335ee|Hitem:18815:0:0:0:0:0:0:0:0|h[Spinal Crusher]|h|r",
        texture = "Interface\\Icons\\INV_Mace_36",
        count = 1,
        quality = 4, -- Epic
        startTime = now - 120,
        duration = 90,
        rolls = {
            TankJoe    = { type = "need",  value = 55 },
            WarriorK   = { type = "need",  value = 73 },
            Buenclima  = { type = "greed", value = 88 },
            DPSKing    = { type = "greed", value = 41 },
            ShadowMaw  = { type = "disenchant", value = 30 },
            AltRoller  = { type = "disenchant", value = 62 },
            RogueX     = { type = "pass" },
            MageBob    = { type = "pass" },
            LockDash   = { type = "pass" },
            HealMePlz  = { type = "pass" },
        },
    })

    -- Rare armor
    table.insert(self.completedRolls, {
        rollID = 8002,
        name = "Pioneer Trousers of the Monkey",
        link = "|cff1eff00|Hitem:22222:0:0:0:0:0:0:0:0|h[Pioneer Trousers of the Monkey]|h|r",
        texture = "Interface\\Icons\\INV_Pants_06",
        count = 1,
        quality = 2, -- Uncommon
        startTime = now - 300,
        duration = 90,
        rolls = {
            Buenclima = { type = "greed", value = 88 },
            RogueX    = { type = "greed", value = 33 },
            HunterAim = { type = "need",  value = 76 },
            TankJoe   = { type = "pass" },
        },
    })

    -- Epic trinket (won by disenchanter)
    table.insert(self.completedRolls, {
        rollID = 8003,
        name = "Mark of the Champion",
        link = "|cffa335ee|Hitem:23207:0:0:0:0:0:0:0:0|h[Mark of the Champion]|h|r",
        texture = "Interface\\Icons\\INV_Trinket_Naxxramas06",
        count = 1,
        quality = 4, -- Epic
        startTime = now - 600,
        duration = 90,
        rolls = {
            HealMePlz   = { type = "need",  value = 44 },
            ShadowMaw   = { type = "need",  value = 29 },
            AltRoller   = { type = "disenchant", value = 85 },
            LockDash    = { type = "disenchant", value = 51 },
            TankJoe     = { type = "pass" },
            WarriorK    = { type = "pass" },
            DPSKing     = { type = "pass" },
            Buenclima   = { type = "pass" },
        },
    })

    self:Print("Test data injected — 3 active rolls (25-man raid), 3 in history.")

    -- Auto-show window
    if LootyFrame and not LootyFrame:IsShown() then
        LootyFrame:Show()
    end

    LootyUI:Refresh()
end

addon:RegisterEvent("PLAYER_LOGIN")
