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
- Style: chams (outline), 2D corner boxes, snaplines, labels, max distance,
  text size. Boxes/snaplines need the Drawing API; they auto-disable with a
  notice when the executor lacks it. Fonts: GothamBlack billboards,
  monospace Drawing text. The Drawing text hides while billboard labels are
  on (otherwise the name shows twice).
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
- Auto Win (instant teleport): 1 clears the boarded entrance, 2 opens drawers
  (keys hide inside), 3 grabs HiddenKey1-4 via their real `KeyPrompt`s
  (position save/restore, inventory-count verified), 4 fires the `Cube.*`
  door-lock prompts, 5 hunts the code (up to 3 rounds of note reading),
  enters it on the real `Keypad` (clicks each `Digit` until its `Readout`
  matches, max 20 tries per digit; screen-click fallback when the executor
  has no `fireclickdetector`) and fires the `Cylinder.002` elevator prompt
  3 times. Generic name scans remain as fallback for every phase.
- Prompts are loosened before firing (`RequiresLineOfSight = false`,
  `MaxActivationDistance = 5000`) and fired via `fireproximityprompt` →
  `InputHoldBegin/End` → real E-key fallback.
- Auto Use Keys: passive loop, spends held keys on nearby exits (no teleport).
- Put Code Now: one-shot code entry at the panel (prefers the real Keypad).
- Collect distance slider (stand-off range when grabbing).
- Live status label.

**Settings**
- Theme config (built-in), rescan world button, copy-Discord button, unload
  button, help.

On every load the script shows the Discord invite and copies it to the
clipboard (`DISCORD_INVITE` at the top of the script — set your real link).

The status bar shows `monster:N  key:N  code:N  hide:N  code:XXXX  keys:H/4`.

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
  digits never resolve to a part via SurfaceGui lookup) and preferred for the
  code value. Paper/note objects + "read" prompts + world digit texts +
  readable code values remain as fallback. Keypads/panels/locks/safes are
  excluded from marking (navigation only); the keypad itself is excluded from
  Key ESP too (`keypad` contains `key`). Our own ESP labels are excluded
  (no self-loop).
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
