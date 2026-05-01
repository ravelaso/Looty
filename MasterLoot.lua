-- Looty Master Loot Module
-- Tracks Master Loot items, manual /roll results, and cheating detection.
-- All players see the UI (transparency), but only the ML has assignment buttons.

local addon = Looty
local L = Looty_L

local MasterLoot = {}
LootyMasterLoot = MasterLoot

-- State
MasterLoot.active = false       -- Is Master Loot mode active?
MasterLoot.items = {}           -- Array of item entries
MasterLoot.currentRoll = nil    -- Index of item currently rolling
MasterLoot.rollTimer = nil      -- Frame for roll countdown
MasterLoot.rollDuration = 30    -- Seconds for each roll
MasterLoot.isML = false         -- Is current player the Master Looter?

-- Remote state (for non-ML clients receiving sync from ML)
MasterLoot.remoteMode = false    -- Are we in remote spectator mode?
MasterLoot.remoteItems = {}      -- Mirror of ML's items (indexed by index)
MasterLoot.remoteML = nil        -- Name of ML we're tracking

-- Throttle for sending messages (rate limit protection)
-- WoW 3.3.5 has rate limiting on SendAddonMessage - sending too many
-- messages too fast can disconnect the player. We use 0.5s between messages.
-- Items are queued and sent one by one with this delay.
MasterLoot.msgThrottle = 0.5    -- Min seconds between auto-messages
MasterLoot.lastMsgTime = 0      -- Timestamp of last message sent
MasterLoot.pendingItems = {}     -- Queue for items waiting to be sent
MasterLoot.sendTimer = nil       -- Timer frame for throttled sending

-- Message Protocol (prefix: "LOOTY")
-- ITEM|index|link|texture|quality|name  → One per item, 0.5s apart
-- ROLL_START|index                      → Roll started for item
-- ROLL_END|index|winnerName          → Roll ended, winner announced
-- ITEM_DONE|index                      → Item marked as done
-- CLEAR                               → All items cleared (ML mode off)

-- ---- Message Sending (ML side) ----

function MasterLoot:SendThrottledMessage(msg)
    if not self.isML then return end
    -- Add to queue
    table.insert(self.pendingItems, msg)
    self:ProcessSendQueue()
end

function MasterLoot:ProcessSendQueue()
    if #self.pendingItems == 0 then return end
    if GetTime() - self.lastMsgTime < self.msgThrottle then
        -- Schedule timer to try again
        if not self.sendTimer then
            self.sendTimer = CreateFrame("Frame")
            self.sendTimer:SetScript("OnUpdate", function(self)
                MasterLoot:ProcessSendQueue()
            end)
        end
        self.sendTimer:Show()
        return
    end

    -- Send next message
    local msg = table.remove(self.pendingItems, 1)
    SendAddonMessage("LOOTY", msg, "RAID")
    self.lastMsgTime = GetTime()

    -- If more items, will be picked up on next OnUpdate
    if #self.pendingItems == 0 and self.sendTimer then
        self.sendTimer:Hide()
    end
end

function MasterLoot:SerializeItem(item, index)
    -- Compact format: ITEM|index|link|texture|quality|name
    -- Escape pipe characters in link (safety measure)
    local link = string.gsub(item.link or "", "|", "||")
    local texture = item.texture or ""
    local quality = tostring(item.quality or 2)
    local name = item.name or "Unknown"

    return string.format("ITEM|%d|%s|%s|%s|%s",
        index, link, texture, quality, name)
end

-- ---- Helper: check if player is Master Looter ----

