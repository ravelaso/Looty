-- Looty MasterLoot Module
-- Owns: Item class, Session object, role detection, protocol send/receive.
-- No UI code. No event registration (Core delegates here).

-- MasterLoot references the Looty global directly at call time (never at load time)

-- ============================================================
-- ---- Protocol constants ----
-- ============================================================
-- Field separator: ASCII \001 (SOH) — never appears in GUIDs or item IDs.
--
-- Item identity key: "{GUID}:{itemID}"  e.g. "Creature-0-1234-5678:18815"
--   GUID    — UnitGUID("target") of the corpse, unique per instance
--   itemID  — from |Hitem:ITEMID:...|h
--   The GUID guarantees uniqueness across different corpses, even when
--   the same item drops from two trash mobs of the same creature type.
--   No slot is needed (slots shift when the ML loots items).
--
-- ITEM\001itemKey\001link                                            → one per item; Raiders extract quality/name from link
-- ROLL_START\001itemKey                                            → roll opened
-- REROLL_START\001itemKey\001player1\001player2...                 → tie re-roll (eligible only)
-- ROLL_END\001itemKey\001winnerName                                → roll closed
-- ITEM_DONE\001itemKey                                             → item finalized
-- FILTER\001qualityValue                                           → ML broadcasts filter change
-- CLEAR                                                            → session ended
--
-- Raiders extract quality from the link's color code and name from
-- the brackets, so the item is fully displayable immediately.
-- GetItemInfo() is used only for the icon texture (cosmetic fallback).
--
-- ClearDone is a LOCAL UI operation — no protocol message is sent.
-- Each client manages its own Done/History view independently.

local SEP = "\001"

local function ExtractItemKey(link, slot)
    local itemID = string.match(link or "", "item:(%d+)")
    return (itemID or "0") .. ":" .. tostring(slot)
end

-- ============================================================
-- ---- Item class ----
-- ============================================================
-- An Item represents one lootable item in a Master Loot session.
-- Both ML (owns the item) and Raiders (mirror of ML state) use the
-- same struct. All business logic lives here, not in the UI.

local Item = {}
Item.__index = Item

function Item.new(itemKey, link, texture, quality, name, slot)
    return setmetatable({
        itemKey          = itemKey,
        link             = link   or "",
        texture          = texture or "",
        quality          = quality or 2,
        name             = name   or "Unknown",
        slot             = slot   or 0,
        infoLoaded       = true,  -- ML: always true; Raider: set after GetItemInfo resolves
        quantity         = 1,
        rolls            = {},    -- { [playerName] = { value, time } }
        rerolls          = {},    -- { [playerName] = { value, time } } duplicate rolls
        rolling          = false,
        rollStart        = nil,
        isDone           = false,
        winner           = nil,
        wasRolled        = nil,
        eligiblePlayers  = nil,   -- set during re-rolls: { [name] = true }
    }, Item)
end

-- ---- Item queries ----

function Item:IsRolling()
    return self.rolling == true
end

function Item:IsDone()
    return self.isDone == true
end

function Item:RollCount()
    local n = 0
    for _ in pairs(self.rolls) do n = n + 1 end
    return n
end

function Item:RerollCount()
    local n = 0
    for _ in pairs(self.rerolls) do n = n + 1 end
    return n
end

function Item:HasRolled(playerName)
    return self.rolls[playerName] ~= nil
end

-- Return all players sharing the highest roll value.
-- Returns { names = { name1, name2 }, value = bestValue }
function Item:GetTiedWinners()
    local bestValue = 0
    local names = {}
    for playerName, info in pairs(self.rolls) do
        if info.value and info.value > bestValue then
            bestValue = info.value
            names = { playerName }
        elseif info.value and info.value == bestValue then
            table.insert(names, playerName)
        end
    end
    if #names <= 1 then return nil end
    return { names = names, value = bestValue }
end

function Item:IsTied()
    return self:GetTiedWinners() ~= nil
end

-- Reset roll state but restrict future rolls to the tied players only.
function Item:ResetForReroll()
    local tied = self:GetTiedWinners()
    if not tied then return end
    self.rolling   = false
    self.rollStart = nil
    self.winner    = nil
    self.eligiblePlayers = {}
    for _, name in ipairs(tied.names) do
        self.eligiblePlayers[name] = true
    end
end

-- Determine winner: highest value among all rolls.
function Item:GetWinner()
    local bestPlayer, bestValue = nil, 0
    for playerName, info in pairs(self.rolls) do
        if info.value and info.value > bestValue then
            bestValue  = info.value
            bestPlayer = playerName
        end
    end
    return bestPlayer, bestValue
end

-- Sorted roll list, descending by value.
function Item:GetSortedRolls()
    local list = {}
    for playerName, info in pairs(self.rolls) do
        table.insert(list, { name = playerName, value = info.value })
    end
    table.sort(list, function(a, b)
        local va = a.value or -1
        local vb = b.value or -1
        if va ~= vb then return va > vb end
        return a.name < b.name
    end)
    return list
end

-- Record a /roll result. Returns "ok", "reroll", or "no_active_roll".
function Item:RecordRoll(playerName, value)
    if not self.rolling then return "no_active_roll" end
    if self.eligiblePlayers and not self.eligiblePlayers[playerName] then
        return "not_eligible"
    end
    if self.rolls[playerName] then
        self.rerolls[playerName] = { value = value, time = GetTime() }
        return "reroll"
    end
    self.rolls[playerName] = { value = value, time = GetTime() }
    return "ok"
end

-- Expose globally so other modules can reference the type.
LootyItem = Item

