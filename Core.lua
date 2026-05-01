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

    -- Master Loot events
    self:RegisterEvent("PARTY_LOOT_METHOD_CHANGED")
    self:RegisterEvent("LOOT_OPENED")
    self:RegisterEvent("LOOT_CLOSED")
    self:RegisterEvent("CHAT_MSG_SYSTEM")

    -- Addon message event (for Master Loot sync).
    -- NOTE: RegisterAddonMessagePrefix does NOT exist in WoW 3.3.5 — it was
    -- added in patch 4.1.0. In 3.3.5, CHAT_MSG_ADDON fires unconditionally
    -- for all addon messages with no prefix registration needed.
    self:RegisterEvent("CHAT_MSG_ADDON")

    -- Class cache: refresh when raid/party composition changes

    -- Class cache: refresh when raid/party composition changes
    self:RegisterEvent("GROUP_ROSTER_UPDATE")

    -- Create the UI window
    LootyUI:Create()

    -- Pre-populate class cache from current roster
    if LootyUI.RefreshClassCache then
        LootyUI:RefreshClassCache()
    end

    -- Initialize Master Loot state (detect if already in ML mode at login)
    if LootyMasterLoot then
        LootyMasterLoot:Initialize()
    end

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

    -- Auto-switch to GroupLoot tab so user sees new rolls
    if LootyUI.SwitchTab then
        LootyUI:SwitchTab("grouplot")
    end

    -- Auto-show window if hidden
    if LootyFrame and not LootyFrame:IsShown() then
        LootyFrame:Show()
    end
end

function addon:CANCEL_LOOT_ROLL(event, rollID)
    if self.activeRolls[rollID] then
        -- Mark as completed but KEEP in activeRolls until we parse the
        -- "X won: [Item]" message. This keeps the roll visible in the
        -- Active tab so users can see results immediately after voting.
        self.activeRolls[rollID].completed = true
        LootyUI:Refresh()
    end
end

-- Move a roll from activeRolls to completedRolls (called after "won" is parsed)
function addon:FinalizeRoll(rollID)
    local roll = self.activeRolls[rollID]
    if not roll then return end

    -- Clean up accordion state for this roll
    if LootyUI and LootyUI.ClearExpandedState then
        LootyUI:ClearExpandedState(rollID)
    end

    table.insert(self.completedRolls, 1, roll)
    self.activeRolls[rollID] = nil
    LootyUI:Refresh()
    LootyUI:UpdateTabCounts()
end

function addon:CHAT_MSG_LOOT(event, message)
    -- Delegate to Parser module
    LootyParser:ProcessMessage(message)
end

-- ---- Master Loot Events ----

function addon:PARTY_LOOT_METHOD_CHANGED(event)
    if LootyMasterLoot then
        LootyMasterLoot:OnLootMethodChanged()
    end
end

function addon:LOOT_OPENED(event)
    if LootyMasterLoot then
        LootyMasterLoot:OnLootOpened()
    end
end

function addon:LOOT_CLOSED(event)
    if LootyMasterLoot then
        LootyMasterLoot:OnLootClosed()
    end
end

function addon:CHAT_MSG_SYSTEM(event, message)
    -- Delegate to Parser for /roll message detection
    LootyParser:ProcessSystemMessage(message)
end

function addon:CHAT_MSG_ADDON(event, prefix, message, distribution, sender)
    -- Debug: log ALL addon messages so we can confirm the event fires at all
    if self.db and self.db.debug then
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cff00ff00[LOOTY ADDON]|r prefix=%s dist=%s sender=%s msg=%.40s",
            tostring(prefix), tostring(distribution),
            tostring(sender), tostring(message)))
    end

    if prefix ~= "LOOTY" then return end
    if LootyMasterLoot then
        LootyMasterLoot:OnAddonMessage(prefix, message, distribution, sender)
    end
end

