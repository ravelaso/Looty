-- Looty Locale: enUS
-- Patterns for parsing CHAT_MSG_LOOT roll messages.
-- These match the default Blizzard messages when
-- "Detailed Loot Information" is enabled in Social
-- options.

local L = {}

-- Format: pattern -> rollType
-- Patterns capture: 1=playerName, 2=itemName
-- The itemName capture includes the item link so
-- we match against GetLootRollItemInfo().

-- Player's own selection (checked FIRST — most specific)
-- "You have selected Greed for: [Veteran Gloves]"
L.ROLL_PATTERNS_SELF = {
    "^You have selected (.-) for%s*:?%s*(.+)$",
}

-- Other players' selection + pass (checked SECOND)
L.ROLL_PATTERNS_OTHER = {
    -- "PlayerName has selected Need for [ItemName]"
    ["^(.-) has selected (.-) for%s*:?%s*(.+)$"] = "other_selection",
    -- "PlayerName has selected to Disenchant [ItemName]"
    ["^(.-) has selected to (.-)%s*:?%s*(.+)$"] = "other_selection_de",
    -- Pass
    ["^(.-) passed on%s*:?%s*(.+)$"] = "pass",
    ["^(.-) automatically passed on%s*:?%s*(.+)$"] = "pass",
}

-- Roll result messages — the main source of truth (type + value + item + player).
L.ROLL_RESULT_PATTERNS = {
    -- Full format: "Greed Roll - 24 for [Item] by PlayerName"
    "^(.-) Roll %- (%d+) for%s*(.+) by (.+)$",
    -- Without "by" (self result): "Greed Roll - 24 for [Item]"
    "^(.-) Roll %- (%d+) for%s*(.+)$",
    -- Other players: "PlayerName rolls 85 (1-100) for [ItemName]"
    "^(.-) rolls (%d+) %(1%-100%) for%s*(.+)$",
    -- No item reference: "PlayerName rolls 85 (1-100)."
    "^(.-) rolls (%d+) %(1%-100%)%.$",
}

-- Roll type display strings
L.ROLL_LABELS = {
    need       = "Need",
    greed      = "Greed",
    disenchant = "DE",
    pass       = "Pass",
}

-- Roll type icons (file paths)
L.ROLL_ICONS = {
    need       = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",
    greed      = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
    disenchant = "Interface\\Buttons\\UI-GroupLoot-DE-Up",
    pass       = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
}

-- Roll type numeric values (for ConfirmLootRoll API)
L.ROLL_VALUES = {
    need       = 1,
    greed      = 2,
    disenchant = 3,
    pass       = 0,
}

-- Roll type display order (lower = shown first)
L.ROLL_ORDER = {
    need       = 1,
    greed      = 2,
    disenchant = 3,
    pass       = 4,
}

Looty_L = L