-- ============================================================
-- ---- Session object ----
-- ============================================================
-- A Session is the shared state for one ML loot encounter.
-- It is the ONLY item store — both ML and Raiders use session.items.
-- Role is stored here; all role-based queries go through accessors.

local Session = {}
Session.__index = Session

function Session.new(role)
    return setmetatable({
        role         = role,   -- "MasterLooter" | "Raider"
        items        = {},     -- { [itemKey] = Item }
        currentRoll  = nil,    -- itemKey of rolling item, or nil
        mlName       = nil,    -- name of the MasterLooter (Raider side only)
    }, Session)
end

function Session:IsML()       return self.role == "MasterLooter" end
function Session:IsRaider()   return self.role == "Raider"       end

function Session:GetItem(itemKey)
    return self.items[itemKey]
end

function Session:GetCurrentRollingItem()
    if self.currentRoll then return self.items[self.currentRoll] end
    return nil
end

function Session:GetActiveItems(minQuality)
    local list = {}
    for _, item in pairs(self.items) do
        if not item:IsDone() then
            -- Show items that: meet quality filter, are loading, or have roll activity.
            if not minQuality or not item.infoLoaded
                or item.quality >= minQuality
                or item:RollCount() > 0
                or item.wasRolled
            then
                table.insert(list, item)
            end
        end
    end
    -- Sort by slot ascending (original loot order per corpse)
    table.sort(list, function(a, b) return a.slot < b.slot end)
    return list
end

function Session:GetDoneItems()
    local list = {}
    for _, item in pairs(self.items) do
        if item:IsDone() then table.insert(list, item) end
    end
    table.sort(list, function(a, b) return a.slot > b.slot end)
    return list
end

function Session:GetActiveItemCount()
    local n = 0
    for _, item in pairs(self.items) do
        if not item:IsDone() then n = n + 1 end
    end
    return n
end

function Session:ClearDone()
    for key, item in pairs(self.items) do
        if item:IsDone() then self.items[key] = nil end
    end
end

-- ============================================================
-- ---- MasterLoot module ----
-- ============================================================

local MasterLoot = {}
LootyMasterLoot  = MasterLoot

-- Active session (nil when not in Master Loot mode)
MasterLoot.session = nil

-- Loot method (raw string from GetLootMethod)
MasterLoot.lootMethod = nil

-- Roll duration (seconds) — configurable
MasterLoot.rollDuration = 30

-- Roll timer frame (ML side)
MasterLoot.rollTimer = nil

-- Award override selection from dropdown: { [itemKey] = playerName }
-- Set by the UI when the ML picks a non-winner from the dropdown.
-- Cleared per-item when a new roll starts on that item.
MasterLoot.pendingAward = {}

-- Pending item info lookups (Raider side): { [itemID] = { [itemKey] = true } }
MasterLoot.pendingItemInfo = {}

-- Retry timer for GetItemInfo polling fallback (if GET_ITEM_INFO_RECEIVED is unavailable)
MasterLoot.pendingRetryTimer = nil

-- Throttle queue for SendAddonMessage
-- 0.1 s = ~10 msgs/s × ~120 bytes ≈ 1200 CPS, well within the ~3000 CPS
-- disconnect threshold measured by ChatThrottleLib's author.
MasterLoot.msgThrottle  = 0.1
MasterLoot.lastMsgTime  = 0
MasterLoot.pendingMsgs  = {}
MasterLoot.sendTimer    = nil

-- ---- Legacy compatibility aliases (read-only, derived from session) ----
-- UI code and external callers can still read these.

function MasterLoot:IsActive()
    return self.session ~= nil
end

function MasterLoot:IsML()
    return self.session ~= nil and self.session:IsML()
end

function MasterLoot:IsRaider()
    return self.session ~= nil and self.session:IsRaider()
end

function MasterLoot:GetRole()
    return self.session and self.session.role or nil
end

-- ============================================================
-- ---- Internal: loot method and ML detection ----
-- ============================================================

local function DetectLootMethod()
    return GetLootMethod()
end

-- Returns true if THIS player is the ML.
-- Authoritative source: wowprogramming.com Wayback Machine, May 2010.
--   partyMaster == 0         → this player is ML (party context)
--   raidMaster == N          → compare ML name from roster to self
-- Name comparison is the only safe cross-subgroup method in raids.
local function DetectIsML()
    local method, partyMaster, raidMaster = GetLootMethod()
    if method ~= "master" then return false end

    local myName = UnitName("player")

    if raidMaster then
        local mlName = GetRaidRosterInfo(raidMaster)
        return mlName == myName
    end

    return partyMaster == 0
end

-- ============================================================
-- ---- Role resolution ----
-- ============================================================

function MasterLoot:ResolveRole()
    local method = DetectLootMethod()
    self.lootMethod = method

    if method ~= "master" then
        self.session = nil
        if Looty.db and Looty.db.debug then
            Looty:Print(string.format("[ML] ResolveRole: method=%s → no session", method))
        end
        return
    end

    local role = DetectIsML() and "MasterLooter" or "Raider"

    if self.session then
        -- Update role in existing session (e.g. ML changes mid-raid)
        self.session.role = role
    else
        self.session = Session.new(role)
    end

        if Looty.db and Looty.db.debug then
            Looty:Print(string.format("[ML] ResolveRole: method=%s role=%s", method, role))
        end
end

-- ============================================================
-- ---- Lifecycle ----
-- ============================================================

