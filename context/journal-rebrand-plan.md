# Fox Journal rebrand — plan of action

Supersedes the layout half of [journal-revamp-plan.md](journal-revamp-plan.md). That
document's **Phase 0 (data layer)** is still accurate, still unbuilt, and still the real
gate — nothing here changes that. What changes is everything downstream of it: we now
have finished book art, so the "sprite shopping list" in the old plan is mostly obsolete.

Design space stays **960×540**, 1:1 with art pixels, same convention as the settings
panel. The launcher is mid-migration to a 2× window (`project.godot` uncommitted:
`window_width_override=1920`, `stretch/mode="canvas_items"`, `scale_mode="integer"`),
which does not move a single coordinate below.

---

## What the art gives us

The plate was re-exported **bare** — book, cover, gutter, seven rings, top bookmarks,
side bookmark, page curl, and nothing else. Every piece of furniture is now separate.
That removes the one real constraint the first draft was built around.

| Asset | Size | Role |
|---|---|---|
| `Journal_Today_Page.png` | 960×540 | Bare plate. Book occupies 85,29 → 917,511 |
| `Fox_Journal-title.png` | 177×32 | Title art |
| `fox_frame.png` | 112×100 | Polaroid, fox painted in |
| `day_tab.png` | 312×190 | Assembled light panel **with** baked ‹ › header |
| `medium_tab.png` | 313×95 | Assembled light panel with a darker sub-header pill |
| `light-panel-{corner,tileable-edge,tileable-centre}.png` | 32×27 / 29×75 / 22×21 | 9-slice kit |
| `sub-panel-{corner,tilable}.png` | 22×17 / 55×50 | 9-slice kit for the darker pill |
| `tilable_line.png` | 53×7 | Ruled line, tiles horizontally |
| 5 × `*_Tab.png` | ~44×51 | Rail chips: paw, pencil, book, up-arrow, blank green |

### The slice kit is verified

I template-matched the kit against the assembled panels. The three `light-panel-*`
pieces are **exact** crops of `day_tab.png` (mean squared error 0.00) — corner at its
bottom-left, edge as its left vertical strip, centre as its interior fill. So the kit
genuinely decomposes the panel and will reassemble at any size: mirror the corner four
ways, tile the edge, fill with the centre. The `sub-panel-*` pieces are a near-match for
`medium_tab.png`'s darker pill and build that separately.

Practical consequence: **panels are free-form now.** Every page lays out its own
furniture at whatever size it needs, rather than every page inheriting one baked set of
three wells. Logbook can run 18 ruled rows down the left page and a day-picker panel on
the right; History can give the month grid a panel sized to the grid instead of squeezing
into a fixed 310×180.

Two ways to use it, and both are fine:
- `day_tab.png` / `medium_tab.png` as **NinePatchRect** sources when a page wants roughly
  those proportions — cheapest path, and it keeps the ‹ › arrows.
- The slice kit when a page wants a panel the assembled ones can't stretch to.

### Tab rail

The book geometry is unchanged from the earlier plate, so the measured rail still holds:
x=66, y=80 / 137 / 194 / 251, 57px pitch. A fifth chip lands at y=308 and clears the
book's bottom edge (511) comfortably.

Mapping: paw = Today · pencil = Logbook · book = History · up-arrow = Den ·
green = Achievements.

---

## Phase order

### ✅ Phase 0 — data layer — **DONE**

`StatsStore` now records events, not just aggregates.

- **Event log.** `events: Array` of `{ts, kind, seconds, task}`, capped at
  `MAX_EVENTS = 2000` with the oldest trimmed off the front. `ts` is when the session
  *started*, which is what the logbook prints. `kind` is `focus` / `short` / `long`, so
  a five-minute breather is distinguishable from a long one.
- **`record_break` signature changed** — now `(seconds, started_at, kind)`. Breaks had
  no recorded duration at all before, so the logbook could never have shown one.
  Updated at the only call site, `world.gd:511`.
- **New queries:** `day(key)`, `day_events(key)`, `day_score(key)`, `first_active_day()`,
  `week_activity(week_offset)`, `month_activity(year, month)`, `month_summary(year, month)`,
  `today_key()`.
- **`month_activity` returns a flat 42-cell array** (6×7, Monday first) with out-of-month
  cells included and flagged `in_month: false`, so the grid walks the array and never
  reasons about alignment.
- **Daily goals** `goal_sessions` (4) and `goal_focus_min` (100), persisted in a `[goals]`
  section of the stats file.
- **The seeder emits events too.** Without this a seeded history looks active on the week
  strip and is completely blank the moment you open the day it points at.

**Two deviations from the original spec, both deliberate:**

1. **Goals live in the stats file, not `focus_fox.cfg`.** `day_score()` is the only thing
   that needs them and it belongs to the store; putting them in the launcher's settings
   file would mean the store reaching upward to answer "how did that day go?".
