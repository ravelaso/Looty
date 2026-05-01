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
--
-- Item identity key: "{itemID}:{slot}"  e.g. "18815:3"
--   - itemID extracted from the item link (|Hitem:ITEMID:...|h)
--   - slot is the loot slot index from GetLootSlotLink(i), stable for the session
--   - Composite key handles duplicate drops of the same item (same itemID, different slot)
--   - Both ML and Raiders key their item tables on this string — no positional indices
--
-- ITEM\001itemKey\001link\001texture\001quality\001name  → One per item, 0.1 s apart
-- ROLL_START\001itemKey                                  → Roll started for item
-- ROLL_END\001itemKey\001winnerName                      → Roll ended, winner announced
-- ITEM_DONE\001itemKey                                   → Item loot session finalized
-- CLEAR                                                  → All items cleared (ML mode off)
--
-- NOTE: ClearDone is a LOCAL UI operation on both ML and Raider — it does NOT send a
-- protocol message. Each client manages its own Done/History view independently.

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
local SEP = "\001"

-- Build the stable identity key for an item: "{itemID}:{slot}"
-- itemID is extracted from the WoW item link format: |Hitem:ITEMID:...|h
-- slot is the loot window slot index (server-assigned, stable for the session).
-- Two drops of the same item get the same itemID but different slots → unique keys.
local function ExtractItemKey(link, slot)
    local itemID = string.match(link or "", "item:(%d+)")
    return (itemID or "0") .. ":" .. tostring(slot)
end

