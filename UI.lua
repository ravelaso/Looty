-- Looty UI
-- Clean dark theme with custom scrollbar and tabs.
-- All graphics APIs compatible with WOTLK 3.3.5.
-- NO SetColorTexture, NO SetResizeBounds, NO BackdropTemplate.

local addon = Looty
local L = Looty_L

local UI = {}
LootyUI = UI

-- Constants
local TAB_BAR_HEIGHT = 24
local MIN_WIDTH = 350
local MIN_HEIGHT = 150
local DEFAULT_WIDTH = 400
local DEFAULT_HEIGHT = 280
local ICON_SIZE = 36
local ROLL_ICON_SIZE = 18
local CONTENT_MARGIN = 4
local PANEL_PADDING = 8
local SCROLL_BAR_WIDTH = 14

-- Item quality colors (WoW standard)
local QUALITY_COLORS = {
    [0] = { r = 0.62, g = 0.62, b = 0.62 },  -- Poor (grey)
    [1] = { r = 1.00, g = 1.00, b = 1.00 },  -- Common (white)
    [2] = { r = 0.12, g = 1.00, b = 0.00 },  -- Uncommon (green)
    [3] = { r = 0.00, g = 0.44, b = 0.87 },  -- Rare (blue)
    [4] = { r = 0.64, g = 0.21, b = 0.93 },  -- Epic (purple)
    [5] = { r = 1.00, g = 0.50, b = 0.00 },  -- Legendary (orange)
}

local WHITE_TEX = "Interface\\Buttons\\WHITE8X8"

local ROLL_SECTIONS = { "need", "greed", "disenchant", "pass" }
local currentTab = "active"
local expandedSections = {} -- rollID → sectionType (persists across refresh)

-- Section colors: consistent across active and history
local SECTION_COLORS = {
    need       = { 0.80, 0.80, 0.80 },  -- White (neutral)
    greed      = { 1.00, 0.85, 0.20 },  -- Yellow (gold coins)
    disenchant = { 0.70, 0.50, 1.00 },  -- Purple (enchantment)
    pass       = { 0.50, 0.50, 0.50 },  -- Gray (faded out)
}

-- Winner highlight: green (matches ">> Winner:" label)
local WINNER_BG   = { 0.12, 0.60, 0.12, 0.30 }
local WINNER_TEXT = { 0.20, 1.00, 0.20 }

-- ---- Determine winner: highest roll, priority need > greed > DE ----
local function DetermineWinner(rolls)
    local sections = { "need", "greed", "disenchant" }
    for _, sectionType in ipairs(sections) do
        local bestPlayer = nil
        local bestValue = 0
        for playerName, rollInfo in pairs(rolls) do
            local rType = type(rollInfo) == "table" and rollInfo.type or rollInfo
            local rValue = type(rollInfo) == "table" and rollInfo.value or nil
            if rType == sectionType and rValue and rValue > bestValue then
                bestValue = rValue
                bestPlayer = playerName
            end
        end
        if bestPlayer then
            return bestPlayer, bestValue, sectionType
        end
    end
    return nil, nil, nil
end

-- ---- Helper: get roll info from data (handles old string + new table format) ----
local function GetRollInfo(rollInfo)
    if type(rollInfo) == "table" then
        return rollInfo.type, rollInfo.value
    end
    return rollInfo, nil
end

-- ---- Helper: solid color texture (3.3.5 compatible) ----
local function ColorTexture(parent, layer, r, g, b, a)
    local tex = parent:CreateTexture(nil, layer)
    tex:SetTexture(WHITE_TEX)
    tex:SetVertexColor(r, g, b, a or 1)
    return tex
end

-- ---- Helper: gradient texture (3.3.5 compatible) ----
local function GradientTexture(parent, layer, orientation, r1,g1,b1,a1, r2,g2,b2,a2)
    local tex = parent:CreateTexture(nil, layer)
    tex:SetTexture(WHITE_TEX)
    tex:SetGradientAlpha(orientation, r1, g1, b1, a1, r2, g2, b2, a2)
    return tex
end

-- ---- Create the main window ----

