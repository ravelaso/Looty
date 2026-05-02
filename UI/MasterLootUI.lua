-- Looty MasterLootUI
-- Renders the Master Loot tab: BuildMasterItemPanel and RefreshMasterLootTab.
-- Reads from LootyMasterLoot (domain) and LootyItem objects.
-- Uses primitives from UI/Primitives.lua.

-- MasterLootUI references Looty globally at call time (never at load time)

-- ============================================================
-- ---- Determine what action buttons a player can take ----
-- ============================================================
-- Returns one of:
--   ML:    "ml_idle" | "ml_rolling" | "ml_tie"
--   Raider: "raider_roll" | "raider_rolled" | "raider_reroll" | "raider_rerolled"
--           "raider_not_eligible" | "raider_tie_pending" | nil

local function GetItemAction(item, isML)
    if item:IsDone() then return nil end
    if isML then
        if item:IsTied() then return "ml_tie" end
        return item:IsRolling() and "ml_rolling" or "ml_idle"
    else
        local myName = UnitName("player")
        -- Re-roll phase: eligiblePlayers is set and rolling
        if item:IsRolling() and item.eligiblePlayers then
            if not item.eligiblePlayers[myName] then
                return "raider_not_eligible"
            end
            return item:HasRolled(myName) and "raider_rerolled" or "raider_reroll"
        end
        -- Normal roll phase
        if item:IsRolling() then
            return item:HasRolled(myName) and "raider_rolled" or "raider_roll"
        end
        -- Tie pending: roll ended, no winner, was rolled
        if item.wasRolled and not item.winner and not item:IsDone() then
            return "raider_tie_pending"
        end
        return nil
    end
end

-- ============================================================
-- ---- Sub-renderers (each returns height consumed) ----
-- ============================================================

-- Button color palettes reused across action states
local BTN_GREEN = { { 0.15, 0.35, 0.15 }, { 0.25, 0.45, 0.25 }, { 0.5, 1.0, 0.5 } }
local BTN_RED   = { { 0.25, 0.15, 0.15 }, { 0.35, 0.25, 0.25 }, { 1.0, 0.5, 0.5 } }
local BTN_ORANGE = { { 0.35, 0.20, 0.05 }, { 0.50, 0.30, 0.10 }, { 1.0, 0.75, 0.3 } }

local function RenderStatusLine(panel, layout, item, alpha)
    local rollCount   = item:RollCount()
    local rerollCount = item:RerollCount()
    local isML        = LootyMasterLoot:IsML()
    local statusColor, statusText

    if item:IsRolling() then
        if item.eligiblePlayers and next(item.eligiblePlayers) then
            local names = {}
            for name in pairs(item.eligiblePlayers) do table.insert(names, name) end
            statusColor = { 1.0, 0.65, 0.2 }
            statusText  = "Re-rolling: " .. table.concat(names, " & ")
        else
            statusColor = { 1.0, 0.85, 0.2 }
            statusText  = "Rolling... (" .. rollCount .. " rolls)"
        end
    elseif not isML and item.wasRolled and not item.winner and not item:IsDone() then
        -- Raider tie pending state
        statusColor = { 1.0, 0.5, 0.2 }
        statusText  = "Tie! Waiting for ML to re-roll..."
    elseif item:IsTied() then
        local tied = item:GetTiedWinners()
        statusColor = { 1.0, 0.5, 0.2 }
        statusText  = "Tie: " .. table.concat(tied.names, " & ") ..
                      " (" .. tied.value .. " each)"
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

    local fs, fsH = LootyMakeLabel(panel, statusText,
        statusColor[1] * alpha, statusColor[2] * alpha, statusColor[3] * alpha, layout.y)
    layout:Advance(fsH)
end

local function RenderTimerBar(panel, layout, item)
    if not item:IsRolling() or not item.rollStart then return end
    LootyMakeTimerBar(panel, layout, LootyMasterLoot.rollDuration, item.rollStart, "_ml", item.itemKey)