function MasterLoot:Initialize()
    self:ResolveRole()
    if Looty.db and Looty.db.debug then
        Looty:Print(string.format("[ML] Initialize: role=%s active=%s",
            tostring(self:GetRole()), tostring(self:IsActive())))
    end
end

-- ============================================================
-- ---- Event: PARTY_LOOT_METHOD_CHANGED ----
-- ============================================================

function MasterLoot:OnLootMethodChanged()
    local wasActive = self:IsActive()
    local wasML     = self:IsML()

    -- If leaving ML mode, send CLEAR while we still have the ML flag
    if wasML and DetectLootMethod() ~= "master" then
        self:SendMessage("CLEAR")
    end

    -- Wipe session if leaving ML mode
    if DetectLootMethod() ~= "master" then
        self.session = nil
    end

    self:ResolveRole()

    -- Sync mode: ML detects Blizzard threshold changes and broadcasts to Raiders
    if self:IsML() and Looty.db and Looty.db.syncBlizzardThreshold then
        local newThreshold = GetLootThreshold()
        if self._lastSyncedThreshold ~= newThreshold then
            self._lastSyncedThreshold = newThreshold
            self:BroadcastFilter()
            if Looty.db.debug then
                Looty:Print("[ML] Blizzard threshold changed → " .. newThreshold .. " broadcast to Raiders")
            end
        end
    end

    local nowActive = self:IsActive()
    if wasActive ~= nowActive then
        if LootyUI and LootyUI.SwitchTab then
            if nowActive then
                LootyUI:SwitchTab("master")
            elseif LootyUI.currentTab == "master" then
                LootyUI:SwitchTab("grouplot")
            end
        end
    end

    if LootyUI and LootyUI.Refresh then LootyUI:Refresh() end
end

-- ============================================================
-- ---- Event: LOOT_OPENED ----
-- ============================================================

function MasterLoot:OnLootOpened()
    self:ResolveRole()
    if not self:IsActive() then return end

    if Looty.db and Looty.db.debug then
        local method, partyID, raidID = GetLootMethod()
        Looty:Print(string.format("[ML] OnLootOpened: method=%s partyID=%s raidID=%s role=%s",
            tostring(method), tostring(partyID), tostring(raidID), tostring(self:GetRole())))
    end

    if not self:IsML() then return end

    local numItems = GetNumLootItems()
    if numItems == 0 then return end

    -- Compound key format: "{corpseGUID}:{itemID}"
    -- The GUID guarantees uniqueness across different corpses of the same
    -- creature type (trash mobs with same creature ID have different GUIDs).
    -- When GUID is nil (rare), fall back to "0" — dedup is by itemID only.
    local corpseGUID = UnitGUID("target") or "0"
    local guidPrefix = corpseGUID .. ":"

    -- Scan ALL loot slots without quality filtering — we store everything
    -- and filter at display time. This ensures that changing the quality
    -- threshold retroactively applies to all items ever scanned.
    local newItems = {}
    for i = 1, numItems do
        local texture, name, quantity, quality = GetLootSlotInfo(i)
        local link = GetLootSlotLink(i)
        if name and link then
            local itemID = string.match(link, "item:(%d+)")
            local itemKey = guidPrefix .. (itemID or "0")
            if not self.session.items[itemKey] then
                local item = Item.new(itemKey, link, texture, quality, name, i)
                item.quantity = quantity or 1
                item.infoLoaded = true
                self.session.items[itemKey] = item
                newItems[itemKey] = item
            end
        end
    end

    -- Broadcast only the items that are actually new this open.
    for _, item in pairs(newItems) do
        self:SendMessage(self:SerializeItem(item))
    end

    if Looty.db and Looty.db.debug then
        local newCount = 0
        for _ in pairs(newItems) do newCount = newCount + 1 end
        Looty:Print(string.format("[ML] Loot opened: %d new item(s) added (total active: %d). GUID=%s",
            newCount, self.session:GetActiveItemCount(), tostring(corpseGUID)))
    end

    if LootyUI and LootyUI.Refresh then LootyUI:Refresh() end
end

function MasterLoot:OnLootClosed()
    -- Items persist after loot window closes; rolls continue.
end

-- ============================================================
-- ---- Throttled message queue ----
-- ============================================================

function MasterLoot:SendMessage(msg)
    if not self:IsML() then return end
    table.insert(self.pendingMsgs, msg)
    self:FlushQueue()
end

function MasterLoot:FlushQueue()
    if #self.pendingMsgs == 0 then return end
    if GetTime() - self.lastMsgTime < self.msgThrottle then
        if not self.sendTimer then
            self.sendTimer = CreateFrame("Frame")
            self.sendTimer:SetScript("OnUpdate", function()
                MasterLoot:FlushQueue()
            end)
        end
        self.sendTimer:Show()
        return
    end

    local msg     = table.remove(self.pendingMsgs, 1)
    local channel = (GetNumRaidMembers() > 0) and "RAID" or "PARTY"

    if Looty.db and Looty.db.debug then
        Looty:Print(string.format("[ML] SEND channel=%s msg=%.50s", channel, msg))
    end

    SendAddonMessage("LOOTY", msg, channel)
    self.lastMsgTime = GetTime()

    if #self.pendingMsgs == 0 and self.sendTimer then
        self.sendTimer:Hide()
    end
end

-- ============================================================
-- ---- Protocol serialization ----
-- ============================================================

function MasterLoot:SerializeItem(item)
    return "ITEM" .. SEP .. item.itemKey .. SEP .. item.link
end