local function CheckIsML()
    local method, masterlooterPartyID, masterlooterRaidID = GetLootMethod()
    if method ~= "master" then
        MasterLoot.isML = false
        return false
    end

    -- In WOTLK 3.3.5, GetLootMethod() returns NUMBERS for ML identity,
    -- NOT names:
    --   masterlooterPartyID = 0 means THIS PLAYER is ML
    --   masterlooterPartyID = 1-4 means party member 1-4 is ML
    --   masterlooterRaidID = raid index or nil
    -- TODO: Check for current player raidID and compare with masterlooterPartyID: see https://web.archive.org/web/20100513002458/http://wowprogramming.com/docs/api/GetLootMethod
    if masterlooterPartyID == 0 then
        MasterLoot.isML = true
        return true
    end

    -- In a raid, check if raid index matches our own
    if masterlooterRaidID and UnitIsRaidMember("player") then
        for i = 1, GetNumGroupMembers() do
            if UnitName("raid" .. i) == UnitName("player") then
                MasterLoot.isML = (masterlooterRaidID == i)
                return MasterLoot.isML
            end
        end
    end

    -- Fallback: party member is ML (not us)
    MasterLoot.isML = false
    return false
end

-- ---- Initialize: called on PLAYER_LOGIN to set initial state ----

function MasterLoot:Initialize()
    -- Check if we're already in Master Loot mode at login
    -- (PARTY_LOOT_METHOD_CHANGED may not have fired since login)
    local method, partyID, raidID = GetLootMethod()
    if method == "master" then
        MasterLoot.active = true
        CheckIsML()
        if addon.db and addon.db.debug then
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "|cff00ff00[LOOTY ML]|r ML at login: method=%s partyID=%s raidID=%s isML=%s",
                tostring(method), tostring(partyID), tostring(raidID), tostring(MasterLoot.isML)))
        end
    else
        MasterLoot.active = false
        MasterLoot.isML = false
        if addon.db and addon.db.debug then
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "|cff00ff00[LOOTY ML]|r Not ML at login: method=%s partyID=%s raidID=%s",
                tostring(method), tostring(partyID), tostring(raidID)))
        end
    end
end

-- ---- Event: PARTY_LOOT_METHOD_CHANGED ----

function MasterLoot:OnLootMethodChanged()
    local method, partyID, raidID = GetLootMethod()
    local wasActive = MasterLoot.active

    if method == "master" then
        MasterLoot.active = true
        CheckIsML()
        if addon.db and addon.db.debug then
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "|cff00ff00[LOOTY ML]|r Master Loot activated: method=%s partyID=%s raidID=%s isML=%s",
                tostring(method), tostring(partyID), tostring(raidID), tostring(MasterLoot.isML)))
        end
    else
        MasterLoot.active = false
        MasterLoot.items = {}
        MasterLoot.currentRoll = nil
        MasterLoot.rollTimer = nil

        -- Sync: notify raid members that ML mode is off (ML only)
        if MasterLoot.isML then
            MasterLoot:SendThrottledMessage("CLEAR")
        end

        -- Clear remote state if we were in remote mode (non-ML clients)
        if MasterLoot.remoteMode then
            MasterLoot.remoteItems = {}
            MasterLoot.remoteMode = false
            MasterLoot.remoteML = nil
        end

        if addon.db and addon.db.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[LOOTY ML]|r Master Loot mode deactivated.")
        end
    end

    if wasActive ~= MasterLoot.active then
        -- Switch to Master tab when mode changes
        if LootyUI and LootyUI.SwitchTab then
            if MasterLoot.active then
                LootyUI:SwitchTab("master")
            elseif LootyUI.currentTab == "master" then
                LootyUI:SwitchTab("grouplot")
            end
        end
    if LootyUI and LootyUI.Refresh then
        LootyUI:Refresh()
    end
end

-- ---- Message Receiving (All clients) ----

function MasterLoot:DeserializeItem(message)
    -- Parse: ITEM|index|link|texture|quality|name
    -- Link may contain escaped pipes (||), need to handle carefully
    local header, rest = string.match(message, "^ITEM|(.+)$")
    if not header then return nil end

    -- Split by | but respect escaped ||
    local parts = {}
    local current = ""
    local i = 1
    while i <= #rest do
        local char = string.sub(rest, i, i)
        if char == "|" and i < #rest and string.sub(rest, i+1, i+1) == "|" then
            current = current .. "|"
            i = i + 2
        elseif char == "|" then
            table.insert(parts, current)
            current = ""
            i = i + 1
        else
            current = current .. char
            i = i + 1
        end
    end
    table.insert(parts, current)  -- Last part

    if #parts < 5 then return nil end

    return {
        index = tonumber(parts[1]),
        link = string.gsub(parts[2], "||", "|"),  -- Unescape
        texture = parts[3],
        quality = tonumber(parts[4]) or 2,
        name = parts[5],
        -- Initialize other fields
        slot = tonumber(parts[1]) or 0,
        quantity = 1,
        rolls = {},
        rerolls = {},
        rolling = false,
        rollStart = nil,
        isDone = false,
        winner = nil,
    }
