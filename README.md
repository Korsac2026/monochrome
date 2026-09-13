# Monochrome ESP

Standalone script for **MONOCHROME** (PlaceId `134208374070897`).
No Uranium, no libraries required. Separate project.

## Run

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Korsac2026/monochrome/main/monochrome-esp.lua"))()
```

## Features

1. **Monster ESP** — highlights the monster (outline + name + distance).
2. **Key ESP** — marks key locations on the map.
3. **Code ESP** — marks WHERE the code IS (world notes / screens / papers
   showing digits), NOT the keypad where you type it. Reads the code for you.
4. **Noclip** — walk through walls.
5. **Fly** — fly with WASD + Space (up) / LeftShift (down).
6. **Speed** — WalkSpeed stepper: 16 / 24 / 32 / 50 / 75 / 100 / 150.
7. **Auto Win** — flies to the 4 keys, grabs them (E), opens the deadbolts,
   then flies to the elevator panel with the code.

All black & white (monochrome).

## GUI

- Draggable from the title bar.
- **RightShift**: show / hide.
- **X**: closes the script and cleans up all ESP.

| Row | What it does |
|---|---|
| MONSTER ESP | Toggles monster ESP |
| KEY ESP | Toggles key ESP |
| CODE ESP | Toggles code-location ESP |
| NPC SCAN | Marks ANY non-player humanoid as monster (fallback if the monster uses a weird name) |
| NOCLIP | Toggles noclip |
| FLY | Toggles fly |
| SPEED | WalkSpeed stepper (also scales fly speed) |
| MAX DIST | ESP render distance (150m / 300m / 500m / 1000m / INF) |
| AUTO WIN | Full auto-run: keys → deadbolts → elevator panel + code |

The status bar shows `monster:N  key:N  code:N  code:XXXX  keys:H/4`.

## Tuning names

If the monster, keys or panels ever use different names, edit the lists at
the top of the script:

- `MONSTER_NAMES` / `MONSTER_FOLDERS`
- `KEY_NAMES`
- `ENTRY_NAMES` / `DEADBOLT_NAMES` (Auto Win navigation only)