-- Parse quality from an item link color code.
-- Returns 0-7 or nil if unknown.
local function ParseItemQuality(link)
    if not link or link == "" then return nil end
    local color = string.match(link, "^|cff(%x%x%x%x%x%x)")
    if not color then return nil end
    color = color:lower()
    local map = {
        ["9d9d9d"] = 0,
        ["ffffff"] = 1,
        ["1eff00"] = 2,
        ["0070dd"] = 3,
        ["a335ee"] = 4,
        ["ff8000"] = 5,
        ["e6cc80"] = 6,
        ["00ccff"] = 7,
    }
    return map[color]
end

-- Extract item name from a link's bracketed portion.
-- "|cff...|Hitem:...|h[Spinal Crusher]|h|r" → "Spinal Crusher"
local function ParseItemName(link)
    return string.match(link or "", "%[(.+)%]")
end

function MasterLoot:DeserializeItem(message)
    if string.sub(message, 1, 5) ~= "ITEM" .. SEP then return nil end
    -- Message format: ITEM\001{key}\001{link}
    local parts = {}
    for seg in string.gmatch(message, "[^" .. SEP .. "]+") do
        table.insert(parts, seg)
    end
    if #parts < 2 then return nil end
    local itemKey = parts[2]
    local itemLink = parts[3] or ""
    local quality  = ParseItemQuality(itemLink) or 2
    local name     = ParseItemName(itemLink) or "Unknown"
    return Item.new(itemKey, itemLink, "", quality, name, 0)
end

-- ============================================================
-- ---- Addon message receiver (Raider side) ----
-- ============================================================

function MasterLoot:OnAddonMessage(prefix, message, distribution, sender)
    if prefix ~= "LOOTY" then return end
    if self:IsML() then return end  -- ML ignores own broadcasts

    -- Ensure we have a session to write into
    if not self.session then
        self:ResolveRole()
        if not self.session then return end
    end

    local itemPrefix = "ITEM" .. SEP
    local ipLen      = #itemPrefix

    if string.sub(message, 1, ipLen) == itemPrefix then
        -- First item received → record who the ML is
        if not self.session.mlName then
            self.session.mlName = sender
            if Looty.db and Looty.db.debug then
                Looty:Print("[ML] Raider: first ITEM received, ML is " .. sender)
            end
        end

        local item = self:DeserializeItem(message)
        if not item then return end
        if self.session.items[item.itemKey] then return end  -- already have it

        -- Try to resolve the icon texture via GetItemInfo (cosmetic — QuestionMark fallback).
        local itemID = item.link and tonumber(string.match(item.link, "item:(%d+)"))
        local texture
        if itemID then
            texture = select(10, GetItemInfo(itemID))
        end
        item.texture = texture or ""

        -- Queue texture resolution for later if uncached.
        if item.texture == "" and itemID then
            if not self.pendingItemInfo[itemID] then
                self.pendingItemInfo[itemID] = {}
            end
            self.pendingItemInfo[itemID][item.itemKey] = true
            self:StartPendingRetry()
        end

        self.session.items[item.itemKey] = item

        if Looty.db and Looty.db.debug then
            Looty:Print("[ML] Raider: received item " .. item.name .. " key=" .. item.itemKey)
        end

    elseif string.sub(message, 1, 11) == "ROLL_START" .. SEP then
        local itemKey = string.sub(message, 12)
        local item    = self.session:GetItem(itemKey)
        if item then
            item.rolling         = true
            item.rollStart       = GetTime()
            item.rolls           = {}
            item.rerolls         = {}
            item.eligiblePlayers = nil
            item.wasRolled       = true
            self.session.currentRoll = itemKey
        end

    elseif string.sub(message, 1, 13) == "REROLL_START" .. SEP then
        -- Parse: REROLL_START\001itemKey\001name1\001name2...
        local parts = {}
        for seg in string.gmatch(message, "[^" .. SEP .. "]+") do
            table.insert(parts, seg)
        end
        -- parts[1]=REROLL_START, parts[2]=itemKey, parts[3..N]=eligible names
        local itemKey = parts[2]
        local item    = self.session:GetItem(itemKey)
        if item and itemKey then
            item.rolling    = true
            item.rollStart  = GetTime()
            item.rolls      = {}
            item.rerolls    = {}
            item.wasRolled  = true
            item.eligiblePlayers = {}
            for i = 3, #parts do
                item.eligiblePlayers[parts[i]] = true
            end
            self.session.currentRoll = itemKey
        end

    elseif string.sub(message, 1, 9) == "ROLL_END" .. SEP then
        local rest   = string.sub(message, 10)
        local sep    = string.find(rest, SEP, 1, true)
        local itemKey, winner
        if sep then
            itemKey = string.sub(rest, 1, sep - 1)
            winner  = string.sub(rest, sep + 1)
        else
            itemKey = rest
        end
        local item = self.session:GetItem(itemKey)
        if item then
            item.rolling   = false
            item.rollStart = nil
            item.winner    = (winner and winner ~= "none") and winner or nil
        end
        self.session.currentRoll = nil

    elseif string.sub(message, 1, 10) == "ITEM_DONE" .. SEP then
        local itemKey = string.sub(message, 11)
        local item    = self.session:GetItem(itemKey)
        if item then item.isDone = true end

    elseif message == "CLEAR" then
        self.session = nil

    elseif string.sub(message, 1, 7) == "FILTER" .. SEP then
        local val = tonumber(string.sub(message, 8))
        if val ~= nil and self.session then
            self.session.qualityFilter = val
            if Looty.db and Looty.db.debug then
                Looty:Print("[ML] Raider: filter synced from ML → " .. val)
            end
        end
    end

    if LootyUI and LootyUI.Refresh then LootyUI:Refresh() end
