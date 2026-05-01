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

        for _, child in ipairs({ secFrame:GetChildren() })  do child:Hide(); child:ClearAllPoints() end
        for _, child in ipairs({ secFrame:GetRegions() })   do child:Hide() end

        LootyColorTex(secFrame, "BACKGROUND", 0.06, 0.06, 0.06, 0.5):SetAllPoints(secFrame)

        local ly   = -4
        local rowH = 16
        for _, entry in ipairs(entries) do
            local isWin = (entry.name == winnerPlayer)

            local rowBg = LootyColorTex(secFrame, "BACKGROUND",
                isWin and LOOTY_WINNER_BG[1] or 0.12,
                isWin and LOOTY_WINNER_BG[2] or 0.12,
                isWin and LOOTY_WINNER_BG[3] or 0.12,
                isWin and LOOTY_WINNER_BG[4] or 0.0)
            rowBg:SetPoint("TOPLEFT",  secFrame, "TOPLEFT",  0, ly)
            rowBg:SetPoint("TOPRIGHT", secFrame, "TOPRIGHT", 0, ly)
            rowBg:SetHeight(rowH)

            local cIcon = secFrame:CreateTexture(nil, "ARTWORK")
            cIcon:SetSize(14, 14)
            cIcon:SetPoint("LEFT", secFrame, "LEFT", 2, 0)
            cIcon:SetPoint("TOP",  rowBg,    "TOP",  0, 0)
            LootyApplyClassIcon(cIcon, entry.name)

            local rIcon = secFrame:CreateTexture(nil, "ARTWORK")
            rIcon:SetSize(14, 14)
            rIcon:SetPoint("LEFT", cIcon, "RIGHT", 2, 0)
            rIcon:SetPoint("TOP",  rowBg, "TOP",   0, 0)
            rIcon:SetTexture(L.ROLL_ICONS[sectionType] or L.ROLL_ICONS.pass)

            local pName = secFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            pName:SetPoint("LEFT", rIcon, "RIGHT", 3, 0)
            pName:SetText(entry.value and (entry.name .. " (" .. entry.value .. ")") or entry.name)
            if isWin then
                pName:SetTextColor(LOOTY_WINNER_TEXT[1], LOOTY_WINNER_TEXT[2], LOOTY_WINNER_TEXT[3])
            else
                pName:SetTextColor(secColor[1], secColor[2], secColor[3])
            end
            ly = ly - rowH - 1
        end

        local h = -ly + 4
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

    panel._accordionSection = secFrame
    panel._accordionTabs    = tabs
    panel._rollsByType      = byType

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

