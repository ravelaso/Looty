-- Looty GroupLootUI
-- Renders the Group Loot tab: BuildRollPanel and RefreshGroupLootTab.
-- Reads from LootyGroupLoot (domain) and LootyLootRoll objects.
-- Uses primitives from UI/Primitives.lua.

-- GroupLootUI references Looty globally at call time (never at load time)
local L = Looty_L

-- ============================================================
-- ---- Constants ----
-- ============================================================

local ROLL_SECTIONS = { "need", "greed", "disenchant", "pass" }

-- Per-panel expanded accordion section: { [rollID] = sectionType }
local expandedSections = {}

-- ============================================================
-- ---- Frame pool ----
-- ============================================================
-- Panels keyed by rollID. Prevents frame accumulation on content.
-- In WoW, frames cannot be destroyed — we hide and reparent them
-- instead of letting them pile up as children of content.

local panelPool = {}  -- { [rollID] = panelFrame }

-- Reset a reused panel: clear all children, regions, and custom fields.
local function ResetPanel(panel)
    for _, child in ipairs({ panel:GetChildren() }) do
        child:Hide(); child:ClearAllPoints()
    end
    for _, region in ipairs({ panel:GetRegions() }) do
        region:Hide()
    end
    panel._glTimerBg   = nil
    panel._glTimerBar  = nil
    panel._glTimerText = nil
    panel._glRollStart = nil
    panel._glDuration  = nil
    panel._glRollID    = nil
    panel._expandedType = nil
    panel:SetScript("OnEnter", nil)
    panel:SetScript("OnLeave", nil)
    panel:SetScript("OnMouseUp", nil)
end

-- Acquire a panel for a rollID. Returns an existing (reset) or new panel.
local function AcquirePanel(rollID, content)
    local panel = panelPool[rollID]
    if panel then
        ResetPanel(panel)
        panel:SetParent(content)
    else
        panel = CreateFrame("Frame", nil, content)
        panelPool[rollID] = panel
    end
    panel:Show()
    return panel
end

-- Release panels not in the current active set.
-- Hides them and removes from content's child hierarchy.
local function ReleaseUnused(activeKeys)
    for rollID, panel in pairs(panelPool) do
        if not activeKeys[rollID] then
            panel:Hide()
            panel:ClearAllPoints()
            panel:SetParent(nil)
        end
    end
end

-- ============================================================
-- ---- Roll panel internals ----
-- ============================================================

