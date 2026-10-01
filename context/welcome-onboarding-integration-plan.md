# Welcome onboarding integration plan

The current welcome art lives in `assets/onboarding/welcome/` and has been reduced to two cleaned transparent PNGs:

- `welcome_modal_full_rough.png` — the full central welcome card, including logo, copy, icons and the baked "LET'S GO!" button.
- `welcome_callout.png` — a blank callout bubble used with live labels for the lower helper notes.

The source is still marked `_rough` because the modal text and button are baked into one image. That is fine for the first playable onboarding pass: it is polished enough to ship internally, and a later cleanup can split the modal into transparent background, logo, icons, live labels and button states without changing the flow.

## Implemented wiring

`src/world/welcome_overlay.gd` builds a modal overlay in the 960×540 menu design space:

- full-window dim scrim;
- centered `welcome_modal_full_rough.png` at native pixel size;
- invisible real `Button` over the baked "LET'S GO!" art;
- reusable lower callouts drawn from `welcome_callout.png` with live `Label`s;
- dismiss via click, Enter, Space or Escape;
- `dismissed` signal for `world.gd`.

`src/world/world.gd` owns the lifecycle:

- creates `WelcomeOverlay` under `MenuLayer` after the settings scrim;
- shows it after the intro has fully revealed the menu;
- stores `ui/welcome_seen` in `user://focus_fox.cfg`;
- blocks session start, journal, settings, den drawer, room panning and background input while welcome is visible;
- marks the welcome as seen and saves immediately on dismiss;
- resets `welcome_seen` when game data is reset.

`src/world/fox_settings_panel.gd` exposes a `Show Welcome` button on the Data tab so the flow can be replayed without clearing data.

## Future art cleanup

When final layered art exists, keep the public flow the same and replace internals of `WelcomeOverlay`:

1. modal frame/body as a clean transparent PNG;
2. logo as a separate transparent PNG;
3. three feature icons as separate transparent PNGs;
4. CTA normal/hover/pressed button states;
5. live text labels for the headline/body/feature captions.

The save flag and replay button should not need to change.

## The first tuck

The welcome card is too early to explain the launcher's disappearing act, so three
one-time callouts (`src/world/hint_callout.gd`, driven from `world.gd`) explain it when it happens:

| Moment | Callout | Flag in `[ui]` |
|---|---|---|
| First focus session starts | "Tucking this away so you can focus…" — replaces the 1.5s tuck, held 6s or until clicked | `first_tuck_seen` |
| Launcher first comes back after that | "Welcome back! Whenever I'm tucked away…" | `first_return_seen` |
| First press of the window's ✕ | "Still here, on your taskbar!…" — then it tucks | `first_close_seen` |

The copy names the **taskbar**, not the tray: Windows 11 hides new tray icons under the `^`
overflow, but the taskbar button is always visible and already brings the launcher back.
Show Welcome and a data reset both clear all three flags.

Not done: animating the window toward the corner as it tucks. The launcher has a normal
title bar, so shrinking its content would leave an empty frame. Sliding the whole window
toward the bottom-right is the alternative if the tuck still confuses people.

The ✕ callout stands in for a proper **"Keep running in the tray / Quit"** confirm modal.
When that exists it replaces the callout inside `_close_to_tray()`; nothing else changes.

## Art still needed (for Kayleigh)

Two pieces, each reused wherever it fits:

1. **A wide hint bubble.** The current callout is 140px wide; hints stretch it to 330px as
   a nine-patch. That looks fine, but a native one would be cleaner: about **330×53**, same
   style, tail on the left, and a plain middle so it can stretch for longer copy. One
   bubble for every hint, no variants.
2. **A small confirm modal frame**, about **360×180**, with a plain middle that can stretch.
   It's for the ✕ "Keep running / Quit" confirm, and it would also replace the stock grey
   Godot dialog that "Reset game data?" uses today. The buttons reuse the existing wood
   buttons, so only the frame is needed.

(The layered welcome modal pieces listed under *Future art cleanup* above still stand.)

Not onboarding, but on the same list: **two achievement badges are unfinished** —
*Just Checking In* and *Still Counts* (both secret ones). Each has the blank Template
plaque as its unlocked art and Ready to Focus's stopwatch as its locked art. They need
their own 64×64 `unlocked.png` + `locked.png` before the Steamworks upload.
`python tools/make_steam_achievements.py` fails until they're done.
