# Fox Journal revamp — implementation plan

Target: replace the flat full-window `JournalPanel` with an open-book spread that has
edge notches switching between pages — Today, Logbook, History, Den, Achievements —
with a page-turn animation and per-day scoring.

Design space is the launcher's **960×540** viewport, 1:1 with art pixels (same
convention as the settings panel — see `settings-panel-layout` in memory).

---

## The honest blocker: the data layer

Everything visual in the mockups is easy. What isn't easy is that **`StatsStore` records
aggregates, not events.** Per day it keeps `{sessions, focus, breaks, tasks[]}`. That
cannot produce:

- a **logbook** (needs per-session rows with a clock time and duration)
- **"focus events for that day"** (needs the events)
- a **score per day** (needs enough detail to be worth scoring)
- **week ‹ › navigation** (`week_activity()` is hardcoded to the current week)
- a **month grid** (no month view at all)

So Phase 0 is a data-layer change, and it gates most of the fun. Two consequences worth
deciding up front:

1. **Old history can't be back-filled.** Existing `days` entries stay and keep powering
   the totals and the trail, but the logbook and per-day scores only have detail from the
   day the new build ships. The Logbook page needs a graceful "nothing recorded yet"
   state for older days.
2. **Two bugs to fix while in here.** `JournalPanel.DEN_FINDS` is a made-up list of eight
   items ("a lamp", "a soft rug", …) that has no relationship to `Den.ITEMS`, which
   contains exactly one entry (`mug`). The journal is currently promising the player den
   items that will never arrive. Also `Den.ITEMS` unlocks at 30 min while the journal's
   ladder assumes 60-minute steps. The catalogue needs to become one shared source of
   truth that both read.

---

## Phase 0 — Data foundation

**`stats_store.gd`**

- Add an **event log**: `events: Array[Dictionary]`, each
  `{ts: int, kind: "focus"|"break", seconds: float, task: String, session_id: String}`.
  Append in `record_focus` / `record_break` (both already receive `started_at`).
- Cap the log (e.g. last 2000 events ≈ years of use) so the config file stays small.
- New queries:
  - `day(key) -> Dictionary` — the aggregate for any day, not just today
  - `day_events(key) -> Array` — the logbook rows for a day
  - `day_score(key) -> Dictionary` — `{score, tier, goal_pct}` (formula below)
  - `week_activity(week_offset := 0)` — generalise the existing method
  - `month_activity(year, month) -> Array` — one entry per cell incl. leading blanks
  - `first_active_day() -> String` — so ‹ › navigation knows where to stop
- Add **daily goals**, persisted with the other settings: `goal_sessions` (default 4),
  `goal_focus_min` (default 100). These drive the Today page's progress bars, and they
  belong in the settings panel's Timer tab as two more stepper rows.

**Score formula** (proposal — easy to tune, one place):

```
goal_pct = 0.6 * min(1, focus_min / goal_focus_min) + 0.4 * min(1, sessions / goal_sessions)
score    = round(goal_pct * 100)
tier     = none | bronze (>=50) | silver (>=100) | gold (>=150, i.e. 1.5x goal)
```
Breaks deliberately don't add score — resting shouldn't be a scored chore — but a day with
zero breaks and 3+ sessions gets a gentle "remember to rest" note instead.

**`den_catalog.gd`** (new)

Move the item catalogue out of `den.gd` into one resource both the den and the journal
read: `{id, name, ladder_icon, room_texture, unlock_min, default_x}`. Den items then
unlock on a single consistent schedule, and the journal's ladder shows the *real* next
five finds.

---

## Phase 1 — Book shell

**`journal_book.gd`** (replaces `journal_panel.gd`, which becomes the Today page)

- Spread art, centre gutter, ring binding, drawn once.
- **Notch rail**: tabs on both outer edges. Left = pages, right = actions.
  - Left: Today (paw) · Logbook (pencil) · History (book) · Den (chest) · Achievements (trophy)
  - Right: Close (X) · Settings (gear, hands off to the settings panel)
