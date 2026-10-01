"""Build the Steamworks achievement upload kit from the game's own definitions.

Steamworks has no bulk import: every achievement is typed into a form, with an achieved
and an unachieved icon uploaded by hand. This makes that a copy-and-upload job rather
than a transcription one, and checks the art on the way.

Reads DEFS straight out of src/world/achievement_store.gd, so rerun it whenever an
achievement changes. Writes to build/steam/achievements/ (gitignored, and outside the
export):

    icons/<api_name>_achieved.png     the unlocked badge, 4x nearest-neighbour
    icons/<api_name>_unachieved.png   the locked badge, likewise
    achievements.csv                  one row per achievement, in DEFS order
    checklist.md                      the same, as a tick-off list for the form

The API name is the DEFS id, which is what achievement_store.gd passes to
Steam.setAchievement, so the two cannot drift.

Usage: python tools/make_steam_achievements.py
Exits 1 if any achievement is missing art, is the blank Template plaque, or is a copy
of another achievement's badge. The icons are still written either way.
"""

import csv
import re
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
STORE = ROOT / "src/world/achievement_store.gd"
ART = ROOT / "assets/achievements"
OUT = ROOT / "build/steam/achievements"

# Badges are drawn at 64. 256 is the icon size Steamworks asks for, and an exact 4x,
# so nearest-neighbour keeps every pixel square.
BADGE_SIZE = 64
ICON_SIZE = 256
# Steam's starting cap; more unlock once the app reaches the Profile Features threshold.
STEAM_ACHIEVEMENT_CAP = 100

ENTRY = re.compile(
    r'^\s*"(?P<id>\w+)":\s*\{\s*"label":\s*"(?P<label>[^"]*)",\s*'
    r'"desc":\s*"(?P<desc>[^"]*)",\s*"hidden":\s*(?P<hidden>true|false)'
)


def read_defs() -> list[dict]:
    text = STORE.read_text(encoding="utf-8")
    block = text[text.index("const DEFS"):text.index("\n}\n", text.index("const DEFS"))]
    defs = [m.groupdict() for line in block.splitlines() if (m := ENTRY.match(line))]
    # A def written in some other shape would be silently skipped by the regex, so
    # count the labels independently and refuse to guess.
    labels = block.count('"label":')
    if len(defs) != labels:
        sys.exit(f"read {len(defs)} achievements but DEFS has {labels} labels; "
                 "an entry's format has drifted from the one-line pattern")
    for d in defs:
        d["hidden"] = d["hidden"] == "true"
    return defs


def badge(folder: Path, name: str, problems: list[str]) -> Image.Image | None:
    path = folder / f"{name}.png"
    if not path.exists():
        problems.append(f"{folder.name}: missing {name}.png")
        return None
    img = Image.open(path).convert("RGBA")
    if img.size != (BADGE_SIZE, BADGE_SIZE):
        problems.append(f"{folder.name}: {name}.png is {img.size[0]}x{img.size[1]}, "
                        f"expected {BADGE_SIZE}x{BADGE_SIZE}")
        return None
    return img


def main() -> int:
    defs = read_defs()
    problems: list[str] = []
    warnings: list[str] = []

    if len(defs) > STEAM_ACHIEVEMENT_CAP:
        problems.append(f"{len(defs)} achievements; Steam starts apps at {STEAM_ACHIEVEMENT_CAP}")

    # Only Template's *unlocked* image is a blank plaque. Its locked one is Ready to
    # Focus's real stopwatch, so a match there means nothing on its own — copies of it
    # are caught by the duplicate check below instead.
    blank = badge(ART / "Template", "unlocked", warnings)

    (OUT / "icons").mkdir(parents=True, exist_ok=True)
    for old in (OUT / "icons").glob("*.png"):
        old.unlink()

    seen_art: dict[bytes, str] = {}
    rows = []
    for d in defs:
        api = d["id"]
        # Same rule as journal_book.gd _achievement_art(): Windows won't take "?".
        folder = ART / d["label"].replace("?", "")
        art = {n: badge(folder, n, problems) for n in ("locked", "unlocked")}
        if None in art.values():
            continue
        for n, img in art.items():
            # Art authored by duplicating a folder: the file exists and loads, but it's
            # the blank plaque or another badge's picture.
            if n == "unlocked" and blank is not None and img.tobytes() == blank.tobytes():
                problems.append(f"{folder.name}: {n}.png is the blank Template plaque")
                continue
            key = n.encode() + img.tobytes()
            if key in seen_art:
                problems.append(f"{folder.name}: {n}.png is a copy of {seen_art[key]}'s")
            seen_art.setdefault(key, folder.name)
        if art["locked"].tobytes() == art["unlocked"].tobytes():
            warnings.append(f"{folder.name}: locked and unlocked are the same image")

        names = {"unlocked": f"{api}_achieved.png", "locked": f"{api}_unachieved.png"}
        for n, img in art.items():
            img.resize((ICON_SIZE, ICON_SIZE), Image.NEAREST).save(OUT / "icons" / names[n])
        rows.append({
            "api_name": api,
            "display_name": d["label"],
            "description": d["desc"],
            "hidden": "yes" if d["hidden"] else "no",
            "achieved_icon": names["unlocked"],
            "unachieved_icon": names["locked"],
        })

    with open(OUT / "achievements.csv", "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()) if rows else ["api_name"])
        writer.writeheader()
        writer.writerows(rows)

    lines = [
        "# Steamworks achievements",
        "",
        "Enter these in order under *Stats & Achievements → Achievements*. API names must",
        "match exactly — the game unlocks by API name. Icons are in `icons/`.",
        "",
    ]
    for i, r in enumerate(rows, 1):
        hidden = " · **hidden**" if r["hidden"] == "yes" else ""
        lines.append(f"- [ ] {i}. `{r['api_name']}` — **{r['display_name']}**{hidden}  ")
        lines.append(f"      {r['description']}")
    (OUT / "checklist.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

    for w in warnings:
        print(f"warning: {w}")
    for p in problems:
        print(f"problem: {p}", file=sys.stderr)
    print(f"{len(rows)} of {len(defs)} achievements written to {OUT.relative_to(ROOT)}")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