function UI:Create()
    if LootyFrame then
        return LootyFrame
    end

    local frame = CreateFrame("Frame", "LootyFrame", UIParent)
    frame:SetSize(DEFAULT_WIDTH, DEFAULT_HEIGHT)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -200)
    frame:SetClampedToScreen(true)
    frame:SetToplevel(true)
    frame:Hide() -- Hidden until first START_LOOT_ROLL

    -- ---- Background: solid dark grey ----
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetTexture(WHITE_TEX)
    bg:SetVertexColor(0.08, 0.08, 0.08, 1.0)
    frame.bg = bg

    -- ---- Thin top accent line (very subtle) ----
    local topLine = ColorTexture(frame, "BORDER", 0.2, 0.2, 0.2, 0.8)
    topLine:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    topLine:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    topLine:SetHeight(1)

    -- ---- Custom scroll area ----
    -- Created BEFORE tabs so tabs render ON TOP of scroll content.
    -- We build our own scroll setup instead of UIPanelScrollFrameTemplate
    -- to have full control over the scrollbar appearance.

    local scrollFrame = CreateFrame("ScrollFrame", "LootyScroll", frame)
    -- Leave room for custom scrollbar on the right
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", CONTENT_MARGIN, -TAB_BAR_HEIGHT - 1)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -CONTENT_MARGIN - SCROLL_BAR_WIDTH - 2, CONTENT_MARGIN)
    frame.scrollFrame = scrollFrame

    local content = CreateFrame("Frame", "LootyContent", scrollFrame)
    content:SetWidth(DEFAULT_WIDTH - CONTENT_MARGIN * 2 - SCROLL_BAR_WIDTH - 2)
    content:SetHeight(20)
    scrollFrame:SetScrollChild(content)
    frame.content = content

    -- ---- Custom scrollbar ----
    local scrollBar = CreateFrame("Frame", nil, frame)
    scrollBar:SetWidth(SCROLL_BAR_WIDTH)
    scrollBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -CONTENT_MARGIN, -TAB_BAR_HEIGHT - 1)
    scrollBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -CONTENT_MARGIN, CONTENT_MARGIN)
    frame.scrollBar = scrollBar

    -- Scrollbar track (dark background)
    local track = ColorTexture(scrollBar, "BACKGROUND", 0.06, 0.06, 0.06, 0.8)
    track:SetAllPoints(scrollBar)
    scrollBar.track = track

    -- Scrollbar thumb (draggable)
    local thumb = CreateFrame("Button", nil, scrollBar)
    thumb:SetWidth(SCROLL_BAR_WIDTH - 4)
    thumb:SetPoint("LEFT", scrollBar, "LEFT", 2, 0)
    thumb:SetHeight(40)
    thumb:EnableMouse(true)
    thumb:RegisterForDrag("LeftButton")
    thumb:SetMovable(false)

    -- Thumb background
    local thumbBg = ColorTexture(thumb, "ARTWORK", 0.22, 0.22, 0.22, 0.9)
    thumbBg:SetAllPoints(thumb)
    thumb.thumbBg = thumbBg

    -- Thumb hover
    local thumbHover = ColorTexture(thumb, "HIGHLIGHT", 0.3, 0.3, 0.3, 0.5)
    thumbHover:SetAllPoints(thumb)
    thumbHover:Hide()
    thumb.thumbHover = thumbHover

    -- Drag logic (with nil guards for resize edge case)
    local thumbOffset = 0
    thumb:SetScript("OnDragStart", function()
        local _, thumbTop = thumb:GetCenter()
        local sbTop = scrollBar:GetTop()
        if not sbTop then sbTop = scrollBar:GetParent():GetTop() - TAB_BAR_HEIGHT end
        thumbOffset = thumbTop - sbTop
        thumb.isDragging = true
    end)
    thumb:SetScript("OnDragStop", function()
        thumb.isDragging = false
    end)
    thumb:SetScript("OnUpdate", function()
        if not thumb.isDragging then return end
        local mouseY = GetCursorPosition()
        local scale = scrollBar:GetEffectiveScale()
        if not scale then return end
        mouseY = mouseY / scale
        local sbTop = scrollBar:GetTop()
        local sbBottom = scrollBar:GetBottom()
        if not sbTop or not sbBottom then return end
        local trackH = sbTop - sbBottom

        local newTop = math.max(sbTop, math.min(sbBottom + thumb:GetHeight(), mouseY + thumbOffset))
        local trackH = sbTop - sbBottom - thumb:GetHeight()
        if trackH <= 0 then return end
        local offset = (sbTop - newTop) / trackH
        local maxOffset = content:GetHeight() - scrollFrame:GetHeight()
        if maxOffset <= 0 then maxOffset = 0 end
        scrollFrame:SetVerticalScroll(offset * maxOffset)
    end)

    scrollBar.thumb = thumb

    -- Mousewheel scroll on the scroll frame
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = content:GetHeight() - self:GetHeight()
        if maxScroll < 0 then maxScroll = 0 end
        local newScroll = current - delta * 30
        newScroll = math.max(0, math.min(maxScroll, newScroll))
        self:SetVerticalScroll(newScroll)
    end)

    -- Scroll update hook
    local origSetScroll = scrollFrame.SetVerticalScroll
    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        scrollFrame:SetVerticalScroll(offset)
        UI:UpdateThumbPosition()
    end)

    -- ---- Tab bar ----
    -- Created AFTER scroll area so the frame sits ON TOP in Z-order.

    local tabBarOverlay = CreateFrame("Frame", nil, frame)
    tabBarOverlay:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    tabBarOverlay:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    tabBarOverlay:SetHeight(TAB_BAR_HEIGHT)

    -- Tab bar background texture
    local tabBarBg = ColorTexture(tabBarOverlay, "BACKGROUND", 0.11, 0.11, 0.11, 1.0)
    tabBarBg:SetAllPoints(tabBarOverlay)
    -- Separator line at bottom
    local tabSep = ColorTexture(tabBarOverlay, "BORDER", 0.2, 0.2, 0.2, 0.6)
    tabSep:SetPoint("BOTTOMLEFT", tabBarOverlay, "BOTTOMLEFT", 0, 0)
    tabSep:SetPoint("BOTTOMRIGHT", tabBarOverlay, "BOTTOMRIGHT", 0, 0)
    tabSep:SetHeight(1)

    -- ---- Tab buttons (children of tabBarOverlay for Z-order) ----
    frame.tabs = {}

    -- Active tab
    local activeTab = CreateFrame("Button", nil, tabBarOverlay)
    activeTab:SetSize(85, TAB_BAR_HEIGHT - 2)
    activeTab:SetPoint("LEFT", tabBarOverlay, "LEFT", 6, 0)
    activeTab:EnableMouse(true)
    activeTab:SetScript("OnClick", function() UI:SwitchTab("active") end)
    activeTab:SetScript("OnEnter", function()
        if currentTab ~= "active" then activeTab.hoverBg:Show() end
    end)
    activeTab:SetScript("OnLeave", function() activeTab.hoverBg:Hide() end)

    -- Active tab indicator line (bottom)
    local activeIndicator = ColorTexture(activeTab, "BORDER", 0.35, 0.35, 0.35, 1.0)
    activeIndicator:SetPoint("BOTTOMLEFT", activeTab, "BOTTOMLEFT", 0, 0)
    activeIndicator:SetPoint("BOTTOMRIGHT", activeTab, "BOTTOMRIGHT", 0, 0)
    activeIndicator:SetHeight(2)
    activeTab.indicator = activeIndicator

    -- Hover background
    local activeHover = ColorTexture(activeTab, "HIGHLIGHT", 0.25, 0.25, 0.25, 0.3)
    activeHover:SetAllPoints(activeTab)
    activeHover:Hide()
    activeTab.hoverBg = activeHover

    local activeText = activeTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    activeText:SetPoint("CENTER", activeTab, "CENTER", 0, 0)
    activeText:SetText("Active: 0")
    activeTab.text = activeText

    frame.tabs.active = activeTab

    -- History tab
    local historyTab = CreateFrame("Button", nil, tabBarOverlay)
    historyTab:SetSize(75, TAB_BAR_HEIGHT - 2)
    historyTab:SetPoint("LEFT", activeTab, "RIGHT", 0, 0)
    historyTab:EnableMouse(true)
    historyTab:SetScript("OnClick", function() UI:SwitchTab("history") end)
    historyTab:SetScript("OnEnter", function()
        if currentTab ~= "history" then historyTab.hoverBg:Show() end
    end)
    historyTab:SetScript("OnLeave", function() historyTab.hoverBg:Hide() end)

    local historyIndicator = ColorTexture(historyTab, "BORDER", 0.12, 0.12, 0.12, 0.0)
    historyIndicator:SetPoint("BOTTOMLEFT", historyTab, "BOTTOMLEFT", 0, 0)
    historyIndicator:SetPoint("BOTTOMRIGHT", historyTab, "BOTTOMRIGHT", 0, 0)
    historyIndicator:SetHeight(2)
    historyTab.indicator = historyIndicator

    local historyHover = ColorTexture(historyTab, "HIGHLIGHT", 0.25, 0.25, 0.25, 0.3)
    historyHover:SetAllPoints(historyTab)
    historyHover:Hide()
    historyTab.hoverBg = historyHover

    local historyText = historyTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    historyText:SetPoint("CENTER", historyTab, "CENTER", 0, 0)
    historyText:SetText("History")
    historyTab.text = historyText

    frame.tabs.history = historyTab

    -- Close button (child of frame, NOT tabBarOverlay, so Hide() closes everything).
    -- Created AFTER tabs for correct Z-order on top.
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, 1)
    closeBtn:SetSize(24, 24)

    -- ---- Dragging the frame ----
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetMovable(true)
    frame:SetScript("OnDragStart", function(self)
        if not addon.db.locked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)

    -- ---- Resizing ----
    frame:SetResizable(true)

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    grip:EnableMouse(true)
    grip:RegisterForDrag("LeftButton")
    grip:SetMovable(false)
    local gripIcon = grip:CreateTexture(nil, "OVERLAY")
    gripIcon:SetSize(14, 14)
    gripIcon:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -2, 2)
    gripIcon:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnDragStart", function()
        frame:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local w = frame:GetWidth()
        local h = frame:GetHeight()
        if w < MIN_WIDTH then frame:SetWidth(MIN_WIDTH); w = MIN_WIDTH end
        if h < MIN_HEIGHT then frame:SetHeight(MIN_HEIGHT); h = MIN_HEIGHT end
        content:SetWidth(w - CONTENT_MARGIN * 2 - SCROLL_BAR_WIDTH - 2)
        frame.content = content
        scrollBar:SetHeight(frame:GetHeight() - TAB_BAR_HEIGHT - 1 - CONTENT_MARGIN)
        UI:Refresh()
    end)
    frame.grip = grip

    -- ---- Timer update loop ----
    frame:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = (self.elapsed or 0) + elapsed
        if self.elapsed >= 0.25 then
            self.elapsed = 0
            UI:UpdateTimers()
        end
    end)
    frame.elapsed = 0

    LootyFrame = frame
    UI:SwitchTab("active")
    return frame
