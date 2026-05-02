-- Looty UI Primitives
-- Shared constants, widget factories, and the class icon system.
-- All UI sub-modules read from this file. No game state here.
-- Compatible with WoW 3.3.5 (no SetColorTexture, no SetResizeBounds, no BackdropTemplate).

-- ============================================================
-- ---- Layout constants ----
-- ============================================================

LOOTY_TAB_BAR_HEIGHT  = 24
LOOTY_DEFAULT_WIDTH   = 400
LOOTY_DEFAULT_HEIGHT  = 280
LOOTY_ICON_SIZE       = 36
LOOTY_CONTENT_MARGIN  = 4
LOOTY_PANEL_PADDING   = 8
LOOTY_SCROLL_WIDTH    = 14
LOOTY_MIN_WIDTH       = 290
LOOTY_MIN_HEIGHT      = 280

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

-- Seeds the class cache with fake names for test data injection.
function LootyPreloadTestClass()
    classCache["IronWall"]  = "WARRIOR"
    classCache["TankJoe"]   = "PALADIN"
    classCache["Buenclima"] = "DRUID"
    classCache["ShadowMaw"] = "WARLOCK"
    classCache["HealMePlz"] = "PRIEST"
    classCache["DPSKing"]   = "DEATHKNIGHT"
    classCache["WarriorK"]  = "WARRIOR"
    classCache["MageBob"]   = "MAGE"
end

-- ============================================================
-- ---- Layout cursors ----
-- ============================================================

-- Vertical layout cursor — stacks children top-to-bottom inside a parent frame.
--
-- parent:  the frame being laid out (used to auto-read width)
-- startY:  the Y position to begin from (negative = below top edge, WoW convention)
-- gap:     default pixel gap inserted after every Advance (default 0)
-- width:   override the available width (default: parent:GetWidth())
--
-- c:Advance(h [, gap])
--   Moves the cursor down by h pixels + gap.
--   Returns the Y position BEFORE advancing, so renderers can anchor at the
--   correct spot and still return a height for the caller.
--   Passing h == 0 is a no-op and returns current y unchanged.
--
-- c:Consumed()
--   Returns total pixels consumed from startY to current y.
--   Use this as the single source of truth for panel height calculations.
--
function LootyVLayout(parent, startY, gap, width)
    local c = {
        parent  = parent,
        y       = startY,
        gap     = gap or 0,
        width   = width or (parent and parent:GetWidth()) or 0,
        _start  = startY,
    }

    function c:Advance(h, customGap)
        if h == 0 then return self.y end
        local before = self.y
        self.y = self.y - h - (customGap ~= nil and customGap or self.gap)
        return before
    end

    function c:Consumed()
        return self._start - self.y
    end

    return c
end

-- Horizontal layout cursor — places children left-to-right inside a parent frame.
--
-- gap: default pixel gap between items (default 4)
--
-- c:Place(widget, parent, startX, atY)
--   Anchors widget relative to parent.
--   First widget: anchored TOPLEFT at (startX, atY).
--   Subsequent widgets: anchored LEFT of previous widget's RIGHT + gap.
--
-- c:Reset()
--   Clears chain state so the next Place starts fresh.
--
-- c.width
--   Running total of pixels consumed horizontally (widget widths + gaps).
--
function LootyHLayout(gap)
    local c = { gap = gap or 4, _prev = nil, width = 0 }

    function c:Place(widget, parent, startX, atY)
        if not self._prev then
            widget:SetPoint("TOPLEFT", parent, "TOPLEFT", startX, atY)
        else
            widget:SetPoint("LEFT", self._prev, "RIGHT", self.gap, 0)
            self.width = self.width + self.gap
        end
        self.width = self.width + widget:GetWidth()
        self._prev = widget
    end

    function c:Reset()
        self._prev = nil
        self.width = 0
    end

    return c
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

-- Simple text label anchored TOPLEFT with a right bound so it wraps correctly.
-- Both anchors (TOPLEFT + TOPRIGHT) constrain the width, enabling word wrap.
-- SetWidth() is explicit because anchors alone may not resolve before SetText.
-- SetNonSpaceWrap(true) allows wrapping at any character boundary.
-- GetHeight() is reliable only after SetText with a width constraint in place.
-- Returns: fontstring, height consumed (actual rendered height, min 16).
function LootyMakeLabel(parent, text, r, g, b, yOffset, xOffset, font)
    xOffset = xOffset or LOOTY_PANEL_PADDING
    font    = font or "GameFontNormalSmall"
    local fs = parent:CreateFontString(nil, "OVERLAY", font)
    fs:SetPoint("TOPLEFT",  parent, "TOPLEFT",  xOffset,  yOffset)
    fs:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -xOffset, yOffset)
    fs:SetJustifyH("LEFT")
    fs:SetWidth(parent:GetWidth() - xOffset * 2)
    fs:SetWordWrap(true)
    fs:SetNonSpaceWrap(true)
    fs:SetText(text)
    fs:SetTextColor(r, g, b)
    return fs, math.max(16, fs:GetHeight())
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

-- Full-width toggle button that switches between two modes.
-- checked: current state (boolean)
-- checkedLabel / uncheckedLabel: text shown for each state
-- onClick: function(isChecked)
-- Returns: button frame, buttonHeight
function LootyMakeToggleButton(parent, checked, checkedLabel, uncheckedLabel, onClick, layoutY)
    local label = checked and checkedLabel or uncheckedLabel
    local nc = checked and { 0.05, 0.20, 0.35 } or { 0.15, 0.15, 0.15 }
    local hc = checked and { 0.10, 0.35, 0.55 } or { 0.25, 0.25, 0.25 }
    local tc = checked and { 0.4, 0.75, 1.0 }  or { 0.7, 0.7, 0.7  }

    local togW = parent:GetWidth() - LOOTY_PANEL_PADDING * 2
    local togH = 24
    local btn = LootyMakeButton(parent, label, togW, togH, nc, hc, tc,
        function() onClick(not checked) end)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", LOOTY_PANEL_PADDING, layoutY)
    btn:Show()
    return btn, togH
