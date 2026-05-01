-- Looty UI Frame
-- Main window, scroll system, tab bar, and the Refresh/UpdateTimers loop.
-- Delegates tab content rendering to GroupLootUI and MasterLootUI.
-- No domain logic. No direct reads of GroupLoot/MasterLoot state.

local addon = Looty

local UI = {}
LootyUI  = UI

-- Currently active tab
local currentTab = "grouplot"

-- ============================================================
-- ---- Create ----
-- ============================================================

function UI:Create()
    if LootyFrame then return LootyFrame end

    local W = LOOTY_DEFAULT_WIDTH
    local H = LOOTY_DEFAULT_HEIGHT
    local TH = LOOTY_TAB_BAR_HEIGHT
    local CM = LOOTY_CONTENT_MARGIN
    local SW = LOOTY_SCROLL_WIDTH

    local frame = CreateFrame("Frame", "LootyFrame", UIParent)
    frame:SetSize(W, H)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -200)
    frame:SetClampedToScreen(true)
    frame:SetToplevel(true)
    frame:Hide()

    -- Background
    local bg = LootyColorTex(frame, "BACKGROUND", 0.08, 0.08, 0.08, 1.0)
    bg:SetAllPoints(frame)

    -- Top accent line
    local topLine = LootyColorTex(frame, "BORDER", 0.2, 0.2, 0.2, 0.8)
    topLine:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, 0)
    topLine:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    topLine:SetHeight(1)

    -- ---- Scroll area ----
    local scrollFrame = CreateFrame("ScrollFrame", "LootyScroll", frame)
    scrollFrame:SetPoint("TOPLEFT",     frame, "TOPLEFT",     CM, -(TH + 1))
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(CM + SW + 2), CM)
    frame.scrollFrame = scrollFrame

    local content = CreateFrame("Frame", "LootyContent", scrollFrame)
    content:SetWidth(W - CM * 2 - SW - 2)
    content:SetHeight(20)
    scrollFrame:SetScrollChild(content)
    frame.content = content

    -- ---- Scrollbar ----
    local scrollBar = CreateFrame("Frame", nil, frame)
    scrollBar:SetWidth(SW)
    scrollBar:SetPoint("TOPRIGHT",    frame, "TOPRIGHT",    -CM, -(TH + 1))
    scrollBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -CM, CM)
    frame.scrollBar = scrollBar

    local track = LootyColorTex(scrollBar, "BACKGROUND", 0.06, 0.06, 0.06, 0.8)
    track:SetAllPoints(scrollBar)

    local thumb = CreateFrame("Button", nil, scrollBar)
    thumb:SetWidth(SW - 4)
    thumb:SetPoint("LEFT", scrollBar, "LEFT", 2, 0)
    thumb:SetHeight(40)
    thumb:EnableMouse(true)
    thumb:RegisterForDrag("LeftButton")

    local thumbBg = LootyColorTex(thumb, "ARTWORK", 0.22, 0.22, 0.22, 0.9)
    thumbBg:SetAllPoints(thumb)

    local thumbOffset = 0
    thumb:SetScript("OnDragStart", function()
        local _, thumbTop = thumb:GetCenter()
        local sbTop = scrollBar:GetTop()
        if not sbTop then sbTop = scrollBar:GetParent():GetTop() - TH end
        thumbOffset = thumbTop - sbTop
        thumb.isDragging = true
    end)
    thumb:SetScript("OnDragStop", function() thumb.isDragging = false end)
    thumb:SetScript("OnUpdate", function()
        if not thumb.isDragging then return end
        local mouseY = GetCursorPosition() / (scrollBar:GetEffectiveScale() or 1)
        local sbTop  = scrollBar:GetTop()
        local sbBot  = scrollBar:GetBottom()
        if not sbTop or not sbBot then return end
        local trackH  = sbTop - sbBot - thumb:GetHeight()
        if trackH <= 0 then return end
        local newTop  = math.max(sbTop, math.min(sbBot + thumb:GetHeight(), mouseY + thumbOffset))
        local offset  = (sbTop - newTop) / trackH
        local maxOff  = math.max(0, content:GetHeight() - scrollFrame:GetHeight())
        scrollFrame:SetVerticalScroll(offset * maxOff)
    end)
    scrollBar.thumb = thumb

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur    = self:GetVerticalScroll()
        local maxOff = math.max(0, content:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxOff, cur - delta * 30)))
    end)
    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        scrollFrame:SetVerticalScroll(offset)
        UI:UpdateThumb()
    end)

    -- ---- Tab bar ----
    local tabBar = CreateFrame("Frame", nil, frame)
    tabBar:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, 0)
    tabBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    tabBar:SetHeight(TH)

    local tabBarBg = LootyColorTex(tabBar, "BACKGROUND", 0.11, 0.11, 0.11, 1.0)
    tabBarBg:SetAllPoints(tabBar)
    local tabSep = LootyColorTex(tabBar, "BORDER", 0.2, 0.2, 0.2, 0.6)
    tabSep:SetPoint("BOTTOMLEFT",  tabBar, "BOTTOMLEFT",  0, 0)
    tabSep:SetPoint("BOTTOMRIGHT", tabBar, "BOTTOMRIGHT", 0, 0)
    tabSep:SetHeight(1)

    -- Helper to create a tab button
    local function MakeTab(parent, label, w, anchorLeft, anchorOffset, onClick)
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(w, TH - 2)
        btn:SetPoint("LEFT", anchorLeft, anchorOffset == 0 and "LEFT" or "RIGHT",
            anchorOffset, 0)
        btn:EnableMouse(true)
        btn:SetScript("OnClick", onClick)

        local indicator = LootyColorTex(btn, "BORDER", 0.12, 0.12, 0.12, 0.0)
        indicator:SetPoint("BOTTOMLEFT",  btn, "BOTTOMLEFT",  0, 0)
        indicator:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
        indicator:SetHeight(2)
        btn.indicator = indicator

        local hover = LootyColorTex(btn, "HIGHLIGHT", 0.25, 0.25, 0.25, 0.3)
        hover:SetAllPoints(btn)
        hover:Hide()
        btn.hoverBg = hover
        btn:SetScript("OnEnter", function()
            if currentTab ~= btn._tabID then hover:Show() end
        end)
        btn:SetScript("OnLeave", function() hover:Hide() end)

        local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        txt:SetPoint("CENTER", btn, "CENTER", 0, 0)
        txt:SetText(label)
        btn.text = txt

        return btn
    end

    frame.tabs = {}

    local glTab = MakeTab(tabBar, "Group: 0", 95, tabBar, 6, function() UI:SwitchTab("grouplot") end)
    glTab._tabID = "grouplot"
    frame.tabs.grouplot = glTab

    local mlTab = MakeTab(tabBar, "Master: 0", 85, glTab, 0, function() UI:SwitchTab("master") end)
    mlTab._tabID = "master"
    frame.tabs.master = mlTab

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, 1)
    closeBtn:SetSize(24, 24)

    -- ---- Drag ----
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetMovable(true)
    frame:SetScript("OnDragStart", function(self)
        if not addon.db.locked then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    -- ---- Resize grip ----
    frame:SetResizable(true)
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    grip:EnableMouse(true)
    grip:RegisterForDrag("LeftButton")

    local gripIcon = grip:CreateTexture(nil, "OVERLAY")
    gripIcon:SetSize(14, 14)
    gripIcon:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -2, 2)
    gripIcon:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    grip:SetScript("OnDragStart", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local fw = math.max(LOOTY_MIN_WIDTH, frame:GetWidth())
        local fh = math.max(LOOTY_MIN_HEIGHT, frame:GetHeight())
        frame:SetSize(fw, fh)
        content:SetWidth(fw - CM * 2 - SW - 2)
        UI:Refresh()
    end)
    frame.grip = grip

    -- ---- Timer loop ----
    frame:SetScript("OnUpdate", function(self, elapsed)
        self._elapsed = (self._elapsed or 0) + elapsed
        if self._elapsed >= 0.25 then
            self._elapsed = 0
            UI:UpdateTimers()
        end
    end)

    LootyFrame = frame
    UI:SwitchTab("grouplot")
    return frame