- Page switching = show/hide page Controls, same pattern as the settings tabs, plus:
- **Page-turn animation**: outgoing page's inner content scales/skews on X to 0 while the
  incoming one grows back, ~0.22s, with the `open`/`close` sfx already in `Audio`.
  Cheap, reads as a turn, no shader needed.
- Notch behaviour: active notch slides ~6px outward and brightens; hover nudges 2px.
- Keyboard: `Q`/`E` or `Left`/`Right` cycle pages, `Esc` closes.
- Bottom edge keeps the thin progress strip from the mockup — it shows the active page
  index, so it doubles as a "there are more pages" hint.

---

## Phase 2 — Today page (the main screen)

Mostly a re-skin of what exists, plus the bars and the score.

- Fox portrait in a polaroid frame, using the current fox palette so it matches the
  player's fox.
- Greeting line: "You and your fox have focused for 12h 35m together."
- Three goal bars: Focus sessions / Time focused / Breaks taken, each `value / goal`.
- **Today's score** as a stamp (bronze/silver/gold) pressed into the page corner, with the
  number underneath. Animates in with a little squash when the page opens.
- Today's tasks as a short list rather than the current single truncated line.
- Right page: This Week strip (7 paws) + the Next Den Find ladder.

## Phase 3 — Logbook page

- The handwritten left page from the first mockup: one ruled row per event.
  `09:41  ·  Focus 25m  ·  "wire up the journal"` with a paw bullet for focus and a leaf
  for breaks.
- Day selector at the top (‹ Today ›), stepping through days that have events.
- Scrollable when a day overflows; ruled lines are baked art so rows align to them.
- Empty state: "This page is still blank. Your fox is waiting."
- Stretch: a free-text note per day, saved to the event log. This is the one genuinely
  new *input* in the whole feature, so it's deliberately last.

## Phase 4 — History page

- Month grid (the second mockup): weekday header, day cells, paw in each active cell,
  today ringed in gold, trail runs joined by the dotted connector.
- ‹ › steps months, clamped to `first_active_day()`.
- Month summary strip beneath: sessions, focus time, best day, days active.
- Cell hover shows a tooltip with that day's numbers; clicking a cell jumps to the
  Logbook page for that day. That cross-link is what makes History feel alive rather
  than decorative.
- All-Time card keeps the five existing totals.

## Phase 5 — Den page

- The ladder from the mockup: next five finds as icons with unlock thresholds, current
  one highlighted and sparkling, earned ones stamped.
- Progress bar to the next find, driven by the real catalogue.
- "Your fox brought home N of M finds."

## Phase 6 — Achievements page

- Grid of badges, 41 defs already exist in `achievement_store.gd`.
- Earned = coloured badge, locked = greyed generic badge + description.
- Category rows matching the existing groupings (First Steps, Session Milestones,
  Time-Based, Streaks, Fox Interaction, Customisation).
- Counter: "12 / 41 found."

## Phase 7 — Polish

- Leaf decorations flanking the title, gentle idle sway.
- Sparkle particles on newly unlocked things.
- Ribbon bookmark that sits at the active page.
- Corner page-curl affordance, clickable, turns to the next page.
- Opening the journal plays a page-flutter; the fox's portrait blinks occasionally.

---

## Checklist

**Phase 0 — data**
- [ ] `stats_store.gd`: event log + append in `record_focus`/`record_break` + cap
- [ ] `stats_store.gd`: `day`, `day_events`, `day_score`, `first_active_day`
- [ ] `stats_store.gd`: `week_activity(offset)`, `month_activity(year, month)`
- [ ] Daily goals: persisted in `focus_fox.cfg`, two stepper rows in Settings ▸ Timer
- [ ] `den_catalog.gd` extracted; `den.gd` and the journal both read it
- [ ] Delete `JournalPanel.DEN_FINDS` / `DEN_STEP_MIN` fiction

