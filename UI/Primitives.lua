-- Looty UI Primitives
-- Shared constants, widget factories, and the class icon system.
-- All UI sub-modules read from this file. No game state here.
-- Compatible with WoW 3.3.5 (no SetColorTexture, no SetResizeBounds, no BackdropTemplate).

-- ============================================================
-- ---- Layout constants ----
-- ============================================================

LOOTY_TAB_BAR_HEIGHT  = 24
LOOTY_MIN_WIDTH       = 350
LOOTY_MIN_HEIGHT      = 150
LOOTY_DEFAULT_WIDTH   = 400
LOOTY_DEFAULT_HEIGHT  = 280
LOOTY_ICON_SIZE       = 36
LOOTY_CONTENT_MARGIN  = 4
LOOTY_PANEL_PADDING   = 8
LOOTY_SCROLL_WIDTH    = 14

-- ============================================================
-- ---- Shared texture reference ----
-- ============================================================

LOOTY_WHITE_TEX = "Interface\\Buttons\\WHITE8X8"

-- ============================================================
-- ---- Item quality colors ----
-- ============================================================

LOOTY_QUALITY_COLORS = {
    [0] = { r = 0.62, g = 0.62, b = 0.62 },  -- Poor    (grey)
    [1] = { r = 1.00, g = 1.00, b = 1.00 },  -- Common  (white)
    [2] = { r = 0.12, g = 1.00, b = 0.00 },  -- Uncommon (green)
    [3] = { r = 0.00, g = 0.44, b = 0.87 },  -- Rare    (blue)
    [4] = { r = 0.64, g = 0.21, b = 0.93 },  -- Epic    (purple)
    [5] = { r = 1.00, g = 0.50, b = 0.00 },  -- Legendary (orange)
}

-- ============================================================
-- ---- Roll section colors ----
-- ============================================================

LOOTY_SECTION_COLORS = {
    need       = { 0.80, 0.80, 0.80 },
    greed      = { 1.00, 0.85, 0.20 },
    disenchant = { 0.70, 0.50, 1.00 },
    pass       = { 0.50, 0.50, 0.50 },
}

LOOTY_WINNER_BG   = { 0.12, 0.60, 0.12, 0.30 }
LOOTY_WINNER_TEXT = { 0.20, 1.00, 0.20 }

-- ============================================================
-- ---- Class icon system ----
-- ============================================================
-- Texture: Interface\WorldStateFrame\ICONS-CLASSES (256×256, 64×64 cells)
-- Layout verified from live WotLK addons:
--   Row 0: Warrior | Mage    | Rogue   | Druid
--   Row 1: Hunter  | Shaman  | Priest  | Warlock
--   Row 2: Paladin | DK      | (empty) | (empty)

local CLASS_ICON_TEX = "Interface\\WorldStateFrame\\ICONS-CLASSES"
local CLASS_TCOORDS  = {
    WARRIOR     = { 0,      0.25,   0,      0.25   },
    MAGE        = { 0.25,   0.5,    0,      0.25   },
    ROGUE       = { 0.5,    0.7656, 0,      0.25   },
    DRUID       = { 0.7656, 1.0,    0,      0.25   },
    HUNTER      = { 0,      0.25,   0.25,   0.5    },
    SHAMAN      = { 0.25,   0.5,    0.25,   0.5    },
    PRIEST      = { 0.5,    0.7656, 0.25,   0.5    },
    WARLOCK     = { 0.7656, 1.0,    0.25,   0.5    },
    PALADIN     = { 0,      0.25,   0.5,    0.7656 },
    DEATHKNIGHT = { 0.25,   0.5,    0.5,    0.7656 },
}

-- Class cache: playerName → classFileName.
-- Persists across refreshes; survives players leaving the raid after rolling.
local classCache = {}

-- Populate the cache from the current raid/party roster.
-- Call on GROUP_ROSTER_UPDATE and at login.
function LootyRefreshClassCache()
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local name, _, _, _, _, cls = GetRaidRosterInfo(i)
            if name and cls then classCache[name] = cls end
        end
    else
        local self = UnitName("player")
        if self then
            local _, cls = UnitClass("player")
            classCache[self] = cls
        end
        for i = 1, GetNumPartyMembers() do
            local unit = "party" .. i
            local n    = UnitName(unit)
            if n then
                local _, cls = UnitClass(unit)
                classCache[n] = cls
            end
        end
    end
end

-- Return the classFileName for playerName, or nil.
function LootyGetPlayerClass(playerName)
    if classCache[playerName] then return classCache[playerName] end

    local classFileName
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local name, _, _, _, _, cls = GetRaidRosterInfo(i)
            if name == playerName then classFileName = cls; break end
        end
    else
        if UnitName("player") == playerName then
            local _, cls = UnitClass("player")
            classFileName = cls
        else
            for i = 1, GetNumPartyMembers() do
                local unit = "party" .. i
                if UnitName(unit) == playerName then
                    local _, cls = UnitClass(unit)
                    classFileName = cls; break
                end
            end
        end
    end

    if classFileName then classCache[playerName] = classFileName end
    return classFileName
end

-- Apply class icon texture coordinates to an existing texture object.
-- Returns true if coordinates were applied, false if class unknown.
function LootyApplyClassIcon(tex, playerName)
    local cls   = LootyGetPlayerClass(playerName)
    local coords = cls and CLASS_TCOORDS[cls]
    if coords then
        tex:SetTexture(CLASS_ICON_TEX)
        tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        return true
    end
    tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    return false
end

-- ============================================================
-- ---- Widget factory functions ----
-- ============================================================

