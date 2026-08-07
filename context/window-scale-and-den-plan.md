# Window scale-up + a den worth decorating — implementation plan

Two goals that sound like one but pull apart:

1. **Legibility** — the launcher is too small to read. Fix: render the same 960×540
   design space at 2×.
2. **Room to customise** — the den should hold more. Fix: *not* window size. Scaling
   the window scales the items with it, so the room holds exactly as much as before.
   The den needs canvas back from the menu chrome.

Phase 1 delivers (1) and is small and self-contained. Phase 2 delivers (2) and is
independent of it. Ship them separately.

---

## The measurement that explains the squinting

| | physical px | logical px (@150% DPI) |
|---|---|---|
| Display | 2560 × 1600 | 1707 × 1067 |
| Launcher today | 960 × 540 | **640 × 360** |
| Launcher at 2× | 1920 × 1080 | 1280 × 720 |

`display/window/dpi/allow_hidpi = true`, so the window is sized in *physical* pixels
while the rest of the desktop is scaled up by 1.5×. The launcher isn't merely small —
it's a third smaller than an unscaled 960×540 window would look. This matches the
observed `GetClientRect` of 640×360 recorded in the `driving-app-from-powershell`
memory note.

At 2× it lands at 1280×720 logical, which sits comfortably inside the ~1707×1010
usable desktop.

---

## Phase 1 — the 2× (small, ships alone)

### Project settings

```ini
[display]
window/size/viewport_width=960          ; unchanged — design space stays 960×540
window/size/viewport_height=540
window/size/window_width_override=1920  ; actual OS window
window/size/window_height_override=1080
window/stretch/mode="canvas_items"
window/stretch/aspect="keep"
window/stretch/scale_mode="integer"
```

`canvas_items` + `integer` is the pixel-art-correct pair: everything renders at a
whole 2× multiple, so with `default_texture_filter=0` (nearest) each source pixel
becomes exactly 4 screen pixels. No resampling, no shimmer. `keep` letterboxes rather
than distorting if the window is dragged to an odd size.

Keeping the design viewport at 960×540 is the whole trick — **every absolute
coordinate in the codebase stays valid**. `world.tscn`'s ~500 lines of hand-placed
offsets, `fox_settings_panel.gd`'s art-native layout, `den_inventory.gd`'s
`VIEW = Vector2(960, 540)`, `journal_panel.gd`'s 960-wide labels: all untouched.

### Code changes

