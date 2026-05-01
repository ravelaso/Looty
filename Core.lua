-- Looty Core
-- Pure event bus and addon lifecycle.
-- No domain logic lives here — delegates to GroupLoot and MasterLoot.

local addon = CreateFrame("Frame", "LootyCore", UIParent)
Looty = addon

local DEFAULT_SAVED = {
    windowPos  = { x = nil, y = nil },
    windowSize = { w = nil, h = nil },
    locked     = false,
    debug      = false,
}

addon.db = {}

-- ============================================================
-- ---- Event dispatch ----
-- ============================================================

function addon:OnEvent(event, ...)
    if self[event] then self[event](self, event, ...) end
end
addon:SetScript("OnEvent", addon.OnEvent)

-- ============================================================
-- ---- Lifecycle ----
-- ============================================================

function addon:PLAYER_LOGIN()
    -- Saved variables
    self.db = Looty_SavedVars or {}
    for k, v in pairs(DEFAULT_SAVED) do
        if self.db[k] == nil then self.db[k] = v end
    end

    -- Group Loot events
    self:RegisterEvent("START_LOOT_ROLL")
    self:RegisterEvent("CANCEL_LOOT_ROLL")
    self:RegisterEvent("CHAT_MSG_LOOT")

    -- Master Loot events
    self:RegisterEvent("PARTY_LOOT_METHOD_CHANGED")
    self:RegisterEvent("LOOT_OPENED")
    self:RegisterEvent("LOOT_CLOSED")
    self:RegisterEvent("CHAT_MSG_SYSTEM")

    -- Addon messages (prefix-less in WoW 3.3.5 — RegisterAddonMessagePrefix
    -- was added in 4.1.0; in 3.3.5 CHAT_MSG_ADDON fires unconditionally).
    self:RegisterEvent("CHAT_MSG_ADDON")

    -- Roster changes (class cache + role re-resolution)
    self:RegisterEvent("GROUP_ROSTER_UPDATE")

    -- Build window
    LootyUI:Create()
    LootyRefreshClassCache()

    -- Initialize domain modules
    LootyMasterLoot:Initialize()

    -- Restore window position / size
    if self.db.windowPos.x and self.db.windowPos.y then
        LootyFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT",
            self.db.windowPos.x, self.db.windowPos.y)
    end
    if self.db.windowSize.w and self.db.windowSize.h then
        LootyFrame:SetSize(self.db.windowSize.w, self.db.windowSize.h)
    end

    self:Print("Loaded. Type /looty to toggle the window.")
end

function addon:PLAYER_LOGOUT()
    if LootyFrame then
        local x, y = LootyFrame:GetLeft(), LootyFrame:GetTop()
        if x and y then self.db.windowPos.x = x; self.db.windowPos.y = y end
        local w, h = LootyFrame:GetWidth(), LootyFrame:GetHeight()
        if w and h then self.db.windowSize.w = w; self.db.windowSize.h = h end
    end
    Looty_SavedVars = self.db
end

-- ============================================================
-- ---- Group Loot events → GroupLoot module ----
-- ============================================================

function addon:START_LOOT_ROLL(event, rollID, duration)
    LootyGroupLoot:StartRoll(rollID, duration)
end

function addon:CANCEL_LOOT_ROLL(event, rollID)
    LootyGroupLoot:MarkCompleted(rollID)
end

function addon:CHAT_MSG_LOOT(event, message)
    LootyParser:ProcessMessage(message)
end

-- ============================================================
-- ---- Master Loot events → MasterLoot module ----
-- ============================================================

function addon:PARTY_LOOT_METHOD_CHANGED()
    LootyMasterLoot:OnLootMethodChanged()
end

function addon:LOOT_OPENED()
    LootyMasterLoot:OnLootOpened()
end

function addon:LOOT_CLOSED()
    LootyMasterLoot:OnLootClosed()
end

function addon:CHAT_MSG_SYSTEM(event, message)
    LootyParser:ProcessSystemMessage(message)
end

function addon:CHAT_MSG_ADDON(event, prefix, message, distribution, sender)
    if self.db and self.db.debug then
        addon:Print(string.format("[ADDON] prefix=%s dist=%s sender=%s msg=%.40s",
            tostring(prefix), tostring(distribution), tostring(sender), tostring(message)))
    end
    if prefix ~= "LOOTY" then return end
    LootyMasterLoot:OnAddonMessage(prefix, message, distribution, sender)
end

function addon:GROUP_ROSTER_UPDATE()
    LootyRefreshClassCache()
    LootyMasterLoot:ResolveRole()
    if LootyUI and LootyUI.Refresh then LootyUI:Refresh() end
end

-- ============================================================
-- ---- Utility ----
-- ============================================================

function addon:Print(...)
    DEFAULT_CHAT_FRAME:AddMessage("|cff7B2D8E[Looty]|r " .. strjoin(" ", ...))
end

-- ============================================================
-- ---- Slash commands ----
-- ============================================================

SLASH_LOOTY1 = "/looty"
SLASH_LOOTY2 = "/lr"

SlashCmdList["LOOTY"] = function(msg)
    msg = msg:lower():trim()

    if msg == "" then
        if not LootyFrame then
            addon:Print("Window not ready — check /framestack for errors")
            return
        end
        if LootyFrame:IsShown() then LootyFrame:Hide() else LootyFrame:Show() end

    elseif msg == "lock" then
        addon.db.locked = not addon.db.locked
        addon:Print("Window " .. (addon.db.locked and "locked" or "unlocked"))
        LootyUI:UpdateMovable()

    elseif msg == "clear" then
        LootyGroupLoot:ClearHistory()

    elseif msg == "test" then
        LootyGroupLoot:InjectTestRolls()

    elseif msg == "mtest" then
        LootyMasterLoot:InjectTestRolls()

    elseif msg == "mtestremote" then
        LootyMasterLoot:InjectRemoteTest()

    elseif msg == "debug" then
        addon.db.debug = not addon.db.debug
        addon:Print("Debug " .. (addon.db.debug and "ON" or "OFF"))

    else
        addon:Print("Commands:")
        addon:Print("  /looty           — Toggle window")
        addon:Print("  /looty lock      — Toggle window lock")
        addon:Print("  /looty clear     — Clear group loot history")
        addon:Print("  /looty test      — Inject mock Group Loot rolls")
        addon:Print("  /looty mtest     — Inject mock Master Loot (ML view)")
        addon:Print("  /looty mtestremote — Inject mock Master Loot (Raider view)")
        addon:Print("  /looty debug     — Toggle debug logging")
    end
end

addon:RegisterEvent("PLAYER_LOGIN")
