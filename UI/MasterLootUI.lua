-- Looty MasterLootUI
-- Renders the Master Loot tab: BuildMasterItemPanel and RefreshMasterLootTab.
-- Reads from LootyMasterLoot (domain) and LootyItem objects.
-- Uses primitives from UI/Primitives.lua.

-- MasterLootUI references Looty globally at call time (never at load time)

-- ============================================================
-- ---- Determine what action buttons a player can take ----
-- ============================================================
-- Returns one of: "ml_idle" | "ml_rolling" | "raider_roll" | "raider_rolled" | nil

local function GetItemAction(item, isML)
    if item:IsDone() then return nil end
    if isML then
        return item:IsRolling() and "ml_rolling" or "ml_idle"
    else
        -- Raider
        if not item:IsRolling() then return nil end
        local myName = UnitName("player")
        return item:HasRolled(myName) and "raider_rolled" or "raider_roll"
    end
end

-- ============================================================
-- ---- Sub-renderers (each returns height consumed) ----
-- ============================================================

local function RenderStatusLine(panel, item, rollY, alpha)
    local rollCount   = item:RollCount()
    local rerollCount = item:RerollCount()
    local statusColor, statusText

    if item:IsRolling() then
        statusColor = { 1.0, 0.85, 0.2 }
        statusText  = "Rolling... (" .. rollCount .. " rolls)"
    elseif item.winner then
        statusColor = { 0.3, 1.0, 0.3 }
        statusText  = "Winner: " .. item.winner
    elseif rollCount > 0 then
        statusColor = { 0.8, 0.8, 0.8 }
        statusText  = "Rolls: " .. rollCount
    else
        statusColor = { 0.4, 0.4, 0.4 }
        statusText  = "No rolls"
    end

    if rerollCount > 0 then
        statusText = statusText .. " | " .. rerollCount .. " re-roll(s)"
    end

    local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", panel, "TOPLEFT", LOOTY_PANEL_PADDING, rollY)
    fs:SetText(statusText)
    fs:SetTextColor(statusColor[1] * alpha, statusColor[2] * alpha, statusColor[3] * alpha)
    return 16
end

local function RenderTimerBar(panel, item, rollY)
    if not item:IsRolling() or not item.rollStart then return 0 end
    local barH = 3

    local bg = LootyColorTex(panel, "BACKGROUND", 0.1, 0.1, 0.1, 0.8)
    bg:SetHeight(barH)
    bg:SetPoint("TOPLEFT",  panel, "TOPLEFT",  LOOTY_PANEL_PADDING,  rollY)
    bg:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -LOOTY_PANEL_PADDING, rollY)

    local bar = LootyColorTex(panel, "ARTWORK", 0.4, 0.4, 0.4, 0.8)
    bar:SetHeight(barH)
    bar:SetPoint("TOPLEFT", panel, "TOPLEFT", LOOTY_PANEL_PADDING, rollY)

    local remaining = LootyMasterLoot.rollDuration - (GetTime() - item.rollStart)
    remaining = math.max(0, remaining)
    local txt = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    txt:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -LOOTY_PANEL_PADDING, rollY - 2)
    txt:SetJustifyH("RIGHT")
    txt:SetText(string.format("%d:%02d", math.floor(remaining / 60), math.floor(remaining % 60)))

    -- Store refs for live updates
    panel._mlItemKey  = item.itemKey
    panel._mlRollStart = item.rollStart
    panel._mlDuration  = LootyMasterLoot.rollDuration
    panel._mlTimerBg   = bg
    panel._mlTimerBar  = bar
    panel._mlTimerText = txt

    return barH + 4
end