-- Render the accordion tab bar + player list for a roll's choices.
-- Returns the total height consumed by the accordion section.
local function RenderAccordion(panel, rollData, rollY, contentWidth, isHistory)
    local pp = LOOTY_PANEL_PADDING

    -- Group by type
    local byType = { need = {}, greed = {}, disenchant = {}, pass = {} }
    for playerName, info in pairs(rollData.rolls) do
        local rType = type(info) == "table" and info.type or info
        local rVal  = type(info) == "table" and info.value or nil
        if byType[rType] then
            table.insert(byType[rType], { name = playerName, value = rVal })
        end
    end
    for _, rt in ipairs(ROLL_SECTIONS) do
        table.sort(byType[rt], function(a, b)
            local va = a.value or -1; local vb = b.value or -1
            if va ~= vb then return va > vb end
            return a.name < b.name
        end)
    end

    local winnerPlayer, _, winType = rollData:DetermineWinner()
    local defaultExpanded = winType
    if defaultExpanded and #byType[defaultExpanded] == 0 then
        defaultExpanded = nil
    end

    local ACC_H   = 20
    local ACC_GAP = 4

    -- Tab bar background
    local tabBarBg = LootyColorTex(panel, "BACKGROUND", 0.08, 0.08, 0.08, 0.5)
    tabBarBg:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, rollY)
    tabBarBg:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, rollY)
    tabBarBg:SetHeight(ACC_H)

    local tabSep = LootyColorTex(panel, "BORDER", 0.18, 0.18, 0.18, 0.4)
    tabSep:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, rollY - ACC_H)
    tabSep:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, rollY - ACC_H)
    tabSep:SetHeight(1)

    -- Section frame (player list, toggled)
    local secFrame = CreateFrame("Frame", nil, panel)
    secFrame:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, rollY - ACC_H)
    secFrame:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, rollY - ACC_H)
    secFrame:Hide()

    local tabWidth = (contentWidth - ACC_GAP * 2) / 4
    local tabs     = {}

    -- Build player list for a section
    local function BuildList(sectionType)
        local entries  = byType[sectionType]
        local secColor = LOOTY_SECTION_COLORS[sectionType]
        local rollIcon = L.ROLL_ICONS[sectionType] or L.ROLL_ICONS.pass

        for _, child in ipairs({ secFrame:GetChildren() })  do child:Hide(); child:ClearAllPoints() end
        for _, child in ipairs({ secFrame:GetRegions() })   do child:Hide() end

        LootyColorTex(secFrame, "BACKGROUND", 0.06, 0.06, 0.06, 0.5):SetAllPoints(secFrame)

        local layout = LootyVLayout(secFrame, -4, 0)
        for _, entry in ipairs(entries) do
            local isWin = (entry.name == winnerPlayer)
            LootyMakePlayerRow(secFrame, entry, isWin, rollIcon, secColor, 1.0, layout)
        end

        local h = -layout.y + 4
        secFrame:SetHeight(h)
        return h
    end

    -- Highlight the active tab
    local function HighlightTab(active)
        for rt, tab in pairs(tabs) do
            local c = LOOTY_SECTION_COLORS[rt]
            if rt == active then
                tab.tabBg:SetVertexColor(c[1] * 0.15, c[2] * 0.15, c[3] * 0.15, 0.8)
            else
                tab.tabBg:SetVertexColor(0.08, 0.08, 0.08, 0.0)
            end
        end
    end

    local function Expand(sectionType)
        panel._expandedType = sectionType
        expandedSections[rollData.rollID] = sectionType
        BuildList(sectionType)
        secFrame:Show()
        HighlightTab(sectionType)
    end

    local function Collapse()
        panel._expandedType = nil
        expandedSections[rollData.rollID] = nil
        secFrame:Hide()
        for _, tab in pairs(tabs) do tab.tabBg:SetVertexColor(0.08, 0.08, 0.08, 0.0) end
    end

    -- Create tab buttons
    for i, rt in ipairs(ROLL_SECTIONS) do
        local count = #byType[rt]
        if count > 0 or rt ~= "pass" then
            local tab = CreateFrame("Button", nil, panel)
            local tx  = ACC_GAP + (i - 1) * tabWidth
            tab:SetSize(tabWidth - ACC_GAP, ACC_H - 2)
            tab:SetPoint("TOPLEFT", panel, "TOPLEFT", tx, rollY - 1)
            tab:EnableMouse(true)

            local tabBg = LootyColorTex(tab, "BACKGROUND", 0.08, 0.08, 0.08, 0.0)
            tabBg:SetAllPoints(tab)
            tab.tabBg = tabBg

            local tIcon = tab:CreateTexture(nil, "ARTWORK")
            tIcon:SetSize(14, 14)
            tIcon:SetPoint("LEFT", tab, "LEFT", 3, 0)
            tIcon:SetTexture(L.ROLL_ICONS[rt] or L.ROLL_ICONS.pass)

            local secColor = LOOTY_SECTION_COLORS[rt]
            local tText = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            tText:SetPoint("LEFT", tIcon, "RIGHT", 3, 0)
            tText:SetText(count)
            tText:SetTextColor(secColor[1], secColor[2], secColor[3])

            tab:SetScript("OnClick", function()
                if secFrame:IsShown() and panel._expandedType == rt then
                    Collapse()
                else
                    Expand(rt)
                end
                LootyUI:Refresh()
            end)
            tab:SetScript("OnEnter", function()
                if panel._expandedType ~= rt then
                    tabBg:SetVertexColor(0.15, 0.15, 0.15, 0.5)
                end
            end)
            tab:SetScript("OnLeave", function()
                if panel._expandedType ~= rt then
                    tabBg:SetVertexColor(0.08, 0.08, 0.08, 0.0)
                end
            end)

            tabs[rt] = tab
        end
    end

    -- Restore or auto-expand winner section
    local saved = expandedSections[rollData.rollID]
    if saved and tabs[saved] then
        Expand(saved)
    elseif defaultExpanded then
        Expand(defaultExpanded)
    end

    local expandedH = secFrame:IsShown() and secFrame:GetHeight() or 0
    return ACC_H + expandedH, secFrame