end

-- ============================================================
-- ---- GET_ITEM_INFO_RECEIVED handler (Raider side) ----
-- ============================================================

-- Called when the game asynchronously resolves item info for an uncached item.
-- Fast-path for texture only (cosmetic — the polling fallback also handles this).
function MasterLoot:OnItemInfoReceived(itemID)
    local pending = self.pendingItemInfo[itemID]
    if not pending then return end

    local texture = select(10, GetItemInfo(itemID))
    if not texture then return end

    for itemKey in pairs(pending) do
        local item = self.session and self.session:GetItem(itemKey)
        if item and item.texture == "" then
            item.texture = texture
        end
    end
    self.pendingItemInfo[itemID] = nil

    if LootyUI and LootyUI.Refresh then LootyUI:Refresh() end
end

-- ============================================================
-- ---- Pending item info retry (polling fallback) ----
-- ============================================================

-- Starts an OnUpdate timer that retries GetItemInfo for uncached items.
-- Used as a fallback for clients where GET_ITEM_INFO_RECEIVED is unavailable.
function MasterLoot:StartPendingRetry()
    if self.pendingRetryTimer then return end
    self.pendingRetryTimer = CreateFrame("Frame")
    self.pendingRetryTimer.elapsed = 0
    self.pendingRetryTimer:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed < 1 then return end  -- retry once per second
        self.elapsed = 0
        MasterLoot:RetryPendingItemInfo()
    end)
    self.pendingRetryTimer:Show()
end

function MasterLoot:RetryPendingItemInfo()
    if not next(self.pendingItemInfo) then
        if self.pendingRetryTimer then
            self.pendingRetryTimer:Hide()
            self.pendingRetryTimer = nil
        end
        return
    end

    local resolved = {}
    for itemID, pending in pairs(self.pendingItemInfo) do
        local texture = select(10, GetItemInfo(itemID))
        if texture then
            for itemKey in pairs(pending) do
                local item = self.session and self.session:GetItem(itemKey)
                if item and item.texture == "" then
                    item.texture = texture
                end
            end
            resolved[itemID] = true
        end
    end
    for itemID in pairs(resolved) do
        self.pendingItemInfo[itemID] = nil
    end

    if next(resolved) and LootyUI and LootyUI.Refresh then
        LootyUI:Refresh()
    end

    if not next(self.pendingItemInfo) and self.pendingRetryTimer then
        self.pendingRetryTimer:Hide()
        self.pendingRetryTimer = nil
    end
end

-- ============================================================
-- ---- Quality filter ----
-- ============================================================

-- Returns the active threshold: blizzard threshold (sync mode), session filter
-- (Raider synced from ML), or local db.
function MasterLoot:GetFilterThreshold()
    if Looty.db and Looty.db.syncBlizzardThreshold then
        return GetLootThreshold()
    end
    if self.session and self.session.qualityFilter ~= nil then
        return self.session.qualityFilter
    end
    return Looty.db and Looty.db.qualityFilter or 2
end

function MasterLoot:ShouldIncludeItem(quality)
    return (quality or 0) >= self:GetFilterThreshold()
end

-- Broadcast current filter to all Raiders via addon channel.
-- Only callable by ML. Raiders update their session filter on receipt.
function MasterLoot:BroadcastFilter()
    if not self:IsML() then return end
    local threshold = self:GetFilterThreshold()
    self:SendMessage("FILTER" .. SEP .. tostring(threshold))
end

-- ============================================================
-- ---- Roll management (ML side) ----
-- ============================================================

function MasterLoot:StartRoll(itemKey)
    if not self:IsML() then return end
    local item = self.session:GetItem(itemKey)
    if not item or item:IsDone() or item:IsRolling() then return end

    if self.rollTimer then self.rollTimer:Hide() end

    -- Clear any manual award override — a new roll resets the selection
    if self.pendingAward then self.pendingAward[itemKey] = nil end

    item.rolling   = true
    item.rollStart = GetTime()
    item.rolls     = {}
    item.rerolls   = {}
    item.winner    = nil
    item.eligiblePlayers = nil
    item.wasRolled = true
    self.session.currentRoll = itemKey

    local msg = ">> Rolling for: " .. (item.link or item.name) ..
                " — /roll now! (" .. self.rollDuration .. "s)"
    SendChatMessage(msg, "RAID_WARNING")
    Looty:Print(msg)

    self:SendMessage("ROLL_START" .. SEP .. itemKey)
    self.rollTimer = self:CreateTimer(itemKey)

    if LootyUI and LootyUI.Refresh then LootyUI:Refresh() end
end

function MasterLoot:EndRoll(itemKey)
    if not self:IsML() then return end
    local item = self.session:GetItem(itemKey)
    if not item or not item:IsRolling() then return end

    item.rolling   = false
    item.rollStart = nil
    self.session.currentRoll = nil
    self.rollTimer           = nil

    local tied = item:GetTiedWinners()
    if tied then
        -- Tie detected — no winner, ML can re-roll tied players
        item.winner = nil
        local tieStr = table.concat(tied.names, " & ")
        local msg = ">> Tie at " .. tied.value .. "! " .. tieStr .. " — ML can re-roll"
        Looty:Print(msg)
        self:SendMessage("ROLL_END" .. SEP .. itemKey .. SEP .. "none")
    else
        local winner, winValue = item:GetWinner()
        item.winner = winner

        if winner then
            local msg = ">> " .. winner .. " wins " .. (item.link or item.name) ..
                        " with " .. winValue .. "!"
            SendChatMessage(msg, "RAID_WARNING")
            Looty:Print(msg)
        else
            Looty:Print("No rolls for " .. (item.link or item.name))
        end

        self:SendMessage("ROLL_END" .. SEP .. itemKey .. SEP .. (winner or "none"))
    end
    if LootyUI and LootyUI.Refresh then LootyUI:Refresh() end
