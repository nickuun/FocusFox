"""Turn the artist's delivered den-item frames into game-ready animated finds.

The sibling of tools/fox_import.py, and the same arrangement: the delivery lives
outside the repo and is never touched, tools/den_items.json says which folder becomes
which find, and everything under assets/main_menu/environment/animated/ is output that
the next run overwrites. Edit the manifest and re-run; don't hand-edit the PNGs.

What it does per find, in order:

  1. Reads the delivered frames in human order (see natural_key -- the frames are
     numbered without padding, so a plain sort puts 10 before 2 and scrambles the loop).
  2. Crops every frame to the SAME rectangle: the union of the drawn area across the
     whole animation. One shared rectangle is the point -- it keeps each frame's
     position relative to the others, so a flame that leans or a leaf that drifts still
     does, and the find's footing doesn't jitter frame to frame.
  3. Scales by one clean fraction (see below).
  4. Writes 001.png, 002.png … plus a frames.json beside them recording the size, the
     frame count and the fps, so den_catalog.gd doesn't have to re-derive any of it.

--- Why the scale is restricted ----------------------------------------------

The delivered art is pixel art with strictly binary alpha, and the project renders with
nearest filtering (default_texture_filter=0). Both facts push the same way: the only
safe reductions are the ones where a whole number of source pixels lands on one
destination pixel. At exactly 1/2, four source pixels become one and every edge stays
on the grid. At 0.4, or 0.7, rows get dropped unevenly -- some 2px outlines survive,
some vanish -- and dense art goes visibly chewed.

So this script accepts 1.0, 1/2, 1/3 and 1/4 and refuses anything else, rather than
quietly producing a mush that only shows up once it's in the room. The same reasoning is
why it resamples with NEAREST and nothing else. Measured on the densest frame in the
delivery (the Victorian fireplace, 326x293):

    NEAREST   151 colours, 0 part-transparent pixels
    BOX      5545 colours, 192 part-transparent pixels
    LANCZOS  9875 colours, 1032 part-transparent pixels

The smooth filters are inventing colour and soft edges that nearest-filtered rendering
then shows as mud. Note this differs from fox_import.py, which *does* resample smoothly
when shrinking -- it can, because it snaps back onto a known 7-colour palette
afterwards. This art has 125-292 colours with no palette to snap to, so the snap isn't
available and NEAREST is the whole answer.

Half scale is still a real reduction: it discards three pixels in four, and fine detail
softens. It is the right call for getting the set playable, not a substitute for a
re-export at den scale.

--- Usage --------------------------------------------------------------------

Measure a delivery without writing anything, and see what each find would come out at:

    python tools/den_import.py --manifest tools/den_items.json --dry-run

Build everything, or one find:

    python tools/den_import.py --manifest tools/den_items.json
    python tools/den_import.py --manifest tools/den_items.json --only fireplace

Every run writes contact sheets to build/den_sheets/ so a loop can be checked without
opening Godot -- worth a look for a loop whose ends do not meet.

Needs Pillow and numpy.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image

# Alpha at or above this counts as drawn. The source is already strictly 0-or-255 and
# NEAREST keeps it that way, so this only ever classifies, never decides an edge.
ALPHA_CUTOFF = 128

# The reductions that land a whole number of source pixels on one destination pixel.
# See the header for why an arbitrary scale is refused rather than accepted quietly.
CLEAN_SCALES = {1.0: "1", 0.5: "1/2", 1.0 / 3.0: "1/3", 0.25: "1/4"}
SCALE_TOLERANCE = 1e-6

# How tall the room's floor-to-ceiling band is, in design pixels, and the width of the
# widest find already in the catalog (the bookshelf). Only used to flag a find that
# arrives wildly out of proportion with the room -- see report_fit.
ROOM_HEIGHT = 300.0
REFERENCE_WIDTH = 150.0


def natural_key(path: Path):
    """Sort frames the way a human reads them.

    The frames arrive named like `Fireplace 2.png` … `Fireplace 20.png`, unpadded, so a
    plain sort puts 10 before 2 and silently scrambles the animation.
    """
    digits = re.findall(r"\d+", path.name)
    return (path.stem.rstrip("0123456789 _"), int(digits[-1]) if digits else 0, path.name)


def load_frames(folder: Path) -> list[Path]:
    frames = sorted(folder.glob("*.png"), key=natural_key)
    if not frames:
        raise SystemExit(f"no PNGs in {folder}")
    return frames


def content_bbox(image: np.ndarray):
    """Bounding box of the drawn pixels, or None for an entirely empty frame."""
    opaque = image[:, :, 3] >= ALPHA_CUTOFF
    rows = np.nonzero(opaque.any(axis=1))[0]
    cols = np.nonzero(opaque.any(axis=0))[0]
    if len(rows) == 0 or len(cols) == 0:
        return None
    return int(cols[0]), int(rows[0]), int(cols[-1]) + 1, int(rows[-1]) + 1


def union_bbox(images: list[np.ndarray]):
    """The one rectangle every frame gets cropped to.

    The union rather than each frame's own box, so motion within the canvas is
    preserved. Cropping frames individually would centre every frame on its own content
    and iron the animation flat -- a flame that leans left would stand up straight.
    """
    boxes = [b for b in (content_bbox(im) for im in images) if b is not None]
    if not boxes:
        raise SystemExit("source frames are entirely transparent")
    return (
        min(b[0] for b in boxes),
        min(b[1] for b in boxes),
        max(b[2] for b in boxes),
        max(b[3] for b in boxes),
    )


def clean_scale_name(scale: float) -> str:
    """The label for a permitted scale, or a refusal naming the ones that are allowed."""
    for value, label in CLEAN_SCALES.items():
        if abs(scale - value) < SCALE_TOLERANCE:
            return label
    allowed = ", ".join(sorted(CLEAN_SCALES.values()))
    raise SystemExit(
        f"scale {scale} is not a clean reduction (allowed: {allowed}).\n"
        f"An arbitrary scale drops pixel rows unevenly and chews the art -- see the "
        f"header of tools/den_import.py."
    )


def process_animation(src: Path, out: Path, scale: float, dry_run: bool) -> dict:
    """Crop, scale and write one folder of frames. Returns a report."""
    paths = load_frames(src)
    images = [np.array(Image.open(p).convert("RGBA")) for p in paths]

    left, top, right, bottom = union_bbox(images)
    src_w, src_h = right - left, bottom - top

    # floor(), not round(): an odd source dimension at half scale has no exact answer,
    # and rounding up would add a column of transparent pixels that then counts toward
    # the find's width, its hitbox and its shadow.
    out_w, out_h = max(1, int(src_w * scale)), max(1, int(src_h * scale))

    report = {
        "src": str(src),
        "out": str(out),
        "frames": len(images),
        "source_size": [src_w, src_h],
        "size": [out_w, out_h],
    }
    if dry_run:
        return report

    # Wiped rather than written over: a re-import from a delivery with fewer frames
    # would otherwise leave the tail of the previous run behind, and those stale frames
    # would play as part of the loop.
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True, exist_ok=True)

    written = []
    for index, image in enumerate(images, start=1):
        frame = Image.fromarray(image).crop((left, top, right, bottom))
        if (out_w, out_h) != (src_w, src_h):
            frame = frame.resize((out_w, out_h), Image.NEAREST)
        frame.save(out / f"{index:03d}.png")
        written.append(np.array(frame))

    report["_written"] = written
    return report


def contact_sheet(images: list[np.ndarray], path: Path, cols: int = 8, cell: int = 120):
    """A grid of every frame, for eyeballing a loop without opening Godot."""
    if not images:
        return
    rows = (len(images) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell, rows * cell), (30, 26, 28, 255))
    for i, image in enumerate(images):
        frame = Image.fromarray(image)
        frame.thumbnail((cell, cell), Image.NEAREST)
        x = (i % cols) * cell + (cell - frame.width) // 2
        y = (i // cols) * cell + (cell - frame.height) // 2
        sheet.alpha_composite(frame, (x, y))
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)


def report_fit(label: str, size: list[int]) -> str:
    """A note when a find lands wildly out of proportion with the room.

    Advisory only. The room is about 300px floor to ceiling and the widest existing
    find (the bookshelf) is 150 wide, so something twice either is worth a second look
    rather than an error -- the stove is legitimately tall.
    """
    width, height = size
    notes = []
    if height > ROOM_HEIGHT * 0.8:
        notes.append(f"{height}px tall against a ~{ROOM_HEIGHT:.0f}px room")
    if width > REFERENCE_WIDTH * 1.5:
        notes.append(f"{width}px wide against the bookshelf's {REFERENCE_WIDTH:.0f}px")
    return f"    ! {label}: {'; '.join(notes)}" if notes else ""


def process_find(spec: dict, root: Path, src_root: Path, dry_run: bool) -> dict:
    find_id = spec["id"]
    scale = float(spec.get("scale", 1.0))
    label = clean_scale_name(scale)
    out_root = root / spec["out"]
    fps = float(spec.get("fps", 10.0))

    def resolve(raw: str) -> Path:
        source = Path(raw)
        if not source.is_absolute():
            source = (src_root / source).resolve()
        if not source.is_dir():
            raise SystemExit(
                f"[{find_id}] source folder not found:\n  {source}\n"
                f"Check 'src_root' in the manifest points at the delivery."
            )
        return source

    print(f"  {find_id}  (scale {label}, {fps:g} fps)")

    variants = spec.get("variants")
    entries = variants if variants else [{"name": "", "src": spec["src"]}]

    built = []
    for entry in entries:
        name = entry.get("name", "")
        out = out_root / name if name else out_root
        report = process_animation(resolve(entry["src"]), out, scale, dry_run)

        shown = name or find_id
        src_w, src_h = report["source_size"]
        out_w, out_h = report["size"]
        print(f"    {shown:12s} {report['frames']:3d} frames  {src_w}x{src_h} -> {out_w}x{out_h}")
        note = report_fit(shown, report["size"])
        if note:
            print(note)

        if not dry_run:
            contact_sheet(
                report.pop("_written"),
                root / "build" / "den_sheets" / f"{find_id}{'_' + name if name else ''}.png",
            )
            # Written beside the frames rather than into den_catalog.gd, so a re-import
            # that changes a frame count or a size doesn't need a matching code edit.
            (out / "frames.json").write_text(
                json.dumps(
                    {
                        "frames": report["frames"],
                        "size": report["size"],
                        "fps": fps,
                        "source": report["src"],
                    },
                    indent=2,
                )
                + "\n",
                encoding="utf-8",
            )
        built.append({"name": name, **report})

    return {"id": find_id, "fps": fps, "variants": built}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--only", action="append", help="build just this find id; repeatable")
    parser.add_argument("--dry-run", action="store_true", help="measure and report, write nothing")
    args = parser.parse_args()

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    root = args.manifest.resolve().parent.parent
    src_root = Path(manifest["src_root"])
    if not src_root.is_dir():
        raise SystemExit(
            f"src_root not found:\n  {src_root}\n"
            f"Point it at wherever the delivery was unpacked on this machine."
        )

    finds = manifest["finds"]
    if args.only:
        wanted = set(args.only)
        finds = [f for f in finds if f["id"] in wanted]
        missing = wanted - {f["id"] for f in finds}
        if missing:
            raise SystemExit(f"no such find in the manifest: {', '.join(sorted(missing))}")

    print(f"{'Measuring' if args.dry_run else 'Building'} {len(finds)} find(s) from {src_root}\n")
    total = 0
    for spec in finds:
        result = process_find(spec, root, src_root, args.dry_run)
        total += sum(v["frames"] for v in result["variants"])
        print()

    print(f"{total} frames {'measured' if args.dry_run else 'written'}.")
    if not args.dry_run:
        print("Contact sheets in build/den_sheets/.")


if __name__ == "__main__":
    main()