local function RenderActionButtons(panel, item, rollY, action)
    if not action then return 0 end
    local btnY = rollY - 4

    if action == "ml_idle" then
        local startBtn = LootyMakeButton(panel, "Start Roll", 70, 20,
            { 0.15, 0.35, 0.15 }, { 0.25, 0.45, 0.25 }, { 0.5, 1.0, 0.5 },
            function() LootyMasterLoot:StartRoll(item.itemKey) end)
        startBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", LOOTY_PANEL_PADDING, btnY)
        startBtn:Show()

        local doneBtn = LootyMakeButton(panel, "Done", 55, 20,
            { 0.25, 0.15, 0.15 }, { 0.35, 0.25, 0.25 }, { 1.0, 0.5, 0.5 },
            function() LootyMasterLoot:ToggleDone(item.itemKey) end)
        doneBtn:SetPoint("LEFT", startBtn, "RIGHT", 4, 0)
        doneBtn:Show()

        return 4 + 22  -- btnY margin + button height + bottom gap

    elseif action == "ml_rolling" then
        local endBtn = LootyMakeButton(panel, "End Roll", 65, 20,
            { 0.25, 0.15, 0.15 }, { 0.35, 0.25, 0.25 }, { 1.0, 0.5, 0.5 },
            function() LootyMasterLoot:EndRoll(item.itemKey) end)
        endBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", LOOTY_PANEL_PADDING, btnY)
        endBtn:Show()
        return 4 + 24

    elseif action == "raider_roll" then
        local rollBtn = LootyMakeButton(panel, "Roll!", 55, 20,
            { 0.15, 0.35, 0.15 }, { 0.25, 0.45, 0.25 }, { 0.5, 1.0, 0.5 },
            function() RandomRoll(1, 100) end)
        rollBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", LOOTY_PANEL_PADDING, btnY)
        rollBtn:Show()
        return 4 + 22

    elseif action == "raider_rolled" then
        local greyBtn = LootyMakeDisabledButton(panel, "Rolled", 55, 20)
        greyBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", LOOTY_PANEL_PADDING, btnY)
        greyBtn:Show()
        return 4 + 22
    end

    return 0
end

local function RenderRollList(panel, item, rollY, alpha)
    local rollCount = item:RollCount()
    if rollCount == 0 then return 0 end

    local sortedRolls = item:GetSortedRolls()
    -- Live: cap at 3; history: show all
    local maxRows = item:IsRolling() and math.min(3, #sortedRolls) or #sortedRolls
    local rowH    = 16
    local consumed = 0

    for i = 1, maxRows do
        local entry  = sortedRolls[i]
        local isWin  = (entry.name == item.winner)
        local y      = rollY - consumed

        -- Winner highlight
        if isWin then
            local winBg = LootyColorTex(panel, "BACKGROUND",
                0.12, 0.60, 0.12, 0.25 * alpha)
            winBg:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, y)
            winBg:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, y)
            winBg:SetHeight(rowH)
        end

        local cIcon = panel:CreateTexture(nil, "ARTWORK")
        cIcon:SetSize(14, 14)
        cIcon:SetPoint("TOPLEFT", panel, "TOPLEFT", LOOTY_PANEL_PADDING, y)
        LootyApplyClassIcon(cIcon, entry.name)

        local rIcon = panel:CreateTexture(nil, "ARTWORK")
        rIcon:SetSize(14, 14)
        rIcon:SetPoint("LEFT", cIcon, "RIGHT", 2, 0)
        rIcon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Dice-Up")

        local pName = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        pName:SetPoint("LEFT", rIcon, "RIGHT", 3, 0)
        pName:SetText(entry.name .. " (" .. tostring(entry.value or "?") .. ")")
        if isWin then
            pName:SetTextColor(0.2 * alpha, 1.0 * alpha, 0.2 * alpha)
        else
            pName:SetTextColor(1.0 * alpha, 0.85 * alpha, 0.2 * alpha)
        end

        consumed = consumed + rowH + 1
    end

    return consumed
end