end

function MasterLoot:OnAddonMessage(prefix, message, distribution, sender)
    -- Only process messages for Looty
    if prefix ~= "LOOTY" then return end
    -- ML doesn't process own messages
    if self.isML then return end

    -- Set remote mode on first ITEM received
    if not self.remoteMode and string.find(message, "^ITEM|") then
        self.remoteMode = true
        self.remoteML = sender
        if addon.db and addon.db.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[LOOTY ML]|r Remote mode activated, ML: " .. sender)
        end
    end

    -- Parse commands
    if string.find(message, "^ITEM|") then
        local item = self:DeserializeItem(message)
        if item then
            self.remoteItems[item.index] = item
            if addon.db and addon.db.debug then
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[LOOTY ML]|r Received item: " .. item.name)
            end
        end
    elseif string.find(message, "^ROLL_START|") then
        local _, _, idx = string.find(message, "ROLL_START|(%d+)")
        idx = tonumber(idx)
        if idx and self.remoteItems[idx] then
            self.remoteItems[idx].rolling = true
            self.remoteItems[idx].rollStart = GetTime()
            self.remoteItems[idx].rolls = {}
            self.remoteItems[idx].rerolls = {}
        end
    elseif string.find(message, "^ROLL_END|") then
        local _, _, idx, winner = string.find(message, "ROLL_END|(%d+)|(.+)")
        idx = tonumber(idx)
        if idx and self.remoteItems[idx] then
            self.remoteItems[idx].rolling = false
            self.remoteItems[idx].rollStart = nil
            self.remoteItems[idx].winner = winner ~= "none" and winner or nil
        end
    elseif string.find(message, "^ITEM_DONE|") then
        local _, _, idx = string.find(message, "ITEM_DONE|(%d+)")
        idx = tonumber(idx)
        if idx and self.remoteItems[idx] then
            self.remoteItems[idx].isDone = true
        end
    elseif message == "CLEAR" then
        self.remoteItems = {}
        self.remoteMode = false
        self.remoteML = nil
    end

    -- Refresh UI
    if LootyUI and LootyUI.Refresh then
        LootyUI:Refresh()
    end
end
end

-- ---- Event: LOOT_OPENED ----

function MasterLoot:OnLootOpened()
    if not MasterLoot.active then return end

    -- Re-verify ML status every time loot opens (it can change between sessions
    -- and PARTY_LOOT_METHOD_CHANGED may not have fired since login).
    CheckIsML()

    -- Debug: log current ML state
    if addon.db and addon.db.debug then
        local method, partyID, raidID = GetLootMethod()
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cff00ff00[LOOTY ML]|r OnLootOpened: method=%s partyID=%s raidID=%s isML=%s items=%d",
            tostring(method), tostring(partyID), tostring(raidID), tostring(MasterLoot.isML), #MasterLoot.items))
    end

    -- Read items from the loot window
    local numItems = GetNumLootItems()
    if numItems == 0 then return end

    MasterLoot.items = {}
    for i = 1, numItems do
        local texture, name, quantity, quality, locked, isQuestItem, questId, isActive = GetLootSlotInfo(i)

        -- WOTLK 3.3.5 does NOT have GetLootSlotType (added in 5.0.4/1.13.2).
        -- Filter out money/coin slots: they return a coin string as name and
        -- have no item link. Real items always return a valid link.
        local link = GetLootSlotLink(i)
        if name and link then
            table.insert(MasterLoot.items, {
                slot = i,
                name = name,
                link = link,
                texture = texture,
                quantity = quantity or 1,
                quality = quality or 2,
                rolls = {},
                rerolls = {},
                rolling = false,
                rollStart = nil,
                isDone = false,
                winner = nil,
            })
        end
    end

    -- Send items to raid members (one per message, 0.5s throttle)
    if self.isML then
        for index, item in ipairs(MasterLoot.items) do
            local msg = self:SerializeItem(item, index)
            self:SendThrottledMessage(msg)
        end
    end

    if addon.db and addon.db.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[LOOTY ML]|r Loot opened: " .. #MasterLoot.items .. " items found.")
    end

    if LootyUI and LootyUI.Refresh then
        LootyUI:Refresh()
    end