end

function MasterLoot:CancelRoll()
    if not self:IsML() then return end
    local itemKey = self.session and self.session.currentRoll
    if not itemKey then return end
    local item = self.session:GetItem(itemKey)
    if item then
        item.rolling   = false
        item.rollStart = nil
    end
    self.session.currentRoll = nil
    if self.rollTimer then
        self.rollTimer:Hide()
        self.rollTimer = nil
    end
    if LootyUI and LootyUI.Refresh then LootyUI:Refresh() end
end

function MasterLoot:StartReRoll(itemKey)
    if not self:IsML() then return end
    local item = self.session:GetItem(itemKey)
    if not item or not item:IsTied() then return end

    if self.rollTimer then self.rollTimer:Hide() end

    item:ResetForReroll()
    item.rolling   = true
    item.rollStart = GetTime()
    item.rolls     = {}
    item.rerolls   = {}
    self.session.currentRoll = itemKey

    local names = {}
    for name in pairs(item.eligiblePlayers) do table.insert(names, name) end
    local tieStr = table.concat(names, " & ")

    local msg = ">> Tie re-roll! Only " .. tieStr ..
                " — /roll now! (" .. self.rollDuration .. "s)"
    SendChatMessage(msg, "RAID_WARNING")
    Looty:Print(msg)

    -- Send REROLL_START with eligible players so Raiders know who is eligible
    local rerollMsg = "REROLL_START" .. SEP .. itemKey
    for _, name in ipairs(names) do
        rerollMsg = rerollMsg .. SEP .. name
    end
    self:SendMessage(rerollMsg)
    self.rollTimer = self:CreateTimer(itemKey)

    if LootyUI and LootyUI.Refresh then LootyUI:Refresh() end
end

function MasterLoot:ToggleDone(itemKey)
    if not self:IsML() then return end
    local item = self.session:GetItem(itemKey)
    if not item then return end
    item.isDone = not item.isDone
    self:SendMessage("ITEM_DONE" .. SEP .. itemKey)
    if LootyUI and LootyUI.Refresh then LootyUI:Refresh() end
end

-- ============================================================
-- ---- Roll recording (both ML and Raider via Parser) ----
-- ============================================================

function MasterLoot:RecordRoll(playerName, value)
    if not self.session then return end
    local item = self.session:GetCurrentRollingItem()
    if not item then return end

    local result = item:RecordRoll(playerName, value)

    if result == "reroll" then
        if Looty.db and Looty.db.debug then
            Looty:Print(string.format("[ML] REROLL detected: %s rolled %d (first: %d)",
                playerName, value, item.rolls[playerName] and item.rolls[playerName].value or 0))
        end
    elseif result == "ok" then
        if Looty.db and Looty.db.debug then
            Looty:Print(string.format("[ML] Roll recorded: %s = %d on %s",
                playerName, value, item.name))
        end
        if LootyUI and LootyUI.Refresh then LootyUI:Refresh() end
    end
end

-- ============================================================
-- ---- Timer (ML side) ----
-- ============================================================

function MasterLoot:CreateTimer(itemKey)
    local timer = CreateFrame("Frame")
    timer.itemKey = itemKey
    timer.elapsed = 0
    timer:Show()
    timer:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed < 1 then return end
        self.elapsed = 0
        local session = MasterLoot.session
        if not session then self:Hide(); return end
        local item = session:GetItem(self.itemKey)
        if item and item:IsRolling() then
            local remaining = MasterLoot.rollDuration - (GetTime() - item.rollStart)
            if remaining <= 0 then
                MasterLoot:EndRoll(self.itemKey)
            end
            -- Timer bar updates handled by global UpdateTimers (250ms tick)
        else
            self:Hide()
        end
    end)
    return timer
end

-- ============================================================
-- ---- ClearDone (local UI operation) ----
-- ============================================================

function MasterLoot:ClearDone()
    if not self.session then return end
    self.session:ClearDone()
    if LootyUI and LootyUI.Refresh then LootyUI:Refresh() end
end

-- ============================================================
-- ---- Public accessors for UI ----
-- ============================================================

function MasterLoot:GetSession()
    return self.session
end

function MasterLoot:GetActiveItemCount()
    if not self.session then return 0 end
    return self.session:GetActiveItemCount()
end

-- ============================================================
-- ---- Award to winner ----
-- ============================================================

-- Trade state machine (nil when idle):
-- { winner=name, bag=n, slot=n, retryTimer=frame|nil }
MasterLoot.tradeState = nil

-- Returns a sorted list of current raid/party members: { {name, class}, ... }
function MasterLoot:GetRaidRoster()
    local list = {}
    local myName = UnitName("player")
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local name, _, _, _, _, cls = GetRaidRosterInfo(i)
            if name then
                table.insert(list, { name = name, class = cls or "WARRIOR" })
            end
        end
    else
        -- party fallback
        table.insert(list, { name = myName, class = select(2, UnitClass("player")) or "WARRIOR" })
        for i = 1, GetNumPartyMembers() do
            local unit = "party" .. i
            local n = UnitName(unit)
            if n then
                local _, cls = UnitClass(unit)
                table.insert(list, { name = n, class = cls or "WARRIOR" })
            end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- Iterates GetMasterLootCandidate(1..40) and returns the index for playerName.
