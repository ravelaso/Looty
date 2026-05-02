-- Looty Core
-- Pure event bus and addon lifecycle.
-- No domain logic lives here — delegates to GroupLoot and MasterLoot.
-- Core.lua loads LAST in the toc so that all domain and UI modules are
-- already defined when events fire. The Looty global is set here and
-- all other files reference it at call time (inside functions), never
-- at module load time — so load order does not cause nil issues.

local addon = CreateFrame("Frame", "LootyCore", UIParent)
Looty = addon

local DEFAULT_SAVED = {
    windowPos             = { x = nil, y = nil },
    windowSize            = { w = nil, h = nil },
    locked                = false,
    debug                 = false,
    qualityFilter         = 2,  -- Uncommon (green) minimum by default
    syncBlizzardThreshold = false,
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

    -- Restore window position / size.
    -- ClearAllPoints is required before SetPoint — otherwise the new anchor
    -- stacks on top of the default one set inside UI:Create(), and both
    -- constraints fight each other producing a wrong position.
    if self.db.windowPos.x and self.db.windowPos.y then
        LootyFrame:ClearAllPoints()
        LootyFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT",
            self.db.windowPos.x, self.db.windowPos.y)
    end
    if self.db.windowSize.w and self.db.windowSize.h then
        LootyFrame:SetSize(self.db.windowSize.w, self.db.windowSize.h)
    end

    self:Print("Loaded. Type /looty to toggle the window.")
end

-- Persist the current frame geometry into db.
-- Called on both drag/resize stop and PLAYER_LOGOUT so a /reload also saves.
function addon:SaveWindowState()
    if not LootyFrame then return end
    local left = LootyFrame:GetLeft()
    local top  = LootyFrame:GetTop()
    if left and top then
        -- Convert screen coords to UIParent-relative offsets.
        -- GetLeft()  = px from left edge of screen  → direct X offset from TOPLEFT
        -- GetTop()   = px from BOTTOM of screen     → subtract UIParent height to get
        --              the negative Y offset from TOPLEFT that SetPoint expects
        self.db.windowPos.x = left
        self.db.windowPos.y = top - UIParent:GetHeight()
    end
    local w, h = LootyFrame:GetWidth(), LootyFrame:GetHeight()
    if w and h then
        self.db.windowSize.w = w
        self.db.windowSize.h = h
    end
    -- Flush to disk immediately so /reload also persists without needing logout
    Looty_SavedVars = self.db
end

function addon:PLAYER_LOGOUT()
    self:SaveWindowState()
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
addon:RegisterEvent("PLAYER_LOGOUT")
