-- Looty Master Loot Module
-- Tracks Master Loot items, manual /roll results, and cheating detection.
-- All players see the UI (transparency), but only the ML has assignment buttons.

local addon = Looty
local L = Looty_L

local MasterLoot = {}
LootyMasterLoot = MasterLoot

-- ---- State ----

-- Loot method state (set independently of role)
MasterLoot.lootMethod         = nil    -- Raw value from GetLootMethod(): "master"|"group"|etc.
MasterLoot.isMasterLootActive = false  -- true when lootMethod == "master"

-- Role of the current player within this loot session:
--   "MasterLooter" → this player is the ML
--   "Raider"       → loot is master but this player is not the ML
--   nil            → not in master loot mode
MasterLoot.role = nil

-- Legacy aliases kept for backward compat with UI / external code.
-- These are DERIVED from role/isMasterLootActive — never set directly.
MasterLoot.active = false   -- true when isMasterLootActive
MasterLoot.isML   = false   -- true when role == "MasterLooter"

-- ML-side item list and roll tracking
MasterLoot.items       = {}   -- Array of item entries (ML only)
MasterLoot.currentRoll = nil  -- Index of item currently rolling
MasterLoot.rollTimer   = nil  -- Frame for roll countdown
MasterLoot.rollDuration = 30  -- Seconds for each roll

-- Remote state (for Raider clients receiving sync from ML)
MasterLoot.remoteMode       = false  -- true once role is "Raider" and ML mode is active
MasterLoot.remoteItems      = {}     -- Mirror of ML's items (indexed by item index)
MasterLoot.remoteML         = nil    -- Name of the ML we are tracking
MasterLoot.currentRemoteRoll = nil   -- Index of the remoteItem currently rolling (Raider side)

-- Throttle for SendAddonMessage (WoW 3.3.5 rate-limit protection).
-- 0.1 s = max 10 msgs/s × ~120 bytes = ~1200 CPS, well within ChatThrottleLib's
-- researched safe limit of 800 CPS sustained / 4000-byte burst before disconnect.
-- A 25-man full boss loot (~30 msgs, ~3600 bytes) completes in ~3 s at this rate.
MasterLoot.msgThrottle  = 0.1  -- Min seconds between auto-messages
MasterLoot.lastMsgTime  = 0    -- Timestamp of last message sent
MasterLoot.pendingItems = {}   -- Queue for messages waiting to be sent
MasterLoot.sendTimer    = nil  -- Timer frame for throttled sending

-- Message Protocol (prefix: "LOOTY")
-- Field separator: \001 (ASCII SOH) — cannot appear in item links or names.
-- ITEM\001index\001link\001texture\001quality\001name      → One per item, 0.1 s apart
-- ROLL_START\001index                                      → Roll started for item
-- ROLL_END\001index\001winnerName                          → Roll ended, winner announced
-- ITEM_DONE\001index                                       → Item marked as done
-- CLEAR_DONE\001idx1\001idx2\001...                        → ML cleared specific done items
-- CLEAR                                                    → All items cleared (ML mode off)
--
-- IMPORTANT: item indices in all messages are the ORIGINAL indices from LOOT_OPENED.
-- ClearDone on the ML side MUST NOT compact self.items — it nils entries in-place
-- so that all subsequent index-keyed messages still match the Raider's remoteItems.

-- ============================================================
-- ---- Internal helpers: loot method and ML detection ----
-- ============================================================

-- Returns the raw loot method string from the API.
local function DetectLootMethod()
    local method = GetLootMethod()
    return method
end

-- Returns true if THIS player is the Master Looter.
--
-- Authoritative source: wowprogramming.com Wayback Machine, May 2010 (3.3.5 era)
--   partyMaster == 0    → THIS player is ML (only reliable in party, or same subgroup in raid)
--   partyMaster == nil  → ML is not in this player's party subgroup (common in raids)
--   raidMaster  == N    → raid index of the ML in a raid group
--
-- Correct pattern (verified against epgp, a real 3.3.5 addon):
--   In a raid:  resolve ML name via GetRaidRosterInfo(raidMaster), compare to UnitName("player")
--   In a party: partyMaster == 0 means this player is ML
--               partyMaster 1-4 means party member N is ML
--
-- DO NOT compare UnitInRaid("player") == raidMaster — UnitInRaid returns a 0-based
-- index internally and its relationship to raidMaster is unreliable across subgroups.
-- Name comparison is the only safe cross-context method.
local function DetectIsML()
    local method, partyMaster, raidMaster = GetLootMethod()
    if method ~= "master" then return false end

    local myName = UnitName("player")

    if raidMaster then
        -- Raid context: get the ML's actual name from the roster and compare
        local mlName = GetRaidRosterInfo(raidMaster)
        return mlName == myName
    end

    if partyMaster == 0 then
        -- Party context: 0 unambiguously means this player is the ML
        return true
    end

    return false
