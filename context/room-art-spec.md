# Room art spec: wallpapers and floors

Written 2026-11-21, when wallpapers and floors went into the game.

**The short version:** the den now has a wallpaper and a floor the player can change
(Journal → Den → The Room). **21 of your wallpapers and 14 of your floors are in**,
and any wallpaper goes with any floor. To add more, paint to the template below and drop
the file in the same folder as the others.

---

## 1. How the room is put together now

The room used to be one picture. Now it's two layers:

- **The wall:** a whole-room picture (back wall, side walls, window, shelves, lamp),
  exactly like the ones you've been making.
- **The floor:** drawn on top of the wall, cut to the floor's outline. Everything above
  the floor line is cut away automatically.

So a wallpaper doesn't need its own floor (anything you paint there gets covered), and a
floor doesn't need a wall (anything above the line gets cut). The floors you painted on
black and the ones painted in a full room both work.

---

## 2. The template

**`context/room_template.png`** is the room with the lines drawn on. Put it on a layer
above your painting at about 50% to check things line up.

| | where (in pixels, on the 3904 × 1088 canvas) |
|---|---|
| Canvas | **3904 × 1088**, always |
| Floor line (back wall meets floor) | y = **701**, from x = 369 to x = 3448 |
| Back corners | x = **369** and x = **3448** |
| Left floor edge | from (0, 866) up to the left corner |
| Right floor edge | from the right corner down to (3904, 896) |
| **Shelves** | plank tops at y = **145** and y = **331**, from x = **380** to **684** |
| Window | the left side wall, as in the current room |
| Lamp | the right side wall, as in the current room |

**The shelves are the strict part.** Players can drop things onto the shelves, and the
game knows where the shelves are by these numbers, not by looking at the picture. If a
wallpaper's shelves sit somewhere else, a mug dropped on them would float in the air or
sink into the plank. That's why four of your wallpapers aren't in yet (below).

The corners and floor line matter less: a few pixels off is hidden under the floor. But
keep them close.

---

## 3. What's waiting on a fix

**Wallpapers with their shelves in a different place** (move the shelves to match the
template and they're in):

- Brick Wall with Grey and Partition: shelves and window further right
- Brick with Grey sides Wall: shelves higher
- Floral Wallpaper with Black Sides: shelves higher and further right
- Gothic Wallpaper 2: different shelves, with books on. Lovely, but in different places.

**Floors that came in small** (1024 × 285 instead of 3904 × 1088). Blown up to room size
they'd look blurry, so they need the full-size export: Black Tiles No Shine, Concrete
Floor 02, Large Black Tiles, Light Wooden Floors 02, Marble Floor, Polished Concrete
Floor.

**Also spotted:** "Dark Wooden Floors" has a forest painted on its walls. The floor is
in, but the forest would make a great wallpaper of its own if you paint it as one.

---

## 4. Adding a new one

1. Paint it at **3904 × 1088** to the template.
2. Save it as a JPEG (or PNG) in the same folder as the others:
   - wallpapers: `assets/main_menu/backgrounds/`
   - floors: `assets/main_menu/Floors/`
3. Commit, push, and tell Nicholas. He adds it to the list and runs the import, which
   checks it and makes the game's copy.

You don't need to worry about file size or format: the import takes care of that.

---

## 5. Coming later: moving shelves and windows

The plan is for the shelves (and maybe the window) to become things the player can move.
For that, the wallpaper will need to be **empty**: no window, no shelves, no lamp. Those
will be separate pictures with see-through backgrounds instead. No need to do anything
about this yet; there'll be a proper note when it's time.

---

## Appendix: notes for the repo, not for the artist

- `tools/room_styles.json` lists every wall and floor (id, label, source file, or
  `skip` with a reason). `python tools/room_import.py --manifest tools/room_styles.json`
  writes the game's copies to `assets/main_menu/room/{walls,floors}/` as WebP, the floor
  cut to the outline with transparency, and regenerates `src/world/room_catalog.gd`.
- Review sheets land in `build/room_sheets/`: `walls_shelves.png` (check the shelves by
  eye: matching a shelf against a busy wallpaper by computer is unreliable),
  `walls_seams.png`, `floors.png`.
- The delivery folders carry a `.gdignore`, so Godot never imports the full-size
  originals into the build; the game only loads the import's output.
- The choice is saved in the den's save file (`room/wall`, `room/floor`) and reset with
  the den on "reset data". Tidy Up leaves it alone.