end

-- ---- Update scrollbar thumb position ----

function UI:UpdateThumbPosition()
    local frame = LootyFrame
    if not frame then return end
    local scrollFrame = frame.scrollFrame
    local scrollBar = frame.scrollBar
    local thumb = scrollBar.thumb

    if not scrollFrame or not scrollBar or not thumb then return end

    local contentH = scrollFrame:GetScrollChild():GetHeight()
    local viewH = scrollFrame:GetHeight()
    local maxScroll = math.max(1, contentH - viewH)
    local currentScroll = scrollFrame:GetVerticalScroll()
    local pct = currentScroll / maxScroll

    local trackH = scrollBar:GetHeight()
    local thumbH = math.max(20, math.min(trackH, viewH / contentH * trackH))

    thumb:SetHeight(thumbH)

    local maxThumbOffset = trackH - thumbH
    local thumbY = pct * maxThumbOffset
    thumb:SetPoint("TOP", scrollBar, "TOP", 0, -thumbY)
end

-- ---- Tab switching ----

function UI:SwitchTab(tab)
    currentTab = tab
    local frame = LootyFrame
    if not frame then return end

    if tab == "active" then
        frame.tabs.active.indicator:SetVertexColor(0.35, 0.35, 0.35, 1.0)
        frame.tabs.active.text:SetTextColor(0.85, 0.85, 0.85)
        frame.tabs.history.indicator:SetVertexColor(0.12, 0.12, 0.12, 0.0)
        frame.tabs.history.text:SetTextColor(0.4, 0.4, 0.4)
    else
        frame.tabs.active.indicator:SetVertexColor(0.12, 0.12, 0.12, 0.0)
        frame.tabs.active.text:SetTextColor(0.4, 0.4, 0.4)
        frame.tabs.history.indicator:SetVertexColor(0.35, 0.35, 0.35, 1.0)
        frame.tabs.history.text:SetTextColor(0.85, 0.85, 0.85)
    end

    -- Reset scroll position
    if frame.scrollFrame then
        frame.scrollFrame:SetVerticalScroll(0)
    end

    UI:Refresh()