end

-- ============================================================
-- ---- Tab switching ----
-- ============================================================

function UI:SwitchTab(tab)
    currentTab = tab
    local frame = LootyFrame
    if not frame then return end

    local function activate(t)
        t.indicator:SetVertexColor(0.35, 0.35, 0.35, 1.0)
        t.text:SetTextColor(0.85, 0.85, 0.85)
    end
    local function deactivate(t)
        t.indicator:SetVertexColor(0.12, 0.12, 0.12, 0.0)
        t.text:SetTextColor(0.4, 0.4, 0.4)
    end

    if tab == "grouplot" then
        activate(frame.tabs.grouplot)
        deactivate(frame.tabs.master)
    else
        deactivate(frame.tabs.grouplot)
        activate(frame.tabs.master)
    end

    if frame.scrollFrame then frame.scrollFrame:SetVerticalScroll(0) end
    UI:Refresh()
end

-- Expose currentTab for other modules that need to know (e.g. timer skipping)
function UI:GetCurrentTab() return currentTab end

-- ============================================================
-- ---- Refresh ----
-- ============================================================

function UI:Refresh()
    local frame = LootyFrame
    if not frame or not frame.content then return end

    local content      = frame.content
    local contentWidth = frame:GetWidth() - LOOTY_CONTENT_MARGIN * 2 - LOOTY_SCROLL_WIDTH - 2
    content:SetWidth(contentWidth)

    -- Clear all children and regions
    for _, child in ipairs({ content:GetChildren() }) do
        child:Hide(); child:ClearAllPoints()
    end
    for _, region in ipairs({ content:GetRegions() }) do
        region:Hide()
    end

    local finalY
    if currentTab == "grouplot" then
        finalY = RefreshGroupLootTab(content, frame)
    else
        finalY = RefreshMasterLootTab(content, frame)
    end

    -- Content height
    content:SetHeight(math.max(-finalY + LOOTY_CONTENT_MARGIN, 20))

    -- Scrollbar thumb
    local sf = frame.scrollFrame
    if sf and frame.scrollBar then
        local cH   = content:GetHeight()
        local vH   = sf:GetHeight()
        if cH > vH then
            frame.scrollBar:Show()
            frame.scrollBar.thumb:Show()
            UI:UpdateThumb()
        else
            frame.scrollBar.thumb:Hide()
            sf:SetVerticalScroll(0)
        end
    end

    UI:UpdateTabCounts()
