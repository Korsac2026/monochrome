# Monochrome ESP

Standalone script for **MONOCHROME** (PlaceId `134208374070897`).
UI: [Zolar Ui](https://github.com/Da7mu/Ui-Collection/tree/main/Zolar%20Ui) (loaded remotely).
No Uranium, no other libraries required. Separate project.

## Run

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Korsac2026/monochrome/main/monochrome-esp.lua"))()
```

Menu key: **RightShift**. In first person press **M** (game's own key) to free the mouse for clicking the menu.

## Tabs

**ESP**
- Monster ESP + NPC scan fallback (any non-player humanoid)
- Key ESP (key locations)
- Code ESP — marks the **NOTE / PAPER where the code IS** (handwritten digits
  live in the paper texture, so it detects paper/note objects + world texts
  with digits). It never marks the keypad where you type the code.
- Max distance slider, text size slider

**Movement**
- Noclip, Fly (WASD + Space up / LeftShift down), Walk speed slider, Fly speed slider

**Auto**
- Auto Win: 1 clears the boarded entrance, 2 opens drawers (keys hide inside),
  3 grabs the 4 keys, 4 opens deadbolts, 5 flies to the elevator panel with the code.
- Live status label.

**Settings**
- Theme config (built-in), unload button, help.

The status bar shows `monster:N  key:N  code:N  code:XXXX  keys:H/4`.

## Notes / fixes

- **Code ESP**: the code is handwritten on a hanging paper (e.g. `9559`), not a
  TextLabel — that's why text-only scanning missed it. It now detects
  note/paper-like objects by name plus world texts with digits.
- **Speed**: the game resets WalkSpeed constantly (sprint/stamina). It is now
  re-applied every frame plus instantly on change.
- **Auto Win**: now opens drawers first (keys spawn inside), pries entrance
  planks, survives respawns, and interacts via `fireproximityprompt` with a
  real E-key fallback (`VirtualInputManager`) when the executor lacks it.
  If the panel has no clickable digits it leaves you at the elevator with the
  code shown.

## Tuning names

If objects ever use different names, edit the lists at the top of the script:

- `MONSTER_NAMES` / `MONSTER_FOLDERS`
- `KEY_NAMES`
- `NOTE_NAMES` (paper/note objects = where the code is)
- `ENTRY_SKIP` (keypads/panels/locks: used for navigation only, never marked)
- `DRAWER_NAMES` / `PLANK_NAMES` / `DEADBOLT_NAMES` (Auto Win phases)