function MasterLoot:FindCandidateIndex(playerName)
    for i = 1, 40 do
        local name = GetMasterLootCandidate(i)
        if name == playerName then return i end
    end
    return nil
end

-- Searches bags 0..NUM_BAG_SLOTS for an item matching itemLink.
-- Returns bag, slot or nil.
function MasterLoot:FindItemInBags(itemLink)
    if not itemLink or itemLink == "" then return nil end
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link == itemLink then return bag, slot end
        end
    end
    return nil
end

-- Single entry point for the Award button.
-- Returns an error code string on failure, nil on success.
function MasterLoot:AwardToWinner(itemKey, playerName)
    if not self:IsML() then return "ERR_NOT_ML" end
    local item = self.session and self.session:GetItem(itemKey)
    if not item then return "ERR_NO_ITEM" end

    -- ---- Scenario 1: loot window is open ----
    -- Only attempt direct award if the loot window is open AND the item is
    -- still in a slot. If not found in the window, fall through to bag search.
    if LootFrame and LootFrame:IsShown() then
        local lootSlot
        for i = 1, GetNumLootItems() do
            if GetLootSlotLink(i) == item.link then
                lootSlot = i
                break
            end
        end
        if lootSlot then
            local candidateIdx = self:FindCandidateIndex(playerName)
            if not candidateIdx then return "ERR_NOT_CANDIDATE" end
            GiveMasterLoot(lootSlot, candidateIdx)
            -- LOOT_SLOT_CLEARED will fire → OnLootSlotCleared marks item done
            if Looty.db and Looty.db.debug then
                Looty:Print(string.format("[ML] GiveMasterLoot slot=%d candidate=%d (%s)",
                    lootSlot, candidateIdx, playerName))
            end
            return nil
        end
        -- Item not in loot window (already looted) — fall through to bag search
    end

    -- ---- Scenario 2: item already in ML bags ----
    local bag, slot = self:FindItemInBags(item.link)
    if not bag then return "ERR_ITEM_NOT_FOUND" end

    -- The winner must be our current target. We'll keep trying via a retry
    -- timer while the ML moves into trade range (common addon pattern).
    if not UnitExists("target") or UnitName("target") ~= playerName then
        return "ERR_TARGET_WINNER"
    end
    -- CheckInteractDistance type 2 = trade range
    if not CheckInteractDistance("target", 2) then
        return "ERR_OUT_OF_RANGE"
    end
    self:StartTradeSequence(playerName, bag, slot)
    return nil
end

-- Initiates the trade and arms the state machine.
function MasterLoot:StartTradeSequence(playerName, bag, slot)
    self.tradeState = { winner = playerName, bag = bag, slot = slot }
    InitiateTrade("target")
    if Looty.db and Looty.db.debug then
        Looty:Print(string.format("[ML] InitiateTrade → %s (bag=%d slot=%d)", playerName, bag, slot))
    end
end

-- Called by Core on TRADE_SHOW.
function MasterLoot:OnTradeShow()
    if not self.tradeState then return end
    local ts = self.tradeState
    PickupContainerItem(ts.bag, ts.slot)
    if CursorHasItem() then
        DropItemOnUnit("target")
        if Looty.db and Looty.db.debug then
            Looty:Print("[ML] Item dropped into trade window for " .. ts.winner)
        end
    else
        -- Item wasn't in that slot anymore (edge case)
        self.tradeState = nil
        Looty:Print("|cffff4040[Looty]|r Trade: item no longer in bags.")
    end
    -- ML accepts manually via Blizzard's trade UI — no AcceptTrade() call here.
end

-- Called by Core on TRADE_CLOSED.
function MasterLoot:OnTradeClosed()
    if not self.tradeState then return end
    if Looty.db and Looty.db.debug then
        Looty:Print("[ML] Trade closed — cleaning up trade state.")
    end
    self.tradeState = nil
    if LootyUI and LootyUI.Refresh then LootyUI:Refresh() end
end

-- Called by Core on LOOT_SLOT_CLEARED.
-- Marks the corresponding item as done when the server confirms the award.
function MasterLoot:OnLootSlotCleared(slot)
    if not self.session then return end
    -- Find the item whose slot index matches the cleared slot
    for _, item in pairs(self.session.items) do
        if item.slot == slot and not item:IsDone() then
            item.isDone = true
            self:SendMessage("ITEM_DONE" .. SEP .. item.itemKey)
            if Looty.db and Looty.db.debug then
                Looty:Print("[ML] LOOT_SLOT_CLEARED slot=" .. slot .. " → " .. item.name .. " marked done")
            end
            break
        end
    end
    if LootyUI and LootyUI.Refresh then LootyUI:Refresh() end
end

-- ============================================================
-- ---- Test data injection ----
-- ============================================================

