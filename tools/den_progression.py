"""Order the den catalog and set every find's unlock time from one curve.

Rewrites the `unlock_min` of every entry in src/world/den_catalog.gd, in place, and
reorders the entries to match. See context/den-progression-plan.md for the reasoning;
this is that plan made executable so the numbers can be retuned in one place instead of
seventy.

--- The curve ----------------------------------------------------------------

    unlock_min(i) = CEILING * (i / (SLOTS - 1)) ** POWER

CEILING is 6250 focus minutes, which is what "Legend of the Little Fox" already asks for
(250 sessions at the 25-minute default). The den is designed against the same player the
achievements already assume exists.

POWER 1.4 rather than a straight line: linear to 104 hours puts the second find four
hours in, so a player's first session would earn nothing. 1.4 is the gentlest curve that
still pays out on the first session, and it never leaves more than three and a half
sessions between finds.

SLOTS is the size of the ladder, not the number of finds. It is fixed at 101 — the target
catalog size — so that adding find #71 does not reprice the seventy that came before it.
A catalog smaller than SLOTS simply uses the first N rungs and finishes early, which is
the right behaviour while the set is still being drawn.

--- The order ----------------------------------------------------------------

Pace and order are separate questions. The curve says when the fortieth find arrives; the
rules below say which one it is.

  * The opening should visibly change the room. A lamp, a plant, a rug — things you
    notice from across the menu. Not a mug.
  * Categories are spread rather than clumped. Five paintings in a row reads as one
    reward, not five, so the ordering interleaves them.
  * Loud pieces land on milestones. The punk posters and the gothic fireplace are strong
    flavour; they arrive at the session counts the achievements already celebrate, so a
    find and a badge land together.
  * The quiet, large and odd pieces go late, where finds arrive slowly enough that each
    should feel like an event.

--- Usage --------------------------------------------------------------------

    python tools/den_progression.py --dry-run     # print the ladder, change nothing
    python tools/den_progression.py               # rewrite den_catalog.gd

Nothing else in the file is touched: comments, textures, categories and every other field
survive untouched, because entries are moved and re-stamped whole rather than rebuilt.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

CATALOG = Path(__file__).resolve().parent.parent / "src/world/den_catalog.gd"

# Focus minutes for the last rung. 6250 = 250 sessions at 25 minutes each, which is what
# the "Legend of the Little Fox" achievement asks for.
CEILING = 6250.0
# The ladder's length, deliberately the TARGET catalog size rather than the current one —
# see the module note. Adding finds fills empty rungs instead of repricing the set.
SLOTS = 101
POWER = 1.4

# The default session length the curve is described against, for the printed report only.
SESSION_MINUTES = 25

## Milestones worth landing a memorable find on, in sessions. These are the achievement
## thresholds from achievement_store.gd — a find and a badge arriving together reads as
## one bigger moment than either alone.
MILESTONE_SESSIONS = [3, 10, 25, 50, 100, 250]

## Finds that carry the most flavour, in the order they should arrive. Each is placed on
## the nearest milestone rung; the rest of the catalog flows around them.
##
## These are chosen for loudness, not quality — a new player should meet the cosy room
## before the gothic fireplace and the anarchy poster, so the strong stuff is spaced out
## across the whole ladder rather than met at the door.
LOUD = [
    "fireplace_brick",         # the first hearth: the room gets a fire
    "philodendron",            # the rigged plant, and the first thing that moves on its own
    "punk_mosh_pit_poster",    # first poster: the wall stops being tasteful
    "fireplace_gothic",        # gargoyles
    "pop_art_vibrant_woman_painting",
    "fireplace_victorian",     # the most ornate piece in the set, for the far end
]

## What the room opens with. Things that visibly change it, in this order, before the
## generated ordering takes over. desk_plant is first and at zero — it has always simply
## been in the room.
OPENING = [
    "desk_plant",
    "lamp",
    "rug",
    "fern",
    "mug",
    "bookshelf",
    "painting",
    "cushion",
    "blanket",
    "clock",
]

## Categories in the order the interleave visits them. Furniture and plants carry the
## most visible change, so they lead each cycle; paintings are the biggest group and fill
## the gaps.
CATEGORY_CYCLE = ["furniture", "plant", "comfort", "poster", "art"]


def unlock_for(index: int) -> int:
    """Focus minutes for the rung at `index`, counting from 0."""
    return int(round(CEILING * (index / float(SLOTS - 1)) ** POWER))


def parse(text: str) -> tuple[str, list[dict], str]:
    """Split the file into (before, entries, after).

    Entries are kept as raw source blocks so that comments inside them, odd spacing and
    every field this script does not care about all survive being reordered.
    """
    start = text.index("const ITEMS := [")
    end = text.index("\n]\n", start)
    head, body, tail = text[:start], text[start:end], text[end:]

    entries = []
    for match in re.finditer(r'^\t\{"id": "([a-z_0-9]+)"(?:.|\n)*?\},$', body, re.M):
        block = match.group(0)
        category = re.search(r'"category": "(\w+)"', block)
        entries.append({
            "id": match.group(1),
            "block": block,
            "category": category.group(1) if category else "comfort",
        })
    return head + body[: body.index("\n") + 1], entries, tail


def order(entries: list[dict]) -> list[dict]:
    """The catalog in the order finds should arrive.

    Opening first, then the rest interleaved by category so no two neighbours are the
    same kind, with the loud pieces pulled onto milestone rungs afterwards.
    """
    by_id = {e["id"]: e for e in entries}
    result: list[dict] = []
    seen: set[str] = set()

    for find_id in OPENING:
        if find_id in by_id:
            result.append(by_id[find_id])
            seen.add(find_id)

    # Everything else, round-robin across categories so a run of paintings is broken up.
    buckets: dict[str, list[dict]] = {name: [] for name in CATEGORY_CYCLE}
    for entry in entries:
        if entry["id"] in seen:
            continue
        buckets.setdefault(entry["category"], []).append(entry)

    # Each category is spread across the WHOLE remaining ladder rather than taken a
    # round at a time. A plain round-robin drains the small categories first — there are
    # five plants against thirty-eight paintings — and leaves a tail of nothing but
    # pictures, which is exactly the clumping this is meant to avoid.
    #
    # So every find is given a position in [0,1] by how far through its own category it
    # is, and the whole lot is sorted on that. A category of five lands at 0.1, 0.3, 0.5,
    # 0.7, 0.9; one of thirty-eight fills in between. Ties break on CATEGORY_CYCLE, which
    # is what puts furniture and plants ahead of paintings at the same depth.
    spread: list[tuple[float, int, dict]] = []
    for name, bucket in buckets.items():
        rank = CATEGORY_CYCLE.index(name) if name in CATEGORY_CYCLE else len(CATEGORY_CYCLE)
        for i, entry in enumerate(bucket):
            spread.append(((i + 0.5) / len(bucket), rank, entry))
    spread.sort(key=lambda row: (row[0], row[1]))
    result.extend(entry for _, _, entry in spread)

    return place_loud(result)


def place_loud(ordered: list[dict]) -> list[dict]:
    """Moves the flavour pieces onto the milestone rungs.

    Each loud find is lifted out and reinserted at the rung whose unlock time is nearest
    a milestone, so it arrives in the same stretch of play as the achievement. Done after
    the interleave rather than before, because moving one find shifts every rung after it
    and the milestones have to be measured against the final order.
    """
    # A milestone past the end of the catalog has no rung to land on yet — the 250-session
    # one sits at rung 101 and there are seventy finds. Those are dropped rather than
    # clamped onto the last entry, where several would pile up on one rung.
    targets = []
    for sessions in MILESTONE_SESSIONS:
        minutes = sessions * SESSION_MINUTES
        rung = next((i for i in range(SLOTS) if unlock_for(i) >= minutes), SLOTS - 1)
        if rung < len(ordered):
            targets.append(rung)

    result = list(ordered)
    for find_id, rung in zip(LOUD, targets):
        current = next((i for i, e in enumerate(result) if e["id"] == find_id), -1)
        if current < 0 or rung >= len(result):
            continue
        entry = result.pop(current)
        result.insert(rung, entry)

    # Any flavour piece with no milestone left goes to the far end, where finds arrive
    # slowly enough that each should feel like an event.
    for find_id in LOUD[len(targets):]:
        current = next((i for i, e in enumerate(result) if e["id"] == find_id), -1)
        if current >= 0:
            result.append(result.pop(current))
    return result


def restamp(block: str, minutes: int) -> str:
    """The same entry with a new unlock_min, everything else untouched."""
    return re.sub(r'"unlock_min": \d+', f'"unlock_min": {minutes}', block, count=1)


def report(ordered: list[dict]) -> None:
    print(f"{len(ordered)} finds on a {SLOTS}-rung ladder, power {POWER}, ceiling {CEILING:.0f} min\n")
    milestones = {s * SESSION_MINUTES for s in MILESTONE_SESSIONS}
    loud = set(LOUD)
    for i, entry in enumerate(ordered):
        minutes = unlock_for(i)
        mark = ""
        if entry["id"] in loud:
            mark = "  <- flavour"
        near = min(milestones, key=lambda m: abs(m - minutes))
        if abs(near - minutes) < 60 and entry["id"] in loud:
            mark += f" (near the {near // SESSION_MINUTES}-session badge)"
        if i < 12 or entry["id"] in loud or i == len(ordered) - 1:
            print(f"  {i + 1:3d}. {minutes:5d} min ({minutes / 60:6.1f} h)  {entry['id']:34s}{mark}")
    print(f"\n  last find at {unlock_for(len(ordered) - 1) / 60:.1f} h; "
          f"the full {SLOTS}-rung ladder ends at {unlock_for(SLOTS - 1) / 60:.1f} h")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    text = CATALOG.read_text(encoding="utf-8")
    head, entries, tail = parse(text)
    if not entries:
        raise SystemExit("no catalog entries found — has den_catalog.gd changed shape?")

    ordered = order(entries)
    if len(ordered) != len(entries):
        raise SystemExit(f"ordering lost entries: {len(entries)} in, {len(ordered)} out")
    if ordered[0]["id"] != OPENING[0]:
        raise SystemExit(f"{OPENING[0]} must be the first find, got {ordered[0]['id']}")

    report(ordered)
    if args.dry_run:
        print("\nDry run: nothing written.")
        return

    blocks = [restamp(e["block"], unlock_for(i)) for i, e in enumerate(ordered)]
    CATALOG.write_text(head + "\n".join(blocks) + tail, encoding="utf-8")
    print(f"\nWrote {len(blocks)} entries to {CATALOG}")


if __name__ == "__main__":
    main()