local function RenderRerollWarning(panel, item, rollY, alpha)
    if item:RerollCount() == 0 then return 0 end
    local names = {}
    for playerName, info in pairs(item.rerolls) do
        table.insert(names, playerName .. "(" .. (info.value or "?") .. ")")
    end
    local warnTxt = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    warnTxt:SetPoint("TOPLEFT", panel, "TOPLEFT", LOOTY_PANEL_PADDING, rollY)
    warnTxt:SetPoint("RIGHT",   panel, "RIGHT",  -LOOTY_PANEL_PADDING, 0)
    warnTxt:SetJustifyH("LEFT")
    warnTxt:SetText("Re-rolls: " .. table.concat(names, ", "))
    warnTxt:SetTextColor(1.0 * alpha, 0.4 * alpha, 0.2 * alpha)
    return 16
end

-- ============================================================
-- ---- BuildMasterItemPanel ----
-- ============================================================

-- Builds one item card for the Master tab.
-- opts: { isDone = bool, isML = bool }
-- Returns: panel frame, total height.
function BuildMasterItemPanel(content, item, itemKey, yOffset, opts)
    opts = opts or {}
    local isDone = opts.isDone or item:IsDone()
    local isML   = opts.isML   or LootyMasterLoot:IsML()
    local alpha  = isDone and 0.5 or 1.0
    local iconH  = LOOTY_ICON_SIZE - 4

    local panel = LootyMakePanel(content, isDone and 0.2 or 0.6)
    panel:SetWidth(content:GetWidth())

    -- Item header (icon, quality border, name, tooltip)
    local rollY = LootyMakeItemHeader(panel, item, iconH, alpha)

    -- Status line
    rollY = rollY - RenderStatusLine(panel, item, rollY, alpha)

    -- Timer bar (when rolling)
    rollY = rollY - RenderTimerBar(panel, item, rollY)

    -- Action buttons
    local action  = GetItemAction(item, isML)
    rollY = rollY - RenderActionButtons(panel, item, rollY, action)

    -- Roll list
    rollY = rollY - RenderRollList(panel, item, rollY, alpha)

    -- Reroll warning
    rollY = rollY - RenderRerollWarning(panel, item, rollY, alpha)

    -- Calculate total height
    local totalH = LOOTY_PANEL_PADDING * 2 - rollY
    if totalH < iconH + LOOTY_PANEL_PADDING * 2 + 20 then
        totalH = iconH + LOOTY_PANEL_PADDING * 2 + 20
    end
    panel:SetHeight(totalH)
    panel:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, yOffset)
    panel:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOffset)

    return panel, totalH
end

-- ============================================================
-- ---- RefreshMasterLootTab ----
-- ============================================================