function MasterLoot:SerializeItem(item)
    -- Format: ITEM\001itemKey\001link\001texture\001quality\001name
    local link    = item.link or ""
    local texture = item.texture or ""
    local quality = tostring(item.quality or 2)
    local name    = item.name or "Unknown"
    return "ITEM" .. SEP .. item.itemKey .. SEP .. link .. SEP .. texture .. SEP .. quality .. SEP .. name
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
    -- Format: ITEM\001itemKey\001link\001texture\001quality\001name
    if not string.find(message, "^ITEM" .. SEP) then return nil end

    local parts = {}
    for segment in string.gmatch(message, "[^" .. SEP .. "]+") do
        table.insert(parts, segment)
    end
    -- parts[1]="ITEM" parts[2]=itemKey parts[3]=link parts[4]=texture
    -- parts[5]=quality parts[6]=name
    if #parts < 6 then return nil end

    local itemKey = parts[2]
    -- Extract slot from itemKey ("{itemID}:{slot}") for local use
    local slot = tonumber(string.match(itemKey, ":(%d+)$")) or 0

    return {
        itemKey   = itemKey,
        link      = parts[3],
        texture   = parts[4],
        quality   = tonumber(parts[5]) or 2,
        name      = parts[6],
        slot      = slot,
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

    -- All message types below use itemKey (string) as the shared identity key.
    if string.sub(message, 1, #itemPrefix) == itemPrefix then
        local item = self:DeserializeItem(message)
        if item then
            self.remoteItems[item.itemKey] = item
            if addon.db and addon.db.debug then
                DEFAULT_CHAT_FRAME:AddMessage(
                    "|cff00ff00[LOOTY ML]|r Raider: received item " .. item.name .. " key=" .. item.itemKey)
            end
        end

    elseif string.sub(message, 1, 11) == "ROLL_START" .. SEP then
        local itemKey = string.sub(message, 12)
        if itemKey ~= "" and self.remoteItems[itemKey] then
            self.remoteItems[itemKey].rolling    = true
            self.remoteItems[itemKey].rollStart  = GetTime()
            self.remoteItems[itemKey].rolls      = {}
            self.remoteItems[itemKey].rerolls    = {}
            self.currentRemoteRoll               = itemKey
        end

    elseif string.sub(message, 1, 9) == "ROLL_END" .. SEP then
        local rest   = string.sub(message, 10)
        local sepPos = string.find(rest, SEP, 1, true)
        local itemKey, winner
        if sepPos then
            itemKey = string.sub(rest, 1, sepPos - 1)
            winner  = string.sub(rest, sepPos + 1)
        else
            itemKey = rest
        end
        if itemKey ~= "" and self.remoteItems[itemKey] then
            self.remoteItems[itemKey].rolling   = false
            self.remoteItems[itemKey].rollStart = nil
            self.remoteItems[itemKey].winner    = (winner and winner ~= "none") and winner or nil
        end
        self.currentRemoteRoll = nil

    elseif string.sub(message, 1, 10) == "ITEM_DONE" .. SEP then
        local itemKey = string.sub(message, 11)
        if itemKey ~= "" and self.remoteItems[itemKey] then
            self.remoteItems[itemKey].isDone = true
        end

    elseif message == "CLEAR" then
        self.remoteItems      = {}
        self.remoteMode       = false
        self.remoteML         = nil
        self.currentRemoteRoll = nil
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
            local itemKey = ExtractItemKey(link, i)
            self.items[itemKey] = {
                itemKey   = itemKey,
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
            }
        end
    end

    -- Broadcast items to Raiders (throttled, 0.1 s apart)
    for _, item in pairs(self.items) do
        self:SendThrottledMessage(self:SerializeItem(item))
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

function MasterLoot:StartRoll(itemKey)
    local item = self.items[itemKey]
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
    self.currentRoll = itemKey

    local msg = ">> Rolling for: " .. (item.link or item.name) ..
                " — /roll now! (" .. self.rollDuration .. "s)"
    SendChatMessage(msg, "RAID_WARNING")
    addon:Print(msg)

    self:SendThrottledMessage("ROLL_START" .. SEP .. itemKey)
    self.rollTimer = self:CreateTimer(itemKey)

    if LootyUI and LootyUI.Refresh then
        LootyUI:Refresh()
    end
end

function MasterLoot:EndRoll(itemKey)
    local item = self.items[itemKey]
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

    self:SendThrottledMessage("ROLL_END" .. SEP .. itemKey .. SEP .. (winner or "none"))

    if LootyUI and LootyUI.Refresh then
        LootyUI:Refresh()
    end
end

function MasterLoot:CancelRoll()
    if not self.currentRoll then return end
    local item = self.items[self.currentRoll]
    if not item then return end

    item.rolling   = false
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

function MasterLoot:CreateTimer(itemKey)
    local timer = CreateFrame("Frame")
    timer.itemKey = itemKey
    timer.elapsed = 0
    timer:Show()
    timer:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed >= 1 then
            self.elapsed = 0
            local item = MasterLoot.items[self.itemKey]
            if item and item.rolling then
                local remaining = MasterLoot.rollDuration - (GetTime() - item.rollStart)
                if remaining <= 0 then
                    MasterLoot:EndRoll(self.itemKey)
                else
                    if LootyUI and LootyUI.UpdateMasterLootTimer then
                        LootyUI:UpdateMasterLootTimer(self.itemKey, remaining)
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

function MasterLoot:ToggleDone(itemKey)
    local item = self.items[itemKey]
    if not item then return end

    item.isDone = not item.isDone
    self:SendThrottledMessage("ITEM_DONE" .. SEP .. itemKey)

    if LootyUI and LootyUI.Refresh then
        LootyUI:Refresh()
    end
end

function MasterLoot:ClearDone()
    -- Local UI operation only — no protocol message sent.
    -- Each client (ML and Raiders) manages their own Done/History view independently.
    -- itemKey-based identity means there is no index drift risk to worry about.
    for key, item in pairs(self.items) do
        if item.isDone then
            self.items[key] = nil
        end
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

-- Sort helper: compare two itemKeys by their slot number descending.
-- itemKey format is "{itemID}:{slot}" so we extract the slot suffix.
local function itemKeySlotDesc(a, b)
    local slotA = tonumber(string.match(a, ":(%d+)$")) or 0
    local slotB = tonumber(string.match(b, ":(%d+)$")) or 0
    return slotA > slotB
end

function MasterLoot:GetDoneItems()
    local items = {}
    local keys  = {}
    for key in pairs(self.items) do table.insert(keys, key) end
    table.sort(keys, itemKeySlotDesc)
    for _, key in ipairs(keys) do
        if self.items[key].isDone then
            table.insert(items, self.items[key])
        end
    end
    return items
end

function MasterLoot:GetRemoteDoneItems()
    local items = {}
    local keys  = {}
    for key in pairs(self.remoteItems) do table.insert(keys, key) end
    table.sort(keys, itemKeySlotDesc)
    for _, key in ipairs(keys) do
        if self.remoteItems[key].isDone then
            table.insert(items, self.remoteItems[key])
        end
    end
    return items
end

function MasterLoot:ClearRemoteDone()
    for key in pairs(self.remoteItems) do
        if self.remoteItems[key].isDone then
            self.remoteItems[key] = nil
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
        ["18815:1"] = {
            itemKey   = "18815:1",
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
                DPSKing = { value = 99, time = GetTime() },
            },
        },
        ["23243:2"] = {
            itemKey   = "23243:2",
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
        ["22734:3"] = {
            itemKey   = "22734:3",
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
    self.currentRoll = "18815:1"

    addon:Print("Master Loot test data injected — 2 pending, 1 done. Role: MasterLooter")

    if LootyUI and LootyUI.SwitchTab then LootyUI:SwitchTab("master") end
    if LootyUI and LootyUI.Refresh   then LootyUI:Refresh() end
end

function MasterLoot:InjectRemoteTest()
    self.isMasterLootActive  = true
    self.active              = true
    self.role                = "Raider"
    self.isML                = false
    self.remoteMode          = true
    self.remoteML            = "TestMaster"
    self.currentRemoteRoll   = "18815:1"
    self.remoteItems = {
        ["18815:1"] = {
            itemKey   = "18815:1",
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
        ["23243:2"] = {
            itemKey   = "23243:2",
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
        ["22734:3"] = {
            itemKey   = "22734:3",
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
