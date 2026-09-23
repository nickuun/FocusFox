# Den progression — the unlock curve for ~101 finds

The catalogue went from 9 finds to 70 in two sessions, and the unlock times came along as
placeholders: flat 30-minute steps I invented, ending at 1460 minutes. With couches fixed,
more plants, and whatever else lands, the target is **about 101 finds**. This is the plan
for when each one comes home.

## The problem with what's there now

Everything unlocks inside **24 hours of focus**. That is the whole collection gone before
a committed player is a third of the way through the achievement ladder this game already
ships:

| Achievement | Sessions | Focus hours at the 25-minute default |
|---|---|---|
| One Paw Forward | 3 | 1.2 |
| Finding Your Rhythm | 10 | 4.2 |
| Fox Flow | 25 | 10.4 |
| Den Discipline | 50 | 20.8 |
| Deep Work Denizen | 100 | 41.7 |
| **Legend of the Little Fox** | **250** | **104.2** |

The achievements already assume a 104-hour player exists. The den should still have
something to give that player. **That is the number to design against**, and it is not a
guess — it is what the game already promises elsewhere.

## The shape

`unlock_min(i) = CEILING * (i / (N-1)) ^ 1.4`, with `N = 101` and `CEILING = 6250`
(Legend of the Little Fox, in focus minutes).

A power curve rather than a straight line, because a straight line to 104 hours puts the
second find four hours in — a player's first session would earn nothing, which is the
worst possible first impression for a game about showing up.

Why 1.4 specifically, against the alternatives:

| Curve | 1 session | 3 sessions | 1 week (~6h) | 1 month (~25h) | 3 months (~75h) |
|---|---|---|---|---|---|
| Linear | 1 | 2 | 6 | 25 | 73 |
| **Power 1.4** | **2** | **5** | **14** | **37** | **80** |
| Power 1.6 | 4 | 7 | 17 | 41 | 82 |
| Power 2.0 | 7 | 11 | 25 | 49 | 85 |

1.4 is the gentlest curve that still pays out on the very first session. 1.6 and 2.0 are
more generous early but spend the collection too fast — at 2.0 a month in you have half
of everything, and the back half has to stretch across seventy hours.

### What it feels like

| After | Items |
|---|---|
| First session (25 min) | 2 |
| First day (3 sessions) | 5 |
| First week | 14 |
| First month | 37 |
| Three months | 80 |
| Everything | 104 h |

And the wait between finds, which is the number that actually decides whether it feels
mean:

| At item | Next find in |
|---|---|
| 1 | 0.4 sessions |
| 5 | 1.0 sessions |
| 20 | 1.8 sessions |
| 50 | 2.6 sessions |
| 100 | 3.5 sessions |

It never gets worse than three and a half sessions. The curve stretches, but it never
stalls — which is the failure mode to avoid, not slowness itself.

## Two things the curve does not decide

**Order is a separate question from pace.** The curve says *when* the 40th find arrives,
not *which* one it is. Ordering wants to be done by hand, and the rules worth keeping:

- The first five should be things that visibly change the room — a lamp, a plant, a rug.
  Not a mug.
- Spread the categories. Five paintings in a row reads as one reward, not five.
- Put the loudest pieces later. The punk posters and the gothic fireplace are strong
  flavour, and a new player should meet the cosy room first.
- The starter plant stays at 0, and the mug should stay early; both are part of what the
  den already feels like.

**The long tail wants a reason to exist.** Past about item 80 the finds arrive slowly
enough that they should feel like an event — that is the natural place for the largest,
oddest, most characterful pieces rather than another small framed picture.

## Implementation

Generated, not typed. Seventy hand-written numbers are how the current placeholders
happened, and a hundred and one would be worse.

Add to `tools/` a script that rewrites the `unlock_min` of every entry in
`den_catalog.gd` from the curve, preserving catalogue order. Then the curve is one
constant and the ordering is the only thing anyone edits by hand.

Two implementation notes:

- **`DenCatalog.ITEMS` must stay sorted by `unlock_min`** — `next_find()` walks the list
  in order and the journal draws its ladder from it. The generator sorts, so this stays
  true by construction rather than by care.
- **The starter plant is unlock 0** and must remain the first entry. The curve gives item
  1 a value of 0 anyway, so this falls out naturally — but it is worth an assertion rather
  than a coincidence.

### Before Steamworks

`achievement_store.gd` still compares against hardcoded thresholds — `perfect_little_desk`
at 5 and `interior_foxcorator` at 10. At 101 finds, "Unlock 10 den items" is an early-game
achievement wearing a completionist's name. Derive the threshold from `DenCatalog.size()`
and reword to "Bring every find home" *before* the Steam achievement list exists, because
after that the description is frozen on Valve's side.

## The open question

101 finds across 104 hours assumes the den is the main long-term reward. If the fox
revamp brings its own progression — new animations, behaviours, things it learns — then
the two ladders are competing for the same hours and the den's curve should probably be
steeper, finishing nearer 60 hours and leaving the top end to the fox.

Worth deciding before the numbers go in, because it changes the ceiling and nothing else.
