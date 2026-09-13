# URANIUM for MONOCHROME

Standalone script for **MONOCHROME** (PlaceId `134208374070897`).
UI: [Zolar Ui](https://github.com/Da7mu/Ui-Collection/tree/main/Zolar%20Ui) (loaded remotely).
No other libraries required. Separate project.

## Run

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Korsac2026/monochrome/main/monochrome-esp.lua"))()
```

Menu key: **RightShift**. In first person press **M** (game's own key) to free the mouse for clicking the menu.

## Tabs

**ESP**
- Monster ESP (+ NPC scan fallback for odd monster names)
- Key ESP (key locations)
- Code ESP — marks the **NOTE / PAPER where the code IS**. The code is
  handwritten in the paper texture (not a TextLabel), so it detects
  note/paper-like objects, "read this" prompts, and world texts showing
  digits. It never marks the keypad where you type the code.
- Max distance slider, text size slider

**Movement**
- Noclip, Fly (WASD + Space up / LeftShift down), Walk speed slider, Fly speed slider

**Auto**
- Auto Win (instant teleport): 1 clears the boarded entrance, 2 opens drawers
  (keys hide inside), 3 grabs the 4 keys, 4 opens deadbolts, 5 reads notes,
  flies to the elevator panel and ENTERS the code (click detectors first,
  then real mouse clicks on digit buttons, code shown if manual entry needed).
- Collect distance slider (stand-off range when grabbing).
- Live status label.

**Settings**
- Theme config (built-in), rescan world button, unload button, help.

The status bar shows `monster:N  key:N  code:N  code:XXXX  keys:H/4`.

## Notes / fixes

- **Teleport method reviewed**: MONOCHROME is an early-development indie horror
  with no movement anticheat — instant CFrame teleport + noclip is undetected
  here and the fastest option, so Auto Win teleports instantly everywhere
  (small waits only for server replication and prompt holds).
- **Speed**: the game resets WalkSpeed constantly (sprint/stamina). It is now
  re-applied every frame plus instantly on change and on respawn.
- **Auto Win**: opens drawers first (keys spawn inside), pries entrance planks,
  survives respawns, interacts via `fireproximityprompt` with a real E-key
  fallback (`VirtualInputManager`) when the executor lacks it, reads notes to
  pull the code from player UI, and types the code at the panel automatically.
- **Code ESP**: paper/note objects by name + "read" prompts + world digit
  texts + readable code values. Keypads/panels/locks/safes are excluded from
  marking (navigation only).

## Tuning names

If objects ever use different names, edit the lists at the top of the script:

- `MONSTER_NAMES` / `MONSTER_FOLDERS`
- `KEY_NAMES`
- `NOTE_NAMES` (paper/note objects = where the code is)
- `ENTRY_SKIP` (keypads/panels/locks: navigation only, never marked)
- `READ_WORDS` (prompts that reveal the code)
- `DRAWER_NAMES` / `PLANK_NAMES` / `DEADBOLT_NAMES` (Auto Win phases)
