-- Looty GroupLoot Module
-- Owns all Group Loot state: active rolls, completed roll history,
-- and the domain operations on them. No UI, no events — pure domain.

-- GroupLoot references the Looty global directly at call time (never at load time)

-- ============================================================
-- ---- LootRoll: a single Group Loot roll entry ----
-- ============================================================
-- Constructor for a Group Loot roll record.
-- Fields:
--   rollID        — WoW's numeric roll ID (from START_LOOT_ROLL)
--   name          — item name string
--   link          — item hyperlink
--   texture       — icon texture path
--   count         — stack size
--   quality       — item quality number (0=poor … 5=legendary)
--   bindOnPickUp  — bool
--   canNeed       — bool
--   canGreed      — bool
--   canDisenchant — bool
--   startTime     — GetTime() when roll started
--   duration      — seconds the roll is open (usually 90)
--   rolls         — { [playerName] = { type, value } }
--   completed     — true once CANCEL_LOOT_ROLL fired (awaiting "won" msg)
--   winner        — playerName string once parsed from chat

local LootRoll = {}
LootRoll.__index = LootRoll

function LootRoll.new(rollID, name, link, texture, count, quality,
                      bindOnPickUp, canNeed, canGreed, canDisenchant, duration)
    return setmetatable({
        rollID        = rollID,
        name          = name,
        link          = link,
        texture       = texture,
        count         = count,
        quality       = quality,
        bindOnPickUp  = bindOnPickUp,
        canNeed       = canNeed,
        canGreed      = canGreed,
        canDisenchant = canDisenchant,
        startTime     = GetTime(),
        duration      = duration or 90,
        rolls         = {},
        completed     = false,
        winner        = nil,
    }, LootRoll)
end

-- Record a player's roll choice.
-- Returns true if recorded, false if the player already has a confirmed value.
function LootRoll:RecordChoice(playerName, rollType, value)
    local existing = self.rolls[playerName]
    if existing and existing.value then
        return false  -- already has a value; skip
    end
    self.rolls[playerName] = { type = rollType, value = value or nil }
    return true
end

-- Update the numeric /roll value for an existing choice entry.
function LootRoll:UpdateValue(playerName, value)
    if self.rolls[playerName] then
        self.rolls[playerName].value = value
        return true
    end
    return false
end

-- Return the winning player for this roll, or nil.
-- Priority: need > greed > disenchant (by highest value within tier).
function LootRoll:DetermineWinner()
    local tiers = { "need", "greed", "disenchant" }
    for _, tier in ipairs(tiers) do
        local bestPlayer, bestValue = nil, 0
        for playerName, info in pairs(self.rolls) do
            if info.type == tier and info.value and info.value > bestValue then
                bestValue  = info.value
                bestPlayer = playerName
            end
        end
        if bestPlayer then
            return bestPlayer, bestValue, tier
        end
    end
    return nil, nil, nil
end

-- True if a player has submitted a roll type (even without a value yet).
function LootRoll:HasRolled(playerName)
    return self.rolls[playerName] ~= nil
end

-- True if this player needs a /roll value still (type set, no value yet).
function LootRoll:NeedsValue(playerName)
    local entry = self.rolls[playerName]
    return entry ~= nil and entry.value == nil
end

-- Expose as global for Parser and UI
LootyLootRoll = LootRoll

-- ============================================================
-- ---- GroupLoot module ----
-- ============================================================

local GroupLoot = {}
LootyGroupLoot = GroupLoot

-- Safety net: poll completed rolls in case chat messages are missed.
-- WoW 3.3.5 has no event for "roll timer expired" — we detect it by
-- checking if WoW no longer knows about the roll via GetLootRollItemInfo.
local safetyFrame = CreateFrame("Frame")
safetyFrame:Hide()
safetyFrame.elapsed = 0
safetyFrame:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < 3 then return end  -- poll every 3 seconds
    self.elapsed = 0

    for rollID, roll in pairs(GroupLoot.activeRolls) do
        if roll.completed and not roll._safetyChecked then
            -- If WoW no longer knows about this roll, the timer expired
            -- and the chat message was likely missed.
            local texture = GetLootRollItemInfo(rollID)
            if not texture then
                roll._safetyChecked = true
                if Looty.db and Looty.db.debug then
                    Looty:Print("[GroupLoot] Safety net: finalizing roll " .. rollID .. " (" .. roll.name .. ")")
                end
                local winner = roll:DetermineWinner()
                roll.winner = winner
                GroupLoot:FinalizeRoll(rollID)
            end
        end
    end

    -- Stop polling if no active rolls remain
    if not next(GroupLoot.activeRolls) then self:Hide() end