function RefreshMasterLootTab(content, frame)
    local session = LootyMasterLoot:GetSession()
    local isML    = LootyMasterLoot:IsML()
    local role    = LootyMasterLoot:GetRole()
    local yOffset = -LOOTY_CONTENT_MARGIN

    -- ---- Role badge ----
    if session then
        local methodLbl, mH = LootyMakeLabel(content, "Loot: Master",
            0.7, 0.7, 0.7, yOffset)
        yOffset = yOffset - mH

        if role == "MasterLooter" then
            local roleLbl, rH = LootyMakeLabel(content, "Role: MasterLooter",
                1.0, 0.82, 0.0, yOffset)
            yOffset = yOffset - rH - 2
        elseif role == "Raider" then
            local roleLbl, rH = LootyMakeLabel(content, "Role: Raider",
                0.4, 0.7, 1.0, yOffset)
            yOffset = yOffset - rH - 2
        end
    end

    -- ---- Active items ----
    local mlCount = 0
    if session then
        local activeItems = session:GetActiveItems()
        mlCount = #activeItems
        for _, item in ipairs(activeItems) do
            local _, h = BuildMasterItemPanel(content, item, item.itemKey, yOffset, { isML = isML })
            yOffset = yOffset - h - 4
        end
    end

    -- ---- Done items section ----
    if session then
        local doneItems = session:GetDoneItems()
        if #doneItems > 0 then
            local sepY = yOffset - 10
            LootyMakeSeparator(content, sepY, 4)
            yOffset = sepY - 1 - 22

            local clearBtn = LootyMakeButton(content, "Clear Done", 80, 20,
                { 0.15, 0.15, 0.15 }, { 0.25, 0.25, 0.25 }, { 0.6, 0.6, 0.6 },
                function() LootyMasterLoot:ClearDone() end)
            clearBtn:SetPoint("TOP", content, "TOP", 0, yOffset)
            clearBtn:Show()
            yOffset = yOffset - 24

            local lbl, lblH = LootyMakeLabel(content,
                "Done (" .. #doneItems .. ")", 0.4, 0.4, 0.4, yOffset)
            yOffset = yOffset - lblH

            for _, item in ipairs(doneItems) do
                local _, h = BuildMasterItemPanel(content, item, item.itemKey, yOffset,
                    { isDone = true, isML = isML })
                yOffset = yOffset - h - 4
            end
        end
    end

    -- ---- Empty state ----
    if mlCount == 0 then
        local empty = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        empty:SetPoint("TOP", content, "TOP", 0, -40)
        if session then
            if role == "Raider" then
                empty:SetText("Waiting for MasterLooter to open a corpse...")
            else
                empty:SetText("No items looted yet — open a corpse with loot")
            end
        else
            empty:SetText("Not in Master Loot mode")
        end
        empty:SetTextColor(0.35, 0.35, 0.35)
        yOffset = yOffset - 50
    end

    -- Update master tab count
    if frame and frame.tabs and frame.tabs.master then
        frame.tabs.master.text:SetText("Master: " .. mlCount)
    end

    return yOffset
end

-- ============================================================
-- ---- Timer update for Master Loot (called from UpdateTimers) ----
-- ============================================================

function UpdateMasterLootTimers(content)
    local session = LootyMasterLoot:GetSession()
    if not session then return end

    for _, child in ipairs({ content:GetChildren() }) do
        if child._mlItemKey and child._mlTimerBar and child._mlRollStart then
            local elapsed   = GetTime() - child._mlRollStart
            local duration  = child._mlDuration or LootyMasterLoot.rollDuration
            local remaining = math.max(0, duration - elapsed)
            local pct       = remaining / duration

            child._mlTimerBar:SetWidth(child._mlTimerBg:GetWidth() * pct)

            if pct < 0.25 then
                child._mlTimerBar:SetVertexColor(0.9, 0.2, 0.15, 0.8)
            elseif pct < 0.5 then
                child._mlTimerBar:SetVertexColor(0.9, 0.7, 0.1, 0.8)
            else
                child._mlTimerBar:SetVertexColor(0.4, 0.4, 0.4, 0.8)
            end

            if child._mlTimerText then
                child._mlTimerText:SetText(string.format("%d:%02d",
                    math.floor(remaining / 60), math.floor(remaining % 60)))
            end
        end
    end
end

-- ---- UpdateMasterLootTimer (called from MasterLoot timer callback) ----

function LootyUpdateMasterLootTimer(itemKey, remaining)
    if not LootyFrame or not LootyFrame.content then return end
    for _, child in ipairs({ LootyFrame.content:GetChildren() }) do
        if child._mlItemKey == itemKey and child._mlTimerBar and child._mlTimerBg then
            local duration = child._mlDuration or LootyMasterLoot.rollDuration
            local pct      = remaining / duration
            child._mlTimerBar:SetWidth(child._mlTimerBg:GetWidth() * pct)

            if pct < 0.25 then
                child._mlTimerBar:SetVertexColor(0.9, 0.2, 0.15, 0.8)
            elseif pct < 0.5 then
                child._mlTimerBar:SetVertexColor(0.9, 0.7, 0.1, 0.8)
            else
                child._mlTimerBar:SetVertexColor(0.4, 0.4, 0.4, 0.8)
            end

            if child._mlTimerText then
                child._mlTimerText:SetText(string.format("%d:%02d",
                    math.floor(remaining / 60), math.floor(remaining % 60)))
            end
            break
        end
    end
end