end

-- ============================================================
-- ---- ResolveRole: single source of truth for role state ----
-- ============================================================

-- Call this whenever the loot method may have changed:
--   Initialize(), OnLootMethodChanged(), OnLootOpened()
--
-- Sets: lootMethod, isMasterLootActive, role, active, isML, remoteMode
function MasterLoot:ResolveRole()
    local method = DetectLootMethod()
    self.lootMethod         = method
    self.isMasterLootActive = (method == "master")

    -- Not in master loot mode at all — clear everything
    if not self.isMasterLootActive then
        self.role   = nil
        self.active = false
        self.isML   = false
        -- remoteMode/remoteML are cleared by the caller (OnLootMethodChanged)
        -- so that the CLEAR sync message can be sent first.
        return
    end

    -- Master loot is active — now determine our role
    self.active = true

    if DetectIsML() then
        self.role       = "MasterLooter"
        self.isML       = true
        self.remoteMode = false  -- ML never operates in remote mode
    else
        self.role       = "Raider"
        self.isML       = false
        self.remoteMode = true   -- Raider is always in receive mode when ML is active
    end

    if addon.db and addon.db.debug then
        local _, partyID, raidID = GetLootMethod()
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cff00ff00[LOOTY ML]|r ResolveRole: method=%s partyID=%s raidID=%s role=%s",
            tostring(method), tostring(partyID), tostring(raidID), tostring(self.role)))
    end
end

-- ============================================================
-- ---- Message Sending (ML side only) ----
-- ============================================================

function MasterLoot:SendThrottledMessage(msg)
    if not self.isML then
        if addon.db and addon.db.debug then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cff00ff00[LOOTY ML]|r SendThrottledMessage SKIPPED — isML=false msg=" .. tostring(msg):sub(1, 40))
        end
        return
    end
    table.insert(self.pendingItems, msg)
    self:ProcessSendQueue()
end

function MasterLoot:ProcessSendQueue()
    if #self.pendingItems == 0 then return end
    if GetTime() - self.lastMsgTime < self.msgThrottle then
        -- Schedule a timer to retry
        if not self.sendTimer then
            self.sendTimer = CreateFrame("Frame")
            self.sendTimer:SetScript("OnUpdate", function()
                MasterLoot:ProcessSendQueue()
            end)
        end
        self.sendTimer:Show()
        return
    end

    local msg = table.remove(self.pendingItems, 1)
    -- Use "RAID" when in a raid group, "PARTY" otherwise.
    -- In WoW 3.3.5, "RAID" does NOT reliably fall back to "PARTY" on all
    -- server implementations, so we must pick the correct channel explicitly.
    -- IsInRaid() does not exist in 3.3.5 — use GetNumRaidMembers() instead.
    local channel = (GetNumRaidMembers() > 0) and "RAID" or "PARTY"
    if addon.db and addon.db.debug then
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cff00ff00[LOOTY ML]|r SEND channel=%s msg=%.50s",
            channel, msg))
    end
    SendAddonMessage("LOOTY", msg, channel)
    self.lastMsgTime = GetTime()

    if #self.pendingItems == 0 and self.sendTimer then
        self.sendTimer:Hide()
    end
end

-- Field separator: ASCII \001 (SOH).
-- Cannot appear in item links, texture paths, quality digits, or item names.
-- This avoids the pipe-escaping problem entirely — WoW item links contain many
-- literal | characters (|c color codes, |H hyperlinks, |h display text, |r reset)
-- that would collide with any pipe-based delimiter scheme.
local SEP = "\001"

function MasterLoot:SerializeItem(item, index)
    -- Format: ITEM\001index\001link\001texture\001quality\001name
    -- No escaping needed — SEP (\001) never appears in any of these fields.
    local link    = item.link or ""
    local texture = item.texture or ""
    local quality = tostring(item.quality or 2)
    local name    = item.name or "Unknown"
    return "ITEM" .. SEP .. index .. SEP .. link .. SEP .. texture .. SEP .. quality .. SEP .. name
