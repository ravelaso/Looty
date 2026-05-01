-- Looty MasterLoot Module
-- Owns: Item class, Session object, role detection, protocol send/receive.
-- No UI code. No event registration (Core delegates here).

-- MasterLoot references the Looty global directly at call time (never at load time)

-- ============================================================
-- ---- Protocol constants ----
-- ============================================================
-- Field separator: ASCII \001 (SOH) — never appears in item links or names.
--
-- Item identity key: "{itemID}:{slot}"  e.g. "18815:3"
--   itemID  — from |Hitem:ITEMID:...|h
--   slot    — loot slot index, stable for the session
--   Two drops of the same item get different slots → unique keys.
--
-- ITEM\001itemKey\001link\001texture\001quality\001name  → one per item
-- ROLL_START\001itemKey                                  → roll opened
-- ROLL_END\001itemKey\001winnerName                      → roll closed
-- ITEM_DONE\001itemKey                                   → item finalized
-- CLEAR                                                  → session ended
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
        itemKey   = itemKey,
        link      = link   or "",
        texture   = texture or "",
        quality   = quality or 2,
        name      = name   or "Unknown",
        slot      = slot   or 0,
        quantity  = 1,
        rolls     = {},    -- { [playerName] = { value, time } }
        rerolls   = {},    -- { [playerName] = { value, time } } duplicate rolls
        rolling   = false,
        rollStart = nil,
        isDone    = false,
        winner    = nil,
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

function Session:GetActiveItems()
    local list = {}
    for _, item in pairs(self.items) do
        if not item:IsDone() then table.insert(list, item) end
    end
    -- Sort by slot ascending (original loot order)
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
    -- Re-verify role every open (roster may not have been ready at login)
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

    -- Rebuild ML's item list for this corpse
    self.session.items = {}
    for i = 1, numItems do
        local texture, name, quantity, quality = GetLootSlotInfo(i)
        local link = GetLootSlotLink(i)
        if name and link then
            local itemKey = ExtractItemKey(link, i)
            self.session.items[itemKey] = Item.new(
                itemKey, link, texture, quality, name, i)
            self.session.items[itemKey].quantity = quantity or 1
        end
    end

    -- Broadcast to Raiders
    for _, item in pairs(self.session.items) do
        self:SendMessage(self:SerializeItem(item))
    end

    if Looty.db and Looty.db.debug then
        Looty:Print("[ML] Loot opened: " .. self.session:GetActiveItemCount() .. " items broadcast.")
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
    return "ITEM" .. SEP .. item.itemKey .. SEP
        .. item.link    .. SEP
        .. item.texture .. SEP
        .. tostring(item.quality) .. SEP
        .. item.name
end

function MasterLoot:DeserializeItem(message)
    if string.sub(message, 1, 5) ~= "ITEM" .. SEP then return nil end
    local parts = {}
    for seg in string.gmatch(message, "[^" .. SEP .. "]+") do
        table.insert(parts, seg)
    end
    -- [1]=ITEM [2]=itemKey [3]=link [4]=texture [5]=quality [6]=name
    if #parts < 6 then return nil end

    local itemKey = parts[2]
    local slot    = tonumber(string.match(itemKey, ":(%d+)$")) or 0
    return Item.new(itemKey, parts[3], parts[4], tonumber(parts[5]) or 2, parts[6], slot)
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
        if item then
            self.session.items[item.itemKey] = item
            if Looty.db and Looty.db.debug then
                Looty:Print("[ML] Raider: received item " .. item.name .. " key=" .. item.itemKey)
            end
        end

    elseif string.sub(message, 1, 11) == "ROLL_START" .. SEP then
        local itemKey = string.sub(message, 12)
        local item    = self.session:GetItem(itemKey)
        if item then
            item.rolling    = true
            item.rollStart  = GetTime()
            item.rolls      = {}
            item.rerolls    = {}
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
    end

    if LootyUI and LootyUI.Refresh then LootyUI:Refresh() end
