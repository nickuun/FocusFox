"""Bring the artist's still deliveries into the game as den finds.

The third importer, beside tools/den_import.py (folders of frames) and
tools/plant_rig.py (parts the engine sways). This one is for art that does not move:
the paintings and the punk posters, and whatever still sets come next.

Same arrangement as the others. The delivery lives outside the repo and is never
touched, tools/den_statics.json says which folder becomes which set, and everything
under assets/main_menu/environment/static/ is output the next run overwrites.

What it does per set:

  1. Picks the delivered PNGs, optionally filtered by source width so one folder can
     supply two sets at two scales -- see the tiers note below.
  2. Trims each to its drawn area. The delivery carries 10-30px of transparent margin,
     and left in it would size the find's hitbox and its hanging position against empty
     space rather than against the picture.
  3. Scales by one clean fraction, NEAREST only. Same restriction and same reasoning as
     den_import.py: this is pixel art rendered with a nearest texture filter, so only a
     whole-number reduction keeps edges on the grid.
  4. Writes <id>.png per piece, plus a catalog.gd fragment to paste into
     den_catalog.gd -- forty-five entries typed by hand is forty-five chances to
     misspell a path.

--- On the two tiers ---------------------------------------------------------

The paintings arrived in two sizes about three times apart: twelve at ~144px and
twenty-four at ~450px. They are NOT normalised to one size, deliberately. Half scale
puts the small ones at 72px, which is the room's existing painting.png to the pixel,
and a third puts the large ones near 150px -- a statement piece at roughly twice the
small ones. A room with both reads as a collection; a room where every picture is the
same size reads as wallpaper.

`min_source_width` and `max_source_width` split one delivered folder between two sets
by measuring rather than by filename, since the artist's names do not encode size.

--- Naming -------------------------------------------------------------------

A find's id comes from its filename, lowercased and reduced to word characters. That
makes the id stable across re-imports and readable in a save file, and it means a
renamed delivery file silently becomes a NEW find rather than updating the old one --
so renames on the artist's side need the same care as renames here. The display name is
the filename tidied up, which is usually right and occasionally needs a hand edit in
den_catalog.gd afterwards (the delivery has "Abtract" and "REALSIM" in it).

--- Usage --------------------------------------------------------------------

    python tools/den_static_import.py --manifest tools/den_statics.json --dry-run
    python tools/den_static_import.py --manifest tools/den_statics.json
    python tools/den_static_import.py --manifest tools/den_statics.json --only posters

Writes a contact sheet per set to build/den_statics/ so the result can be checked
without opening Godot.

Needs Pillow.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
from pathlib import Path

from PIL import Image

# Only reductions that land a whole number of source pixels on one destination pixel.
# See the header, and den_import.py's, for why an arbitrary scale is refused.
CLEAN_SCALES = {1.0: "1", 0.5: "1/2", 1.0 / 3.0: "1/3", 0.25: "1/4"}
SCALE_TOLERANCE = 1e-6

# The wall band a hung find has to live in, from Den.WALL_TOP to Den.WALL_BOTTOM. Only
# used to flag a piece that cannot comfortably hang; kept in sync by hand.
WALL_BAND = 245.0
# A piece taller than this share of the band is called out. At 0.8 a painting is nearly
# floor-to-ceiling on the wall, which is worth a second look rather than an error.
WALL_WARN_RATIO = 0.8


def clean_scale_name(scale: float) -> str:
    for value, label in CLEAN_SCALES.items():
        if abs(scale - value) < SCALE_TOLERANCE:
            return label
    allowed = ", ".join(sorted(CLEAN_SCALES.values()))
    raise SystemExit(
        f"scale {scale} is not a clean reduction (allowed: {allowed}).\n"
        f"An arbitrary scale drops pixel rows unevenly and chews the art."
    )


def slug(stem: str) -> str:
    """A stable, readable id from a delivered filename.

    Lowercased, non-word runs collapsed to underscores. "Punk Poster - Death Ray"
    becomes "punk_poster_death_ray", which is what ends up in the player's save file.
    """
    out = re.sub(r"[^a-z0-9]+", "_", stem.lower()).strip("_")
    return re.sub(r"_+", "_", out)


def display_name(stem: str, article: str) -> str:
    """The name the drawer and the journal show.

    Every find in the catalog reads as a phrase rather than a title -- "a mug", "a
    little painting", "a wood-burning stove" -- because the journal writes it into a
    sentence: "Your fox brought home %s!". So the delivered filename is lowercased and
    given an article, and a title-cased "Abstract Brush Strokes Painting" becomes "an
    abstract brush strokes painting".

    Typos in the delivery ("Abtract", "REALSIM", "Pianting") survive this on purpose --
    silently correcting them would hide a filename that ought to be fixed at the source.
    """
    text = re.sub(r"\s*[-_]+\s*", " ", stem).strip()
    text = re.sub(r"\s+", " ", text).lower()
    if not text:
        return article + " find"
    # "a" or "an" by what the name actually starts with, so the journal reads properly.
    lead = "an" if text[0] in "aeiou" else "a"
    return f"{lead} {text}" if article == "auto" else f"{article} {text}"


def collect(src: Path, spec: dict) -> list[Path]:
    """The delivered files for this set, filtered by drawn width where asked.

    Width rather than filename, because the artist's names do not encode size and one
    folder legitimately holds both tiers.
    """
    low = float(spec.get("min_source_width", 0))
    high = float(spec.get("max_source_width", 1e9))
    # An explicit shortlist, by filename stem. For trialling a handful out of a big
    # delivery before committing to the lot — a set on trial should not quietly grow to
    # eighteen finds the next time someone re-runs the importer.
    only = spec.get("only")
    picked = []
    for path in sorted(src.glob("*.png")):
        if only is not None and path.stem not in only:
            continue
        with Image.open(path) as image:
            box = image.convert("RGBA").getbbox()
        if box is None:
            print(f"    ! {path.name} is entirely transparent, skipped")
            continue
        width = box[2] - box[0]
        if low <= width < high:
            picked.append(path)
    return picked


def contact_sheet(images: list[Image.Image], path: Path, cols: int = 6, cell: int = 180) -> None:
    if not images:
        return
    rows = (len(images) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell, rows * cell), (38, 34, 36, 255))
    for i, image in enumerate(images):
        thumb = image.copy()
        thumb.thumbnail((cell - 12, cell - 12), Image.NEAREST)
        x = (i % cols) * cell + (cell - thumb.width) // 2
        y = (i // cols) * cell + (cell - thumb.height) // 2
        sheet.alpha_composite(thumb, (x, y))
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)


def process_set(spec: dict, root: Path, src_root: Path, dry_run: bool) -> list[dict]:
    set_id = spec["id"]
    scale = float(spec.get("scale", 1.0))
    label = clean_scale_name(scale)
    src = (src_root / spec["src"]).resolve()
    if not src.is_dir():
        raise SystemExit(f"[{set_id}] source folder not found:\n  {src}")

    files = collect(src, spec)
    if not files:
        raise SystemExit(f"[{set_id}] no PNGs matched in {src}")

    out_dir = root / spec["out"]
    print(f"  {set_id}  (scale {label}, {len(files)} pieces)")

    if not dry_run:
        if out_dir.exists():
            shutil.rmtree(out_dir)
        out_dir.mkdir(parents=True, exist_ok=True)

    entries: list[dict] = []
    thumbs: list[Image.Image] = []
    seen: dict[str, str] = {}

    for path in files:
        image = Image.open(path).convert("RGBA")
        image = image.crop(image.getbbox())
        src_w, src_h = image.size
        if scale != 1.0:
            # floor(), not round(): rounding up adds a transparent column that then
            # counts toward the find's width and its hitbox.
            image = image.resize((max(1, int(src_w * scale)), max(1, int(src_h * scale))), Image.NEAREST)

        find_id = slug(path.stem)
        if find_id in seen:
            raise SystemExit(
                f"[{set_id}] two files reduce to the same id '{find_id}':\n"
                f"  {seen[find_id]}\n  {path.name}\nRename one in the delivery."
            )
        seen[find_id] = path.name

        note = ""
        if image.height > WALL_BAND * WALL_WARN_RATIO:
            note = f"  ! {image.height}px tall against a {WALL_BAND:.0f}px wall band"
        print(f"    {path.stem[:40]:40s} {src_w:3d}x{src_h:<3d} -> {image.width:3d}x{image.height:<3d}{note}")

        if not dry_run:
            image.save(out_dir / f"{find_id}.png")
        thumbs.append(image)
        entries.append({
            "id": find_id,
            "name": display_name(path.stem, str(spec.get("article", "auto"))),
            "texture": f"res://{spec['out']}/{find_id}.png".replace("\\", "/"),
            "mount": str(spec.get("mount", "floor")),
            "category": str(spec.get("category", "comfort")),
            "size": [image.width, image.height],
        })

    if not dry_run:
        contact_sheet(thumbs, root / "build" / "den_statics" / f"{set_id}.png")

    return entries


def write_catalog_fragment(all_entries: list[dict], path: Path) -> None:
    """The catalog lines to paste into den_catalog.gd.

    Generated rather than hand-written: forty-five entries is forty-five chances to
    misspell a path, and a misspelt path is a find that silently never appears.

    unlock_min and default_x are deliberately left at placeholder values -- progression
    is tuned separately once the full item list exists, and a default_x per piece is a
    composition decision to make with the room on screen.
    """
    lines = ["\t# Generated by tools/den_static_import.py -- see its header.",
             "\t# unlock_min and default_x are placeholders; progression is tuned separately.\n"]
    for i, entry in enumerate(all_entries):
        unlock = 1000 + i * 10
        x = 200.0 + float((i % 7) * 110)
        y = 150.0 + float((i % 3) * 40)
        lines.append(
            '\t{"id": "%s", "name": "%s", "unlock_min": %d, "default_x": %.1f,\n'
            '\t\t"texture": "%s",\n'
            '\t\t"mount": "%s", "default_y": %.1f, "category": "%s"},'
            % (entry["id"], entry["name"], unlock, x, entry["texture"],
               entry["mount"], y, entry["category"])
        )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--only", action="append", help="build just this set id; repeatable")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    root = args.manifest.resolve().parent.parent
    src_root = Path(manifest["src_root"])
    if not src_root.is_dir():
        raise SystemExit(f"src_root not found:\n  {src_root}")

    sets = manifest["sets"]
    if args.only:
        wanted = set(args.only)
        sets = [s for s in sets if s["id"] in wanted]
        missing = wanted - {s["id"] for s in sets}
        if missing:
            raise SystemExit(f"no such set: {', '.join(sorted(missing))}")

    print(f"{'Measuring' if args.dry_run else 'Building'} {len(sets)} set(s) from {src_root}\n")
    everything: list[dict] = []
    for spec in sets:
        everything.extend(process_set(spec, root, src_root, args.dry_run))
        print()

    print(f"{len(everything)} pieces {'measured' if args.dry_run else 'written'}.")
    if not args.dry_run:
        fragment = root / "build" / "den_statics" / "catalog_fragment.gd"
        write_catalog_fragment(everything, fragment)
        print(f"Contact sheets in build/den_statics/.")
        print(f"Catalog lines to paste: {fragment}")


if __name__ == "__main__":
    main()