end

-- ---- Event: LOOT_CLOSED ----

function MasterLoot:OnLootClosed()
    -- Keep items in MasterLoot.items so rolls can continue after looting
    -- They stay until ML clears them or switches loot method
end

-- ---- Start Roll ----

function MasterLoot:StartRoll(itemIndex)
    local item = MasterLoot.items[itemIndex]
    if not item or item.isDone or item.rolling then return end

    -- Cancel any previous roll
    if MasterLoot.rollTimer then
        MasterLoot.rollTimer:Hide()
    end

    item.rolling = true
    item.rollStart = GetTime()
    item.rolls = {}
    item.rerolls = {}
    item.winner = nil
    MasterLoot.currentRoll = itemIndex

    -- Announce to raid
    local msg = ">> Rolling for: " .. (item.link or item.name) .. " — /roll now! (" .. MasterLoot.rollDuration .. "s)"
    SendChatMessage(msg, "RAID_WARNING")
    addon:Print(msg)

    -- Sync: notify raid members (ML only)
    if MasterLoot.isML then
        MasterLoot:SendThrottledMessage("ROLL_START|" .. itemIndex)
    end

    -- Start countdown timer
    MasterLoot.rollTimer = MasterLoot:CreateTimer(itemIndex)

    if LootyUI and LootyUI.Refresh then
        LootyUI:Refresh()
    end
end

-- ---- End Roll (manual) ----

function MasterLoot:EndRoll(itemIndex)
    local item = MasterLoot.items[itemIndex]
    if not item or not item.rolling then return end

    item.rolling = false
    item.rollStart = nil
    MasterLoot.currentRoll = nil
    MasterLoot.rollTimer = nil

    -- Determine winner
    local winner, winValue = MasterLoot:GetWinner(item)
    item.winner = winner

    if winner then
        local announceMsg = ">> " .. winner .. " wins " .. (item.link or item.name) .. " with " .. winValue .. "!"
        SendChatMessage(announceMsg, "RAID_WARNING")
        addon:Print(announceMsg)
    else
        addon:Print("No rolls for " .. (item.link or item.name))
    end

    -- Sync: notify raid members (ML only)
    if MasterLoot.isML then
        MasterLoot:SendThrottledMessage("ROLL_END|" .. itemIndex .. "|" .. (winner or "none"))
    end

    if LootyUI and LootyUI.Refresh then
        LootyUI:Refresh()
    end
end

-- ---- Timer ----

function MasterLoot:CreateTimer(itemIndex)
    local timer = CreateFrame("Frame")
    timer.itemIndex = itemIndex
    timer.elapsed = 0
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

-- ---- Record Roll ----

function MasterLoot:RecordRoll(playerName, value, itemName)
    if not MasterLoot.active then return end
    if not MasterLoot.currentRoll then return end

    local item = MasterLoot.items[MasterLoot.currentRoll]
    if not item or not item.rolling then return end

    -- Validate item name match (fuzzy — just check if item name is in the message)
    if itemName and item.name and not (itemName:find(item.name, 1, true) or item.name:find(itemName, 1, true)) then
        -- Don't reject outright — in Master Loot, /roll doesn't include item name
        -- so we just associate with current roll
    end

    -- Check for duplicate (cheating detection)
    if item.rolls[playerName] then
        item.rerolls[playerName] = { value = value, time = GetTime() }
        if addon.db and addon.db.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[LOOTY ML]|r REROLL detected: " .. playerName .. " rolled " .. value .. " (first: " .. item.rolls[playerName].value .. ")")
        end
        return
    end

    -- Record the roll
    item.rolls[playerName] = { value = value, time = GetTime() }

    if addon.db and addon.db.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[LOOTY ML]|r Roll recorded: " .. playerName .. " = " .. value .. " on " .. (item.name or "?"))
    end

    if LootyUI and LootyUI.Refresh then
        LootyUI:Refresh()
    end