end

-- Tab button with indicator, hover, and text.
-- getCurrentTab: function() returning the active tab ID string (for hover suppression)
-- Returns: tab frame with .indicator, .text, .hoverBg, ._tabID
function LootyMakeTab(parent, label, w, tabID, anchorRel, anchorPt, anchorOffset, onClick, getCurrentTab)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(w, LOOTY_TAB_BAR_HEIGHT - 2)
    btn:SetPoint("LEFT", anchorRel, anchorPt, anchorOffset, 0)
    btn:EnableMouse(true)
    btn._tabID = tabID
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
        local ct = getCurrentTab and getCurrentTab() or ""
        if ct ~= tabID then btn.hoverBg:Show() end
    end)
    btn:SetScript("OnLeave", function() btn.hoverBg:Hide() end)

    local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    txt:SetPoint("CENTER", btn, "CENTER", 0, 0)
    txt:SetText(label)
    btn.text = txt

    return btn
end

-- Timer bar with background, progress fill, and MM:SS text.
-- Stores refs on panel with prefix for live updates.
--   prefix = "_ml" for MasterLoot, "" for GroupLoot
-- Returns: nothing; advances layout by barH + 4
function LootyMakeTimerBar(panel, layout, duration, startTime, prefix, itemKey)
    if not duration or not startTime then return end
    local barH = 5

    local bg = LootyColorTex(panel, "BACKGROUND", 0.1, 0.1, 0.1, 0.8)
    bg:SetHeight(barH)
    bg:SetPoint("TOPLEFT",  panel, "TOPLEFT",  LOOTY_PANEL_PADDING,  layout.y)
    bg:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -LOOTY_PANEL_PADDING, layout.y)

    local remaining = duration - (GetTime() - startTime)
    remaining = math.max(0, remaining)
    local pct  = remaining / duration
    local barW = (panel:GetWidth() or 300) - LOOTY_PANEL_PADDING * 2

    local bar = LootyColorTex(panel, "ARTWORK", 0.4, 0.4, 0.4, 0.8)
    bar:SetHeight(barH)
    bar:SetWidth(barW * pct)
    bar:SetPoint("TOPLEFT", panel, "TOPLEFT", LOOTY_PANEL_PADDING, layout.y)

    local txt = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    txt:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -LOOTY_PANEL_PADDING, layout.y - 2)
    txt:SetJustifyH("RIGHT")
    txt:SetText(string.format("%d:%02d", math.floor(remaining / 60), math.floor(remaining % 60)))

    panel[prefix .. "TimerBg"]   = bg
    panel[prefix .. "TimerBar"]  = bar
    panel[prefix .. "TimerText"] = txt
    panel[prefix .. "RollStart"] = startTime
    panel[prefix .. "Duration"]  = duration
    if itemKey then
        panel[prefix .. "ItemKey"] = itemKey
    end

    layout:Advance(barH + 4)
end

-- Player row: class icon + roll icon + name + optional winner background.
-- Standardized anchoring: all icons TOPLEFT at y, name anchored LEFT+RIGHT.
-- rowIcon: texture path (default: dice). secColor: {r,g,b} for non-winner text.
-- Returns: nothing; advances layout by rowH + 1
function LootyMakePlayerRow(parent, entry, isWin, rowIcon, secColor, alpha, layout)
    local rowH = 16
    local y    = layout.y

    if isWin then
        local winBg = LootyColorTex(parent, "BACKGROUND",
            0.12, 0.60, 0.12, 0.25 * alpha)
        winBg:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, y)
        winBg:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
        winBg:SetHeight(rowH)
    end

    local cIcon = parent:CreateTexture(nil, "ARTWORK")
    cIcon:SetSize(14, 14)
    cIcon:SetPoint("TOPLEFT", parent, "TOPLEFT", LOOTY_PANEL_PADDING, y)
    LootyApplyClassIcon(cIcon, entry.name)

    local rIcon = parent:CreateTexture(nil, "ARTWORK")
    rIcon:SetSize(14, 14)
    rIcon:SetPoint("LEFT", cIcon, "RIGHT", 2, 0)
    rIcon:SetTexture(rowIcon or "Interface\\Buttons\\UI-GroupLoot-Dice-Up")

    local pName = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pName:SetPoint("LEFT", rIcon, "RIGHT", 3, 0)
    pName:SetPoint("RIGHT", parent, "RIGHT", -LOOTY_PANEL_PADDING, 0)
    pName:SetJustifyH("LEFT")
    pName:SetText(entry.name .. " (" .. tostring(entry.value or "?") .. ")")
    if isWin then
        pName:SetTextColor(0.2 * alpha, 1.0 * alpha, 0.2 * alpha)
    else
        pName:SetTextColor(secColor[1] * alpha, secColor[2] * alpha, secColor[3] * alpha)
    end

    layout:Advance(rowH + 1)
end

-- Centered empty-state text.
-- Returns: height consumed (24px fixed)
function LootyMakeEmptyState(parent, text, yOffset)
    local empty = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    empty:SetPoint("TOPLEFT",  parent, "TOPLEFT",  LOOTY_PANEL_PADDING,  yOffset)
    empty:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -LOOTY_PANEL_PADDING, yOffset)
    empty:SetJustifyH("CENTER")
    empty:SetWordWrap(true)
    empty:SetText(text)
    empty:SetTextColor(0.35, 0.35, 0.35)
    return 24
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