**Phase 1 — shell**
- [ ] `journal_book.gd` with spread art + ring binding
- [ ] Notch rail, 5 page tabs + 2 action tabs, hover/active states
- [ ] Page switching + page-turn tween + sfx
- [ ] Keyboard nav, bottom page-index strip
- [ ] `world.gd` wiring: journal icon opens the book, Esc/X closes, gear notch → settings

**Phases 2–6 — pages**
- [ ] Today page (portrait, greeting, 3 goal bars, score stamp, tasks, week strip, den ladder)
- [ ] Logbook page (ruled event rows, day selector, scroll, empty state)
- [ ] History page (month grid, ‹ › months, summary strip, cell → logbook cross-link)
- [ ] Den page (find ladder, progress, earned stamps)
- [ ] Achievements page (badge grid, categories, counter)

**Phase 7 — polish**
- [ ] Leaves, sparkles, ribbon bookmark, page-curl, open flutter

---

## Sprite shopping list

Sizes are art-native pixels at 1:1 with the design viewport. Where I say "one shape, I'll
tint it", that's me asking for **less** art, not more — Godot can recolour a neutral sprite
per state, so a single well-drawn shape often beats four variants.

### Book chrome — needed before anything renders

| # | Asset | Size | Description |
|---|---|---|---|
| 1 | `journal_spread.png` | 880×504 | The open book: two cream pages, centre gutter shadow, outer cover/leather border. The single most important asset — everything else sits on it. |
| 2 | `journal_rings.png` | 40×32 | **One** binding ring. I'll repeat it down the gutter, so I only need one. |
| 3 | `page_ruled_line.png` | 360×28 | One ruled row for the logbook — a faint line with the row's vertical spacing baked in. Repeated down the page so text lands on the lines. |
| 4 | `page_curl.png` | 72×72 | Bottom-right corner curl for the "turn page" affordance. Ideally 2 frames (flat, lifted) for hover. |
| 5 | `notch.png` | 56×48 | **One blank notch tab** — a rounded rectangle poking out from the page edge, drawn neutral/pale. I'll tint it per tab and mirror it for the right side. |
| 6 | `notch_active.png` | 56×48 | Same shape, brighter/raised, for the selected tab. |

### Icons — 28×28 each, dark-on-transparent so I can tint

| # | Asset | Description |
|---|---|---|
| 7 | `icon_paw.png` | Today page. |
| 8 | `icon_pencil.png` | Logbook page. |
| 9 | `icon_book.png` | History page. |
| 10 | `icon_chest.png` | Den page. You already have the settings `Lock Icon` chest — a sibling in this style is perfect. |
| 11 | `icon_trophy.png` | Achievements page. |
| 12 | `icon_gear.png` | Settings notch (a 28px cousin of the existing gear). |
| 13 | `icon_close.png` | Close notch. |
| 14 | `icon_arrow.png` | One right-pointing chevron for ‹ › — I'll flip it for left. |

### Calendar + trail

| # | Asset | Size | Description |
|---|---|---|---|
| 15 | `paw_print.png` | 32×32 | A proper pixel paw print to replace the procedurally-drawn `PawIcon`. Solid, mid-brown — I'll fade it for inactive days rather than needing a second file. |
| 16 | `day_cell.png` | 36×36 | Empty rounded day cell for the month grid, pale. |
| 17 | `day_cell_active.png` | 36×36 | Same cell, green-tinted, for a day with sessions. |
| 18 | `day_cell_today.png` | 36×36 | Same cell, gold, for today — the ringed cell in your mockup. |
| 19 | `trail_dot.png` | 8×8 | One dot for the dotted connector between consecutive active days. |

### Progress bars

| # | Asset | Size | Description |
|---|---|---|---|
| 20 | `bar_track.png` | 200×16 | Empty bar, rounded caps. I'll 3-slice it so it works at any width. |
| 21 | `bar_fill.png` | 200×16 | The filled bar, same silhouette. Green like the mockup. |

