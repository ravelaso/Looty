# Design: Master Loot Multi-User Sync

## Technical Approach

Use WoW WOTLK 3.3.5 `SendAddonMessage` + `CHAT_MSG_ADDON` to broadcast Master Loot state changes from ML to all raid members. **ONE item per message** with 0.5s throttle between messages. **NO resync logic** — players sync automatically on next boss loot.

---

## Architecture Decisions

### Decision 1: Communication Method

| | |
|---|---|
| **Choice** | `SendAddonMessage` with "LOOTY" prefix |
| **Alternatives** | Chat messages (RAID_WARNING), Guild info hacking |
| **Rationale** | Native API designed for addon-to-addon communication. Messages are INVISIBLE to users. Available since WOTLK patch 1.12. 254 char limit manageable with single-item messages. |

### Decision 2: Item Broadcasting (SIMPLIFIED)

| | |
|---|---|
| **Choice** | ONE item per message, compacted: `ITEM\|index\|link\|texture\|quality\|name` |
| **Alternatives** | Batch multiple items, fragment large messages |
| **Rationale** | Simple 1:1 mapping (message = item). No fragmentation complexity. Item links ~70-80 chars + metadata fits easily in 254 char limit. 0.5s throttle prevents disconnect from rate limiting. |

### Decision 3: NO Resync Logic

| | |
|---|---|
| **Choice** | Remove resync completely |
| **Alternatives** | RESYNC_REQ/RESYNC response, periodic full resync |
| **Rationale** | In actual raids, people rarely join mid-boss. If someone gets replaced after a boss, addon detects Raider mode and syncs on NEXT boss loot. Less code = fewer bugs, better performance. KISS principle. |

### Decision 4: Message Serialization

| | |
|---|---|
| **Choice** | Compact pipe-delimited format with escaped pipes |
| **Format** | `ITEM\|index\|link\|texture\|quality\|name` |
| **Rationale** | All critical item data in one message. Receiver can reconstruct item object. Escape `\|\|` for pipes inside links. |

### Decision 5: Prefix Filtering (WOTLK 3.3.5 specific)