end

-- ---- Get Winner ----

function MasterLoot:GetWinner(item)
    local bestPlayer = nil
    local bestValue = 0

    for playerName, rollInfo in pairs(item.rolls) do
        if rollInfo.value and rollInfo.value > bestValue then
            bestValue = rollInfo.value
            bestPlayer = playerName
        end
    end

    return bestPlayer, bestValue
end

-- ---- Clear Done Items ----

function MasterLoot:ClearDone()
    local newItems = {}
    for _, item in ipairs(MasterLoot.items) do
        if not item.isDone then
            table.insert(newItems, item)
        end
    end
    MasterLoot.items = newItems

    if LootyUI and LootyUI.Refresh then
        LootyUI:Refresh()
    end
end

-- ---- Toggle Item Done ----

function MasterLoot:ToggleDone(itemIndex)
    local item = MasterLoot.items[itemIndex]
    if not item then return end

    item.isDone = not item.isDone

    -- Sync: notify raid members (ML only)
    if MasterLoot.isML then
        MasterLoot:SendThrottledMessage("ITEM_DONE|" .. itemIndex)
    end

    if LootyUI and LootyUI.Refresh then
        LootyUI:Refresh()
    end
end

-- ---- Cancel Current Roll ----

function MasterLoot:CancelRoll()
    if not MasterLoot.currentRoll then return end
    local item = MasterLoot.items[MasterLoot.currentRoll]
    if not item then return end

    item.rolling = false
    item.rollStart = nil
    MasterLoot.currentRoll = nil
    if MasterLoot.rollTimer then
        MasterLoot.rollTimer:Hide()
        MasterLoot.rollTimer = nil
    end

    if LootyUI and LootyUI.Refresh then
        LootyUI:Refresh()
    end
end

-- ---- Get Items by State ----

function MasterLoot:GetPendingItems()
    local items = {}
    for _, item in ipairs(MasterLoot.items) do
        if not item.isDone then
            table.insert(items, item)
        end
    end
    return items
end

function MasterLoot:GetDoneItems()
    local items = {}
    -- Iterate backwards so most recent done items appear first
    for i = #self.items, 1, -1 do
        if self.items[i].isDone then
            table.insert(items, self.items[i])
        end
    end
    return items
end

-- ---- Get Active Item Count ----

function MasterLoot:GetActiveItemCount()
    local count = 0
    for _, item in ipairs(MasterLoot.items) do
        if not item.isDone then
            count = count + 1
        end
    end
    return count
end

-- ---- Test Data Injection ----