function MasterLoot:InjectTestRolls()
    LootyPreloadTestClass()
    self.session = Session.new("MasterLooter")
    local now    = GetTime()
    local GUID   = "Creature-0-TEST-TEST-00001"

    local function makeItem(key, link, tex, qual, name, slot)
        return Item.new(key, link, tex, qual, name, slot)
    end

    local i1 = makeItem(GUID .. ":18815",
        "|cffa335ee|Hitem:18815:0:0:0:0:0:0:0:0|h[Spinal Crusher]|h|r",
        "Interface\\Icons\\INV_Mace_36", 4, "Spinal Crusher", 1)
    i1.rolling   = true
    i1.rollStart = now
    i1.rolls = {
        IronWall  = { value = 45, time = now }, TankJoe   = { value = 73, time = now },
        Buenclima = { value = 22, time = now }, ShadowMaw = { value = 88, time = now },
        HealMePlz = { value = 15, time = now }, DPSKing   = { value = 61, time = now },
        WarriorK  = { value = 94, time = now }, MageBob   = { value = 33, time = now },
    }
    i1.rerolls = { DPSKing = { value = 99, time = now } }

    local i2 = makeItem(GUID .. ":23243",
        "|cffa335ee|Hitem:23243:0:0:0:0:0:0:0:0|h[Staff of the Shadowflame]|h|r",
        "Interface\\Icons\\INV_Staff_13", 4, "Staff of the Shadowflame", 2)

    local i3 = makeItem(GUID .. ":22734",
        "|cff0070dd|Hitem:22734:0:0:0:0:0:0:0:0|h[Ring of the Eternal]|h|r",
        "Interface\\Icons\\INV_Jewelry_Ring_15", 3, "Ring of the Eternal", 3)
    i3.isDone  = true
    i3.winner  = "HealMePlz"
    i3.rolls = {
        HealMePlz = { value = 87, time = now },
        ShadowMaw = { value = 34, time = now },
        MageBob   = { value = 65, time = now },
    }

    -- Item with a tie: IronWall and ShadowMaw both rolled 94
    local i4 = makeItem(GUID .. ":29329",
        "|cffff8000|Hitem:29329:0:0:0:0:0:0:0:0|h[Ring of the Titans]|h|r",
        "Interface\\Icons\\INV_Jewelry_Ring_42", 5, "Ring of the Titans", 4)
    i4.rolls = {
        IronWall  = { value = 94, time = now },
        Buenclima = { value = 94, time = now },
        DPSKing   = { value = 77, time = now },
        MageBob   = { value = 45, time = now },
    }
    i4.wasRolled = true

    self.session.items       = { [GUID .. ":18815"] = i1, [GUID .. ":23243"] = i2, [GUID .. ":22734"] = i3, [GUID .. ":29329"] = i4 }
    self.session.currentRoll = GUID .. ":18815"

    Looty:Print("Master Loot test data injected — 2 rolling, 1 done, 1 tie. Role: MasterLooter")
    if LootyUI and LootyUI.SwitchTab then LootyUI:SwitchTab("master") end
    if LootyUI and LootyUI.Refresh   then LootyUI:Refresh() end
end

function MasterLoot:InjectRemoteTest()
    LootyPreloadTestClass()
    self.session = Session.new("Raider")
    self.session.mlName = "TestMaster"
    local now = GetTime()
    local GUID = "Creature-0-TEST-TEST-00001"

    local function makeItem(key, link, tex, qual, name, slot)
        return Item.new(key, link, tex, qual, name, slot)
    end

    local i1 = makeItem(GUID .. ":18815",
        "|cffa335ee|Hitem:18815:0:0:0:0:0:0:0|h[Spinal Crusher]|h|r",
        "Interface\\Icons\\INV_Mace_36", 4, "Spinal Crusher", 1)
    i1.rolling   = true
    i1.rollStart = now
    i1.rolls = {
        IronWall  = { value = 45, time = now }, TankJoe   = { value = 73, time = now },
        Buenclima = { value = 22, time = now }, ShadowMaw = { value = 88, time = now },
        HealMePlz = { value = 15, time = now }, DPSKing   = { value = 61, time = now },
        WarriorK  = { value = 94, time = now }, MageBob   = { value = 33, time = now },
    }
    i1.rerolls = { DPSKing = { value = 99, time = now } }

    local i2 = makeItem(GUID .. ":23243",
        "|cffa335ee|Hitem:23243:0:0:0:0:0:0:0|h[Staff of the Shadowflame]|h|r",
        "Interface\\Icons\\INV_Staff_13", 4, "Staff of the Shadowflame", 2)

    local i3 = makeItem(GUID .. ":22734",
        "|cff0070dd|Hitem:22734:0:0:0:0:0:0:0|h[Ring of the Eternal]|h|r",
        "Interface\\Icons\\INV_Jewelry_Ring_15", 3, "Ring of the Eternal", 3)
    i3.isDone  = true
    i3.winner  = "HealMePlz"
    i3.rolls = {
        HealMePlz = { value = 87, time = now },
        ShadowMaw = { value = 34, time = now },
        MageBob   = { value = 65, time = now },
    }

    local i4 = makeItem(GUID .. ":29329",
        "|cffff8000|Hitem:29329:0:0:0:0:0:0:0:0|h[Ring of the Titans]|h|r",
        "Interface\\Icons\\INV_Jewelry_Ring_42", 5, "Ring of the Titans", 4)
    i4.rolls = {
        IronWall  = { value = 94, time = now },
        ShadowMaw = { value = 94, time = now },
        DPSKing   = { value = 77, time = now },
        MageBob   = { value = 45, time = now },
    }
    i4.wasRolled = true

    self.session.items       = { [GUID .. ":18815"] = i1, [GUID .. ":23243"] = i2, [GUID .. ":22734"] = i3, [GUID .. ":29329"] = i4 }
    self.session.currentRoll = GUID .. ":18815"

    Looty:Print("Remote test data injected — 2 rolling, 1 done, 1 tie. Role: Raider  ML: TestMaster")
    if LootyUI and LootyUI.SwitchTab then LootyUI:SwitchTab("master") end
    if LootyUI and LootyUI.Refresh   then LootyUI:Refresh() end
end
