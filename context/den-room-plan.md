# The den as a room — implementation plan

The den is the game's answer to "what was all that focus *for*". Nine finds, all of
them drawn, arriving from 30 minutes of focus up to 8 hours. What's missing isn't the
finds — it's a room big enough to hold them, a sense that the room is a place, and
anywhere to read about it. This pass delivers all three.

The shape of it: **the menu is one authored screen of a wider room, and den mode is
where you walk the rest of it.** That single sentence is what makes the mode and the
panning one feature instead of two — the chrome is pinned, so any screenful you
scrolled to outside den mode would have a stats panel welded across its top.

`wide-background.png` now exists, so the room this plans for is real and measured
rather than hypothetical. **Everything below is keyed to its actual geometry**, which
differs from the old background in ways that move a lot of constants — see
[The numbers that move](#the-numbers-that-move).

---

## What's actually in the way

Two separate problems that read as one.

### The room is occupied

The placement mechanism was never the constraint. `Den.place()` clamps floor finds to
`x ∈ [48, 912], y ∈ [48, 440]` and `ThrowableProp.rest_at()` then makes wherever you
dropped it that find's new floor — so a mug already *can* go anywhere in the window.
What stops the den feeling like a room is that the room is full of menu.

Measured off [world.tscn](../src/world/world.tscn), in design space:

| What | x | y | Which modes |
|---|---|---|---|
| Stats panel | 163–833 | 9–81 | all |
| Settings gear / journal icon | 25–68 / 902–945 | 16–68 | all |
| Bring-home button | 382–572 | 102–150 | CHOOSE, RUNNING |
| Session label | 230–830 | 168–218 | RUNNING |
| Status label | 130–830 | 250–300 | CHOOSE |
| Clock dial (full-window sprite) | 0–960 | 0–540 | RUNNING |
| Timer label | 230–830 | 300–350 | RUNNING |
| Task input | 280–680 | 312–352 | CHOOSE |
| Button row | 165–768 | 424–484 | all |
| Drawer body (open) | 0–903 | 410–540 | any |
| Preview fox (320px tall at `fox_scale` 2) | ~321–641 | 47–367 | HOME |

- **HOME has room** — an unbroken 864 × 343 band between the stats panel and the
  buttons, minus the fox's column.
- **CHOOSE does not.** Bring-home, status and the task input chop the middle into
  strips; the largest clean run is about **864 × 100**.
- **RUNNING is worse** and doesn't matter — the launcher parks itself off-screen 1.5s
  in ([world.gd:435](../src/world/world.gd#L435)).

CHOOSE is the mode you sit in between sessions, so that 864 × 100 is what the den
actually feels like. **This needs a mode, not a bigger room.**

### The floor was nearly full

| Surface | Old room | In use at 9 finds |
|---|---|---|
| Floor | 864px wide, one line | 750px of item widths — **~87%** |
| Wall band (y 95–390) | 864 × 295 | a 72×81 painting and a 34×48 clock |

Some of that 87% legitimately overlaps — a rug goes *under* a bookshelf — but one
screen held about nine floor finds and no more. **This needs a wider room**, which is
what the new art is.

Panning alone would leave you arranging through a 343px letterbox with pinned chrome
above and below. A mode alone leaves you 87% full at nine finds. Den mode is the clean
viewport; panning is what there is to see in it.

---

## The room, measured

`assets/main_menu/backgrounds/wide-background.png` — 3904 × 1088, RGBA, fully opaque,
lossless import.

**It's authored at 2× design scale.** At `scale = 0.5` it becomes **1952 × 544** design
px: 2.03 screens wide, 4px taller than the window. That factor is the one to keep,
because the launcher already renders the 960×540 design space at 2× — so 0.5 design
scale × 2 window scale puts the art at **1:1 physical pixels**. No resampling, perfectly
sharp. Treat *backgrounds are drawn at 2× design scale* as the convention from here.

Geometry, in design px after the 0.5 scale:

| Feature | Art px | Design px |
|---|---|---|
| Room size | 3904 × 1088 | **1952 × 544** |
| Wall/floor junction | y 697 | **y 348.5** |
| Floor depth (junction → bottom) | 391 | **195.5** |
| Corner — angled side wall ends | x 361 | **x 180** |
| Window (on the angled wall) | x 60–320 | x 30–160 |
| Upper shelf (plank top) | y 145, x 380–684 | **y 72.5, x 190–342** |
| Lower shelf (plank top) | y 331, x 380–684 | **y 165.5, x 190–342** |

Two things it inherits that the old background didn't have:

- **A receding floor plane.** The old room was a flat elevation with one floor line.
  This one has 195px of floor drawn in one-point perspective. My earlier note that
  "vertical space can only ever become wall" is superseded — there's real depth now.
- **A light falloff.** Wall luminance runs 227 near the window and settles to ~200
  across the right two-thirds, transitioning around design x 1100–1300. It reads as
  light from the window, which is lovely — just worth an eye on whether the transition
  shows as a band once there's furniture over it.

### The perspective is steep enough to matter

Measured off floorboard seam pitch down a column: **42px at the wall, 63px at the front
edge — a 1 : 1.5 ratio.** The same mug placed against the wall and at the front of the
room should differ in size by half again. Place finds freely across that depth without
scaling them and the back ones read as giants.

### The band that solves it for free

Keep floor placement in a shallow band at the **back** of the floor:

```
design y ∈ [348.5, 410]
```

Across those 60px the board pitch only goes 42 → ~49, so perspective varies **10–15%**
— under the threshold where anyone notices. No scaling, no art changes, and every
existing find sprite stays correct.

Better still, it resolves the drawer clash I flagged before this art existed. The open
drawer occupies y 410–540 — **exactly the floor in front of the placement band.** So:
drawer in the foreground, finds against the wall. The two stop competing for pixels.

Usable floor goes from 864px to **~1856px — 2.15× capacity** — on width alone.

### The happy accident

The preview fox is 320px tall in design space (32px frame × 5 sprite scale × 2 body
scale) centred at y=207, which puts its **feet at y ≈ 367**. That's 18px in front of the
new wall/floor junction — the fox lands on the new floor essentially perfectly, having
floated 60px above the old one.

So don't move the fox; **derive `FLOOR_Y` from it.** Set it to ~367 and the finds stand
on the same line the fox does, which is the one alignment in the room a player would
actually notice.

### If you want the full depth later

There's a clean exit. At the default 2× launcher, design-space scales of **1.0 and 1.5
both land on integral physical pixels** (2 and 3 per texel). So two depth tiers — back
at 1.0×, front at 1.5× — stay pixel-perfect, while 1.25 or 1.33 don't. That's the
upgrade path once the shallow band feels limiting; it isn't this pass, because it
touches shadows, the drawer's ghost preview, surfaces and saved positions all at once.

---

## The numbers that move

Every authored y in the den was measured against a floor line 60–70px lower. This is
the full list:

| Constant | Was | Becomes | Why |
|---|---|---|---|
| `Den.FLOOR_Y` | 428 | **367** | The fox's feet; 18px in front of the junction |
| `Den.ROOM_BOTTOM` | 440 | **410** | The open drawer's top edge |
| `Den.WALL_BOTTOM` | 390 | **340** | Just above the junction at 348.5 |
| `Den.WALL_TOP` | 95 | 95 | Unchanged — still clearing the stats panel |
| `Den.ROOM_MARGIN` | 48 | **split** | See below |
| `DenInventory.VIEW` | (960, 540) | unchanged | The drawer is screen furniture, not room |

`ROOM_MARGIN` has to become per-mount, because the left end of the room is a corner:

- **Floor finds** can stand from about x=60 — the floor continues into the corner and an
  item standing there reads fine.
- **Wall finds** must start at **x ≥ 195**, past the corner at 180. A painting hung on
  the angled side wall would be flat art on a perspective plane, which will look broken.

Also stale: `Den.FLOOR_Y`'s comment about "the room art puts the skirting board at
y≈402". The new art has no skirting — just a wall/floor junction.

**Bump `LAYOUT_VERSION` to 3** and let existing dens re-home to their authored spots.
Saved positions are all measured against the old floor line, so keeping them would
scatter everyone's furniture 60px into the wall.

---

## Art asks

Mostly delivered. What's left:

1. **A right end for the room.** The wall and floor cut off flat at x=1952 — panning
   right hits a raw edge. Mirror the left corner, or put a door there.
2. **A contact shadow.** ~64 × 20, soft black ellipse on transparent, one file reused by
   every find. Nothing the fox brings home currently casts a shadow (see Phase 3) and
   this is the highest-impact sprite left in the pass.
3. **A den icon**, 43×46 to match every other icon in `assets/main_menu/icons/`, in the
   journal icon's warm painted hand. Den mode currently borrows `customize.png` — the
   right name, but the art is a leftover purple planet from the planetoid days and it
   looks it. Swapping the file is the whole change.

4. **More finds.** Nine now fill ~40% of the floor. The room is built for roughly 18 —
   no rush, the ladder is meant to unspool over patches.
5. **Shelves are done** — two are baked into the wall, and they become surfaces for
   free in Phase 5.

One constraint to know: **3904 is just under the 4096 texture limit** GL Compatibility
can rely on. A wider room than this has to be split into two sprites. Lossless import is
the right call (VRAM compression would band those gradients); ~17MB VRAM is fine for a
desktop app.

---

## Phase 1 — Den mode

A fourth mode that clears the chrome and leaves the room, the finds and the drawer.

### world.gd

```gdscript
enum Mode { HOME, CHOOSE, RUNNING, DEN }
```

`_set_mode()` at [world.gd:353](../src/world/world.gd#L353) is already a flat visibility
switch, so this is additive:

| Node | In DEN |
|---|---|
| Background, den finds, desk plant | shown |
| Drawer (`DenInventory`) | shown, **opened on entry** |
| Preview fox | shown if the fox isn't out on the desktop, same rule as HOME |
| Stats panel, title, all buttons, session/status/timer labels, task input, clock dial | hidden |
| Settings gear | hidden — it opens a panel that covers the room anyway |
| Journal icon, den icon | shown; they're the way out |

Enterable from HOME, CHOOSE and RUNNING. Store the mode you came from:

```gdscript
var _mode_before_den := Mode.HOME

func _set_den_open(open: bool) -> void:
	if open:
		if _intro_running or _mode == Mode.DEN:
			return
		_mode_before_den = _mode
		_hide_settings_panel()
		_set_journal_open(false)
		_set_mode(Mode.DEN)
		_den_inventory.set_open(true)
	else:
		_den_inventory.set_open(false)
		_set_mode(_mode_before_den)
```

Restoring the prior mode is what stops "I opened the den mid-session and my timer
vanished". Two flows override it, deliberately: `_on_clock_finished()` and
`_on_fox_spawned_changed()` both call `_set_mode()` already — let them win, and set
`_mode_before_den` to match so a later exit doesn't rewind.

`_queue_minimize()` needs no second guard: its token check at
[world.gd:440](../src/world/world.gd#L440) already tests `_mode == Mode.RUNNING`, so
entering den mode inside the 1.5s window cancels the park for free. Worth a comment,
since it's load-bearing by accident.

### Getting in and out

A `DenIcon` `TextureButton` in `MenuLayer` under the journal icon —
`offset_left = 902, offset_top = 78`, 43×46, the size every icon in
`assets/main_menu/icons/` already is. `customize.png` is the obvious glyph and is
otherwise unused. Swap to `home-icon.png` while open, the pattern the journal icon uses
at [world.gd:745](../src/world/world.gd#L745).

The journal and the den are mutually exclusive; each opener closes the other. Escape
leaves den mode — but `JournalBook` handles its own Escape in `_unhandled_key_input`, so
world.gd's handler must check the journal isn't visible first or the two fight over the
key.

### The finds in the other modes

Recommended: **finds stay visible in every mode**, with the `Den` node's `modulate:a`
tweened to ~0.6 in CHOOSE and RUNNING, 1.0 in HOME and DEN. The room stays the backdrop;
the session UI stays legible. Four lines, reversible in one.

Hiding them outside den mode is tidier and colder — the menu *is* the den, and a home
you only see when you go looking for it isn't a home.

---

## Phase 2 — the wide room and panning

### Scene restructure

The room pans while the chrome stays pinned, so they can't stay siblings:

```
MenuLayer/MainMenu
├── Room            (new Node2D — this is what pans; scale 0.5 on the background)
│   ├── Background  (wide-background.png)
│   ├── Planet      (desk plant + its shadow)
│   └── Den         (added in code by _setup_den)
├── MainmenuStatsPanel
├── Title, Buttons, labels, TaskInput …   (unchanged, all pinned)
```

`DenInventory`, `JournalBook`, `ClockDial` and `JournalIcon` are already siblings up in
`MenuLayer` and are unaffected. `_setup_den()` changes one line —
`_main_menu.add_child(_den)` becomes `_room.add_child(_den)`.

**The intro trap.** `_play_intro()` at [world.gd:869](../src/world/world.gd#L869) fades
every child of `MainMenu` except the background and title. After the restructure `Room`
is a single child *containing* the background, so fading it fades the background too —
exactly what the intro avoids. Skip `Room` in the loop and append its `Den` and `Planet`
children individually.

**The desk plant needs re-placing.** It's authored at (135, 364), centred, 101×96 — base
at y=412, which was the old floor. Against the new art that's 63px in front of the wall,
standing in open floor near the corner. Either move it back to the new floor line or
leave it as deliberate foreground; decide it with the art in front of you.

### Panning

Range `x ∈ [-(1952 - 960), 0]` = `[-992, 0]`, clamped. **Only den mode pans**; every
other mode sits at the authored home view. Three ways to move:

- **Drag empty room.** Items answer clicks through their own `Area2D.input_event`, so a
  press reaching `_unhandled_input` is by definition empty floor. Grab and drag it — how
  every decorating game works, needs no affordance to teach.
- **Mouse wheel**, as the fast path.
- **Auto-pan at the edges while carrying something.** Dwell in the outer ~60px with an
  item held and the room scrolls. Without it you cannot move the mug from screen 1 to
  screen 2, so it isn't optional — but it *is* the fiddliest thing in the pass and will
  want an afternoon on the dead zone and ramp.

Plus an affordance so nobody misses that the room continues — a soft arrow or edge
lightening, live only when there's room that way.

### Coordinates — where this will bite

Everything in `Den` becomes room-space, which is what you want (saved positions are
pan-independent). The seams are where screen-space meets room-space:

- **`ThrowableProp` mixes the two today.** `_begin_drag()` computes
  `_drag_offset = position - get_global_mouse_position()` — parent-relative minus global.
  Identical while `Den` sits at the origin, silently wrong the moment it pans. Convert
  the prop to work in its parent's space throughout. This is the one genuine bug the
  restructure introduces and it presents as *items jump when you grab them after
  scrolling*.
- **`_on_den_place_requested`** takes a design-space point from the drawer and hands it
  to `Den.place()`, which treats it as local. Needs `_den.to_local(at)`.
- **`Den._clamp_to_room`** uses `get_viewport_rect().size.x` for its right edge → room
  width. Read it from the background texture rather than hardcoding:
  `_background.texture.get_width() * _background.scale.x`.
- **`ThrowableProp._compute_bounds`** does the same for `_max_x`; same fix.
- **`DenInventory.contains_point`** stays screen-space and is compared against
  `get_global_mouse_position()` in `_on_item_released` — consistent, leave it alone.
- **Saved positions** are already relative to the left edge, which is where the home view
  sits, so panning itself needs no migration. The floor-line change in
  [The numbers that move](#the-numbers-that-move) does.

---

## Phase 3 — make it read as a room

Ordering and shadow, not scale — see [the band](#the-band-that-solves-it-for-free) for
why the perspective doesn't force scaling.

The scale argument, for the record: every other decision in this codebase refuses
fractional pixel-art scaling on purpose — `den_inventory.gd`'s `ICON_RATIOS` snaps to
tidy fractions, `throwable_prop.gd` slides hung finds sideways instead of rotating them,
`Den._create_item()` anchors off-centre so odd sprites land on whole pixels. The finds
are pixel art (the bookshelf is hard-edged 150×200) even though the room behind them is
painted, so they keep pixel rules.

- **z-order from y:**

  ```gdscript
  const DEPTH_Z_MIN := 2
  const DEPTH_Z_MAX := 18

  func _apply_depth(spr: Sprite2D) -> void:
      var t := clampf(inverse_lerp(FLOOR_BAND_TOP, ROOM_BOTTOM, spr.position.y), 0.0, 1.0)
      spr.z_index = int(round(lerpf(DEPTH_Z_MIN, DEPTH_Z_MAX, t)))
  ```

  Called from `_create_item`, `place()` and `_on_item_settled`. **The band matters:**
  `MenuLayer` runs ClockDial at 20, labels at 30, Buttons at 40, the drawer at 70, the
  journal at 80, the scrim at 110, the settings panel at 120. At or below 18 keeps finds
  under all of it and above the background.

- **Atmospheric tint** — finds nearer the wall take a slight cool darkening (`modulate`
  toward ~`Color(0.88, 0.90, 0.95)`), white at the front. Multiplies cleanly on this
  warm art and costs nothing. With only 60px of band it's subtle, which is right.

- **Contact shadows.** The big one, and currently missing entirely:
  `ThrowableProp._update_shadow()` only finds a sibling literally named `PlantShadow`
  ([throwable_prop.gd:61](../src/world/throwable_prop.gd#L61)), which only the menu's
  desk plant has. Every den find floats. The lift/fade logic already works — it just
  needs `Den._create_item()` to *create* the shadow rather than look it up by name.

### The traps

- `Den._reveal()` tweens `scale` to a hardcoded `Vector2.ONE` and `store()` to
  `Vector2(0.3, 0.3)` ([den.gd:194](../src/world/den.gd#L194),
  [den.gd:279](../src/world/den.gd#L279)). Harmless while depth is z-and-tint only, and
  a bug the day depth tiers arrive. Comment them now.
- `ThrowableProp._compute_bounds()` reads `_top_extent()` off the untransformed texture.
  Same story.

---

## Phase 4 — the journal's Den page

The last placeholder in the book: [journal_book.gd:229](../src/world/journal_book.gd#L229)
still calls `_build_placeholder()`. Everything needed exists — `DenCatalog.ITEMS` is
public static data, the panel/rule/label helpers are in place, and the Achievements page
is a working model of the same shape (grid left, reader right).

**Left page** (`LEFT_PAGE` = 112, 47, 340×433) — the find ladder on ruled lines at
`RULE_PITCH` 26:

```
[icon] a mug              30m    home
[icon] a lamp             60m    home
[icon] a soft rug        120m    in the drawer
[icon] a bookshelf       180m    18m to go     ← next
[icon] a cozy blanket    240m    —
```

Nine rows is 234px and fits. **At ~18 finds it won't** — 468px against a 433px page. Build
it paged from the start (the large panel's baked `‹ ›` arrows and `_arrow_button()` exist
for exactly this); retrofitting is the more annoying order.

Rows are clickable and drive the right-hand reader, same as `_on_badge_input`. Locked rows
show the threshold but not the art.

**Right page** (`RIGHT_PAGE` = 512, 50, 333×428) — three panels from the existing sprites
(`day_tab.png` 312×190, `medium_tab.png` 313×95) at the offsets Achievements already uses
(`+8`, `+212`, `+320`):

1. **The selected find** — art at full size, name, when it arrives or arrived, where it is.
2. **Next find** — name, remaining minutes, progress bar. `_refresh_find()` already does
   this for the Today page; lift the body into a shared helper rather than writing it twice.
3. **The room** — "6 of 9 found · 4 out on display", plus a **Tidy Up** button.

```gdscript
func ladder(focus_seconds: float) -> Array   # every catalog entry + earned/placed/remaining
func placed_count() -> int
func restore_defaults() -> void              # authored positions; does NOT touch _earned
```

`restore_defaults()` matters: `reset_layout()` exists but wipes `_earned` too, so wiring
Tidy Up to it would delete the player's den.

Wiring: `_refresh_current()` gains `Page.DEN: _refresh_den()`; `refresh(stats, den)`
already receives the den; connect `Den.placement_changed` so the page can't go stale
while open.

---

## Phase 5 — surfaces, so the mug can go on the shelf

Today a floor find dropped mid-air *stays* mid-air: `rest_at()` makes the drop point the
new floor. In a 100px strip nobody noticed. In a room you walk across, a mug hanging in
space is what breaks the illusion.

Keep the freedom, add the charm: a find rests where dropped **if something is under it**,
and falls otherwise.

```gdscript
## The y a floor find should come to rest at, given where it was let go: the top of
## whatever it was dropped over, or the floor.
func _support_y(id: String, at: Vector2) -> float:
    var best := FLOOR_Y
    for shelf in BAKED_SHELVES:               # authored: the room's own furniture
        if shelf.has_point(at) and shelf.position.y < best:
            best = shelf.position.y
    for other_id in _items:
        if other_id == id:
            continue
        var other := _items[other_id] as Sprite2D
        var item := DenCatalog.find(other_id)
        if item.is_empty() or DenCatalog.is_wall(item):
            continue
        var w := other.texture.get_size().x
        if absf(at.x - other.position.x) > w * 0.5:
            continue
        var top := other.position.y - other.texture.get_size().y
        if at.y <= top + SUPPORT_TOLERANCE and top < best:
            best = top
    return best
```

**The two baked shelves are free surfaces** — they're painted into the background, so
they can't be derived from item sprites and have to be authored as data:

```gdscript
## Painted into wide-background.png, so they're room furniture rather than finds. The
## plank tops, in room space — see the geometry table above.
const BAKED_SHELVES := [
    Rect2(190, 72.5, 152, 4),
    Rect2(190, 165.5, 152, 4),
]
```

Note the upper shelf at y=72.5 sits **behind the stats panel** (y 9–81) in the home view,
so in HOME you'd only ever see what's on the lower one. Either the stats panel moves, or
the upper shelf is decorative, or you accept that the top shelf is a den-mode reward.

Applied in `place()` and `_on_item_settled`. `SUPPORT_TOLERANCE` around 12px makes "near
enough" land on the shelf instead of punishing a 3px miss.

Consequence to accept: saved mid-air positions become invalid — which the
`LAYOUT_VERSION` 3 bump already covers.

If time runs short, this is the phase to cut. Phases 1–4 stand alone.

---

## Phase 6 — the arrival moment

The cheapest trailer footage in the pass. Today a new find fades in and a `Label` at
(160, 150) says "Your fox brought home a mug!" ([den.gd:284](../src/world/den.gd#L284)).

- Put the banner on `medium_tab.png` so it belongs to the same world as the journal.
- Make it clickable: **"See it →"** drops into den mode with the new find selected and
  pans to where it landed. It's the one moment the player most wants to look at the room,
  and nothing currently invites them to.

---

## One bug to fix while you're in here

`interior_foxcorator` ("Unlock 10 den items") needs 10
([achievement_store.gd:322](../src/world/achievement_store.gd#L322)). The catalog has
**nine**. It's impossible to earn, and the new Den page will show "9 of 9 found" directly
opposite a locked achievement demanding ten.

Growing the catalog toward ~18 fixes it eventually, but not *at ship* unless find ten
lands first. Either get one more find in, or retune to 9 and reword to "Bring every find
home." Free before launch, expensive after.

---

## What this pass does not touch

- No window size or stretch-aspect change. Everything stays in the 960×540 design space
  at an integer multiple.
- No vertical panning — the room is exactly the window's height.
- No depth scaling of finds. The shallow band makes it unnecessary; the 1.0/1.5 tier
  trick is the upgrade path.

---

## Recommended order

| | | Est. | |
|---|---|---|---|
| 1 | Den mode + entry icon + fade rule | half a day | **done** |
| 2a | Swap the background in, re-key the constants, `LAYOUT_VERSION` 3 | 2 hours | **done** |
| 2b | `Room` restructure, coordinate fixes, panning, auto-pan | 1–1.5 days | |
| 3 | Contact shadows, z-order depth | half a day | **done** (tint skipped, see below) |
| 4 | Journal Den page | most of a day | |
| 5 | Surfaces incl. baked shelves | half a day | **done** |
| 6 | Arrival moment, achievement retune | 2 hours | |

Total **three to four days**. 2a was worth doing first and alone — it de-risked
everything after it by getting the geometry on screen, and 367 verified as the right
floor line the moment the fox and the finds lined up on it.

**Atmospheric tint was skipped deliberately.** Across a 60px band the effect is
marginal, and anchoring it wrong tints the whole room grey by default. Worth revisiting
only if the room looks flat once it can be panned — the shadows turned out to do the
work it was there for.

For the trailer: **1 + 2 + 3** is the shot — walking a wide room full of things you
earned, everything casting a shadow.

---

## Open questions

1. **The right end of the room** — mirrored corner, or a door?
2. **The upper shelf behind the stats panel** — move the panel, or let it be a den-mode
   reward?
3. **Does the pan hard-stop or rubber-band at the ends?** Rubber-band feels better and is
   four lines; hard stop is more honest to pixel-perfect framing.
4. **Do finds stay visible during a session?** Recommending yes, faded to ~0.6.
5. **Surfaces this pass or next?** Best feel-win on the list, most cuttable.
6. **Where does the desk plant stand** against the new floor? It's currently 63px out
   from the wall.
