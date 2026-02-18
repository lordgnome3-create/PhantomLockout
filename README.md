# PhantomLockout - Turtle WoW Raid Lockout Tracker

A World of Warcraft addon for **Turtle WoW** that tracks all raid lockout timers and displays them in an Auction House-style GUI.

## Features

- **All Turtle WoW Raids Tracked:**
  - **40-Man (7-Day Reset):** Molten Core, Blackwing Lair, AQ40, Naxxramas, Emerald Sanctum
  - **40-Man (5-Day Reset):** Onyxia's Lair, Karazhan
  - **20-Man (3-Day Reset):** Zul'Gurub, Ruins of Ahn'Qiraj

- **Auction House-Style UI** with the classic WoW AH textures and layout
- **Live Countdown Timers** updating every second
- **Color-Coded Status:** LOCKED → TODAY → SOON → IMMINENT
- **Detailed Info Panel** showing boss count, reset cycle, and raid descriptions
- **Rich Tooltips** with next reset date/time on hover
- **Server Time Display** in the top-right corner
- **Minimap Button** for quick access
- **Draggable Window** - position it wherever you like
- **Slash Commands** for quick chat-based lookups

## Installation

1. Extract the `PhantomLockout` folder into your `Interface/AddOns/` directory
2. Restart WoW or type `/reload` if already in-game
3. Click the minimap button (clock icon) or type `/pl` to open

## Slash Commands

| Command | Description |
|---------|-------------|
| `/pl` | Toggle the lockout window |
| `/phantomlockout` | Toggle the lockout window |
| `/plock` | Toggle the lockout window |
| `/pl help` | Show help in chat |
| `/pl next` | Print all upcoming resets to chat |

## Reset Schedule (Turtle WoW)

All resets occur at **11:00 PM EST (Server Time)**:

| Raids | Cycle | Reset Day |
|-------|-------|-----------|
| MC, BWL, AQ40, Naxx, ES | 7 Days | Every Tuesday |
| Onyxia's Lair | 5 Days | Rolling |
| Karazhan | 5 Days | Rolling |
| Zul'Gurub, AQ20 | 3 Days | Rolling |

## Notes

- Timers are calculated based on the known Turtle WoW reset schedule
- The addon uses the server's fixed reset schedule, not personal lockout IDs
- Press **Escape** to close the window
- Window position resets on reload (drag to reposition)
# PhantomLockout
