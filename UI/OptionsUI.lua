-- Looty OptionsUI
-- Renders the Options tab: quality filter selector for Master Loot.
-- Uses primitives from UI/Primitives.lua.

-- OptionsUI references Looty globally at call time (never at load time)

local QUALITY_TIERS = {
    { id = 0, label = "Poor",        color = { 0.62, 0.62, 0.62 } },
    { id = 1, label = "Common",      color = { 1.00, 1.00, 1.00 } },
    { id = 2, label = "Uncommon",    color = { 0.12, 1.00, 0.00 } },
    { id = 3, label = "Rare",        color = { 0.00, 0.44, 0.87 } },
    { id = 4, label = "Epic",        color = { 0.64, 0.21, 0.93 } },
    { id = 5, label = "Legendary",   color = { 1.00, 0.50, 0.00 } },
}

local function GetQualityLabel(quality)
    for _, tier in ipairs(QUALITY_TIERS) do
        if tier.id == quality then return tier.label end
    end
    return "Unknown"
end

-- ============================================================
-- ---- RefreshOptionsTab ----
-- ============================================================

function RefreshOptionsTab(content, frame)
    local yOffset = -LOOTY_CONTENT_MARGIN

    -- Section title
    local title, tH = LootyMakeLabel(content, "Master Loot Filters",
        0.7, 0.7, 0.7, yOffset)
    yOffset = yOffset - tH - 2

    -- ---- Quality Filter Panel ----
    local panel = LootyMakePanel(content, 0.6)
    panel:SetWidth(content:GetWidth())

    local layout = LootyVLayout(panel, -(LOOTY_PANEL_PADDING + 14), 0)

    local filterLabel, flH = LootyMakeLabel(panel, "Minimum item quality to track:",
        0.6, 0.6, 0.6, layout.y)
    layout:Advance(flH, 2)

    -- Current filter display
    local currentFilter = Looty.db and Looty.db.qualityFilter or 2
    local fc = LOOTY_QUALITY_COLORS[currentFilter] or LOOTY_QUALITY_COLORS[2]
    local currentLbl, clH = LootyMakeLabel(panel,
        "Current: " .. GetQualityLabel(currentFilter), fc.r, fc.g, fc.b, layout.y)
    layout:Advance(clH, 6)

    -- Quality tier buttons
    local btnW = (panel:GetWidth() - LOOTY_PANEL_PADDING * 2 - 4 * 4) / 6
    local btnH = 20
    local row = LootyHLayout(4)
    local atY = layout.y - 4

    for _, tier in ipairs(QUALITY_TIERS) do
        local isActive = (tier.id == currentFilter)
        local nc = isActive and { tier.color[1] * 0.4, tier.color[2] * 0.4, tier.color[3] * 0.4 }
                               or { 0.15, 0.15, 0.15 }
        local hc = { tier.color[1] * 0.5, tier.color[2] * 0.5, tier.color[3] * 0.5 }
        local tc = isActive and { tier.color[1], tier.color[2], tier.color[3] }
                              or { 0.5, 0.5, 0.5 }

        local tierLabel = string.sub(tier.label, 1, 3)
        local btn = LootyMakeButton(panel, tierLabel, btnW, btnH, nc, hc, tc,
            function()
                if Looty.db then
                    Looty.db.qualityFilter = tier.id
                    Looty:Print("Quality filter set to " .. GetQualityLabel(tier.id) .. " and above")
                end
                LootyUI:Refresh()
            end)
        row:Place(btn, panel, LOOTY_PANEL_PADDING, atY)
        btn:Show()
    end

    layout:Advance(4 + btnH + LOOTY_PANEL_PADDING)

    -- Info text
    local info, infoH = LootyMakeLabel(panel,
        "Only items of this quality or higher will appear in the Master Loot tab and trigger rolls.",
        0.4, 0.4, 0.4, layout.y - 2, nil, "GameFontHighlightSmall")
    layout:Advance(infoH)

    local totalH = -layout.y + LOOTY_PANEL_PADDING
    panel:SetHeight(totalH)
    panel:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, yOffset)
    panel:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOffset)

    yOffset = yOffset - totalH - 8

    return yOffset
end