end

local function RenderActionButtons(panel, layout, item, action)
    if not action then return end

    local BTN_H   = 20
    local TOP_GAP = 4
    local BOT_GAP = 4
    local row     = LootyHLayout(4)
    local atY     = layout.y - TOP_GAP

    if action == "ml_idle" then
        local startBtn = LootyMakeButton(panel, "Start Roll", 70, BTN_H,
            BTN_GREEN[1], BTN_GREEN[2], BTN_GREEN[3],
            function() LootyMasterLoot:StartRoll(item.itemKey) end)
        local doneBtn = LootyMakeButton(panel, "Done", 55, BTN_H,
            BTN_RED[1], BTN_RED[2], BTN_RED[3],
            function() LootyMasterLoot:ToggleDone(item.itemKey) end)
        row:Place(startBtn, panel, LOOTY_PANEL_PADDING, atY)
        row:Place(doneBtn,  panel, LOOTY_PANEL_PADDING, atY)
        startBtn:Show(); doneBtn:Show()

    elseif action == "ml_tie" then
        local rerollBtn = LootyMakeButton(panel, "Re-roll", 65, BTN_H,
            BTN_ORANGE[1], BTN_ORANGE[2], BTN_ORANGE[3],
            function() LootyMasterLoot:StartReRoll(item.itemKey) end)
        local endBtn  = LootyMakeButton(panel, "End", 50, BTN_H,
            BTN_RED[1], BTN_RED[2], BTN_RED[3],
            function() LootyMasterLoot:EndRoll(item.itemKey) end)
        row:Place(rerollBtn, panel, LOOTY_PANEL_PADDING, atY)
        row:Place(endBtn,   panel, LOOTY_PANEL_PADDING, atY)
        rerollBtn:Show(); endBtn:Show()

    elseif action == "ml_rolling" then
        local endBtn  = LootyMakeButton(panel, "End Roll", 65, BTN_H,
            BTN_RED[1], BTN_RED[2], BTN_RED[3],
            function() LootyMasterLoot:EndRoll(item.itemKey) end)
        local rollBtn = LootyMakeButton(panel, "Roll!", 55, BTN_H,
            BTN_GREEN[1], BTN_GREEN[2], BTN_GREEN[3],
            function() RandomRoll(1, 100) end)
        row:Place(endBtn,  panel, LOOTY_PANEL_PADDING, atY)
        row:Place(rollBtn, panel, LOOTY_PANEL_PADDING, atY)
        endBtn:Show(); rollBtn:Show()

    elseif action == "raider_roll" then
        local rollBtn = LootyMakeButton(panel, "Roll!", 55, BTN_H,
            BTN_GREEN[1], BTN_GREEN[2], BTN_GREEN[3],
            function() RandomRoll(1, 100) end)
        row:Place(rollBtn, panel, LOOTY_PANEL_PADDING, atY)
        rollBtn:Show()

    elseif action == "raider_rolled" then
        local greyBtn = LootyMakeDisabledButton(panel, "Rolled", 55, BTN_H)
        row:Place(greyBtn, panel, LOOTY_PANEL_PADDING, atY)
        greyBtn:Show()

    elseif action == "raider_reroll" then
        local rerollBtn = LootyMakeButton(panel, "Re-roll!", 65, BTN_H,
            BTN_ORANGE[1], BTN_ORANGE[2], BTN_ORANGE[3],
            function() RandomRoll(1, 100) end)
        row:Place(rerollBtn, panel, LOOTY_PANEL_PADDING, atY)
        rerollBtn:Show()

    elseif action == "raider_rerolled" then
        local greyBtn = LootyMakeDisabledButton(panel, "Re-rolled", 65, BTN_H)
        row:Place(greyBtn, panel, LOOTY_PANEL_PADDING, atY)
        greyBtn:Show()

    elseif action == "raider_not_eligible" then
        local greyBtn = LootyMakeDisabledButton(panel, "Tied out", 65, BTN_H)
        row:Place(greyBtn, panel, LOOTY_PANEL_PADDING, atY)
        greyBtn:Show()

    elseif action == "raider_tie_pending" then
        -- No button — status line already explains the state
    end

    layout:Advance(TOP_GAP + BTN_H + BOT_GAP)