end

-- ---- Build a single roll panel (shared by active and history tabs) ----
-- opts: { isHistory: bool }

local function BuildRollPanel(content, rollData, yOffset, opts)
    opts = opts or {}
    local isHistory = opts.isHistory or false

    -- DEBUG: dump roll data
    if addon and addon.db and addon.db.debug then
        local dump = "rolls={"
        for pn, info in pairs(rollData.rolls or {}) do
            local v = type(info) == "table" and (info.value or "nil") or info
            dump = dump .. pn .. ":" .. v .. ","
        end
        dump = dump .. "}"
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[LOOTY UI]|r " .. rollData.name .. " | " .. dump .. " | hist=" .. tostring(isHistory))
    end

    local panel = CreateFrame("Frame", nil, content)
    local contentWidth = content:GetWidth()
    panel:SetWidth(contentWidth)

    -- Style configuration (consistent across active and history)
    local iconH      = isHistory and 28 or (ICON_SIZE - 4)
    local lineH      = 14
    local nameFont   = isHistory and "GameFontNormalSmall" or "GameFontNormal"
    local qColor     = QUALITY_COLORS[rollData.quality] or QUALITY_COLORS[2]
    local panelBgA   = isHistory and 0.3 or 0.6

    -- -- Panel background
    local panelBg = ColorTexture(panel, "BACKGROUND", 0.12, 0.12, 0.12, panelBgA)
    panelBg:SetAllPoints(panel)

    -- Panel border (all 4 sides, subtle)
    local borderColor = { 0.20, 0.20, 0.20 }
    local borderThick = 1
    local panelBorderTop = ColorTexture(panel, "BORDER", borderColor[1], borderColor[2], borderColor[3], 0.6)
    panelBorderTop:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    panelBorderTop:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    panelBorderTop:SetHeight(borderThick)

    local panelBorderLeft = ColorTexture(panel, "BORDER", borderColor[1], borderColor[2], borderColor[3], 0.4)
    panelBorderLeft:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    panelBorderLeft:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
    panelBorderLeft:SetWidth(borderThick)

    local panelBorderRight = ColorTexture(panel, "BORDER", borderColor[1], borderColor[2], borderColor[3], 0.4)
    panelBorderRight:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    panelBorderRight:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    panelBorderRight:SetWidth(borderThick)

    local panelBorderBottom = ColorTexture(panel, "BORDER", borderColor[1], borderColor[2], borderColor[3], 0.3)
    panelBorderBottom:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
    panelBorderBottom:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    panelBorderBottom:SetHeight(borderThick)

    -- -- Item header: icon + name
    local icon = panel:CreateTexture(nil, "ARTWORK")
    icon:SetSize(iconH, iconH)
    icon:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_PADDING, -PANEL_PADDING)
    icon:SetTexture(rollData.texture or "Interface\\Icons\\INV_Misc_QuestionMark")

    -- Quality border (consistent alpha)
    local iconBorder = ColorTexture(panel, "BORDER", qColor.r, qColor.g, qColor.b, 0.5)
    iconBorder:SetSize(iconH + 2, iconH + 2)
    iconBorder:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)

    -- Item name (full brightness always)
    local name = panel:CreateFontString(nil, "OVERLAY", nameFont)
    name:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    name:SetPoint("RIGHT", panel, "RIGHT", -PANEL_PADDING, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(true)
    local displayName = rollData.name
    if rollData.count and rollData.count > 1 then
        displayName = displayName .. " (x" .. rollData.count .. ")"
    end
    name:SetText(displayName)
    name:SetTextColor(qColor.r, qColor.g, qColor.b)

    -- -- Timer bar (active only, hidden for completed/history)
    local timerRowY = -PANEL_PADDING - iconH - 6
    local timerBarH = 3
    local timerBg, timerBar, timerText

    if not isHistory and not rollData.completed then
        timerBg = ColorTexture(panel, "BACKGROUND", 0.1, 0.1, 0.1, 0.8)
        timerBg:SetHeight(timerBarH)
        timerBg:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_PADDING, timerRowY)
        timerBg:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PANEL_PADDING, timerRowY)

        timerBar = ColorTexture(panel, "ARTWORK", 0.4, 0.4, 0.4, 0.8)
        timerBar:SetHeight(timerBarH)
        timerBar:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_PADDING, timerRowY)

        timerText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        timerText:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PANEL_PADDING, timerRowY - 2)
        timerText:SetJustifyH("RIGHT")
        timerText:SetText(string.format("%d:%02d", math.floor(rollData.duration / 60), math.floor(rollData.duration % 60)))
    end

    -- -- Winner banner
    local rollY = timerRowY - timerBarH - 6
    local winnerPlayer, winValue, winType = DetermineWinner(rollData.rolls)

    if winnerPlayer then
        local winTypeLabel = L.ROLL_LABELS[winType] or winType
        local winText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        winText:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_PADDING, rollY)
        winText:SetText(">> Winner: " .. winnerPlayer .. " (" .. winTypeLabel .. ": " .. winValue .. ")")
        winText:SetTextColor(0.3, 1.0, 0.3)
        rollY = rollY - lineH - 2
    end

    -- ---- Accordion tabs + player list ----
    -- Group rolls by type
    local rollsByType = { need = {}, greed = {}, disenchant = {}, pass = {} }
    for playerName, rollInfo in pairs(rollData.rolls) do
        local rType = GetRollInfo(rollInfo)
        if rollsByType[rType] then
            table.insert(rollsByType[rType], { name = playerName, value = type(rollInfo) == "table" and rollInfo.value or nil })
        end
    end
    -- Sort: by value desc (highest first), then name
    for _, rt in ipairs(ROLL_SECTIONS) do
        table.sort(rollsByType[rt], function(a, b)
            local va = a.value or -1
            local vb = b.value or -1
            if va ~= vb then return va > vb end
            return a.name < b.name
        end)
    end

    -- Track expanded section: default to winner's type
    -- If winner is nil or has no entries, all closed
    local defaultExpanded = winType
    if defaultExpanded and #rollsByType[defaultExpanded] == 0 then
        defaultExpanded = nil
    end

    -- Accordion constants
    local ACC_TAB_HEIGHT = 20
    local ACC_TAB_GAP = 4

    -- Accordion tab bar row
    local tabBarY = rollY
    local tabBarBg = ColorTexture(panel, "BACKGROUND", 0.08, 0.08, 0.08, 0.5)
    tabBarBg:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, tabBarY)
    tabBarBg:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, tabBarY)
    tabBarBg:SetHeight(ACC_TAB_HEIGHT)

    local tabSep = ColorTexture(panel, "BORDER", 0.18, 0.18, 0.18, 0.4)
    tabSep:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, tabBarY - ACC_TAB_HEIGHT)
    tabSep:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, tabBarY - ACC_TAB_HEIGHT)
    tabSep:SetHeight(1)

    -- Create tab buttons
    local tabWidth = (contentWidth - ACC_TAB_GAP * 2) / 4
    local accordionTabs = {}
    for i, rt in ipairs(ROLL_SECTIONS) do
        local count = #rollsByType[rt]
        if count > 0 or rt ~= "pass" then  -- Always show non-pass, show pass only if has entries
            local tab = CreateFrame("Button", nil, panel)
            local tabX = ACC_TAB_GAP + (i - 1) * tabWidth
            tab:SetSize(tabWidth - ACC_TAB_GAP, ACC_TAB_HEIGHT - 2)
            tab:SetPoint("TOPLEFT", panel, "TOPLEFT", tabX, tabBarY - 1)
            tab:EnableMouse(true)

            -- Tab background (dark by default)
            local tabBg = ColorTexture(tab, "BACKGROUND", 0.08, 0.08, 0.08, 0.0)
            tabBg:SetAllPoints(tab)
            tab.tabBg = tabBg

            -- Icon (no history dimming — consistent colors everywhere)
            local tIcon = tab:CreateTexture(nil, "ARTWORK")
            tIcon:SetSize(14, 14)
            tIcon:SetPoint("LEFT", tab, "LEFT", 3, 0)
            tIcon:SetTexture(L.ROLL_ICONS[rt] or L.ROLL_ICONS.pass)

            -- Count text
            local tText = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            tText:SetPoint("LEFT", tIcon, "RIGHT", 3, 0)
            tText:SetText(count)

            -- Color by type (consistent constants)
            local tabColor = SECTION_COLORS[rt]
            tText:SetTextColor(tabColor[1], tabColor[2], tabColor[3])

            accordionTabs[rt] = tab
        end
    end

    -- Expanded section (player list) — created as a subframe for toggle
    local sectionFrame = CreateFrame("Frame", nil, panel)
    sectionFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, tabBarY - ACC_TAB_HEIGHT)
    sectionFrame:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, tabBarY - ACC_TAB_HEIGHT)
    sectionFrame:Hide()
    panel._accordionSection = sectionFrame
    panel._accordionTabs = accordionTabs
    panel._rollsByType = rollsByType

    -- Helper: build player list for a section
    local function buildPlayerList(sectionType)
        local entries = rollsByType[sectionType]
        local sectionColor = SECTION_COLORS[sectionType]

        -- Clear previous
        for _, child in ipairs({ sectionFrame:GetChildren() }) do
            child:Hide(); child:ClearAllPoints()
        end
        for _, child in ipairs({ sectionFrame:GetRegions() }) do
            child:Hide()
        end

        ColorTexture(sectionFrame, "BACKGROUND", 0.06, 0.06, 0.06, 0.5):SetAllPoints(sectionFrame)

        local listY = -4
        local playerRowH = 16
        for _, entry in ipairs(entries) do
            local isWinner = (entry.name == winnerPlayer)

            -- Row background (green highlight for winner)
            local rowBg = ColorTexture(sectionFrame, "BACKGROUND",
                isWinner and WINNER_BG[1] or 0.12,
                isWinner and WINNER_BG[2] or 0.12,
                isWinner and WINNER_BG[3] or 0.12,
                isWinner and WINNER_BG[4] or 0.0)
            rowBg:SetPoint("TOPLEFT", sectionFrame, "TOPLEFT", 0, listY)
            rowBg:SetPoint("TOPRIGHT", sectionFrame, "TOPRIGHT", 0, listY)
            rowBg:SetHeight(playerRowH)

            -- Player icon (no history dimming)
            local pIcon = sectionFrame:CreateTexture(nil, "ARTWORK")
            pIcon:SetSize(14, 14)
            pIcon:SetPoint("LEFT", sectionFrame, "LEFT", 8, 0)
            pIcon:SetPoint("TOP", rowBg, "TOP", 0, 0)
            pIcon:SetTexture(L.ROLL_ICONS[sectionType] or L.ROLL_ICONS.pass)

            -- Player name (green text for winner, section color for others)
            local pName = sectionFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            pName:SetPoint("LEFT", pIcon, "RIGHT", 4, 0)
            pName:SetText(entry.value and (entry.name .. " (" .. entry.value .. ")") or entry.name)
            if isWinner then
                pName:SetTextColor(WINNER_TEXT[1], WINNER_TEXT[2], WINNER_TEXT[3])
            else
                pName:SetTextColor(sectionColor[1], sectionColor[2], sectionColor[3])
            end
            listY = listY - playerRowH - 1
        end

        local sectionH = -listY + 4
        sectionFrame:SetHeight(sectionH)
        return sectionH
    end

    -- Helper: highlight active tab
    local function highlightTab(sectionType)
        local secColor = SECTION_COLORS[sectionType]
        for rt, tab in pairs(accordionTabs) do
            if rt == sectionType then
                tab.tabBg:SetVertexColor(secColor[1] * 0.15, secColor[2] * 0.15, secColor[3] * 0.15, 0.8)
            else
                tab.tabBg:SetVertexColor(0.08, 0.08, 0.08, 0.0)
            end
        end
    end

    -- Helper: expand a section
    local function expandSection(sectionType)
        panel._expandedType = sectionType
        expandedSections[rollData.rollID] = sectionType
        buildPlayerList(sectionType)
        sectionFrame:Show()
        highlightTab(sectionType)
    end

    -- Helper: collapse all sections
    local function collapseSection()
        panel._expandedType = nil
        expandedSections[rollData.rollID] = nil
        sectionFrame:Hide()
        for _, tab in pairs(accordionTabs) do
            tab.tabBg:SetVertexColor(0.08, 0.08, 0.08, 0.0)
        end
    end

    -- Click handlers
    local function toggleSection(sectionType)
        local isCurrentlyExpanded = sectionFrame:IsShown() and panel._expandedType == sectionType
        if isCurrentlyExpanded then
            collapseSection()
        else
            expandSection(sectionType)
        end
        UI:Refresh()
    end

    for rt, tab in pairs(accordionTabs) do
        tab:SetScript("OnClick", function() toggleSection(rt) end)
        tab:SetScript("OnEnter", function()
            if panel._expandedType ~= rt then
                tab.tabBg:SetVertexColor(0.15, 0.15, 0.15, 0.5)
            end
        end)
        tab:SetScript("OnLeave", function()
            if panel._expandedType ~= rt then
                tab.tabBg:SetVertexColor(0.08, 0.08, 0.08, 0.0)
            end
        end)
    end

    -- Restore state from module-level storage, or auto-expand winner
    local savedState = expandedSections[rollData.rollID]
    if savedState and accordionTabs[savedState] then
        expandSection(savedState)
    elseif defaultExpanded then
        expandSection(defaultExpanded)
    end

    -- Calculate total height: header + winner + accordion bar + expanded section + padding
    local expandedH = sectionFrame:IsShown() and sectionFrame:GetHeight() or 0
    local totalH = PANEL_PADDING * 2 + iconH + 6 + lineH + 2 + ACC_TAB_HEIGHT + expandedH
    panel:SetHeight(totalH)

    -- Store for timer updates (active panels only)
    if not isHistory and timerBar then
        panel.rollID = rollData.rollID
        panel.duration = rollData.duration
        panel.startTime = rollData.startTime
        panel.timerBar = timerBar
        panel.timerBg = timerBg
        panel.timerText = timerText
    end

    panel:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOffset)
    panel:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOffset)

    return panel, totalH