function MasterLoot:InjectTestRolls()
    MasterLoot.active = true
    MasterLoot.isML = true
    MasterLoot.items = {
        {
            slot = 1,
            name = "Spinal Crusher",
            link = "|cffa335ee|Hitem:18815:0:0:0:0:0:0:0:0|h[Spinal Crusher]|h|r",
            texture = "Interface\\Icons\\INV_Mace_36",
            quantity = 1,
            quality = 4,
            rolling = true,
            rollStart = GetTime(),
            isDone = false,
            winner = nil,
            rolls = {
                IronWall   = { value = 45, time = GetTime() },
                TankJoe    = { value = 73, time = GetTime() },
                Buenclima  = { value = 22, time = GetTime() },
                ShadowMaw  = { value = 88, time = GetTime() },
                HealMePlz  = { value = 15, time = GetTime() },
                DPSKing    = { value = 61, time = GetTime() },
                WarriorK   = { value = 94, time = GetTime() },
                MageBob    = { value = 33, time = GetTime() },
            },
            rerolls = {
                DPSKing = { value = 99, time = GetTime() }, -- cheating attempt
            },
        },
        {
            slot = 2,
            name = "Staff of the Shadowflame",
            link = "|cffa335ee|Hitem:23243:0:0:0:0:0:0:0:0|h[Staff of the Shadowflame]|h|r",
            texture = "Interface\\Icons\\INV_Staff_13",
            quantity = 1,
            quality = 4,
            rolling = false,
            rollStart = nil,
            isDone = false,
            winner = nil,
            rolls = {},
            rerolls = {},
        },
        {
            slot = 3,
            name = "Ring of the Eternal",
            link = "|cff0070dd|Hitem:22734:0:0:0:0:0:0:0:0|h[Ring of the Eternal]|h|r",
            texture = "Interface\\Icons\\INV_Jewelry_Ring_15",
            quantity = 1,
            quality = 3,
            rolling = false,
            rollStart = nil,
            isDone = true, -- Already done
            winner = "HealMePlz",
            rolls = {
                HealMePlz  = { value = 87, time = GetTime() },
                ShadowMaw  = { value = 34, time = GetTime() },
                MageBob    = { value = 65, time = GetTime() },
            },
            rerolls = {},
        },
    }
    MasterLoot.currentRoll = 1

    addon:Print("Master Loot test data injected — 2 pending, 1 done.")

    if LootyUI and LootyUI.SwitchTab then
        LootyUI:SwitchTab("master")
    end
    if LootyUI and LootyUI.Refresh then
        LootyUI:Refresh()
    end
end

-- ---- Inject Remote Test Data (simulate receiving items from ML) ----

function MasterLoot:InjectRemoteTest()
    -- Simulate remote mode with test items
    self.remoteMode = true
    self.remoteML = "TestMaster"

    self.remoteItems = {
        [1] = {
            index = 1,
            slot = 1,
            name = "Spinal Crusher",
            link = "|cffa335ee|Hitem:18815:0:0:0:0:0:0:0|h[Spinal Crusher]|h|r",
            texture = "Interface\\Icons\\INV_Mace_36",
            quantity = 1,
            quality = 4,
            rolling = true,
            rollStart = GetTime(),
            isDone = false,
            winner = nil,
            rolls = {
                IronWall   = { value = 45, time = GetTime() },
                TankJoe    = { value = 73, time = GetTime() },
                Buenclima  = { value = 22, time = GetTime() },
                ShadowMaw  = { value = 88, time = GetTime() },
                HealMePlz  = { value = 15, time = GetTime() },
                DPSKing    = { value = 61, time = GetTime() },
                WarriorK   = { value = 94, time = GetTime() },
                MageBob    = { value = 33, time = GetTime() },
            },
            rerolls = {
                DPSKing = { value = 99, time = GetTime() }, -- cheating attempt
            },
        },
        [2] = {
            index = 2,
            slot = 2,
            name = "Staff of the Shadowflame",
            link = "|cffa335ee|Hitem:23243:0:0:0:0:0:0:0|h[Staff of the Shadowflame]|h|r",
            texture = "Interface\\Icons\\INV_Staff_13",
            quantity = 1,
            quality = 4,
            rolling = false,
            rollStart = nil,
            isDone = false,
            winner = nil,
            rolls = {},
            rerolls = {},
        },
        [3] = {
            index = 3,
            slot = 3,
            name = "Ring of the Eternal",
            link = "|cff0070dd|Hitem:22734:0:0:0:0:0:0:0|h[Ring of the Eternal]|h|r",
            texture = "Interface\\Icons\\INV_Jewelry_Ring_15",
            quantity = 1,
            quality = 3,
            rolling = false,
            rollStart = nil,
            isDone = true, -- Already done
            winner = "HealMePlz",
            rolls = {
                HealMePlz  = { value = 87, time = GetTime() },
                ShadowMaw  = { value = 34, time = GetTime() },
                MageBob    = { value = 65, time = GetTime() },
            },
            rerolls = {},
        },
    }

    addon:Print("Remote test data injected — 2 pending, 1 done. ML: TestMaster")

    if LootyUI and LootyUI.SwitchTab then
        LootyUI:SwitchTab("master")
    end
    if LootyUI and LootyUI.Refresh then
        LootyUI:Refresh()
    end
end