| | |
|---|---|
| **Choice** | Manual prefix check in `CHAT_MSG_ADDON` handler |
| **Alternatives** | `RegisterAddonMessagePrefix` (doesn't exist in 3.3.5) |
| **Rationale** | `RegisterAddonMessagePrefix()` was added in Cataclysm 4.1.0. In 3.3.5, ALL addon messages go to ALL addons. Must check `prefix == "LOOTY"` manually. |

---

## Data Flow

```
[Master Looter Client]                    [Raid Member Clients]
        │                                        │
        ├─ LOOT_OPENED                         │
        │   └─ For each item (0.5s apart):     │
        │       SendAddonMessage(              │
        │         "LOOTY",                     │
        │         "ITEM|idx|link|tex|q|name") │
        │            ────────────────────────→  CHAT_MSG_ADDON
        │                                        ├─ Parse "ITEM|..."
        │                                        ├─ Deserialize item
        │                                        ├─ Add to remoteItems[]
        │                                        └─ Refresh UI
        │                                        │
        ├─ StartRoll(itemIndex)                │
        │   └─ Send "ROLL_START|index"        │
        │            ────────────────────────→  Show rolling UI
        │                                        │
        ├─ Player rolls /roll                  │
        │   └─ CHAT_MSG_SYSTEM caught         │
        │       by ML → RecordRoll()           │
        │       (No sync needed - all see /roll)│
        │                                        │
        ├─ EndRoll(itemIndex)                 │
        │   └─ Send "ROLL_END|idx|winner"    │
        │            ────────────────────────→  Show winner
        │                                        │
        └─ ToggleDone(itemIndex)              │
           └─ Send "ITEM_DONE|index"          │
                  ────────────────────────→  Mark as done
```

---

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `Core.lua` | Modify | Register `CHAT_MSG_ADDON` event, delegate to `LootyMasterLoot:OnAddonMessage()` |
| `MasterLoot.lua` | Modify | Add: `remoteItems{}`, `remoteML`, `SendThrottledMessage()`, `SerializeItem()`, `DeserializeItem()`, `OnAddonMessage()` parser |
| `UI.lua` | Modify | Show `remoteItems` for non-ML, disable buttons, show "Spectator - ML: Name" indicator |

---

## Interfaces / Contracts

### Addon Message Protocol (Prefix: "LOOTY")

```
ITEM|index|itemLink|texture|quality|name
  → Sent when ML opens loot, ONE per item with 0.5s delay
  → index: number (loot slot index)
  → itemLink: full itemLink string
  → texture: icon path (e.g., "Interface\\Icons\\INV_Sword_01")
  → quality: number 0-7
  → name: item name (for fallback if link parse fails)

ROLL_START|index
  → Sent when ML starts a roll for an item
  → index: number (index in items/remoteItems)

ROLL_END|index|winnerName
  → Sent when ML ends roll and announces winner
  → winnerName: string

ITEM_DONE|index
  → Sent when ML marks item as done
  → index: number

CLEAR
  → Sent when ML switches loot method off or clears all
  → No payload
```

### Compact Item Serialization (ML side)

```lua
function MasterLoot:SerializeItem(item, index)
    -- Compact format: ITEM|index|link|texture|quality|name
    -- Escape pipe characters in link (safety measure)
    local link = string.gsub(item.link or "", "|", "||")
    local texture = item.texture or ""
    local quality = tostring(item.quality or 2)
    local name = item.name or "Unknown"
    
    return string.format("ITEM|%d|%s|%s|%s|%s", 
        index, link, texture, quality, name)
end
```

### Item Deserialization (Receiver side)

```lua
function MasterLoot:DeserializeItem(message)
    -- Parse: ITEM|index|link|texture|quality|name
    -- Link may contain escaped pipes (||), need to handle carefully
    local header, rest = string.match(message, "^ITEM|(.+)$")
    if not header then return nil end
    
    -- Split by | but respect escaped ||
    local parts = {}
    local current = ""
    local i = 1
    while i <= #rest do
        local char = string.sub(rest, i, i)
        if char == "|" and i < #rest and string.sub(rest, i+1, i+1) == "|" then
            current = current .. "|"
            i = i + 2
        elseif char == "|" then
            table.insert(parts, current)
            current = ""
            i = i + 1
        else
            current = current .. char
            i = i + 1
        end
    end
    table.insert(parts, current)  -- Last part
    
    if #parts < 5 then return nil end
    
    return {
        index = tonumber(parts[1]),
        link = string.gsub(parts[2], "||", "|"),  -- Unescape
        texture = parts[3],
        quality = tonumber(parts[4]) or 2,
        name = parts[5],
    }
end
```

### State Structures

```lua
-- In MasterLoot.lua

-- Master Looter's local state (existing)
MasterLoot.items = {
    [1] = {
        slot = number,
        name = string,
        link = string,
        texture = string,
        quantity = number,
        quality = number,
        rolls = { [playerName] = { value = number, time = number } },
        rerolls = { [playerName] = { value = number, time = number } },
        rolling = boolean,
        rollStart = number or nil,
        isDone = boolean,
        winner = string or nil,
    },
    -- ...
}

-- Remote state (for non-ML clients) - NEW
MasterLoot.remoteMode = false      -- Are we in remote spectator mode?
MasterLoot.remoteItems = {}       -- Mirror of ML's items (indexed by index)
MasterLoot.remoteML = nil         -- Name of ML we're tracking
MasterLoot.isML = false          -- Is player the ML? (existing)

-- Throttle for sending messages (rate limit protection) - NEW
MasterLoot.msgThrottle = 0.5     -- Min seconds between auto-messages
MasterLoot.lastMsgTime = 0
MasterLoot.pendingItems = {}      -- Queue for items waiting to be sent
MasterLoot.sendTimer = nil        -- Timer frame for throttled sending
```

### Throttled Sending (ML side)

```lua
function MasterLoot:SendThrottledMessage(msg)
    -- Add to queue
    table.insert(self.pendingItems, msg)
    self:ProcessSendQueue()
end

function MasterLoot:ProcessSendQueue()
    if #self.pendingItems == 0 then return end
    if GetTime() - self.lastMsgTime < self.msgThrottle then
        -- Schedule timer to try again
        if not self.sendTimer then
            self.sendTimer = CreateFrame("Frame")
            self.sendTimer:SetScript("OnUpdate", function(self)
                MasterLoot:ProcessSendQueue()
            end)
        end
        self.sendTimer:Show()
        return
    end
    
    -- Send next message
    local msg = table.remove(self.pendingItems, 1)
    SendAddonMessage("LOOTY", msg, "RAID")
    self.lastMsgTime = GetTime()
    
    -- If more items, will be picked up on next OnUpdate
    if #self.pendingItems == 0 and self.sendTimer then
        self.sendTimer:Hide()
    end
end
```

### UI Contract (for remote mode)

```lua
-- In UI.lua
-- When rendering Master Loot tab for non-ML:
local isML = LootyMasterLoot.isML
local items = isML and LootyMasterLoot.items or LootyMasterLoot.remoteItems

-- Show "Spectator Mode" indicator if not ML
if not isML and LootyMasterLoot.remoteMode then
    -- Display: "Spectating - ML: " .. LootyMasterLoot.remoteML
    -- Disable all action buttons (Start Roll, Done, End Roll, Cancel)
end
```

---

## Testing Strategy

| Layer | What to Test | Approach |
|-------|-------------|----------|
| Unit | Message parsing (`OnAddonMessage`) | Create test cases with mock messages, verify state changes |
| Unit | Item serialization/deserialization | Test compact format parse with various item links |
| Unit | Throttle mechanism | Verify 0.5s delay between messages |
| Integration | Full sync flow (ML → remote) | Simulate `CHAT_MSG_ADDON` events, verify `remoteItems` |
| Manual | Real raid scenario | Have 2 clients, ML opens loot, verify other sees items |

---

## Migration / Rollout

No migration required. This is a new feature.

- Non-ML clients with old version: won't receive sync (expected)
- ML with new version + old clients: old clients won't see items (expected)
- Both sides updated: full sync works

---

## Open Questions

- [x] ~~Resync logic needed?~~ → **REMOVED**. Not needed per user's reasoning.
- [ ] Should we show a "Player X is using outdated Looty" warning? → **DECISION: NO**, overcomplicates.
- [ ] What happens if ML changes mid-raid? → Clear remote state on `PARTY_LOOT_METHOD_CHANGED`.

---

**Next Step**: Ready for `sdd-tasks` (break down into implementable tasks).