end

-- ============================================================
-- ---- Scrollbar thumb ----
-- ============================================================

function UI:UpdateThumb()
    local frame = LootyFrame
    if not frame then return end
    local sf    = frame.scrollFrame
    local sb    = frame.scrollBar
    if not sf or not sb then return end

    local thumb   = sb.thumb
    local cH      = sf:GetScrollChild():GetHeight()
    local vH      = sf:GetHeight()
    local maxScrl = math.max(1, cH - vH)
    local pct     = sf:GetVerticalScroll() / maxScrl
    local trackH  = sb:GetHeight()
    local thumbH  = math.max(20, math.min(trackH, vH / cH * trackH))
    thumb:SetHeight(thumbH)
    thumb:SetPoint("TOP", sb, "TOP", 0, -(pct * (trackH - thumbH)))
end

-- ============================================================
-- ---- Tab count labels ----
-- ============================================================

function UI:UpdateTabCounts()
    local frame = LootyFrame
    if not frame then return end

    local gl = LootyGroupLoot
    if gl and frame.tabs.grouplot then
        local total = #gl:GetAllActiveRolls() + #gl:GetCompletedRolls()
        frame.tabs.grouplot.text:SetText("Group: " .. total)
    end

    local ml = LootyMasterLoot
    if ml and frame.tabs.master then
        frame.tabs.master.text:SetText("Master: " .. ml:GetActiveItemCount())
    end
end

-- ============================================================
-- ---- Timer updates ----
-- ============================================================

function UI:UpdateTimers()
    local frame = LootyFrame
    if not frame or not frame:IsShown() then return end
    local content = frame.content

    if currentTab == "grouplot" then
        UpdateGroupLootTimers(content)
    elseif currentTab == "master" then
        UpdateMasterLootTimers(content)
    end
end

-- Called from MasterLoot.CreateTimer callback
function UI:UpdateMasterLootTimer(itemKey, remaining)
    LootyUpdateMasterLootTimer(itemKey, remaining)
end

-- ============================================================
-- ---- Misc ----
-- ============================================================

function UI:UpdateMovable()
    local frame = LootyFrame
    if not frame then return end
    frame:SetMovable(not addon.db.locked)
    frame:SetResizable(not addon.db.locked)
    if frame.grip then frame.grip:EnableMouse(not addon.db.locked) end
end

-- Called by GroupLoot:FinalizeRoll to clean up accordion state
function UI:ClearExpandedState(rollID)
    ClearGroupLootExpandedState(rollID)
end
