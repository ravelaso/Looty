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

L.ROLL_PATTERNS = {
    -- Need
    ["^(.*) has selected Need for%s*: (.*)$"] = "need",
    -- Greed
    ["^(.*) has selected Greed for%s*: (.*)$"] = "greed",
    -- Disenchant
    ["^(.*) has selected to Disenchant%s*: (.*)$"] = "disenchant",
    -- Pass (auto-pass on ineligible items)
    ["^(.*) passed on%s*: (.*)$"] = "pass",
    ["^(.*) automatically passed on%s*: (.*)$"] = "pass",
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