end

local function RenderRollList(panel, layout, item, alpha)
    local rollCount = item:RollCount()
    if rollCount == 0 then return end

    local sortedRolls = item:GetSortedRolls()
    local maxRows = item:IsRolling() and math.min(3, #sortedRolls) or #sortedRolls

    for i = 1, maxRows do
        local entry = sortedRolls[i]
        local isWin = (entry.name == item.winner)
        LootyMakePlayerRow(panel, entry, isWin, nil,
            { 1.0, 0.85, 0.2 }, alpha, layout)
    end
end

local function RenderRerollWarning(panel, layout, item, alpha)
    if item:RerollCount() == 0 then return end
    local names = {}
    for playerName, info in pairs(item.rerolls) do
        table.insert(names, playerName .. " " .. "(" .. (info.value or "?") .. ")")
    end
    local warnTxt, warnH = LootyMakeLabel(panel, "Re-rolls: " .. table.concat(names, ", "),
        1.0 * alpha, 0.4 * alpha, 0.2 * alpha, layout.y, nil, "GameFontHighlightSmall")
    layout:Advance(warnH)
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

    local panel  = LootyMakePanel(content, isDone and 0.2 or 0.6)
    panel:SetWidth(content:GetWidth())

    -- Item header (icon, quality border, name, tooltip)
    -- LootyMakeItemHeader returns the y cursor start (below the icon row)
    local layout = LootyVLayout(panel, LootyMakeItemHeader(panel, item, iconH, alpha), 0)

    -- Rows — each renderer advances the cursor by what it actually consumed
    RenderStatusLine(panel, layout, item, alpha)
    RenderTimerBar(panel, layout, item)
    RenderActionButtons(panel, layout, item, GetItemAction(item, isML))
    RenderRollList(panel, layout, item, alpha)
    RenderRerollWarning(panel, layout, item, alpha)

    -- Total height = distance from panel top (y=0) to cursor end + bottom padding.
    -- layout.y is negative (WoW convention), so -layout.y gives the full depth.
    -- Top padding is already embedded in LootyMakeItemHeader's starting Y.
    local totalH = -layout.y + LOOTY_PANEL_PADDING
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
        local _, mH = LootyMakeLabel(content, "Loot: Master",
            0.7, 0.7, 0.7, yOffset)
        yOffset = yOffset - mH

        if role == "MasterLooter" then
            local _, rH = LootyMakeLabel(content, "Role: MasterLooter",
                1.0, 0.82, 0.0, yOffset)
            yOffset = yOffset - rH - 2
        elseif role == "Raider" then
            local _, rH = LootyMakeLabel(content, "Role: Raider",
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
    -- Only shown when there are truly no items at all (no active AND no done).
    local doneCount = session and #session:GetDoneItems() or 0
    if mlCount == 0 and doneCount == 0 then
        local emptyY = yOffset - 16
        local text
        if session then
            text = role == "Raider"
                and "Waiting for MasterLooter to open a corpse..."
                or  "No items looted yet — open a corpse with loot"
        else
            text = "Not in Master Loot mode"
        end
        LootyMakeEmptyState(content, text, emptyY)
        yOffset = emptyY - 24
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
            local barW      = child:GetWidth() - LOOTY_PANEL_PADDING * 2

            child._mlTimerBar:SetWidth(barW * pct)

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
            local barW     = child:GetWidth() - LOOTY_PANEL_PADDING * 2
            child._mlTimerBar:SetWidth(barW * pct)

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