### Score stamps

| # | Asset | Size | Description |
|---|---|---|---|
| 22 | `stamp_bronze.png` | 64×64 | An ink-stamp / wax-seal look, pressed into the page. Slightly rough edges sell it. |
| 23 | `stamp_silver.png` | 64×64 | As above. |
| 24 | `stamp_gold.png` | 64×64 | As above, the celebratory one. |

### Den finds — the big content ask

The den has exactly one item today (`mug`). The mockup's ladder shows five, and the ladder
looks thin with fewer than ~8. **Each find needs two sizes:**

| # | Asset | Size | Description |
|---|---|---|---|
| 25 | `den/<item>_icon.png` | 32×32 | The ladder/inventory icon. |
| 26 | `den/<item>.png` | ~48–96 tall | The room-scale sprite that actually appears in the launcher and gets flung around. |

Suggested set of 8, reading as a den slowly furnishing itself — **lamp, rug, bookshelf,
blanket, potted fern, small painting, cushion, wall clock**. Those are the eight names the
journal already invents, so shipping them makes the existing promise true. A ninth
"birdhouse" and a "gold bar" would match your mockup's later rungs.

### Achievements

41 achievements × earned + locked = 82 icons is not a reasonable ask. Instead:

| # | Asset | Size | Description |
|---|---|---|---|
| 27 | `badge_locked.png` | 48×48 | One generic locked badge — a silhouette/question-mark plaque. Used for every unearned achievement. |
| 28 | `badge_<category>.png` ×6 | 48×48 | One badge per category (First Steps, Sessions, Time, Streaks, Fox, Customisation). Earned achievements show their category badge until bespoke art exists. |

Then bespoke 48×48 icons can trickle in per achievement over time — the code will prefer a
per-id icon and fall back to the category badge, so you can add them one at a time without
another code change. You already have `Welcome_Home,_Fox.png` in that spirit.

### Decoration

| # | Asset | Size | Description |
|---|---|---|---|
| 29 | `leaf.png` | 32×32 | One leaf; I'll mirror it for the other side of the title and sway both. |
| 30 | `polaroid_frame.png` | 120×140 | The photo frame for the fox portrait on the Today page — white border, slight tilt, small shadow. |
| 31 | `sparkle.png` | 16×16 | One sparkle for newly-unlocked things. 3–4 frames if you fancy it, otherwise I'll scale/fade a single one. |

### Priority

If you want to draw in the order I can use it:

1. **#1 `journal_spread.png`** — nothing can be laid out until this exists.
2. **#5, #6 notch + active** and **#7–14 icons** — unlocks the whole shell.
3. **#15–19 calendar/trail** and **#20–21 bars** — unlocks Today + History.
4. **#22–24 stamps**, **#3 ruled line** — unlocks Logbook + scoring.
5. **#25–26 den items** — the content pass; the ladder works with placeholders until then.
6. **#27–28 badges**, **#29–31 decoration** — last.

I can build Phase 0 (all the data work) and the page *logic* against coloured rectangles
before any art lands, so nothing here blocks a start.

---

## Open decisions

1. **Window size.** The journal is a full-window overlay in a 960×540 launcher. Everything
   above fits, but it's snug — the mockups are drawn much roomier. If the journal should
   feel as spacious as the mockup, the launcher wants to be ~1200×675, which affects the
   whole menu, not just this. Worth deciding before I lay out pages.
2. **Score visibility.** Is the daily score a gentle flourish (a stamp you notice) or a
   real mechanic (streaks of gold days, an achievement for it)? I've planned the former.
3. **Logbook notes.** Do you want the free-text note per day, or is the logbook purely a
   record of what happened? The former is the only new input in the feature.
4. **Goals in settings.** Happy for me to add `goal_sessions` / `goal_focus_min` steppers
   to Settings ▸ Timer, or should goals stay fixed defaults?