- **[world.gd:4](../src/world/world.gd#L4)** — `launcher_window_size := Vector2i(960, 540)`
  → `Vector2i(1920, 1080)`. Required: `_setup_launcher_window()` assigns
  `window.size = launcher_window_size` at runtime, which overrides the project
  setting. This is the *only* mandatory code edit.
- **[world.gd:228-229](../src/world/world.gd#L228-L229)** — the centring math already
  reads `screen_get_usable_rect`, but 1920×1080 does not fit every screen (a 1366×768
  laptop, an external 1080p monitor with a taskbar). Add a fit check that picks the
  largest integer multiple that fits and falls back to 1×:

  ```gdscript
  func _launcher_size_for_screen() -> Vector2i:
      var base := Vector2i(960, 540)
      var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size
      var mult := mini(usable.x / base.x, usable.y / base.y)
      return base * maxi(1, mini(mult, launcher_scale))   # launcher_scale = 2 default
  ```

  Note this must set `window.content_scale_factor` to match the chosen multiple when
  it differs from the project setting's 2×.

### Verified as already safe

- **Overlay windows.** Probed Godot 4.6 directly: a freshly created `Window` reports
  `content_scale_mode = 0` (DISABLED), so the fox and ball overlays created by
  [overlay_window.gd](../src/world/overlay_window.gd) ignore the root's stretch
  entirely. The desktop fox stays exactly the size `fox_scale` says. Correct — it's a
  desktop pet, not launcher chrome.
- **Screen ↔ design conversion.** `DesktopFox.get_preview_screen_position()` already
  derives its own `window_size / viewport_size` scale factor, so the fox flying out of
  the launcher still lands on the right pixel.
- **Dragging and throwing.** `throwable_prop.gd`, `den.gd` and `den_inventory.gd` all
  use `get_global_mouse_position()`, which returns canvas (design) space under
  `canvas_items` stretch. `desktop_fox.gd` uses `DisplayServer.mouse_get_position()`,
  which is screen space and is only ever compared against screen-space overlay
  positions. Both are already correct on either side of the change.

### Must verify by eye

- **Pixel font crispness.** `PixelOperator.ttf` is a TTF, not a bitmap font. Godot 4.6
  reworked font oversampling; at exactly 2× it should rasterise cleanly, but if glyphs
  smear, set `get_viewport().use_oversampling = false` (or disable oversampling on the
  font import) so it rasterises at design size and scales as texels.
- **The clock dial shader.** [clock_dial.gdshader](../src/world/clock_dial.gdshader)
  takes an `aspect = 1.7777778` uniform and a normalised `center`. Both are
  resolution-independent, so it should be fine — but the dial reveal is the one effect
  where a subtle break would be easy to miss.
- **The background's edges.** `backgrounds/background.png` is 970×941 placed at
  (480, 75), so the canvas is covered with ~10px of horizontal slack. Letterboxing at
  a non-2× window size could expose an edge. Worth a look while resizing.

### Follow-ups

- Expose window scale in the settings panel (1× / 2× / fit-to-screen). Needed anyway
  for the small-screen fallback, and it makes the fit logic user-visible rather than
  magic.
- Update the `driving-app-from-powershell` memory note — the design→client ratio flips
  from 0.667 to 1.333, which silently breaks every scripted click and screenshot.

---

## Phase 2 — give the den a room

### The actual constraint

Placement is *already* free-form. `Den.place()` clamps to
`x ∈ [48, 912], y ≤ 400` and then `ThrowableProp.rest_at()` makes wherever you dropped
it the item's new floor. So mechanically you can put a find anywhere in an 864×352
rect — 59% of the canvas.

What you can't do is put it anywhere that isn't already occupied. The canvas budget:

| band | owner |
|---|---|
| y 0–75 | stats panel |
| y 100–150 | "Bring fox home" |
| y 160–300 | title, preview fox, clock dial |
| **y 300–400** | **the only visually clear floor** |
| y 410–540 | drawer / button row |

That leaves a ~864×100 strip. Doubling the window doubles the chrome too, so the
strip stays exactly one strip. **This is why window size can't fix the den.**

### The fix: a den mode

`_set_mode()` in [world.gd:325](../src/world/world.gd#L325) is already a clean
visibility switch across `HOME` / `CHOOSE` / `RUNNING`. Add `Mode.DEN`:

- Hide: title, stats panel, clock dial, session buttons, bring-home, preview fox.
- Keep: background, den items, the drawer.
- Enter/leave via a den icon next to the journal icon (the journal already models the
  icon-swap pattern — `JOURNAL_ICON` ↔ `HOME_ICON` in world.gd).

Clear placement area goes from ~864×100 to ~864×410 — **4× the usable room**, with no
new art and no change to the save format.

### Then make it feel like a room

- **Depth.** Scale items by `y` within the floor band (≈0.9 at the back wall → ≈1.1 at
  the front) and set `z_index` from `y` so nearer things overlap farther ones. Cheap,
  and it's most of what makes the mockup read as a room rather than a shelf.
- **Zones.** Add `zone: "floor" | "wall" | "surface"` to `DenCatalog.ITEMS`. Wall items
  pin where dropped with no gravity; floor items keep today's behaviour. The catalog
  already implies this — `painting` and `clock` are wall objects, `rug`/`blanket`/
  `cushion` are floor objects. Persist the zone alongside the position in
  `focus_fox_den.cfg` (add a `[zone]` section; default from the catalog so existing
  saves migrate silently, same as the existing pre-drawer fallback in `Den._load()`).
- **Drawer capacity.** `PER_PAGE = 7` in one row. Either go to 2 rows × 8, or use the
  category tabs the art already provides — `category-tab.png` is named for a tab set
  but only one tab is ever drawn.

### Stretch goal: the room is as big as you make the window

Switching `stretch/aspect` from `keep` to `expand` makes the design viewport grow with
the window instead of letterboxing, so dragging the launcher bigger yields *actual
extra design pixels* of floor. The catch is that it invalidates every layout that
hardcodes 960×540 and anchors to an edge — chiefly `den_inventory.gd`'s `VIEW`,
`BODY_Y`, `BODY_W` and `NEXT_ARROW_X` constants, which would need to recompute on
`size_changed`. Worth doing eventually, not worth blocking Phase 1 on.

---

## Phase 3 — something to put in it

7 of the 9 entries in [den_catalog.gd](../src/world/den_catalog.gd) have `texture: ""`
and so can never be earned; `fern` is a stand-in reusing the desk plant, so you get two
identical pots. More room only matters if there's more to put in it. Art for `lamp`,
`rug`, `bookshelf`, `blanket`, `painting`, `cushion` and `clock` is the real unlock —
and the zone model above should be settled first so each piece is drawn for where it
lives.

---

## Recommended order

1. Phase 1 — one settings block, one line, a fit guard. Half a day including visual
   verification. Fixes the squinting outright.
2. Phase 2 den mode + depth. The 4× room gain with no new art.
3. Phase 2 zones + drawer capacity, then Phase 3 art.