end)

-- Active rolls keyed by rollID (numeric, from WoW API)
GroupLoot.activeRolls = {}

-- Completed roll history (array, newest first)
GroupLoot.completedRolls = {}

-- ---- Public accessors ----

function GroupLoot:GetRoll(rollID)
    return self.activeRolls[rollID]
end

function GroupLoot:GetAllActiveRolls()
    local rolls = {}
    for _, v in pairs(self.activeRolls) do
        table.insert(rolls, v)
    end
    table.sort(rolls, function(a, b) return a.startTime > b.startTime end)
    return rolls
end

function GroupLoot:GetCompletedRolls()
    return self.completedRolls
end

-- ---- Domain operations ----

function GroupLoot:StartRoll(rollID, duration)
    local texture, name, count, quality, bindOnPickUp,
          canNeed, canGreed, canDisenchant = GetLootRollItemInfo(rollID)
    if not name then return end

    -- Convert milliseconds to seconds (WoW 3.3.5 API passes ms)
    local durationSec = (duration or 90000) / 1000

    local link = GetLootRollItemLink(rollID)
    self.activeRolls[rollID] = LootRoll.new(
        rollID, name, link, texture, count, quality,
        bindOnPickUp, canNeed, canGreed, canDisenchant, durationSec
    )

    Looty:Print("New roll: " .. name)
    LootyUI:Refresh()

    if LootyUI.SwitchTab then
        LootyUI:SwitchTab("grouplot")
    end
    if LootyFrame and not LootyFrame:IsShown() then
        LootyFrame:Show()
    end
end

-- CANCEL_LOOT_ROLL fired: mark completed but keep visible until "won" is parsed.
function GroupLoot:MarkCompleted(rollID)
    local roll = self.activeRolls[rollID]
    if roll then
        roll.completed = true
        safetyFrame:Show()  -- start safety net polling
        LootyUI:Refresh()
    end
end

-- Move active → history after "X won" chat message is parsed.
function GroupLoot:FinalizeRoll(rollID)
    local roll = self.activeRolls[rollID]
    if not roll then return end

    -- Cancel safety net check for this roll (chat was received)
    if roll then roll._safetyChecked = true end

    if LootyUI and LootyUI.ClearExpandedState then
        LootyUI:ClearExpandedState(rollID)
    end

    table.insert(self.completedRolls, 1, roll)
    self.activeRolls[rollID] = nil
    LootyUI:Refresh()
    LootyUI:UpdateTabCounts()
end

function GroupLoot:RecordChoice(rollID, playerName, rollType, value)
    -- Search active rolls first, then history (messages can arrive late)
    local roll = self.activeRolls[rollID]
    if not roll then
        for _, cr in ipairs(self.completedRolls) do
            if cr.rollID == rollID then roll = cr; break end
        end
    end
    if not roll then
        if Looty.db and Looty.db.debug then
            Looty:Print("[GroupLoot] RecordChoice FAILED — no roll " .. rollID)
        end
        return false
    end

    local ok = roll:RecordChoice(playerName, rollType, value)
    if ok then
        if Looty.db and Looty.db.debug then
            Looty:Print(string.format("[GroupLoot] RecordChoice OK — %s type=%s val=%s on %s",
                playerName, rollType, tostring(value), roll.name))
        end
        -- Don't refresh — let timer update naturally, avoids timer bar flicker
    end
    return ok
end

function GroupLoot:UpdateRollValue(rollID, playerName, value)
    local roll = self.activeRolls[rollID]
    if not roll then return end
    if roll:UpdateValue(playerName, value) then
        LootyUI:Refresh()
    end
end