-- Solid color texture (3.3.5-compatible, no SetColorTexture).
function LootyColorTex(parent, layer, r, g, b, a)
    local tex = parent:CreateTexture(nil, layer)
    tex:SetTexture(LOOTY_WHITE_TEX)
    tex:SetVertexColor(r, g, b, a or 1)
    return tex
end

-- Standard panel background + 4-sided border.
-- Returns the panel frame.
function LootyMakePanel(parent, bgAlpha)
    local panel = CreateFrame("Frame", nil, parent)
    local bg = LootyColorTex(panel, "BACKGROUND", 0.12, 0.12, 0.12, bgAlpha or 0.6)
    bg:SetAllPoints(panel)

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

    return panel
end

-- Horizontal separator line (1 px, subtle grey).
-- Returns height consumed (1 px line + margin).
function LootyMakeSeparator(parent, yOffset, margin)
    margin = margin or 4
    local sep = LootyColorTex(parent, "BORDER", 0.25, 0.25, 0.25, 0.4)
    sep:SetPoint("TOPLEFT",  parent, "TOPLEFT",  margin,  yOffset)
    sep:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -margin, yOffset)
    sep:SetHeight(1)
    return 1
end

-- Simple text label anchored TOPLEFT.
-- Returns height consumed.
function LootyMakeLabel(parent, text, r, g, b, yOffset, xOffset, font)
    xOffset = xOffset or LOOTY_PANEL_PADDING
    font    = font or "GameFontNormalSmall"
    local fs = parent:CreateFontString(nil, "OVERLAY", font)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, yOffset)
    fs:SetText(text)
    fs:SetTextColor(r, g, b)
    return fs, 16
end

-- A styled button with a solid colored background, hover highlight, and label.
-- normalColor  = { r, g, b }   base background color
-- hoverColor   = { r, g, b }   hover background color
-- textColor    = { r, g, b }
-- onClick      = function()
-- Returns the button frame.
function LootyMakeButton(parent, label, w, h, normalColor, hoverColor, textColor, onClick)
    h = h or 20
    local nc = normalColor
    local hc = hoverColor

    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(w, h)
    btn:EnableMouse(true)

    local bg = LootyColorTex(btn, "BACKGROUND", nc[1], nc[2], nc[3], 0.8)
    bg:SetAllPoints(btn)

    local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    txt:SetPoint("CENTER", btn, "CENTER", 0, 0)
    txt:SetText(label)
    txt:SetTextColor(textColor[1], textColor[2], textColor[3])

    btn:SetScript("OnEnter", function() bg:SetVertexColor(hc[1], hc[2], hc[3], 0.8) end)
    btn:SetScript("OnLeave", function() bg:SetVertexColor(nc[1], nc[2], nc[3], 0.8) end)
    if onClick then btn:SetScript("OnClick", onClick) end

    return btn
end

-- A greyed-out non-interactive "disabled" button label.
function LootyMakeDisabledButton(parent, label, w, h)
    h = h or 20
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(w, h)
    btn:EnableMouse(false)

    local bg = LootyColorTex(btn, "BACKGROUND", 0.15, 0.15, 0.15, 0.6)
    bg:SetAllPoints(btn)

    local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    txt:SetPoint("CENTER", btn, "CENTER", 0, 0)
    txt:SetText(label)
    txt:SetTextColor(0.4, 0.4, 0.4)

    return btn
end

-- Item header: icon + quality border + name fontstring + tooltip.
-- Anchors icon TOPLEFT inside parent at (PANEL_PADDING, -PANEL_PADDING).
-- Returns yOffset after the header (i.e. the next usable yOffset below the icon).
function LootyMakeItemHeader(parent, item, iconH, alpha)
    alpha    = alpha or 1.0
    local qc = LOOTY_QUALITY_COLORS[item.quality] or LOOTY_QUALITY_COLORS[2]
    local pp = LOOTY_PANEL_PADDING

    -- Icon
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(iconH, iconH)
    icon:SetPoint("TOPLEFT", parent, "TOPLEFT", pp, -pp)
    icon:SetTexture(item.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    icon:SetAlpha(alpha)

    -- Quality border
    local border = LootyColorTex(parent, "BORDER", qc.r, qc.g, qc.b, 0.5 * alpha)
    border:SetSize(iconH + 2, iconH + 2)
    border:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)

    -- Item name
    local displayName = item.link or item.name or "Unknown"
    if item.count and item.count > 1 then
        displayName = displayName .. " (x" .. item.count .. ")"
    elseif item.quantity and item.quantity > 1 then
        displayName = displayName .. " (x" .. item.quantity .. ")"
    end

    local nameFont = (iconH <= 28) and "GameFontNormalSmall" or "GameFontNormal"
    local name = parent:CreateFontString(nil, "OVERLAY", nameFont)
    name:SetPoint("LEFT",  icon,   "RIGHT", 8,   0)
    name:SetPoint("RIGHT", parent, "RIGHT", -pp, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(true)
    name:SetText(displayName)
    name:SetTextColor(qc.r * alpha, qc.g * alpha, qc.b * alpha)

    -- Tooltip + click-to-link
    if item.link then
        parent:EnableMouse(true)
        parent:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(item.link)
            GameTooltip:Show()
        end)
        parent:SetScript("OnLeave", function() GameTooltip:Hide() end)
        parent:SetScript("OnMouseUp", function(_, button)
            SetItemRef(item.link, item.link, button)
        end)
    end

    -- Return the yOffset below the icon row
    return -(pp + iconH + 6)
end