end

-- ============================================================
-- ---- Roll management (ML side) ----
-- ============================================================

function MasterLoot:StartRoll(itemKey)
    if not self:IsML() then return end
    local item = self.session:GetItem(itemKey)
    if not item or item:IsDone() or item:IsRolling() then return end

    if self.rollTimer then self.rollTimer:Hide() end

    item.rolling   = true
    item.rollStart = GetTime()
    item.rolls     = {}
    item.rerolls   = {}
    item.winner    = nil
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
            else
                if LootyUI and LootyUI.UpdateMasterLootTimer then
                    LootyUI:UpdateMasterLootTimer(self.itemKey, remaining)
                end
            end
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
-- ---- Test data injection ----
-- ============================================================

function MasterLoot:InjectTestRolls()
    self.session = Session.new("MasterLooter")
    local now    = GetTime()

    local function makeItem(key, link, tex, qual, name, slot)
        return Item.new(key, link, tex, qual, name, slot)
    end

    local i1 = makeItem("18815:1",
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

    local i2 = makeItem("23243:2",
        "|cffa335ee|Hitem:23243:0:0:0:0:0:0:0:0|h[Staff of the Shadowflame]|h|r",
        "Interface\\Icons\\INV_Staff_13", 4, "Staff of the Shadowflame", 2)

    local i3 = makeItem("22734:3",
        "|cff0070dd|Hitem:22734:0:0:0:0:0:0:0:0|h[Ring of the Eternal]|h|r",
        "Interface\\Icons\\INV_Jewelry_Ring_15", 3, "Ring of the Eternal", 3)
    i3.isDone  = true
    i3.winner  = "HealMePlz"
    i3.rolls = {
        HealMePlz = { value = 87, time = now },
        ShadowMaw = { value = 34, time = now },
        MageBob   = { value = 65, time = now },
    }

    self.session.items       = { ["18815:1"] = i1, ["23243:2"] = i2, ["22734:3"] = i3 }
    self.session.currentRoll = "18815:1"

    Looty:Print("Master Loot test data injected — 2 pending, 1 done. Role: MasterLooter")
    if LootyUI and LootyUI.SwitchTab then LootyUI:SwitchTab("master") end
    if LootyUI and LootyUI.Refresh   then LootyUI:Refresh() end
end

function MasterLoot:InjectRemoteTest()
    self.session = Session.new("Raider")
    self.session.mlName = "TestMaster"
    local now = GetTime()

    local function makeItem(key, link, tex, qual, name, slot)
        return Item.new(key, link, tex, qual, name, slot)
    end

    local i1 = makeItem("18815:1",
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

    local i2 = makeItem("23243:2",
        "|cffa335ee|Hitem:23243:0:0:0:0:0:0:0|h[Staff of the Shadowflame]|h|r",
        "Interface\\Icons\\INV_Staff_13", 4, "Staff of the Shadowflame", 2)

    local i3 = makeItem("22734:3",
        "|cff0070dd|Hitem:22734:0:0:0:0:0:0:0|h[Ring of the Eternal]|h|r",
        "Interface\\Icons\\INV_Jewelry_Ring_15", 3, "Ring of the Eternal", 3)
    i3.isDone  = true
    i3.winner  = "HealMePlz"
    i3.rolls = {
        HealMePlz = { value = 87, time = now },
        ShadowMaw = { value = 34, time = now },
        MageBob   = { value = 65, time = now },
    }

    self.session.items       = { ["18815:1"] = i1, ["23243:2"] = i2, ["22734:3"] = i3 }
    self.session.currentRoll = "18815:1"

    Looty:Print("Remote test data injected — 2 pending, 1 done. Role: Raider  ML: TestMaster")
    if LootyUI and LootyUI.SwitchTab then LootyUI:SwitchTab("master") end
    if LootyUI and LootyUI.Refresh   then LootyUI:Refresh() end
end