2. **The score formula's tiers were unreachable as written.** The spec clamped
   `goal_pct` to 1.0 and then put gold at `>= 150` — nothing could ever score above 100.
   Now `score` is uncapped (so beating your goal is visible and gold means 1.5× goal) and
   `goal_pct` is the clamped copy used only for progress bars.

**Verified:** seeder produces 34 events across 17 days; `day_events`, `day_score`,
`week_activity` at offsets 0/−1/−2/+1, and `month_activity` all return correct data.
Month grids check out against real calendars (Aug 2026 starts Saturday, Jul 2026 starts
Wednesday) and leap years are right (Feb 2024 = 29 days, Feb 2025 = 28). Full headless
project load is clean.

`den_catalog.gd` was already extracted in commit c8eb31a, and `JournalPanel.DEN_FINDS`
was already deleted with it — the remaining Phase 0 checklist items from the old plan.

### ✅ Phase 1 + 2 — book shell and Today page — **DONE**

`journal_book.gd` (≈470 lines) replaces `journal_panel.gd`, which is deleted.
`world.tscn`'s node is now `MenuLayer/JournalBook`; `world.gd` keeps the same
`refresh(stats, den)` call sites.

**Built:**
- Bare plate + composed furniture. `_panel()` wraps the two assembled panel sprites as
  `NinePatchRect`s with the measured margins (32/46/32/27 large, 32/32/32/27 medium),
  so the painted border and the baked header survive stretching.
- `_rule()` tiles `tilable_line.png` and returns the baseline y, so text sits *on* lines.
- Five-tab rail at x=66, y=80/137/194/251/308. Active slides 6px out and brightens,
  hover 2px. Verified by measuring chip edges in a screenshot, not by eye.
- Page switching with a 0.22s X-scale squash pivoted on the gutter, `open` sfx pitched up.
- Keyboard: `Esc` emits `close_requested` (wired in `world.gd`), `Q`/`E` and `←`/`→` cycle.
- Today page: title art, polaroid, day score with tier colour and flavour line, greeting,
  three goal bars off the new `goal_sessions`/`goal_focus_min`, task list, week paw strip
  with working ‹ › week stepping, next-den-find bar, all-time totals.
- **Backdrop.** The plate is a book on a transparent surround, so the launcher showed
  through around the covers. The book now carries its own dim ColorRect rather than
  reusing the settings scrim — the settings scrim sits at z=110 and would have covered
  the journal icon, which is the way back out.

**Verified in the running app**, not just headless: journal opens as the book, tabs
switch, ruled placeholder pages render, and stepping the week back twice shows
"2 Weeks Ago" with the paw pattern and totals matching the seeded data exactly.

**Two deviations:**
1. **All Time shows three totals, not five.** 313px can hold three readable numbers.
   Longest streak and total breaks move to the History page, which has room.
2. **`Achievements_Tab.png` is now a knife-and-fork.** It reads as food or feeding, not
   achievements. Wired to the Achievements page for now — see open question 1.

---

### ▶ Phase 3 — Logbook page — **NEXT**

The left page's ruled lines are the whole point of this page, and they already tile
correctly — the placeholder proves it. **No new art needed.**

**1. Row layout.** `_rule()` already returns the baseline, so rows land on lines
exactly. 12 rows at `RULE_PITCH = 26` fills the left page. Each row:
`09:41 · Focus 25m · "wire up the journal"`, with a small paw glyph for focus and a
dimmer mark for breaks. `PawIcon` is procedural and scales to any size, so a 14px
bullet costs nothing.

**2. Day selector** in the large panel's baked ‹ › header on the right page — same
pattern as the week stepper that's already working, but stepping `day_events(key)`.
Clamped to `first_active_day()` so it can't walk into empty history.

**3. Right page** below the selector: that day's score stamp area, its three goal
numbers, and its task list. Reuses the Today page's `_goal_row()` verbatim.

**4. Overflow.** More than 12 events in a day needs paging, not scrolling — a scrollbar
inside a painted book looks wrong. A "+3 more" line on the last rule, and the ‹ › header
gains a page indicator when a day overflows.

**5. Two empty states, not one.** `day()` and `day_events()` disagree for days recorded
before the event log existed: the day has totals but no rows. So:
- no sessions at all → "This page is still blank. Your fox is waiting."
- sessions but no rows → "3 sessions, 1h 20m — recorded before the logbook was kept."

That second state is the entire pre-existing history, so it isn't an edge case.

### Phase 4 — History page (straight after)

Month grid, ‹ › stepping months, clamped to `first_active_day()`. `month_activity()`
already returns the flat 42-cell array and `month_summary()` the totals beneath it.
Cell click jumps to Logbook for that day — the cross-link that makes History feel alive.
Longest streak and total breaks land here, from the All Time panel that couldn't hold
five columns.

**This one does want a sprite** — see #1 in the shopping list below.

### Phase 2 — Today page

Left page: title, polaroid, greeting, three goal bars on ruled lines, today's tasks,
score stamp in the lower-right corner.
Right page: week paw strip in a `day_tab` panel, next-find progress in a `medium_tab`.