-- Builds a single roll card.
-- opts: { isHistory = bool }
-- Returns: panel frame, total panel height.
function BuildRollPanel(content, rollData, yOffset, opts)
    opts = opts or {}
    local isHistory  = opts.isHistory or false
    local iconH      = isHistory and 28 or (LOOTY_ICON_SIZE - 4)
    local alpha      = isHistory and 0.6 or 1.0
    local contentWidth = content:GetWidth()

    local panel = LootyMakePanel(content, isHistory and 0.3 or 0.6)
    panel:SetWidth(contentWidth)

    -- Item header
    local rollY = LootyMakeItemHeader(panel, rollData, iconH, alpha)

    -- Timer bar (active rolls only)
    local timerBg, timerBar, timerText
    if not isHistory and not rollData.completed then
        local timerH = 3
        timerBg = LootyColorTex(panel, "BACKGROUND", 0.1, 0.1, 0.1, 0.8)
        timerBg:SetHeight(timerH)
        timerBg:SetPoint("TOPLEFT",  panel, "TOPLEFT",  LOOTY_PANEL_PADDING, rollY)
        timerBg:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -LOOTY_PANEL_PADDING, rollY)

        timerBar = LootyColorTex(panel, "ARTWORK", 0.4, 0.4, 0.4, 0.8)
        timerBar:SetHeight(timerH)
        timerBar:SetPoint("TOPLEFT", panel, "TOPLEFT", LOOTY_PANEL_PADDING, rollY)

        timerText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        timerText:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -LOOTY_PANEL_PADDING, rollY - 2)
        timerText:SetJustifyH("RIGHT")
        timerText:SetText(string.format("%d:%02d",
            math.floor(rollData.duration / 60),
            math.floor(rollData.duration % 60)))
        rollY = rollY - timerH - 6
    end

    -- Winner banner
    local winnerPlayer, winValue, winType = rollData:DetermineWinner()
    if winnerPlayer then
        local label = L.ROLL_LABELS[winType] or winType
        local winTxt = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        winTxt:SetPoint("TOPLEFT", panel, "TOPLEFT", LOOTY_PANEL_PADDING, rollY)
        winTxt:SetText(">> Winner: " .. winnerPlayer .. " (" .. label .. ": " .. winValue .. ")")
        winTxt:SetTextColor(0.3, 1.0, 0.3)
        rollY = rollY - 16 - 2
    end

    -- Accordion
    local accH, _ = RenderAccordion(panel, rollData, rollY, contentWidth, isHistory)

    -- Calculate total height
    local expandedH  = panel._accordionSection and panel._accordionSection:IsShown()
                       and panel._accordionSection:GetHeight() or 0
    local totalH = LOOTY_PANEL_PADDING * 2 + iconH + 6
                 + (winnerPlayer and 18 or 0)
                 + (not isHistory and not rollData.completed and (3 + 6) or 0)
                 + 20 + expandedH  -- accordion tabs + section

    panel:SetHeight(totalH)

    -- Store timer refs for live update (active panels)
    if not isHistory and timerBar then
        panel.rollID    = rollData.rollID
        panel.duration  = rollData.duration
        panel.startTime = rollData.startTime
        panel.timerBar  = timerBar
        panel.timerBg   = timerBg
        panel.timerText = timerText
    end

    panel:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, yOffset)
    panel:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOffset)

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

    -- Active rolls
    for _, rollData in ipairs(activeRolls) do
        local _, h = BuildRollPanel(content, rollData, yOffset, { isHistory = false })
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
            local _, h = BuildRollPanel(content, rollData, yOffset, { isHistory = true })
            yOffset = yOffset - h - 4
        end
    end

    -- Empty state
    if #activeRolls == 0 and #completedRolls == 0 then
        local empty = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        empty:SetPoint("TOP", content, "TOP", 0, -40)
        empty:SetText("No rolls yet")
        empty:SetTextColor(0.35, 0.35, 0.35)
        yOffset = yOffset - 50
    end

    -- Update tab count
    if frame and frame.tabs and frame.tabs.grouplot then
        local total = #activeRolls + #completedRolls
        frame.tabs.grouplot.text:SetText("Group: " .. total)
    end

    return yOffset
end

-- ============================================================
-- ---- Timer update (called from UpdateTimers) ----
-- ============================================================

function UpdateGroupLootTimers(content)
    for _, child in ipairs({ content:GetChildren() }) do
        if child.rollID and child.timerBar and child.timerBar:IsShown() then
            local elapsed   = GetTime() - child.startTime
            local remaining = math.max(0, child.duration - elapsed)
            local pct       = remaining / child.duration

            child.timerBar:SetWidth(child.timerBg:GetWidth() * pct)

            if pct < 0.25 then
                child.timerBar:SetVertexColor(0.9, 0.2, 0.15, 0.8)
            elseif pct < 0.5 then
                child.timerBar:SetVertexColor(0.9, 0.7, 0.1, 0.8)
            else
                child.timerBar:SetVertexColor(0.4, 0.4, 0.4, 0.8)
            end

            if child.timerText then
                child.timerText:SetText(string.format("%d:%02d",
                    math.floor(remaining / 60), math.floor(remaining % 60)))
            end
        end
    end
end

-- ---- Clear accordion expanded state (called when roll is finalized)
function ClearGroupLootExpandedState(rollID)
    expandedSections[rollID] = nil
end