function addon:GROUP_ROSTER_UPDATE(event)
    -- Refresh class cache when raid/party composition changes
    if LootyUI.RefreshClassCache then
        LootyUI:RefreshClassCache()
    end
    -- Re-resolve ML role: roster may not be populated during PLAYER_LOGIN,
    -- so a player logging in while already in a ML group will get the correct
    -- role here once the roster is ready.
    if LootyMasterLoot then
        LootyMasterLoot:ResolveRole()
        if LootyUI and LootyUI.Refresh then
            LootyUI:Refresh()
        end
    end
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
    elseif msg == "mtest" then
        if LootyMasterLoot then
            LootyMasterLoot:InjectTestRolls()
        else
            addon:Print("Master Loot module not loaded.")
        end
    elseif msg == "mtestremote" then
        -- Inject remote test data (simulate receiving items from ML)
        if LootyMasterLoot then
            LootyMasterLoot:InjectRemoteTest()
        else
            addon:Print("Master Loot module not loaded.")
        end
    elseif msg == "debug" then
        addon.db.debug = not addon.db.debug
        addon:Print("Debug " .. (addon.db.debug and "ON" or "OFF"))
    else
        addon:Print("Commands:")
        addon:Print("  /looty        - Toggle window")
        addon:Print("  /looty lock   - Toggle window lock (dragging)")
        addon:Print("  /looty clear  - Clear completed roll history")
        addon:Print("  /looty test   - Inject mock Group Loot rolls")
        addon:Print("  /looty mtest  - Inject mock Master Loot data")
        addon:Print("  /looty mtestremote - Inject mock remote ML data")
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
    -- 25-player raid roster (WOTLK 3.3.5 composition):
    --   Tanks (2): IronWall, ShieldBrk
    --   Healers (6): HolyMend, ChainHeal, CircleHeal, Moonwell,
    --                 LightWave, PrayHeal
    --   Melee DPS (7): BloodStrike, ShadowDance, WindFury,
    --                    Retrib, Eviscerate, MangleCat, FistOfRage
    --   Ranged DPS (10): FrostBolt, StarFire, AimedShot, ShadowBolt,
    --                     ArcaneX, MindFlay, MultiShot, CurseDot,
    --                     PyroBlast, Boomkin
    -- ============================================================

    -- ---- ACTIVE ROLL ----
    -- Epic cloth chest (Vestments of Redemption T3)
    -- Eligible for NEED: Priests, Warlocks, Mages (cloth wearers)
    -- Greed: Anyone who can equip cloth (healers, casters, some hybrids)
    -- Pass: Tanks, physical DPS who cannot/won't use cloth
    --
    -- Expected winner: MindFlay (Shadow Priest, need 96)
    self.activeRolls[9001] = {
        rollID = 9001,
        name = "Vestments of Redemption",
        link = "|cffa335ee|Hitem:23063:0:0:0:0:0:0:0:0|h[Vestments of Redemption]|h|r",
        texture = "Interface\\Icons\\INV_Chest_Cloth_75",
        count = 1,
        quality = 4, -- Epic (T3)
        startTime = now,
        duration = 90,
        rolls = {
            -- ---- TANKS (2) — cannot equip cloth, pass ----
            IronWall  = { type = "pass" },
            ShieldBrk = { type = "pass" },

            -- ---- HEALERS (6) — can equip cloth, mostly greed ----
            HolyMend   = { type = "greed", value = 12 },  -- Holy Paladin
            ChainHeal  = { type = "greed", value = 38 },  -- Resto Shaman
            CircleHeal = { type = "need",  value = 45 },  -- Disc Priest
            Moonwell   = { type = "greed", value = 27 },  -- Resto Druid
            LightWave  = { type = "greed", value = 61 },  -- Holy Paladin
            PrayHeal   = { type = "need",  value = 73 },  -- Holy Priest

            -- ---- MELEE DPS (7) — mostly pass, some greed ----
            BloodStrike  = { type = "pass" },            -- DK (plate)
            ShadowDance  = { type = "pass" },            -- Rogue (leather)
            WindFury     = { type = "greed", value = 5 }, -- Shaman (mail)
            Retrib       = { type = "pass" },            -- Paladin (plate)
            Eviscerate   = { type = "pass" },            -- Rogue (leather)
            MangleCat    = { type = "greed", value = 8 }, -- Druid (leather)
            FistOfRage   = { type = "pass" },            -- Warrior (plate)

            -- ---- RANGED DPS (10) — casters need, others pass/greed ----
            FrostBolt  = { type = "need", value = 55 },  -- Mage
            StarFire   = { type = "greed", value = 42 }, -- Balance Druid
            AimedShot  = { type = "pass" },              -- Hunter (mail)
            ShadowBolt = { type = "need", value = 88 },  -- Warlock
            ArcaneX    = { type = "need", value = 67 },  -- Mage
            MindFlay   = { type = "need", value = 96 },  -- Shadow Priest → WINNER
            MultiShot  = { type = "pass" },              -- Hunter (mail)
            CurseDot   = { type = "greed", value = 19 }, -- Warlock
            PyroBlast  = { type = "need", value = 81 },  -- Mage
            Boomkin    = { type = "greed", value = 34 }, -- Balance Druid
        },
    }

    -- ---- COMPLETED ROLL (History) ----
    -- Epic caster staff (Staff of Disruption)
    -- Eligible for NEED: All casters and healers (INT/stamina caster weapon)
    -- Greed: Hybrids who can use staves
    -- Disenchant: Enchanters wanting shards
    -- Pass: Physical DPS, tanks
    --
    -- Expected winner: ShadowBolt (need 86, highest need)
    self.completedRolls = {
        {
            rollID = 8001,
            name = "Staff of Disruption",
            link = "|cffa335ee|Hitem:23243:0:0:0:0:0:0:0:0|h[Staff of Disruption]|h|r",
            texture = "Interface\\Icons\\INV_Staff_13",
            count = 1,
            quality = 4, -- Epic
            startTime = now - 180,
            duration = 90,
            rolls = {
                -- ---- TANKS (2) — pass ----
                IronWall  = { type = "pass" },
                ShieldBrk = { type = "pass" },

                -- ---- HEALERS (6) — all need caster weapons ----
                HolyMend   = { type = "need", value = 33 },  -- Holy Paladin
                ChainHeal  = { type = "greed", value = 91 }, -- Resto Shaman → WINNER (greed, no higher need)
                CircleHeal = { type = "need", value = 57 },  -- Disc Priest
                Moonwell   = { type = "need", value = 44 },  -- Resto Druid
                LightWave  = { type = "need", value = 28 },  -- Holy Paladin
                PrayHeal   = { type = "need", value = 62 },  -- Holy Priest

                -- ---- MELEE DPS (7) — mostly pass, some disenchant ----
                BloodStrike  = { type = "pass" },               -- DK
                ShadowDance  = { type = "pass" },               -- Rogue
                WindFury     = { type = "disenchant", value = 47 }, -- Shaman (enchanter)
                Retrib       = { type = "pass" },               -- Paladin
                Eviscerate   = { type = "pass" },               -- Rogue
                MangleCat    = { type = "pass" },               -- Druid
                FistOfRage   = { type = "disenchant", value = 55 }, -- Warrior (enchanter)

                -- ---- RANGED DPS (10) — casters need, others mixed ----
                FrostBolt  = { type = "need", value = 79 },    -- Mage
                StarFire   = { type = "need", value = 41 },    -- Balance Druid
                AimedShot  = { type = "pass" },                -- Hunter
                ShadowBolt = { type = "need", value = 86 },    -- Warlock
                ArcaneX    = { type = "need", value = 64 },    -- Mage
                MindFlay   = { type = "need", value = 53 },    -- Shadow Priest
                MultiShot  = { type = "pass" },                -- Hunter
                CurseDot   = { type = "need", value = 38 },    -- Warlock
                PyroBlast  = { type = "disenchant", value = 72 }, -- Mage (enchanter)
                Boomkin    = { type = "greed", value = 15 },   -- Balance Druid
            },
        },
    }

    self:Print("Test data injected — 1 active roll + 1 history (25-player raid, all voted).")

    -- Auto-show window
    if LootyFrame and not LootyFrame:IsShown() then
        LootyFrame:Show()
    end

    LootyUI:Refresh()
end

addon:RegisterEvent("PLAYER_LOGIN")
