"""Turn a folder of cut-up plant parts into a rig the engine can animate.

The other half of tools/den_import.py. That one takes an animation the artist drew
frame by frame and shrinks it; this one takes a plant drawn ONCE, in pieces, and works
out how the pieces fit together so the game can do the animating.

The difference is the whole point. A 27-frame plant is 27 drawings that play back at one
speed and loop. A rigged plant is 12 drawings that sway on their own phases, never
repeat, and can be recombined into other plants. Same delivery effort, far more game.

--- What the artist delivers ------------------------------------------------

One folder per plant, holding:

  * `Main <name>.png` — the assembled plant, as reference. Never used in game; it is
    what every part is located against.
  * one PNG per part — each leaf, plus `Pot.png`.

Parts may be cropped to their own bounding box (that is how the first delivery came) or
exported on one shared canvas with the rest. Either works: this script finds each part's
place by matching it against the reference image, so the layout is recovered from the
art rather than typed in by hand.

A shared canvas is still the better delivery, because matching is guesswork-free when
positions are already absolute — the match here is a bridge, not the plan.

--- What it works out -------------------------------------------------------

For every part, two things:

  1. `offset` — where it sits relative to the pot, so the plant reassembles exactly as
     the artist composed it.
  2. `pivot` — the point it should rotate about. A leaf sways from where its stem meets
     the soil, not from its middle: rotating about the centre makes a leaf orbit, which
     reads as a bug. The hinge is taken as the part's drawn pixel nearest the soil
     anchor, which is what "where the stem enters the pot" means geometrically.

Both are written to rig.json next to the copied parts. den_catalog.gd points a find at
that folder and plant_rig.gd does the rest.

--- Matching, and when it is wrong -----------------------------------------

Each part is slid over the reference and scored on mean colour difference across its own
opaque pixels. The reported error per part is printed: under about 8 is a confident
match, and anything higher is worth looking at in the contact sheet this writes. The pot
usually scores worst and it does not matter — it is matched for position only and never
rotates.

A part that appears twice in the reference (a repeated leaf) will match one of them
arbitrarily. Nothing here detects that; check the rebuild.

--- Usage -------------------------------------------------------------------

    python tools/plant_rig.py --src "C:/path/to/Plant 06 Sprites" --name plant_06
    python tools/plant_rig.py --src ... --name plant_06 --scale 0.5 --dry-run

Writes assets/main_menu/environment/plants/<name>/ and a rebuild preview to
build/plant_rigs/<name>.png — check that against the artist's reference before shipping.

Needs Pillow and numpy.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
from pathlib import Path

import numpy as np
from PIL import Image

ALPHA_CUTOFF = 128

# Same restriction as den_import.py, for the same reason: only a whole-number reduction
# keeps nearest-filtered pixel art on the grid. See that file's header.
CLEAN_SCALES = {1.0: "1", 0.5: "1/2", 1.0 / 3.0: "1/3", 0.25: "1/4"}
SCALE_TOLERANCE = 1e-6

# How far down the pot's own art the soil sits, as a fraction of its height. The leaves
# hinge at the soil line, not at the pot's top edge or its middle.
SOIL_DEPTH = 0.1

# A part whose match scores worse than this is called out. Advisory: the pot routinely
# scores badly because it is large and low-contrast, and it never rotates anyway.
MATCH_WARN = 8.0


def content_bbox(image: Image.Image):
    return image.getbbox()


def load_part(path: Path) -> tuple[Image.Image, np.ndarray, np.ndarray]:
    """The part cropped to its drawn area, plus its opacity mask and RGB."""
    im = Image.open(path).convert("RGBA")
    box = content_bbox(im)
    if box is None:
        raise SystemExit(f"{path.name} is entirely transparent")
    im = im.crop(box)
    a = np.array(im)
    return im, a[:, :, 3] >= ALPHA_CUTOFF, a[:, :, :3].astype(int)


def match_position(reference: np.ndarray, opaque: np.ndarray, rgb: np.ndarray):
    """Where this part sits on the reference: (x, y, mean colour error).

    Coarse pass on a stride, then a fine sweep around the winner — a full per-pixel
    search over every part is minutes of work for an answer the two-stage search gets in
    seconds.
    """
    ref_h, ref_w, _ = reference.shape
    h, w = opaque.shape
    if h > ref_h or w > ref_w:
        return None
    best = None
    for step in (3, 1):
        if best is None:
            ys, xs = range(0, ref_h - h + 1, step), range(0, ref_w - w + 1, step)
        else:
            ys = range(max(0, best[1] - 4), min(ref_h - h, best[1] + 4) + 1)
            xs = range(max(0, best[2] - 4), min(ref_w - w, best[2] + 4) + 1)
        current = None
        for y in ys:
            for x in xs:
                window = reference[y : y + h, x : x + w]
                error = float(np.abs(window - rgb)[opaque].mean())
                if current is None or error < current[0]:
                    current = (error, y, x)
        best = current
    return best[2], best[1], best[0]


def pivot_for(opaque: np.ndarray, at: tuple[int, int], soil: np.ndarray) -> tuple[int, int]:
    """The part's drawn pixel nearest the soil — where its stem enters the pot.

    This is the hinge the sway rotates about. Taken from the art rather than assumed to
    be a corner, because the leaves point in every direction: the one at the back left
    enters the soil at its bottom-right, the one on the right at its bottom-left.
    """
    ys, xs = np.nonzero(opaque)
    gx, gy = xs + at[0], ys + at[1]
    nearest = int(np.argmin((gx - soil[0]) ** 2 + (gy - soil[1]) ** 2))
    return int(xs[nearest]), int(ys[nearest])


def clean_scale_name(scale: float) -> str:
    for value, label in CLEAN_SCALES.items():
        if abs(scale - value) < SCALE_TOLERANCE:
            return label
    allowed = ", ".join(sorted(CLEAN_SCALES.values()))
    raise SystemExit(f"scale {scale} is not a clean reduction (allowed: {allowed})")


def natural_key(path: Path):
    digits = re.findall(r"\d+", path.name)
    return (int(digits[0]) if digits else 999, path.name)


def build(src: Path, name: str, scale: float, root: Path, dry_run: bool) -> None:
    label = clean_scale_name(scale)
    reference_path = next((p for p in src.glob("*.png") if p.stem.lower().startswith("main")), None)
    if reference_path is None:
        raise SystemExit(f"no 'Main *.png' reference in {src} — it is what parts are located against")

    reference = np.array(Image.open(reference_path).convert("RGB")).astype(int)
    parts = sorted((p for p in src.glob("*.png") if p != reference_path), key=natural_key)
    if not parts:
        raise SystemExit(f"no part PNGs in {src}")

    pot_path = next((p for p in parts if "pot" in p.stem.lower()), None)
    if pot_path is None:
        raise SystemExit("no Pot.png — the pot is what the plant is anchored and sorted against")

    print(f"{name}  (scale {label}, {len(parts)} parts, reference {reference_path.name})")

    # The pot first: everything else is positioned relative to it, and the soil line it
    # implies is what the leaves hinge at.
    pot_image, pot_opaque, pot_rgb = load_part(pot_path)
    pot_match = match_position(reference, pot_opaque, pot_rgb)
    pot_x, pot_y, pot_error = pot_match
    pot_h, pot_w = pot_opaque.shape
    soil = np.array([pot_x + pot_w * 0.5, pot_y + pot_h * SOIL_DEPTH])

    out_dir = root / "assets/main_menu/environment/plants" / name
    entries = []
    rebuilt = Image.new("RGBA", Image.open(reference_path).size, (0, 0, 0, 0))

    for path in parts:
        image, opaque, rgb = load_part(path)
        match = match_position(reference, opaque, rgb)
        if match is None:
            print(f"    {path.stem:24s} SKIPPED — larger than the reference")
            continue
        x, y, error = match
        is_pot = path == pot_path
        pivot = (0, 0) if is_pot else pivot_for(opaque, (x, y), soil)

        # Composited after the loop rather than here, so the pot can be laid down first
        # and the leaves drawn over its rim — see the draw-order note in plant_rig.gd.
        # The artist's file order paints the pot last.

        flag = "  ! check" if error > MATCH_WARN and not is_pot else ""
        print(f"    {path.stem:24s} {opaque.shape[1]:3d}x{opaque.shape[0]:<3d} at ({x:3d},{y:3d})  err={error:4.1f}{flag}")

        entries.append({
            "file": f"{len(entries):02d}.png",
            "at": [x, y],
            "source": path.name,
            # Relative to the pot's top-left, so the rig can be placed by its pot and
            # every part follows. Scaled with the art.
            "offset": [round((x - pot_x) * scale), round((y - pot_y) * scale)],
            "pivot": [round(pivot[0] * scale), round(pivot[1] * scale)],
            "size": [round(opaque.shape[1] * scale), round(opaque.shape[0] * scale)],
            "pot": is_pot,
            "match_error": round(error, 1),
            "_image": image,
        })

    # Pot first, then the leaves over its rim, so the plant reads as growing out of the
    # soil rather than standing behind the pot. The artist paints the pot last, so her
    # file order is the reverse of the draw order. plant_rig.gd reorders the same way.
    for entry in sorted(entries, key=lambda e: not e["pot"]):
        rebuilt.alpha_composite(entry["_image"], tuple(entry["at"]))

    if dry_run:
        print(f"\n  {len(entries)} parts measured, nothing written.")
        return

    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    for entry in entries:
        image = entry.pop("_image")
        if scale != 1.0:
            image = image.resize(
                (max(1, int(image.width * scale)), max(1, int(image.height * scale))), Image.NEAREST
            )
        image.save(out_dir / entry["file"])

    (out_dir / "rig.json").write_text(
        json.dumps({
            "name": name,
            "scale": scale,
            "source": str(src),
            # Where the pot's own art sits inside the rig, so the plant can be anchored
            # at the base of the pot the way every other find is anchored at its base.
            "pot_size": [round(pot_w * scale), round(pot_h * scale)],
            "parts": entries,
        }, indent=2) + "\n",
        encoding="utf-8",
    )

    # The icon the drawer and the journal draw: the plant composed at rest, trimmed.
    # Written here rather than composed at runtime, because stacking a dozen rotated
    # sprites for every drawer cell is work for a picture that never moves.
    icon = rebuilt.crop(rebuilt.getbbox())
    if scale != 1.0:
        icon = icon.resize(
            (max(1, int(icon.width * scale)), max(1, int(icon.height * scale))), Image.NEAREST
        )
    icon.save(out_dir / "icon.png")

    preview = root / "build" / "plant_rigs"
    preview.mkdir(parents=True, exist_ok=True)
    rebuilt.resize((rebuilt.width * 2, rebuilt.height * 2), Image.NEAREST).save(preview / f"{name}.png")

    print(f"\n  wrote {len(entries)} parts to {out_dir}")
    print(f"  rebuild preview: build/plant_rigs/{name}.png — compare it against {reference_path.name}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--src", required=True, type=Path, help="the artist's folder of parts")
    parser.add_argument("--name", required=True, help="the rig's name in the game, e.g. plant_06")
    parser.add_argument("--scale", type=float, default=1.0)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if not args.src.is_dir():
        raise SystemExit(f"not a folder: {args.src}")
    build(args.src, args.name, args.scale, Path(__file__).resolve().parent.parent, args.dry_run)


if __name__ == "__main__":
    main()