### Phase 3 — Logbook page

Left page's ruled lines are the point — one event per line,
`09:41 · Focus 25m · "wire up the journal"`, laid at the tile pitch so text sits on the
lines. Day stepper uses `day_tab`'s baked ‹ › header on the right page.
Empty state: "This page is still blank. Your fox is waiting."

### Phase 4 — History page

Month grid gets a panel sized to it (~7×6 cells at 40×34 ≈ 280×204 plus chrome) rather
than a fixed well, with the ‹ › header stepping months. Month summary and all-time
totals below. Clicking a cell jumps to Logbook for that day.

### Phase 5 — Den page

Real ladder from `den_catalog.gd`. Blocked on art (see below) — 7 of 9 catalog entries
have `texture: ""` and can never be earned.

### Phase 6 — Achievements page

41 defs already exist in `achievement_store.gd`. Needs a home — see open question 2.

---

## Sprite prep

### Actually needed

| # | Asset | Size | Why |
|---|---|---|---|
| 1 | **Day cell for the month grid** | 34×34 | The one asset Phase 4 actually wants. **One** pale rounded cell in the panel's cream — I'll tint it green for an active day and gold for today rather than needing three files. Without it the grid falls back to StyleBox rectangles, which will look flat next to the painted panels. |
| 1b | **Achievements chip glyph** | 45×50 | `Achievements_Tab.png` is now a knife-and-fork, which reads as food or feeding, not achievements. Either a trophy/medal/star in the same chalky white, or tell me the fifth page is something else — see open question 1. |
| 2 | **Everything at 2×** — plate, panels, tabs, frame, title, line | 2× each | The art is painterly, not pixel art. At 960 native on the new 2× window every soft edge becomes a 2×2 block. Re-export at 2×, draw into the same 960×540 rects, and it rasterises 1:1 with device pixels. Biggest visual win on the list and it needs no code change. |
| 3 | Close chip | 45×50 | Still no X anywhere. Optional — see Q2. |
| 4 | Den item sprites ×7 | ~48–96 tall | `lamp, rug, bookshelf, blanket, painting, cushion, clock`. The single biggest content gap in the game — the journal currently promises finds that can never arrive. |
| 5 | Den item icons ×9 | 32×32 | Ladder/inventory thumbnails. |
| 6 | Achievement badges | 64×64 in-game | Author 64 native, master 256 (matches the existing `Welcome_Home,_Fox.png` convention). Plus **one** generic `badge_locked.png` so 41 achievements don't need 82 files. |
| 7 | Score stamps ×3 | 64×64 | bronze/silver/gold wax-seal look. Only if scoring ships. |

### Nice to have, not blocking

- **Horizontal edge piece** for the light-panel kit. Only a vertical edge shipped; for
  top/bottom runs I'll rotate it 90°. On a flat cream fill with a thin border that reads
  fine, but if the panel's light direction looks off at unusual sizes, a dedicated
  horizontal strip fixes it.
- **Per-page titles.** `Fox_Journal-title.png` is art; the other four pages would need
  their own, or I set them in `PixelOperator` and accept the mismatch. Rendering the
  other four as text next to a painted "Fox Journal" will look inconsistent, so either
  four more title PNGs or drop title art entirely and set all five in the font.
- **Empty polaroid.** `fox_frame.png` has the fox painted in, so it won't track the
  player's customised fox colour. An empty frame lets me composite the live fox.

### Explicitly NOT needed

Ruled lines, rings, gutter, page curl, book cover, panel backgrounds, ‹ › arrows, tab
active states (slide + tint in code), bar tracks (a rounded StyleBox matches the painted
style better than a sprite).

---

## Open questions

1. **What is the fifth tab?** The chip is a knife-and-fork now, wired to Achievements.
   That glyph says food. If there's a feeding or treats page in your head, say so and
   Achievements moves or gains a sixth chip at y=365 (the rail has room).
2. **Close affordance.** `Esc` works and the journal icon toggles. Add a red chip to the
   rail, or leave it as is?
3. **Titles** — `Fox_Journal-title.png` is painted art; Logbook/History/Den/Achievements
   currently render in `PixelOperator`, which is visibly a different hand. Either four
   more title PNGs, or I drop the art and set all five in the font.
4. **Daily goals** — `goal_sessions` / `goal_focus_min` as steppers in Settings ▸ Timer,
   or leave at 4 / 100min? They're live and persisted either way; this is only about
   whether the player can change them.

---

## Recommended order

1. ~~Phase 0 data layer~~ — **done**.
2. ~~Phase 1 shell + panel helpers + Today page~~ — **done**.
3. **Phase 3 Logbook, then Phase 4 History** — next. Logbook needs no new art at all;
   History wants the day cell (#1).
4. Re-export at 2× (#2) — drop-in, no code change, biggest remaining visual win.
5. Den art (#4, #5) → Phase 5. Chip glyph (#1b) + badges (#6) → Phase 6.

Logbook is not blocked on anything.