end

-- ============================================================
-- ---- Lifecycle ----
-- ============================================================

-- Called on PLAYER_LOGIN to set initial state.
function MasterLoot:Initialize()
    self:ResolveRole()

    if addon.db and addon.db.debug then
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cff00ff00[LOOTY ML]|r Initialize complete: role=%s active=%s isML=%s remoteMode=%s",
            tostring(self.role), tostring(self.active),
            tostring(self.isML), tostring(self.remoteMode)))
    end
end

-- ============================================================
-- ---- Event: PARTY_LOOT_METHOD_CHANGED ----
-- ============================================================

function MasterLoot:OnLootMethodChanged()
    local wasActive = self.active

    -- Send CLEAR before wiping state so the ML flag is still true during send
    local wasML = self.isML
    local newMethod = DetectLootMethod()

    if newMethod ~= "master" then
        -- Notify raid that ML mode is off (ML only, while isML is still true)
        if wasML then
            self:SendThrottledMessage("CLEAR")
        end

        -- Clear all state
        self.items       = {}
        self.currentRoll = nil
        self.rollTimer   = nil
        self.remoteItems = {}
        self.remoteMode  = false
        self.remoteML    = nil
    end

    -- Now resolve the new role (also clears active/isML if not master)
    self:ResolveRole()

    -- Switch tabs on mode change
    if wasActive ~= self.active then
        if LootyUI and LootyUI.SwitchTab then
            if self.active then
                LootyUI:SwitchTab("master")
            elseif LootyUI.currentTab == "master" then
                LootyUI:SwitchTab("grouplot")
            end
        end
    end

    if LootyUI and LootyUI.Refresh then
        LootyUI:Refresh()
    end
end

-- ============================================================
-- ---- Message Receiving (Raider side) ----
-- ============================================================

function MasterLoot:DeserializeItem(message)
    -- Format: ITEM\001index\001link\001texture\001quality\001name
    -- SEP is \001 — split cleanly with no pipe-escaping complications.
    if not string.find(message, "^ITEM" .. SEP) then return nil end

    local parts = {}
    -- strsplit does not exist in all Lua environments; use gmatch with SEP
    -- Note: string.gmatch pattern-escaping — \001 has no special meaning in
    -- Lua patterns so it can be used directly as a literal character.
    for segment in string.gmatch(message, "[^" .. SEP .. "]+") do
        table.insert(parts, segment)
    end
    -- parts[1] = "ITEM", parts[2] = index, parts[3] = link, parts[4] = texture,
    -- parts[5] = quality, parts[6] = name
    if #parts < 6 then return nil end

    local idx = tonumber(parts[2])
    return {
        index     = idx,
        link      = parts[3],
        texture   = parts[4],
        quality   = tonumber(parts[5]) or 2,
        name      = parts[6],
        slot      = idx or 0,
        quantity  = 1,
        rolls     = {},
        rerolls   = {},
        rolling   = false,
        rollStart = nil,
        isDone    = false,
        winner    = nil,
    }
end

