# Tasks: Master Loot Multi-User Sync

## Phase 1: Foundation

- [x] 1.1 In `Core.lua`: Register `CHAT_MSG_ADDON` event in `PLAYER_LOGIN`
- [x] 1.2 In `Core.lua`: Add `CHAT_MSG_ADDON` handler, delegate to `LootyMasterLoot:OnAddonMessage()`
- [x] 1.3 In `MasterLoot.lua`: Add state vars (`remoteMode`, `remoteItems{}`, `remoteML`, `msgThrottle`, `lastMsgTime`, `pendingItems{}`, `sendTimer`)

## Phase 2: Message Sending (ML side)

- [x] 2.1 In `MasterLoot.lua`: Implement `SendThrottledMessage()` with 0.5s queue
- [x] 2.2 In `MasterLoot.lua`: Implement `SerializeItem()` → `"ITEM|index|link|texture|quality|name"`
- [x] 2.3 In `MasterLoot.lua`: Modify `OnLootOpened()` to send items via `SendThrottledMessage()` (one per 0.5s)
- [x] 2.4 In `MasterLoot.lua`: Send `"ROLL_START|index"` in `StartRoll()`
- [x] 2.5 In `MasterLoot.lua`: Send `"ROLL_END|index|winner"` in `EndRoll()`
- [x] 2.6 In `MasterLoot.lua`: Send `"ITEM_DONE|index"` in `ToggleDone()`
- [x] 2.7 In `MasterLoot.lua`: Send `"CLEAR"` in `OnLootMethodChanged()` when deactivating

## Phase 3: Message Receiving (All clients)

- [x] 3.1 In `MasterLoot.lua`: Implement `DeserializeItem()` to parse `"ITEM|index|link|texture|quality|name"`
- [x] 3.2 In `MasterLoot.lua`: Implement `OnAddonMessage(prefix, message, distribution, sender)`
- [x] 3.3 In `MasterLoot.lua`: Parse `ITEM` messages → populate `remoteItems{}`
- [x] 3.4 In `MasterLoot.lua`: Parse `ROLL_START` → set remote item `rolling=true`
- [x] 3.5 In `MasterLoot.lua`: Parse `ROLL_END` → set remote item `winner`, `rolling=false`
- [x] 3.6 In `MasterLoot.lua`: Parse `ITEM_DONE` → set remote item `isDone=true`
- [x] 3.7 In `MasterLoot.lua`: Parse `CLEAR` → wipe `remoteItems{}`
- [x] 3.8 In `MasterLoot.lua`: Set `remoteMode=true`, `remoteML=sender` on first `ITEM` received

## Phase 4: UI Integration

- [x] 4.1 In `UI.lua`: Modify Master Loot tab to use `remoteItems{}` when not ML
- [x] 4.2 In `UI.lua`: Disable all action buttons (Start Roll, Done, End Roll) for `remoteMode`
- [x] 4.3 In `UI.lua`: Add `"Spectator - ML: [Name]"` indicator when `remoteMode=true`
- [x] 4.4 In `UI.lua`: Refresh UI on `CHAT_MSG_ADDON` (through `MasterLoot:OnAddonMessage()` calling `LootyUI:Refresh()`)

## Phase 5: Cleanup

- [x] 5.1 In `MasterLoot.lua`: Clear `remoteItems` on `PARTY_LOOT_METHOD_CHANGED` if not ML
- [x] 5.2 Add comments explaining throttle logic and message protocol
- [x] 5.3 Test: Inject test data for remote mode (`/looty mtestremote`)

---

## Implementation Order

**Phase 1** (Foundation) → **Phase 2** (ML sends) → **Phase 3** (All receive) → **Phase 4** (UI) → **Phase 5** (Cleanup)

---

**Next Step**: Ready for `sdd-apply` (implement tasks).
