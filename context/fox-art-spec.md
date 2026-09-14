# Fox animation art spec

For the fox animations. Written against the set delivered 2026-09-07, revised
2026-09-14 after getting all of it into the game.

**The short version:** everything you sent is in the game, at a consistent size, and it
looks great. The sizes have been evened out by resizing on our side — nothing needed
redrawing. The `play` animation turned out to be so complete that we cut three extra
clips out of it, which covers most of what was still missing.

**There is a pack of files to go with this doc** (`build/fox-art-pack`). It contains the
frames the game is actually running now, at the size it runs them. Its README lists what's
worth fixing in each clip. **If you tidy anything up, please work on those files rather
than your originals** — the originals are no longer what the game loads.

---

## 1. What you already got right

These are all easy to get wrong and none of them are wrong, so please keep doing them:

- **The colours are exact.** Every clip uses the same seven colours, and the two body
  oranges are precisely `#d67941` and `#9d5021` in all of them. The game recolours the fox
  for the player's colour options by looking for exactly those two values, so if they had
  drifted even slightly between clips, the colour options would have silently stopped
  working on some of them. They don't. This is the single most valuable thing you've been
  consistent about, and it's the kind of thing that's very hard to fix after the fact.
- **Hard edges, no anti-aliasing.** Every pixel is either fully solid or fully
  transparent. Exactly right for this game.
- **The fox always faces left.** Consistent across the whole set; the game flips it to
  face right.
- **Separate layers for the fox and the ball.** Right call — it's what let us reuse the
  ball animation for three other things. Please keep doing it (see §4d).
- **Footing is steady.** The fox's feet stay at a consistent height across the frames of a
  clip. That's what stops it bobbing in-game, and it's easy to get wrong.

---

## 2. Sizes: sorted, and not your problem any more

The clips arrived at three different sizes relative to each other, because each one got
resized by hand at a different point:

| clip | as delivered | what we did |
|---|---|---|
| `walk`, `sleep` | the reference | nothing |
| `sit`, `run` | two-thirds size | scaled up ×1.5 |
| `play` | about 4.6× too big | scaled down, and cut into four clips |

**The ×1.5 on `sit` and `run` was exact, not approximate.** Those two were drawn with 2px
outlines where `walk` has 3px, and 2 × 1.5 = 3, so scaling them up landed every outline
exactly on the reference thickness with no blurring and no new colours. They should need
no cleanup at all — worth a glance, but we're not expecting anything.

**Going forward, don't resize before sending.** Send whatever size you finish at and we'll
match it up — there's a script that does the cropping and scaling and checks the result.
Working out sizes by hand is the one thing that's been causing trouble, and it's the one
thing you can stop doing.

---

## 3. What we did to your `play` animation

Your `Fox Play 02` is one continuous 151-frame performance, and it turned out to contain
four separate things the game needed. It's now four clips:

| new clip | your frames | what it is |
|---|---|---|
| `idle` | 5–23 | the fox standing, blinking, tail moving |
| `stalk` | 61–99 (every 2nd) | the low creep |
| `pounce` | 97–104 | the leap, stopping just before the paws land |
| `play` | 125–151 | on its back, kicking the ball |

Each was cropped to the fox, scaled to match the rest of the set, and — for the first
three — had the grey ball removed automatically.

The cut points were chosen by measurement rather than by eye, so they're best guesses.

---

## 4. What would help most next

Roughly in order, and **please don't take all of this at once** — the den items come first.
Everything here is a "would be nice", not a blocker; the game runs on what it has.

### a. A standing idle drawn as a **loop** — the big one
The `idle` we cut out of `play` works, but it isn't a loop. It's a slice of a longer
performance, so the last frame doesn't lead back into the first and it visibly jumps. The
game currently hides that by playing it forwards and then backwards.

This is the pose the desktop pet holds most of the time, so it's the one most worth having
properly. It would be the fox standing still, facing left, with something small and
continuous: breathing, an ear flick, the tail.

> **What "a loop" means here, since it comes up a few times:** the game plays these over
> and over with no gap, so the last frame has to lead straight back into the first. The
> usual way to check is to flip between your first and last frames — if that looks like a
> jump, it'll look like a jump in the game. `walk` and `sleep` both do this correctly and
> are good references.

### b. Close the `run` cycle
`run` is the one clip with an actual animation problem: the last frame doesn't lead back
into the first, so it hitches once every cycle. It's a fix to the last few frames rather
than a redraw — they need pulling back toward frame 1. Until then the game can't use the
clip, so it isn't hooked up to anything.

### c. The roll section without the ball
In `play` (the rolling-on-its-back part) the fox is holding the ball, and the grey ball is
drawn into the fox layer, so we couldn't separate them the way we could elsewhere. The
game draws its own blue ball, so the grey one clashes with it.

If that section could be redrawn with the paws in the same positions but **no ball in the
fox layer at all** — ball only on the ball layer, as you already do — the game can put its
own ball into the fox's paws.

### d. Nice to have, no rush
- **A glance-around** — a few seconds of the fox looking to one side and back, starting and
  ending on the standing idle pose. Plays occasionally so the pet doesn't look frozen.
- **A stand → sit transition.** There's an older one, but it ends facing front while the
  current `sit` is angled, so they don't join up. Only worth it if we want the fox to
  visibly settle rather than cut straight to sitting.

---

## 5. Conventions to keep

- **Don't resize before sending** (§2) — the only actual change being asked for.
- Frames on their own transparent canvas, hard-edged alpha, no anti-aliasing.
- The fox faces left.
- One folder per clip, numbered frames. One small request: **zero-pad the numbers**
  (`001`, `002` … `152`, not `2` … `152`). Unpadded, a file listing puts frame 100 before
  frame 11, which quietly scrambles the order — it's been caught every time so far, but
  it's one more thing that can go wrong.
- Keep the ball, and anything else that moves independently, on its own layer.
- Consistent footing within a clip.
- **Canvas size doesn't matter and doesn't need to be consistent between clips.** The game
  measures where the fox's feet are in each clip and lines them up itself, so please don't
  spend time matching canvases or margins.

---

## Appendix: notes for the repo, not for the artist

The fox is deliberately **not** drawn at final screen size — it's drawn smaller and scaled
up, so it reads slightly chunkier than the room around it. That's a chosen look, and it's
why "make everything bigger" is no longer on this list. What the nearest-neighbour filter
needs is a whole number of physical pixels per source texel, not 1:1.

All eight clips are now `art_scale` 1.0: the size matching happens once at import instead
of being compensated for at runtime.

`assets/fox/animations/v2/` is **generated output**. The source is the delivery outside the
repo, `tools/fox_clips.json` records which delivered frames become which clip, and
`tools/fox_import.py` does the work. `--pack` builds the artist folder described at the top.
Editing the PNGs directly is pointless — the next run overwrites them.