-- Find the most recent active roll where playerName has a type but no value yet.
function GroupLoot:FindRollByPlayer(playerName)
    local active = self:GetAllActiveRolls()
    for _, roll in ipairs(active) do
        if roll:NeedsValue(playerName) then
            return roll.rollID
        end
    end
    return nil
end

function GroupLoot:ClearHistory()
    self.completedRolls = {}
    Looty:Print("Roll history cleared.")
    LootyUI:Refresh()
end

-- ---- Test data injection ----

function GroupLoot:InjectTestRolls()
    self.activeRolls    = {}
    self.completedRolls = {}
    local now = GetTime()

    -- Active: Vestments of Redemption (T3 cloth chest)
    local r1 = LootRoll.new(9001,
        "Vestments of Redemption",
        "|cffa335ee|Hitem:23063:0:0:0:0:0:0:0:0|h[Vestments of Redemption]|h|r",
        "Interface\\Icons\\INV_Chest_Cloth_75",
        1, 4, false, true, true, true, 90)
    r1.startTime = now
    r1.rolls = {
        IronWall  = { type = "pass" },
        ShieldBrk = { type = "pass" },
        HolyMend   = { type = "greed", value = 12 },
        ChainHeal  = { type = "greed", value = 38 },
        CircleHeal = { type = "need",  value = 45 },
        Moonwell   = { type = "greed", value = 27 },
        LightWave  = { type = "greed", value = 61 },
        PrayHeal   = { type = "need",  value = 73 },
        BloodStrike = { type = "pass" },
        ShadowDance = { type = "pass" },
        WindFury    = { type = "greed", value = 5 },
        Retrib      = { type = "pass" },
        Eviscerate  = { type = "pass" },
        MangleCat   = { type = "greed", value = 8 },
        FistOfRage  = { type = "pass" },
        FrostBolt  = { type = "need", value = 55 },
        StarFire   = { type = "greed", value = 42 },
        AimedShot  = { type = "pass" },
        ShadowBolt = { type = "need", value = 88 },
        ArcaneX    = { type = "need", value = 67 },
        MindFlay   = { type = "need", value = 96 },
        MultiShot  = { type = "pass" },
        CurseDot   = { type = "greed", value = 19 },
        PyroBlast  = { type = "need", value = 81 },
        Boomkin    = { type = "greed", value = 34 },
    }
    self.activeRolls[9001] = r1

    -- History: Staff of Disruption
    local r2 = LootRoll.new(8001,
        "Staff of Disruption",
        "|cffa335ee|Hitem:23243:0:0:0:0:0:0:0:0|h[Staff of Disruption]|h|r",
        "Interface\\Icons\\INV_Staff_13",
        1, 4, false, true, true, true, 90)
    r2.startTime = now - 180
    r2.rolls = {
        IronWall  = { type = "pass" },
        ShieldBrk = { type = "pass" },
        HolyMend   = { type = "need", value = 33 },
        ChainHeal  = { type = "greed", value = 91 },
        CircleHeal = { type = "need", value = 57 },
        Moonwell   = { type = "need", value = 44 },
        LightWave  = { type = "need", value = 28 },
        PrayHeal   = { type = "need", value = 62 },
        BloodStrike = { type = "pass" },
        ShadowDance = { type = "pass" },
        WindFury    = { type = "disenchant", value = 47 },
        Retrib      = { type = "pass" },
        Eviscerate  = { type = "pass" },
        MangleCat   = { type = "pass" },
        FistOfRage  = { type = "disenchant", value = 55 },
        FrostBolt  = { type = "need", value = 79 },
        StarFire   = { type = "need", value = 41 },
        AimedShot  = { type = "pass" },
        ShadowBolt = { type = "need", value = 86 },
        ArcaneX    = { type = "need", value = 64 },
        MindFlay   = { type = "need", value = 53 },
        MultiShot  = { type = "pass" },
        CurseDot   = { type = "need", value = 38 },
        PyroBlast  = { type = "disenchant", value = 72 },
        Boomkin    = { type = "greed", value = 15 },
    }
    self.completedRolls = { r2 }

    Looty:Print("Group Loot test data injected — 1 active, 1 history (25-player raid).")

    if LootyFrame and not LootyFrame:IsShown() then LootyFrame:Show() end
    LootyUI:Refresh()
end