function MasterLoot:OnAddonMessage(prefix, message, distribution, sender)
    if prefix ~= "LOOTY" then return end
    -- ML ignores its own broadcast messages
    if self.isML then return end

    -- When we receive the first ITEM sync, record who the ML is
    local itemPrefix = "ITEM" .. SEP
    if string.sub(message, 1, #itemPrefix) == itemPrefix and not self.remoteML then
        self.remoteML = sender
        if addon.db and addon.db.debug then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cff00ff00[LOOTY ML]|r Raider: first ITEM received, ML is " .. sender)
        end
    end

    -- Dispatch by message type
    if string.sub(message, 1, #itemPrefix) == itemPrefix then
        local item = self:DeserializeItem(message)
        if item then
            self.remoteItems[item.index] = item
            if addon.db and addon.db.debug then
                DEFAULT_CHAT_FRAME:AddMessage(
                    "|cff00ff00[LOOTY ML]|r Raider: received item " .. item.name)
            end
        end

    elseif string.sub(message, 1, 11) == "ROLL_START" .. SEP then
        local idx = tonumber(string.sub(message, 12))
        if idx and self.remoteItems[idx] then
            self.remoteItems[idx].rolling    = true
            self.remoteItems[idx].rollStart  = GetTime()
            self.remoteItems[idx].rolls      = {}
            self.remoteItems[idx].rerolls    = {}
            self.currentRemoteRoll           = idx  -- track for Raider roll capture
        end

    elseif string.sub(message, 1, 9) == "ROLL_END" .. SEP then
        local rest   = string.sub(message, 10)
        local sepPos = string.find(rest, SEP, 1, true)
        local idx, winner
        if sepPos then
            idx    = tonumber(string.sub(rest, 1, sepPos - 1))
            winner = string.sub(rest, sepPos + 1)
        else
            idx = tonumber(rest)
        end
        if idx and self.remoteItems[idx] then
            self.remoteItems[idx].rolling   = false
            self.remoteItems[idx].rollStart = nil
            self.remoteItems[idx].winner    = (winner and winner ~= "none") and winner or nil
        end
        self.currentRemoteRoll = nil  -- roll over, stop capturing

    elseif string.sub(message, 1, 10) == "ITEM_DONE" .. SEP then
        local idx = tonumber(string.sub(message, 11))
        if idx and self.remoteItems[idx] then
            self.remoteItems[idx].isDone = true
        end

    elseif string.sub(message, 1, 11) == "CLEAR_DONE" .. SEP then
        -- ML cleared specific done items by index. Remove only those indices
        -- so that active items and their indices are preserved intact.
        local rest = string.sub(message, 12)
        for segment in string.gmatch(rest, "[^" .. SEP .. "]+") do
            local idx = tonumber(segment)
            if idx then
                self.remoteItems[idx] = nil
            end
        end

    elseif message == "CLEAR" then
        self.remoteItems = {}
        self.remoteMode  = false
        self.remoteML    = nil
    end

    if LootyUI and LootyUI.Refresh then
        LootyUI:Refresh()
    end
end

-- ============================================================
-- ---- Event: LOOT_OPENED ----
-- ============================================================

function MasterLoot:OnLootOpened()
    -- Re-verify role every time loot opens; PARTY_LOOT_METHOD_CHANGED may
    -- not have fired since login (e.g. player joined a group already in ML).
    self:ResolveRole()

    if not self.active then return end

    if addon.db and addon.db.debug then
        local method, partyID, raidID = GetLootMethod()
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cff00ff00[LOOTY ML]|r OnLootOpened: method=%s partyID=%s raidID=%s role=%s items=%d",
            tostring(method), tostring(partyID), tostring(raidID),
            tostring(self.role), #self.items))
    end

    -- Only the ML reads and broadcasts the loot window
    if not self.isML then return end

    local numItems = GetNumLootItems()
    if numItems == 0 then return end

    self.items = {}
    for i = 1, numItems do
        local texture, name, quantity, quality = GetLootSlotInfo(i)
        -- WOTLK 3.3.5 has no GetLootSlotType; filter money by absence of link
        local link = GetLootSlotLink(i)
        if name and link then
            table.insert(self.items, {
                slot      = i,
                name      = name,
                link      = link,
                texture   = texture,
                quantity  = quantity or 1,
                quality   = quality or 2,
                rolls     = {},
                rerolls   = {},
                rolling   = false,
                rollStart = nil,
                isDone    = false,
                winner    = nil,
            })
        end
    end

    -- Broadcast items to Raiders (throttled, 0.1 s apart)
    -- self.items is a sparse table keyed by slot index — use pairs, not ipairs.
    for index, item in pairs(self.items) do
        local msg = self:SerializeItem(item, index)
        self:SendThrottledMessage(msg)
    end

    if addon.db and addon.db.debug then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cff00ff00[LOOTY ML]|r Loot opened: " .. #self.items .. " items broadcast.")
    end

    if LootyUI and LootyUI.Refresh then
        LootyUI:Refresh()
    end
end

-- ============================================================
-- ---- Event: LOOT_CLOSED ----
-- ============================================================

function MasterLoot:OnLootClosed()
    -- Items stay alive so rolls can continue after the loot window closes.
    -- They are cleared only when the ML switches loot method or calls ClearDone.
end

-- ============================================================
-- ---- Roll management (ML side) ----
-- ============================================================

function MasterLoot:StartRoll(itemIndex)
    local item = self.items[itemIndex]
    if not item or item.isDone or item.rolling then return end

    -- Cancel any previous active roll
    if self.rollTimer then
        self.rollTimer:Hide()
    end

    item.rolling  = true
    item.rollStart = GetTime()
    item.rolls    = {}
    item.rerolls  = {}
    item.winner   = nil
    self.currentRoll = itemIndex

    local msg = ">> Rolling for: " .. (item.link or item.name) ..
                " — /roll now! (" .. self.rollDuration .. "s)"
    SendChatMessage(msg, "RAID_WARNING")
    addon:Print(msg)

        self:SendThrottledMessage("ROLL_START" .. SEP .. itemIndex)
    self.rollTimer = self:CreateTimer(itemIndex)

    if LootyUI and LootyUI.Refresh then
        LootyUI:Refresh()
    end
end

function MasterLoot:EndRoll(itemIndex)
    local item = self.items[itemIndex]
    if not item or not item.rolling then return end

    item.rolling  = false
    item.rollStart = nil
    self.currentRoll = nil
    self.rollTimer   = nil

    local winner, winValue = self:GetWinner(item)
    item.winner = winner

    if winner then
        local announceMsg = ">> " .. winner .. " wins " ..
                            (item.link or item.name) .. " with " .. winValue .. "!"
        SendChatMessage(announceMsg, "RAID_WARNING")
        addon:Print(announceMsg)
    else
        addon:Print("No rolls for " .. (item.link or item.name))
    end

    self:SendThrottledMessage("ROLL_END" .. SEP .. itemIndex .. SEP .. (winner or "none"))

    if LootyUI and LootyUI.Refresh then
        LootyUI:Refresh()
    end
end

function MasterLoot:CancelRoll()
    if not self.currentRoll then return end
    local item = self.items[self.currentRoll]
    if not item then return end

    item.rolling  = false
    item.rollStart = nil
    self.currentRoll = nil

    if self.rollTimer then
        self.rollTimer:Hide()
        self.rollTimer = nil
    end

    if LootyUI and LootyUI.Refresh then
        LootyUI:Refresh()
    end
end

-- ============================================================
-- ---- Timer ----
-- ============================================================

function MasterLoot:CreateTimer(itemIndex)
    local timer = CreateFrame("Frame")
    timer.itemIndex = itemIndex
    timer.elapsed   = 0
    timer:Show()
    timer:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed >= 1 then
            self.elapsed = 0
            local item = MasterLoot.items[self.itemIndex]
            if item and item.rolling then
                local remaining = MasterLoot.rollDuration - (GetTime() - item.rollStart)
                if remaining <= 0 then
                    MasterLoot:EndRoll(self.itemIndex)
                else
                    if LootyUI and LootyUI.UpdateMasterLootTimer then
                        LootyUI:UpdateMasterLootTimer(self.itemIndex, remaining)
                    end
                end
            else
                self:Hide()
            end
        end
    end)
    return timer
end

-- ============================================================
-- ---- Roll recording (ML and Raider, driven by Parser) ----
-- ============================================================

function MasterLoot:RecordRoll(playerName, value, itemName)
    if not self.active then return end

    local item

    if self.isML then
        -- ML path: use its own items table and currentRoll index
        if not self.currentRoll then return end
        item = self.items[self.currentRoll]
    elseif self.remoteMode then
        -- Raider path: use remoteItems and currentRemoteRoll index.
        -- CHAT_MSG_SYSTEM fires locally for all group members, so Raiders
        -- receive the same /roll messages as the ML without any extra protocol.
        if not self.currentRemoteRoll then return end
        item = self.remoteItems[self.currentRemoteRoll]
    else
        return
    end

    if not item or not item.rolling then return end

    -- Duplicate roll → cheating detection (same logic for both roles)
    if item.rolls[playerName] then
        item.rerolls[playerName] = { value = value, time = GetTime() }
        if addon.db and addon.db.debug then
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "|cff00ff00[LOOTY ML]|r REROLL detected: %s rolled %d (first: %d)",
                playerName, value, item.rolls[playerName].value))
        end
        return
    end

    item.rolls[playerName] = { value = value, time = GetTime() }

    if addon.db and addon.db.debug then
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cff00ff00[LOOTY ML]|r Roll recorded: %s = %d on %s",
            playerName, value, item.name or "?"))
    end

    if LootyUI and LootyUI.Refresh then
        LootyUI:Refresh()
    end
