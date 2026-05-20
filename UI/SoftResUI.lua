-- Looty SoftResUI
-- Renders the SoftRes tab: import controls (ML only), data summary, item list.

local ICON_H = 18
local PANEL_MARGIN = 6

local function GetItemName(id)
    local name = GetItemInfo(id)
    if name then return name end
    return "(id: " .. id .. ")"
end

local function GetItemIconPath(id)
    return GetItemIcon(id) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function GetItemQuality(id)
    local _, _, rarity = GetItemInfo(id)
    return rarity or 1
end

function RefreshSoftResTab(content, frame)
    local yOffset = -LOOTY_CONTENT_MARGIN
    local cw = content:GetWidth()
    local isML = LootyMasterLoot and LootyMasterLoot:IsML()
    local imported = LootySoftRes and LootySoftRes:IsImported()

    -- ============================================================
    -- Import section (ML only)
    -- ============================================================
    if isML then
        local inpTitle, th1 = LootyMakeLabel(content, "SoftRes Gargul String",
            0.7, 0.7, 0.7, yOffset)
        yOffset = yOffset - th1 - 4

        -- Edit box
        local eb = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
        eb:SetSize(cw - LOOTY_CONTENT_MARGIN * 2, 22)
        eb:SetPoint("TOPLEFT", content, "TOPLEFT", LOOTY_CONTENT_MARGIN, yOffset)
        eb:SetAutoFocus(false)
        eb:SetMultiLine(false)
        eb:SetTextInsets(4, 4, 0, 0)
        local ebBg = LootyColorTex(eb, "BACKGROUND", 0.10, 0.10, 0.10, 0.8)
        ebBg:SetAllPoints(eb)
        eb:SetScript("OnEscapePressed", function() eb:ClearFocus() end)
        eb:Show()
        yOffset = yOffset - 26

        -- Button row
        local layout = LootyHLayout(6)
        local btnY = yOffset

        local importBtn = LootyMakeButton(content, "Import", 70, 22,
            { 0.05, 0.25, 0.15 }, { 0.10, 0.40, 0.25 }, { 0.3, 1.0, 0.4 },
            function()
                local str = eb:GetText()
                if not str or str == "" then
                    Looty:Print("Paste a Gargul export string first.")
                    return
                end
                local ok, err = LootySoftRes.Import(str)
                if ok then
                    Looty:Print("SoftRes import successful.")
                    LootyUI:Refresh()
                else
                    Looty:Print("SoftRes import failed: " .. tostring(err))
                end
            end)
        layout:Place(importBtn, content, LOOTY_CONTENT_MARGIN, btnY)
        importBtn:Show()

        local clearBtn = LootyMakeButton(content, "Clear", 70, 22,
            { 0.25, 0.10, 0.10 }, { 0.40, 0.15, 0.15 }, { 1.0, 0.4, 0.4 },
            function()
                LootySoftRes.Clear()
                Looty:Print("SoftRes data cleared.")
                eb:SetText("")
                LootyUI:Refresh()
            end)
        layout:Place(clearBtn, content, 0, btnY)
        clearBtn:Show()

        yOffset = yOffset - 22 - 8
    end

    -- ============================================================
    -- Status / Empty State
    -- ============================================================
    if not imported then
        local msg = isML
            and "Paste a Gargul export string above and click Import."
            or "Waiting for MasterLooter to import SoftRes data..."
        local emptyLbl, eh = LootyMakeLabel(content, msg,
            0.5, 0.5, 0.5, yOffset, nil, "GameFontHighlightSmall")
        yOffset = yOffset - eh - 4
        return yOffset
    end

    -- ============================================================
    -- Summary header
    -- ============================================================
    local data = LootySoftRes.data
    local meta = data.metadata
    local numItems = 0
    for _ in pairs(LootySoftRes.byItem) do numItems = numItems + 1 end
    local numPlayers = 0
    for _ in pairs(LootySoftRes.byPlayer) do numPlayers = numPlayers + 1 end

    local instanceList = ""
    if meta.instances then
        instanceList = tconcat(meta.instances, ", ")
    end

    local summaryStr = string.format("ID: %s | %s | %d items, %d players",
        meta.id or "?", instanceList, numItems, numPlayers)
    local sumLabel, sumH = LootyMakeLabel(content, summaryStr,
        0.6, 0.6, 0.6, yOffset)
    yOffset = yOffset - sumH - 2

    if meta.note and meta.note ~= "" then
        local noteLbl, noteH = LootyMakeLabel(content, "Note: " .. meta.note,
            0.4, 0.4, 0.4, yOffset, nil, "GameFontHighlightSmall")
        yOffset = yOffset - noteH - 2
    end

    yOffset = yOffset - LootyMakeSeparator(content, yOffset, 0) - 4

    -- ============================================================
    -- Item list
    -- ============================================================
    local byItem = LootySoftRes.byItem
    local byPlayer = LootySoftRes.byPlayer

    -- Sort items by ID for consistent display
    local sorted = {}
    for id in pairs(byItem) do tinsert(sorted, id) end
    tsort(sorted)

    for _, itemID in ipairs(sorted) do
        local info = byItem[itemID]
        local panel = LootyMakePanel(content, 0.5)
        local pw = cw
        panel:SetWidth(pw)
        panel:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOffset)
        panel:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOffset)
        panel:Show()

        local iy = -PANEL_MARGIN

        -- Item icon
        local icon = panel:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ICON_H, ICON_H)
        icon:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_MARGIN, iy)
        icon:SetTexture(GetItemIconPath(itemID))

        -- Quality border
        local qc = LOOTY_QUALITY_COLORS[GetItemQuality(itemID)] or LOOTY_QUALITY_COLORS[1]
        local qb = LootyColorTex(panel, "BORDER", qc.r, qc.g, qc.b, 0.4)
        qb:SetSize(ICON_H + 2, ICON_H + 2)
        qb:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)

        -- Item name
        local itemName = GetItemName(itemID)
        local nameFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameFS:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        nameFS:SetPoint("RIGHT", panel, "RIGHT", -PANEL_MARGIN, 0)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetText(itemName)

        -- HR badge if any
        local hdrY = iy
        if info.hardReservedFor then
            local hrFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            hrFS:SetPoint("RIGHT", panel, "RIGHT", -PANEL_MARGIN, hdrY)
            hrFS:SetText("|cffff4444HR: " .. info.hardReservedFor .. "|r")
            hdrY = hdrY - 14
        end

        iy = iy - (ICON_H + 4)

        -- Player list
        -- Sort players by name
        local players = {}
        for _, name in ipairs(info.players) do
            local pInfo = byPlayer[strlower(name)]
            tinsert(players, {
                name = name,
                class = (pInfo and pInfo.class) or LootyGetPlayerClass(name) or "",
                plusOnes = (pInfo and pInfo.plusOnes) or 0,
                note = (pInfo and pInfo.note) or "",
            })
        end
        tsort(players, function(a, b) return a.name < b.name end)

        for _, p in ipairs(players) do
            local row = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_MARGIN + 2, iy)
            row:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PANEL_MARGIN, iy)
            row:SetJustifyH("LEFT")
            local classLabel = (p.class ~= "") and ("(" .. p.class .. ")") or ""
            local plusLabel = (p.plusOnes > 0) and (" +" .. p.plusOnes) or ""
            local noteSuffix = (p.note ~= "") and (" — " .. p.note) or ""
            row:SetText("  → " .. p.name .. " " .. classLabel .. plusLabel .. noteSuffix)
            row:SetTextColor(0.8, 0.8, 0.8)
            iy = iy - 14
        end

        -- Tooltip on mouseover for the panel
        panel:EnableMouse(true)
        panel:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. itemID .. ":0:0:0:0")
            GameTooltip:Show()
        end)
        panel:SetScript("OnLeave", function() GameTooltip:Hide() end)

        local pH = -iy - PANEL_MARGIN
        panel:SetHeight(pH)
        yOffset = yOffset - pH - 4
    end

    return yOffset
end