end

-- ============================================================
-- ---- BuildRollPanel ----
-- ============================================================

-- Builds a single roll card into a pre-acquired panel.
-- opts: { isHistory = bool }
-- Returns: panel frame, total panel height.
function BuildRollPanel(panel, rollData, yOffset, opts)
    opts = opts or {}
    local isHistory    = opts.isHistory or false
    local iconH        = isHistory and 28 or (LOOTY_ICON_SIZE - 4)
    local alpha        = isHistory and 0.6 or 1.0
    local contentWidth = panel:GetParent():GetWidth()

    panel:SetWidth(contentWidth)

    -- Background + border (LootyMakePanel inline — panel is pre-acquired)
    LootyColorTex(panel, "BACKGROUND", 0.12, 0.12, 0.12, isHistory and 0.2 or 0.6):SetAllPoints(panel)
    local function border(pt1, pt2, isH)
        local t = LootyColorTex(panel, "BORDER", 0.20, 0.20, 0.20, 0.5)
        t:SetPoint(pt1, panel, pt1, 0, 0)
        t:SetPoint(pt2, panel, pt2, 0, 0)
        if isH then t:SetHeight(1) else t:SetWidth(1) end
    end
    border("TOPLEFT",    "TOPRIGHT",    true)
    border("BOTTOMLEFT", "BOTTOMRIGHT", true)
    border("TOPLEFT",    "BOTTOMLEFT",  false)
    border("TOPRIGHT",   "BOTTOMRIGHT", false)

    -- Item header — returns y start for the cursor
    local layout = LootyVLayout(panel, LootyMakeItemHeader(panel, rollData, iconH, alpha), 0)

    -- Timer bar (active rolls only)
    if not isHistory and not rollData.completed then
        LootyMakeTimerBar(panel, layout, rollData.duration, rollData.startTime, "_gl", rollData.rollID)
    end

    -- Winner banner
    local winnerPlayer, winValue, winType = rollData:DetermineWinner()
    if winnerPlayer then
        local label  = L.ROLL_LABELS[winType] or winType
        local winTxt = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        winTxt:SetPoint("TOPLEFT",  panel, "TOPLEFT",  LOOTY_PANEL_PADDING,  layout.y)
        winTxt:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -LOOTY_PANEL_PADDING, layout.y)
        winTxt:SetJustifyH("LEFT")
        winTxt:SetWordWrap(true)
        winTxt:SetText(">> Winner: " .. winnerPlayer .. " (" .. label .. ": " .. winValue .. ")")
        winTxt:SetTextColor(0.3, 1.0, 0.3)
        layout:Advance(math.max(16, winTxt:GetHeight()), 2)
    end

    -- Accordion — returns height consumed (tabs + expanded section)
    local accH = RenderAccordion(panel, rollData, layout.y, contentWidth, isHistory)
    layout:Advance(accH)

    -- Total height = distance from panel top (y=0) to cursor end + bottom padding.
    -- layout.y is negative (WoW convention), so -layout.y gives the full depth.
    -- Top padding is already embedded in LootyMakeItemHeader's starting Y.
    local totalH = -layout.y + LOOTY_PANEL_PADDING
    panel:SetHeight(totalH)

    panel:SetPoint("TOPLEFT",  panel:GetParent(), "TOPLEFT",  0, yOffset)
    panel:SetPoint("TOPRIGHT", panel:GetParent(), "TOPRIGHT", 0, yOffset)

    return panel, totalH
