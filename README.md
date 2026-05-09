# Looty

A lightweight Master Loot & Group Loot addon for **WoW WotLK (3.3.5)**. Tracks rolls in real-time, gives the Master Looter full control over loot distribution, and syncs automatically to other players using the addon — no configuration needed.

## Screenshots

**Master Loot Dashboard**

![Master Loot](Screenshots/MasterLoot.png)

**Options — Quality Filter**

![Options](Screenshots/options.png)

## Why Looty?

WoW's default loot windows are slow, cluttered, and disappear after a roll. Looty keeps everything visible in one scrollable window: who rolled, what they rolled, who's winning, and when the timer expires.

Whether you're a raid leader managing drops or a player tracking your rolls, Looty makes loot transparent and organized.

## Features

### Group Loot Tracking
- **Hooks into Blizzard's native Group Loot system** — captures roll results automatically
- Sections players by their choice: **Need**, **Greed**, **Disenchant**, **Pass**
- Accordion panels per roll — expand to see who rolled what value
- Winner highlighted in green, timer countdown on active rolls
- Roll history with a "Clear History" button

### Master Loot Control
- **Full ML dashboard** — see all items from every looted corpse, accumulated across the raid
- **Start, end, and re-roll** with one click — button label changes to "Re-Roll" after the first roll
- **Tie detection** — automatically detects ties and offers a re-roll restricted to the tied players
- **Re-roll protocol** — only tied players can re-roll; raiders see their eligibility status
- **Award to winner** — one-click item delivery with two automatic scenarios:
  - Loot window open → `GiveMasterLoot` delivers directly to the winner from the corpse
  - Item in ML bags → initiates trade automatically using the winner's raid unit (no manual targeting required); item is placed in the trade window automatically
- **Override dropdown** — ML can award to any raid member regardless of who won, via a themed dropdown roster picker
- **Mark items done** — manually track what has been distributed
- **Raider sync** — ML broadcasts item data and roll states to all players using Looty; items are reconstructed on raider clients using `GetItemInfo` with link as immediate fallback

### Quality Filter
- Six-tier quality filter (Poor → Legendary) to control which items appear in the UI
- **Sync with Blizzard** — toggle to follow the default WoW loot threshold automatically
- Filter change applies instantly to all existing items without requiring a re-scan
- Filter syncs from ML to Raiders via the addon protocol

### UI
- Scrollable, resizable window with drag support
- Class icons next to every player name
- Live timer bars with color-coded urgency (grey → yellow → red)
- Themed custom dropdown consistent with the addon's dark style
- Three tabs: **Group** (group loot), **Master** (ML dashboard), **Options** (settings)

## No Sync? No Problem

Looty works in two modes:

1. **Addon sync** — when ML and Raiders both use Looty, everything syncs automatically (items, rolls, filters, tie re-rolls, award state)
2. **Standalone** — Group Loot tab hooks into Blizzard's native system; Master Loot tab still tracks rolls and items locally for the ML

You always get value, regardless of how many people are using Looty.

## Installation

1. Download the addon
2. Place the `Looty` folder in `Interface/AddOns/`
3. Reload or restart WoW
4. Type `/looty` to open the window

## Commands

| Command | Description |
|---------|-------------|
| `/looty` | Toggle the Looty window |
| `/looty lock` | Toggle window lock (prevents dragging/resizing) |
| `/looty clear` | Clear group loot history |
| `/looty test` | Inject mock Group Loot rolls (development) |
| `/looty mtest` | Inject mock Master Loot session as ML (development) |
| `/looty mtestremote` | Inject mock Master Loot session as Raider (development) |
| `/looty debug` | Toggle debug logging |
| `/lr` | Short alias for `/looty` |

## Compatibility

- **WoW 3.3.5a (Wrath of the Lich King)**
- Works with any loot method (Group Loot, Need Before Greed, Master Loot)
- No external libraries required