end

-- ---- Update tab counts (always updates both tabs) ----

function UI:UpdateTabCounts()
    local frame = LootyFrame
    if not frame then return end

    local activeCount = #addon:GetAllActiveRolls()
    local historyCount = #addon:GetCompletedRolls()

    if frame.tabs.active and frame.tabs.active.text then
        frame.tabs.active.text:SetText("Active: " .. activeCount)
    end
    if frame.tabs.history and frame.tabs.history.text then
        frame.tabs.history.text:SetText("History (" .. historyCount .. ")")
    end
end

-- ---- Clear accordion expanded state for a rollID (called when roll moves to history) ----

function UI:ClearExpandedState(rollID)
    expandedSections[rollID] = nil
end

-- ---- Refresh the entire UI ----

function UI:Refresh()
    local frame = LootyFrame
    if not frame or not frame.content then return end

    local content = frame.content
    local contentWidth = frame:GetWidth() - CONTENT_MARGIN * 2 - SCROLL_BAR_WIDTH - 2

    -- DEBUG: dump state
    if addon and addon.db and addon.db.debug then
        local ar = addon:GetAllActiveRolls()
        local cr = addon:GetCompletedRolls()
        local activeIds = ""
        for _, r in ipairs(ar) do activeIds = activeIds .. r.rollID .. "(" .. r.name .. ")," end
        local compIds = ""
        for _, r in ipairs(cr) do compIds = compIds .. r.rollID .. "(" .. r.name .. ")," end
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[LOOTY UI]|r Refresh: tab=" .. currentTab .. " active=" .. #ar .. " [" .. activeIds .. "] history=" .. #cr .. " [" .. compIds .. "]")
    end

    -- Clear all children
    for _, child in ipairs({ content:GetChildren() }) do
        child:Hide()
        child:ClearAllPoints()
    end

    -- Clear textures
    for _, child in ipairs({ content:GetRegions() }) do
        child:Hide()
    end

    local yOffset = -CONTENT_MARGIN

    if currentTab == "active" then
        local activeRolls = addon:GetAllActiveRolls()
        for i, rollData in ipairs(activeRolls) do
            local panel, panelH = BuildRollPanel(content, rollData, yOffset, { isHistory = false })
            yOffset = yOffset - panelH - 6
        end

        if #activeRolls == 0 then
            local empty = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            empty:SetPoint("TOP", content, "TOP", 0, -40)
            empty:SetText("No active rolls")
            empty:SetTextColor(0.35, 0.35, 0.35)
            yOffset = yOffset - 50
        end

        frame.tabs.active.text:SetText("Active: " .. #activeRolls)

    elseif currentTab == "history" then
        local completedRolls = addon:GetCompletedRolls()
        for i, rollData in ipairs(completedRolls) do
            local entry, entryH = BuildRollPanel(content, rollData, yOffset, { isHistory = true })
            yOffset = yOffset - entryH - 4
        end

        if #completedRolls == 0 then
            local empty = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            empty:SetPoint("TOP", content, "TOP", 0, -40)
            empty:SetText("No completed rolls yet")
            empty:SetTextColor(0.35, 0.35, 0.35)
            yOffset = yOffset - 50
        end

        frame.tabs.history.text:SetText("History (" .. #completedRolls .. ")")
    end

    -- Always update both tab counts
    UI:UpdateTabCounts()

    -- Update content dimensions
    content:SetWidth(contentWidth)
    content:SetHeight(math.max(-yOffset + CONTENT_MARGIN, 20))

    -- Show/hide scrollbar thumb
    local scrollFrame = frame.scrollFrame
    if scrollFrame and frame.scrollBar then
        local contentH = content:GetHeight()
        local viewH = scrollFrame:GetHeight()
        if contentH > viewH then
            frame.scrollBar:Show()
            frame.scrollBar.thumb:Show()
            UI:UpdateThumbPosition()
        else
            frame.scrollBar.thumb:Hide()
            scrollFrame:SetVerticalScroll(0)
        end
    end
end

-- ---- Update timer bars ----

function UI:UpdateTimers()
    local frame = LootyFrame
    if not frame or not frame:IsShown() then return end
    if currentTab ~= "active" then return end

    local content = frame.content
    for _, child in ipairs({ content:GetChildren() }) do
        if child.rollID and child.timerBar and child.timerBar:IsShown() then
            local elapsed = GetTime() - child.startTime
            local remaining = math.max(0, child.duration - elapsed)
            local pct = remaining / child.duration

            local bgWidth = child.timerBg:GetWidth()
            child.timerBar:SetWidth(bgWidth * pct)

            if pct < 0.25 then
                child.timerBar:SetVertexColor(0.9, 0.2, 0.15, 0.8)
            elseif pct < 0.5 then
                child.timerBar:SetVertexColor(0.9, 0.7, 0.1, 0.8)
            else
                child.timerBar:SetVertexColor(0.4, 0.4, 0.4, 0.8)
            end

            local mins = math.floor(remaining / 60)
            local secs = math.floor(remaining % 60)
            if child.timerText then
                child.timerText:SetText(string.format("%d:%02d", mins, secs))
            end
        end
    end
end

-- ---- Update movable/resizable state ----

function UI:UpdateMovable()
    local frame = LootyFrame
    if not frame then return end
    frame:SetMovable(not addon.db.locked)
    frame:SetResizable(not addon.db.locked)
    if frame.grip then
        frame.grip:EnableMouse(not addon.db.locked)
    end
end