end

-- ============================================================
-- ---- RefreshGroupLootTab ----
-- ============================================================

-- Renders the entire GroupLoot tab into content frame.
-- Returns the final yOffset.
function RefreshGroupLootTab(content, frame)
    local pp = LOOTY_PANEL_PADDING
    local yOffset = -LOOTY_CONTENT_MARGIN

    local activeRolls    = LootyGroupLoot:GetAllActiveRolls()
    local completedRolls = LootyGroupLoot:GetCompletedRolls()

    -- Track which panels are currently needed
    local activeKeys = {}

    -- Active rolls
    for _, rollData in ipairs(activeRolls) do
        activeKeys[rollData.rollID] = true
        local panel = AcquirePanel(rollData.rollID, content)
        local _, h = BuildRollPanel(panel, rollData, yOffset, { isHistory = false })
        yOffset = yOffset - h - 6
    end

    -- History section
    if #completedRolls > 0 then
        -- Separator
        local sepY = yOffset - 10
        LootyMakeSeparator(content, sepY, 4)
        yOffset = sepY - 1 - 22  -- 1px separator + margin + button row

        -- Clear History button
        local clearBtn = LootyMakeButton(content, "Clear History", 80, 20,
            { 0.15, 0.15, 0.15 }, { 0.25, 0.25, 0.25 }, { 0.6, 0.6, 0.6 },
            function()
                LootyGroupLoot:ClearHistory()
            end)
        clearBtn:SetPoint("TOP", content, "TOP", 0, yOffset)
        clearBtn:Show()
        yOffset = yOffset - 24

        -- "Completed (N)" label
        local lbl, lblH = LootyMakeLabel(content,
            "Completed (" .. #completedRolls .. ")", 0.4, 0.4, 0.4, yOffset)
        yOffset = yOffset - lblH

        for _, rollData in ipairs(completedRolls) do
            activeKeys[rollData.rollID] = true
            local panel = AcquirePanel(rollData.rollID, content)
            local _, h = BuildRollPanel(panel, rollData, yOffset, { isHistory = true })
            yOffset = yOffset - h - 4
        end
    end

    -- Empty state — only shown when there are truly no rolls at all.
    if #activeRolls == 0 and #completedRolls == 0 then
        local emptyY = yOffset - 16
        LootyMakeEmptyState(content, "No rolls yet", emptyY)
        yOffset = emptyY - 24
    end

    -- Update tab count
    if frame and frame.tabs and frame.tabs.grouplot then
        local total = #activeRolls + #completedRolls
        frame.tabs.grouplot.text:SetText("Group: " .. total)
    end

    -- Release panels no longer in use
    ReleaseUnused(activeKeys)

    return yOffset
end

-- ============================================================
-- ---- Timer update (called from UpdateTimers) ----
-- ============================================================

function UpdateGroupLootTimers()
    for _, panel in pairs(panelPool) do
        if panel:IsShown() and panel._glTimerBar and panel._glRollStart then
            local elapsed   = GetTime() - panel._glRollStart
            local remaining = math.max(0, panel._glDuration - elapsed)
            local pct       = remaining / panel._glDuration

            panel._glTimerBar:SetWidth(panel._glTimerBg:GetWidth() * pct)

            if pct < 0.25 then
                panel._glTimerBar:SetVertexColor(0.9, 0.2, 0.15, 0.8)
            elseif pct < 0.5 then
                panel._glTimerBar:SetVertexColor(0.9, 0.7, 0.1, 0.8)
            else
                panel._glTimerBar:SetVertexColor(0.4, 0.4, 0.4, 0.8)
            end

            if panel._glTimerText then
                panel._glTimerText:SetText(string.format("%d:%02d",
                    math.floor(remaining / 60), math.floor(remaining % 60)))
            end
        end
    end
end

-- ---- Clear accordion expanded state (called when roll is finalized)
function ClearGroupLootExpandedState(rollID)
    expandedSections[rollID] = nil
end
