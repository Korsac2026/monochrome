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
- Monster ESP (+ NPC scan fallback, monster color) — matches `workspace.VER`
  exactly, plus name/folder heuristics.
- Key ESP (+ key color) — HiddenKey1-4 pickups.
- Code ESP (+ code color) — marks the **NOTE / PAPER where the code IS**.
  `CodeNote > Printed > Digits` is read directly (it is a plain TextLabel, not
  a SurfaceGui, so generic text scans can't resolve its part). Fallbacks:
  note/paper objects, "read this" prompts, world digit texts, readable code
  values. It never marks the keypad.
- Closet ESP (+ closet color) — hiding spots by name (closet/wardrobe/locker)
  and "hide" prompts.
- Style: chams (outline), 2D corner boxes, snaplines (ON by default), labels,
  max distance, text size. Boxes/snaplines need the Drawing API; they
  auto-disable with a notice when the executor lacks it. Fonts: GothamBlack
  billboards, monospace Drawing text. The Drawing text hides while billboard
  labels are on (otherwise the name shows twice).
- Material chams: ForceField overlay on every mark, with transparency slider
  + flat-color tint toggle (follows each kind color). Originals are restored
  on remove/disable/unload.
- Shader chams: fullscreen monochrome FX (ColorCorrection) with saturation
  and contrast sliders, re-applied every second in case the game wipes FX.
- Do NOT run other MONOCHROME scripts at the same time: their ESP
  (`ESP_Label`, `VER_ESP`, `HiddenKeyESP`, `PlayerESP`) duplicates every mark.
  Our scanner ignores those objects, and only one monster entry is kept
  (disable with NPC scan if you ever want multiples).

**Movement**
- Noclip (hotkey **N**), Fly (hotkey **V**, WASD + Space up / LeftShift down),
  Walk speed slider, Fly speed slider
- Survival: **Infinite Lives** — pins Humanoid health to max (signal +
  every-frame clamp) and locks any life/vida counter to 999, re-armed on
  respawn. Investigated the reference script for a lives "CVE": it contains
  no lives/death/health logic at all — deaths are handled server-side with
  no client-visible check or vulnerable remote, so no client exploit exists.
  Fully effective when the game trusts the client; otherwise combine with
  Noclip/Fly.
- World: Fullbright, TP Spawn
- Interaction: Instant Interact (all E prompts complete with zero hold)

**Auto**
- Auto Win (instant teleport): streamlined sequence —
  1 Teleports to HiddenKey1-4, grabs them with zero hold time and returns,
  2 Teleports to door locks (Cube.028, Cube.035, Cube.031, Cube.033), equips key and unlocks them,
  3 Teleports near CodeNote, reads the code directly from Printed > Digits,
  4 Teleports in front of the Keypad, enters the code digits with ClickDetector,
  5 Activates the elevator prompt to finish the game automatically.
- Put Code Now: one-shot code entry at the Keypad with direct positioning and forced execution.
- View Code: shows the code + copies it to clipboard immediately.
- Insta Collect: ultra-fast proximity pickup (0.04s tick, zero hold duration, scans HiddenKey1-4 and all key prompts within radius).

**Trolling**
- TP All Players to Monster (Kill All): teleports all other players on the server right onto the monster so they die.
- TP Random Player to Monster (Kill): teleports a random player directly to the monster.
- Loop TP Players to Monster: continuous loop teleporting all players onto the monster's hitbox.
- TP Monster to All Players: pulls the monster directly onto other players.
- Player ESP: marks other players with name + distance.
- TP to Monster (VER): teleports you to the monster.
- TP Monster to Me: pulls the monster to you.
- Visit loop: auto-teleports you to each player every N seconds.
- Bait TP (random player to you): brings a player to your position.
- Bait TP (you to random player): teleports you to a player.

On every load the script shows the Discord invite and copies it to the
clipboard (`DISCORD_INVITE` at the top of the script — set your real link).

The status bar shows `monster:N  key:N  code:N  hide:N  note:Y/N  code:XXXX  keys:H/4`.

## Notes / fixes

- **Teleport method reviewed**: MONOCHROME is an early-development indie horror
  with no movement anticheat — instant CFrame teleport + noclip is undetected
  here and the fastest option, so Auto Win teleports instantly everywhere
  (small waits only for server replication and prompt holds).
- **Speed**: the game resets WalkSpeed constantly (sprint/stamina). It is
  re-applied every frame plus instantly on change and on respawn.
- **Auto Win**: opens drawers first (keys spawn inside), pries entrance planks,
  survives respawns, interacts via `fireproximityprompt` with a real E-key
  fallback (`VirtualInputManager`) when the executor lacks it, reads notes to
  pull the code from player UI, and types the code at the panel automatically.
- **Code ESP**: `CodeNote` is force-marked structurally (plain-TextLabel
  digits never resolve to a part via SurfaceGui lookup; Folder-type notes
  anchor on their first inner part) and preferred for the code value. The
  hunt also sweeps every "read" prompt in the world. Paper/note objects +
  "read" prompts + world digit texts + readable code values remain as
  fallback. Keypads/panels/locks/safes are excluded from marking
  (navigation only); the keypad itself is excluded from Key ESP too
  (`keypad` contains `key`). Our own ESP labels are excluded (no self-loop).
- **Diagnostics**: the status bar shows `note:Y/N` (CodeNote presence,
  refreshed every 10s); on load the script warns if `CodeNote` / `VER` /
  `HiddenKey1-4` are missing (game renamed objects); View Code reports the
  same when the code is not found. Send those values if something is missing.
- **Unload**: fully removes ESP, drawings, fly/noclip/fullbright/prompt changes
  (restored), closes the menu and destroys the UI holders.

## Tuning names

If objects ever use different names, edit the lists at the top of the script:

- `MONSTER_NAMES` / `MONSTER_FOLDERS` (`VER` is matched exactly)
- `KEY_NAMES`
- `NOTE_NAMES` (paper/note objects = where the code is)
- `ENTRY_SKIP` (keypads/panels/locks: navigation only, never marked)
- `READ_WORDS` (prompts that reveal the code)
- `CLOSET_NAMES` / `HIDE_WORDS` (closet ESP)
- `LOCK_PARTS` / `ELEVATOR_PART` / `HIDDEN_KEY_PREFIX` (structural Auto Win)
- `DRAWER_NAMES` / `PLANK_NAMES` / `DEADBOLT_NAMES` (Auto Win phases)
