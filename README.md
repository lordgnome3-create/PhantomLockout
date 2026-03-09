# PhantomLockout

**PhantomLockout** is a Classic WoW raid lockout tracker with real-time guild synchronisation. It shows your personal lockout status for every raid instance, shares that information automatically with guildmates who also have the addon installed, and lets you quickly see who is available to run each raid.

---

## Features

- **Personal lockout tracking** — Displays your saved instance status for every raid with a live countdown to expiry.
- **Guild synchronisation** — Automatically broadcasts your lockouts to guildmates via addon messages. No configuration required; it works the moment two players with the addon are online in the same guild.
- **Presence detection** — Sends a hello ping on login so all online addon users are discovered immediately, rather than waiting for the next broadcast cycle.
- **Scrollable member popup** — Hover any raid row to open a popup listing every addon user in the guild, colour-coded by status (locked in orange, available in green), with their guild name and lockout timer.
- **Guild Lockouts column** — The main window shows locked members by name and an available member count directly in the raid list.
- **Next Reset column** — Always-visible countdown to the next reset for every raid, whether you are locked or not.
- **Right-click to invite** — Right-click any raid row to invite all available guild members (those with the addon who are not locked) in one click.
- **Minimap button** — Draggable minimap button for quick access.
- **Resizable window** — The main frame can be dragged and resized. All columns reflow automatically.
- **Instance reset** — One-click button to reset non-persistent dungeon instances.
- **Guild Board** — Hidden admin-only message board (bottom-left corner of the main window) for sharing a guild MOTD. Configurable per admin.
- **Debug command** — `/plockout debug` prints the raw instance names returned by the server, useful for diagnosing unrecognised lockouts.

---

## Supported Raids

| Raid | Size | Reset Cycle |
|---|---|---|
| Molten Core | 40-Man | 7-Day |
| Blackwing Lair | 40-Man | 7-Day |
| Temple of Ahn'Qiraj | 40-Man | 7-Day |
| Naxxramas | 40-Man | 7-Day |
| Emerald Sanctum | 40-Man | 7-Day |
| Onyxia's Lair | 40-Man | 5-Day |
| Karazhan (40) | 40-Man | 5-Day |
| Karazhan (10) | 10-Man | 3-Day |
| Zul'Gurub | 20-Man | 3-Day |
| Ruins of Ahn'Qiraj | 20-Man | 3-Day |

---

## Installation

1. Download or copy `PhantomLockout.lua` into your addons folder:
   ```
   World of Warcraft/Interface/AddOns/PhantomLockout/
   ```
2. Create a `PhantomLockout.toc` file in the same folder with at minimum:
   ```
   ## Interface: 11200
   ## Title: PhantomLockout
   ## Notes: Raid lockout tracker with guild sync
   ## SavedVariables: PhantomLockoutDB
   PhantomLockout.lua
   ```
3. Restart the game or reload your UI (`/reload`).

---

## Usage

### Opening the window

- Click the **minimap button** (key icon, draggable).
- Or type `/plockout` in chat.

### Main window

- **Left-click** a raid row to select it and see full details in the info panel at the bottom.
- **Right-click** a raid row to invite all available guild members who have the addon.
- **Hover** a raid row to open the member popup.
- **Scroll** or **resize** the window to show more rows.

### Member popup

Appears when hovering a raid row. Shows:

- The raid name, size, and reset cycle.
- Your personal status and timer.
- All guild addon users sorted by status — **locked members first** (orange, with time remaining), then **available members** (green).
- Guild name displayed next to each member.
- Mousewheel scrollable when there are more members than fit.

### Slash commands

| Command | Description |
|---|---|
| `/plockout` | Toggle the main window |
| `/plockout next` | Print upcoming lockouts to chat |
| `/plockout guild` | Print guild lockout summary to chat |
| `/plockout reset` | Reset non-persistent dungeon instances |
| `/plockout debug` | Print raw saved instance names from the server |
| `/plockout help` | Show all commands |

---

## Guild Synchronisation

PhantomLockout uses WoW's addon message system (guild channel) to share lockout data. No external services, databases, or server-side components are needed.

**How it works:**

- On login, a presence ping is broadcast so all online addon users discover each other immediately.
- Lockouts are re-broadcast every 60 seconds and whenever your saved instance list updates.
- Received lockouts are stored with absolute expiry times so they remain accurate across sessions.
- Expired entries are pruned every 5 minutes.

All data is stored in `PhantomLockoutDB` (SavedVariables) and persists across sessions.

---

## Troubleshooting

**A raid shows Available even though I am locked out**

The addon matches lockout names returned by the server against its internal list. Some raids use unexpected name strings. Run `/plockout debug` immediately after logging in while locked to see the raw name the server returns, then report it so an alias can be added.

**Guild members are not appearing in the popup**

Guild sync requires both players to have the addon installed and loaded. Members who logged in before you may not appear until they broadcast (up to 60 seconds). Members who log in after you will be discovered within a few seconds via the presence ping.

**Timers seem slightly off**

Weekly resets (7-day raids) are calculated from server time via `GetGameTime()`. Rolling resets (3-day and 5-day raids) use an epoch anchor. Minor drift of a few minutes is normal. Personal lockout timers come directly from the server and are always accurate.

---

## Saved Variables

PhantomLockout stores the following in `PhantomLockoutDB`:

| Key | Contents |
|---|---|
| `guildData` | Guild member lockout expiry times, keyed by raid short name |
| `addonUsers` | Known addon users and their last-seen timestamps |
| `motd` | Guild board message (admin only) |

---

## Version History

| Version | Notes |
|---|---|
| 1.2 | Added scrollable member popup, Next Reset column, guild sync presence pings, instance name normalisation, alias matching for ambiguous raid names (AQ40, Karazhan variants) |
| 1.1 | Added guild lockout sharing, right-click invite, minimap button, resizable window |
| 1.0 | Initial release — personal lockout tracking |
