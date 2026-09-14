# Fox animation art spec

What the game needs from each fox clip, and how to check a frame is right without
opening the project. Written against the set delivered 2026-09-07.

**The one-line version:** the fox should be drawn so that one art pixel is one screen
pixel — the same as the room background already is. Right now it isn't, so the game
scales the art up to compensate, and the fox comes out blockier than the room it's
standing in.

---

## The target

Every clip, once re-exported, has a **6 px dark outline**. That single number is the
whole spec — it's what makes the fox the right size *and* the right resolution at the
same time, and it's checkable on any single frame without reference to anything else.

| clip | canvas now | → **canvas target** | content now | → **content target** | factor |
|---|---|---|---|---|---|
| **sit** | 200 × 140 | **600 × 420** | 127 × 125 | **381 × 375** | ×3 |
| **walk** | 257 × 179 | **514 × 358** | 231 × 175 | **462 × 350** | ×2 |
| **run** | 200 × 132 | **600 × 396** | 160 × 125 | **480 × 375** | ×3 |
| **sleep** | 202 × 156 | **404 × 312** | 174 × 130 | **348 × 260** | ×2 |
| **play** | 1920 × 1080 | see [Play](#play) | — | — | ×⅔ |

"Content" is the drawn fox measured across *all* frames of the clip — the union, not one
frame — so a tail that swings wide is included.

**The factors differ per clip because the delivered set is not internally consistent.**
Measured two ways that agree (outline thickness, and the height of the eye), the clips
fall into two groups: `walk` and `sleep` at one size, `sit` and `run` at two-thirds of
it. That mismatch alone would make the fox visibly grow by half when it stood up and
walked off. The factors above fix the inconsistency and reach 1:1 in the same step.

### Checking a frame

On any finished frame, at 100% zoom:

| measure | must be |
|---|---|
| dark outline thickness | **6 px** |
| eye height | **~42 px** |

Outline is the reliable one; the eye is a sanity check. For reference, the delivered set
measures 3 px outline (walk, sleep) and 2 px (sit, run) — so everything is currently
between two and three times too small.

### Please re-export, don't resize

The frames have hard-edged alpha and no anti-aliasing, which is right and should stay
that way. But it means **scaling a finished PNG up is not the same as drawing it bigger**:

- It adds no detail. Enlarging the delivered sit frames to 600 × 420 gives a file three
  times the size showing exactly the same blocky fox — the game can already do that
  itself, and does today.
- At ×1.5 it isn't even clean, because 1.5 isn't a whole number: some pixels become two
  wide and some three, and the outline goes lumpy.

So the enlargement has to happen **in the source file, before export** — same drawing,
more pixels in it.

---

## Per-clip notes

### sit
Despite the folder name ("Fox Sitting Down 02") this is a **seated idle**, not a
sitting-down transition — the fox is already sitting in frame 1 and still sitting in
frame 25. That's fine and it's what the menu uses. **If a real stand → sit transition is
also wanted, it doesn't exist yet.**

Its ends don't quite meet, so the game plays it out and back rather than looping. That
suits a tail sweep and a blink, so no change needed unless a one-way version is wanted.

### walk
The best clip in the set. Clean 12-frame cycle, ends meet properly. **Only needs the
size change.**

### run
**The cycle doesn't close.** Going from the last frame back to the first is a jump about
1.5× larger than the average step between frames, so it visibly hitches once every
cycle. `walk` and `sleep` both close cleanly, so this is just the last few frames needing
to be pulled back toward frame 1. Until it's fixed the clip isn't usable.

### sleep
Ends meet, breathing reads well. **Only needs the size change.**

### play
This one needs rebuilding rather than resizing. As delivered it's 151 frames × two
layers (Fox, Ball) on a full **1920 × 1080** canvas — about 1.2 GB of video memory per
layer, so the game cannot load it at all in its current form.

Two changes:

1. **Tight canvas.** Crop to the fox, the way the other clips are.
2. **Don't animate the travel.** The fox currently walks across the 1920px canvas, so the
   movement is baked into the frames. It should stay in place in the frame — the game
   moves it. Same for the ball.

Then the same 6 px outline target applies; play is currently about 1.5× over it, so it
comes *down* slightly. Keeping the ball on its own layer is right — please keep doing
that.

---

## Conventions that already work — please keep

- **Frames on their own transparent canvas**, hard-edged alpha, no anti-aliasing.
- **The fox faces left** in every clip. Consistent across the whole set; the game flips
  it to face right.
- **Numbered frames**, one folder per clip. One request: **zero-pad the numbers**
  (`001`, `002` … `152`, not `2` … `152`). Unpadded, a file listing sorts frame 100
  before frame 11, which silently scrambles the order.
- **Consistent footing** within a clip — the fox's feet at the same height across frames,
  except where the animation genuinely leaves the ground. The delivered clips are good on
  this and it's what keeps the fox from bobbing.