end

-- ============================================================
-- ---- Winner resolution ----
-- ============================================================

function MasterLoot:GetWinner(item)
    local bestPlayer = nil
    local bestValue  = 0
    for playerName, rollInfo in pairs(item.rolls) do
        if rollInfo.value and rollInfo.value > bestValue then
            bestValue  = rollInfo.value
            bestPlayer = playerName
        end
    end
    return bestPlayer, bestValue
end

-- ============================================================
-- ---- Item state helpers ----
-- ============================================================

function MasterLoot:ToggleDone(itemIndex)
    local item = self.items[itemIndex]
    if not item then return end

    item.isDone = not item.isDone
    self:SendThrottledMessage("ITEM_DONE" .. SEP .. itemIndex)

    if LootyUI and LootyUI.Refresh then
        LootyUI:Refresh()
    end
end

function MasterLoot:ClearDone()
    -- Collect indices BEFORE modifying, so we can broadcast them to Raiders.
    -- MUST nil in-place rather than rebuilding the array — rebuilding would
    -- shift indices and desync all subsequent ROLL_START/ROLL_END/ITEM_DONE
    -- messages that Raiders key against original LOOT_OPENED indices.
    local clearedIndices = {}
    for idx, item in pairs(self.items) do
        if item.isDone then
            clearedIndices[#clearedIndices + 1] = idx
            self.items[idx] = nil
        end
    end

    -- Notify Raiders to remove the same indices
    if #clearedIndices > 0 then
        local msg = "CLEAR_DONE" .. SEP .. table.concat(clearedIndices, SEP)
        self:SendThrottledMessage(msg)
    end

    if LootyUI and LootyUI.Refresh then
        LootyUI:Refresh()
    end
end

function MasterLoot:GetPendingItems()
    local items = {}
    for _, item in pairs(self.items) do
        if not item.isDone then
            table.insert(items, item)
        end
    end
    return items
end

function MasterLoot:GetDoneItems()
    -- self.items is sparse after ClearDone — collect indices, sort descending.
    local items = {}
    local indices = {}
    for idx in pairs(self.items) do
        table.insert(indices, idx)
    end
    table.sort(indices, function(a, b) return a > b end)
    for _, idx in ipairs(indices) do
        if self.items[idx].isDone then
            table.insert(items, self.items[idx])
        end
    end
    return items
end

-- Raider equivalents: operate on remoteItems (sparse table, iterate by index)
function MasterLoot:GetRemoteDoneItems()
    local items = {}
    -- Collect indices first so we can sort them descending (most recent last = first in list)
    local indices = {}
    for idx in pairs(self.remoteItems) do
        table.insert(indices, idx)
    end
    table.sort(indices, function(a, b) return a > b end)
    for _, idx in ipairs(indices) do
        if self.remoteItems[idx].isDone then
            table.insert(items, self.remoteItems[idx])
        end
    end
    return items
end

function MasterLoot:ClearRemoteDone()
    for idx in pairs(self.remoteItems) do
        if self.remoteItems[idx].isDone then
            self.remoteItems[idx] = nil
        end
    end
    if LootyUI and LootyUI.Refresh then
        LootyUI:Refresh()
    end
end

function MasterLoot:GetActiveItemCount()
    local count = 0
    for _, item in pairs(self.items) do
        if not item.isDone then count = count + 1 end
    end
    return count
end

-- ============================================================
-- ---- Test Data Injection ----
-- ============================================================

function MasterLoot:InjectTestRolls()
    self.isMasterLootActive = true
    self.active = true
    self.role   = "MasterLooter"
    self.isML   = true
    self.items  = {
        {
            slot      = 1,
            name      = "Spinal Crusher",
            link      = "|cffa335ee|Hitem:18815:0:0:0:0:0:0:0:0|h[Spinal Crusher]|h|r",
            texture   = "Interface\\Icons\\INV_Mace_36",
            quantity  = 1,
            quality   = 4,
            rolling   = true,
            rollStart = GetTime(),
            isDone    = false,
            winner    = nil,
            rolls = {
                IronWall  = { value = 45, time = GetTime() },
                TankJoe   = { value = 73, time = GetTime() },
                Buenclima = { value = 22, time = GetTime() },
                ShadowMaw = { value = 88, time = GetTime() },
                HealMePlz = { value = 15, time = GetTime() },
                DPSKing   = { value = 61, time = GetTime() },
                WarriorK  = { value = 94, time = GetTime() },
                MageBob   = { value = 33, time = GetTime() },
            },
            rerolls = {
                DPSKing = { value = 99, time = GetTime() },  -- cheating attempt
            },
        },
        {
            slot      = 2,
            name      = "Staff of the Shadowflame",
            link      = "|cffa335ee|Hitem:23243:0:0:0:0:0:0:0:0|h[Staff of the Shadowflame]|h|r",
            texture   = "Interface\\Icons\\INV_Staff_13",
            quantity  = 1,
            quality   = 4,
            rolling   = false,
            rollStart = nil,
            isDone    = false,
            winner    = nil,
            rolls     = {},
            rerolls   = {},
        },
        {
            slot      = 3,
            name      = "Ring of the Eternal",
            link      = "|cff0070dd|Hitem:22734:0:0:0:0:0:0:0:0|h[Ring of the Eternal]|h|r",
            texture   = "Interface\\Icons\\INV_Jewelry_Ring_15",
            quantity  = 1,
            quality   = 3,
            rolling   = false,
            rollStart = nil,
            isDone    = true,
            winner    = "HealMePlz",
            rolls = {
                HealMePlz = { value = 87, time = GetTime() },
                ShadowMaw = { value = 34, time = GetTime() },
                MageBob   = { value = 65, time = GetTime() },
            },
            rerolls = {},
        },
    }
    self.currentRoll = 1

    addon:Print("Master Loot test data injected — 2 pending, 1 done. Role: MasterLooter")

    if LootyUI and LootyUI.SwitchTab then LootyUI:SwitchTab("master") end
    if LootyUI and LootyUI.Refresh   then LootyUI:Refresh() end
end

function MasterLoot:InjectRemoteTest()
    self.isMasterLootActive = true
    self.active     = true
    self.role       = "Raider"
    self.isML       = false
    self.remoteMode = true
    self.remoteML   = "TestMaster"
    self.remoteItems = {
        [1] = {
            index     = 1,
            slot      = 1,
            name      = "Spinal Crusher",
            link      = "|cffa335ee|Hitem:18815:0:0:0:0:0:0:0|h[Spinal Crusher]|h|r",
            texture   = "Interface\\Icons\\INV_Mace_36",
            quantity  = 1,
            quality   = 4,
            rolling   = true,
            rollStart = GetTime(),
            isDone    = false,
            winner    = nil,
            rolls = {
                IronWall  = { value = 45, time = GetTime() },
                TankJoe   = { value = 73, time = GetTime() },
                Buenclima = { value = 22, time = GetTime() },
                ShadowMaw = { value = 88, time = GetTime() },
                HealMePlz = { value = 15, time = GetTime() },
                DPSKing   = { value = 61, time = GetTime() },
                WarriorK  = { value = 94, time = GetTime() },
                MageBob   = { value = 33, time = GetTime() },
            },
            rerolls = {
                DPSKing = { value = 99, time = GetTime() },
            },
        },
        [2] = {
            index     = 2,
            slot      = 2,
            name      = "Staff of the Shadowflame",
            link      = "|cffa335ee|Hitem:23243:0:0:0:0:0:0:0|h[Staff of the Shadowflame]|h|r",
            texture   = "Interface\\Icons\\INV_Staff_13",
            quantity  = 1,
            quality   = 4,
            rolling   = false,
            rollStart = nil,
            isDone    = false,
            winner    = nil,
            rolls     = {},
            rerolls   = {},
        },
        [3] = {
            index     = 3,
            slot      = 3,
            name      = "Ring of the Eternal",
            link      = "|cff0070dd|Hitem:22734:0:0:0:0:0:0:0|h[Ring of the Eternal]|h|r",
            texture   = "Interface\\Icons\\INV_Jewelry_Ring_15",
            quantity  = 1,
            quality   = 3,
            rolling   = false,
            rollStart = nil,
            isDone    = true,
            winner    = "HealMePlz",
            rolls = {
                HealMePlz = { value = 87, time = GetTime() },
                ShadowMaw = { value = 34, time = GetTime() },
                MageBob   = { value = 65, time = GetTime() },
            },
            rerolls = {},
        },
    }

    addon:Print("Remote test data injected — 2 pending, 1 done. Role: Raider  ML: TestMaster")

    if LootyUI and LootyUI.SwitchTab then LootyUI:SwitchTab("master") end
    if LootyUI and LootyUI.Refresh   then LootyUI:Refresh() end
end
