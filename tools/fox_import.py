"""Turn the artist's delivered fox frames into game-ready clips.

The artist works at whatever size the source generation comes out at — usually
1920x1080 — and cleans up there. That is the right way round: cleanup wants pixels.
What the game needs is small, tightly-cropped, consistently-sized frames. This script
is the bit in between, so nobody has to decide canvas sizes or frame counts by hand.

What it does per clip, in order:

  1. Takes a slice of the source frames (start, end, step) — so one long delivered
     animation can be cut into several game clips, and slow sections can be thinned.
  2. Crops every frame to the SAME rectangle: the union of the drawn area across the
     whole slice, plus a margin. One shared rectangle is the point — it preserves the
     fox's motion relative to the canvas, so a tail that swings or a body that bobs
     still does, and the footing stays put.
  3. Scales the whole clip by one factor, shrinking or growing (see below).
  4. Snaps every pixel back onto the source's own palette and re-hardens the alpha.
  5. Writes 001.png, 002.png … and reports the anchor to paste into fox_v2.gd, plus a
     size metric so a clip that doesn't match the others is obvious.

--- Why the snap in step 4 matters -------------------------------------------

The art is exactly seven colours with a fully binary alpha — no anti-aliasing, no
partial transparency. Two things depend on that and would break silently without it:

  * `fox_palette.gdshader` recolours the fox by matching #d67941 and #9d5021 within a
    tolerance of 0.04. Any resampling produces in-between colours, which stop matching,
    and the fox colour options would quietly do nothing on the new art.
  * The project renders with nearest filtering (default_texture_filter=0), which makes
    a soft edge look like mud rather than like a soft edge.

So the RGB is resampled for smoothness and then forced back onto the palette it came
from, and the alpha is resampled and re-thresholded. The palette is read off the source
rather than hard-coded, so this works for the ball (17 blues) as well as the fox.

--- Two ways to resample, picked by direction --------------------------------

Shrinking and growing want opposite filters here, so the script chooses:

  scale < 1  (shrinking, e.g. the 1920x1080 play frames)
      Smooth resample, then snap back to the palette and re-harden the alpha, as above.
      Smooth is right because there is detail to average; the snap is what undoes the
      in-between colours it produces.

  scale >= 1 (growing, e.g. sit and run at x1.5)
      Nearest-neighbour, nothing else. A smooth filter here is actively wrong: LANCZOS
      at x1.5 turns a 7-colour frame into 5705 colours with 3721 part-transparent
      pixels, which is exactly what the palette shader and the nearest texture filter
      cannot cope with. Nearest keeps it at 7 colours and 0, bit-exact.

Growing does not invent detail, and this script does not pretend otherwise. What it is
for is making the clips agree with each other: `sit` and `run` were drawn two-thirds the
size of `walk` and `sleep`, with 2px outlines against their 3px. At exactly x1.5 every
2px run becomes a 3px run — the arithmetic works out so that a two-pixel source run
lands on three pixels wherever it starts — so the upscaled clips match the reference
outline exactly rather than going lumpy. That only holds at x1.5; an arbitrary scale
would give a mix of 2px and 3px and look chewed.

--- Usage --------------------------------------------------------------------

Measure a folder and get a suggested scale (relative to `walk`, the size reference):

    python tools/fox_import.py --probe "C:/path/to/frames"

Build clips from the manifest:

    python tools/fox_import.py --manifest tools/fox_clips.json
    python tools/fox_import.py --manifest tools/fox_clips.json --only idle
    python tools/fox_import.py --manifest tools/fox_clips.json --dry-run

Build, and also assemble a folder to send back to the artist — every clip at the size
the game uses, contact sheets, and a README saying what's worth fixing in each:

    python tools/fox_import.py --manifest tools/fox_clips.json --pack

Every run writes contact sheets to build/fox_sheets/ so the result can be checked
without opening Godot. Nothing is ever written back to the artist's delivery.

Needs Pillow and numpy.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import textwrap
from collections import Counter
from pathlib import Path

import numpy as np
from PIL import Image

# The clip whose fox size everything else is matched to. `walk` is the cleanest clip in
# the delivered set — a proper 12-frame cycle whose ends meet — so it sets the standard.
SIZE_REFERENCE = "walk"

# Measured mean sqrt(drawn area) of SIZE_REFERENCE, used by --probe to suggest a scale.
# Re-measure with --probe on the walk folder if that clip is ever re-exported.
REFERENCE_AREA = 135.3

# Alpha at or above this survives the crop/scale as fully opaque; below it becomes fully
# transparent. The source art is already strictly 0-or-255, so this only ever has to
# decide the new edge pixels that resampling invents.
ALPHA_CUTOFF = 128

# A colour needs at least this share of the drawn pixels to count as part of the palette.
# Keeps a stray dozen pixels from becoming a colour that everything else snaps onto.
PALETTE_MIN_SHARE = 0.0005


def natural_key(path: Path):
    """Sort frames the way a human reads them.

    The frames arrive named like `Fox Play 2.png` … `Fox Play 152.png`, unpadded, so a
    plain sort puts 100 before 11 and silently scrambles the animation. The trailing
    number is the frame index; everything before it is the clip's name.
    """
    digits = re.findall(r"\d+", path.name)
    return (int(digits[-1]) if digits else 0, path.name)


def load_frames(folder: Path) -> list[Path]:
    frames = sorted(folder.glob("*.png"), key=natural_key)
    if not frames:
        raise SystemExit(f"no PNGs in {folder}")
    return frames


def drawn_area(image: np.ndarray) -> int:
    return int((image[:, :, 3] >= ALPHA_CUTOFF).sum())


def content_bbox(image: np.ndarray):
    """Bounding box of the drawn pixels, or None for an entirely empty frame.

    Empty frames are real: the ball layer of `play` is blank until the ball rolls in.
    """
    opaque = image[:, :, 3] >= ALPHA_CUTOFF
    rows = np.nonzero(opaque.any(axis=1))[0]
    cols = np.nonzero(opaque.any(axis=0))[0]
    if len(rows) == 0 or len(cols) == 0:
        return None
    return int(cols[0]), int(rows[0]), int(cols[-1]) + 1, int(rows[-1]) + 1


def build_palette(images: list[np.ndarray]) -> np.ndarray:
    """The set of colours the source actually uses, commonest first.

    Read from the art rather than hard-coded so this works unchanged for the fox (seven
    colours) and the ball (seventeen blues), and keeps working if the palette is ever
    revised.
    """
    counts: Counter = Counter()
    for image in images:
        opaque = image[:, :, 3] >= ALPHA_CUTOFF
        if not opaque.any():
            continue
        pixels = image[opaque][:, :3]
        for colour, n in Counter(map(tuple, pixels)).items():
            counts[colour] += n
    total = sum(counts.values())
    if total == 0:
        raise SystemExit("source frames are entirely transparent")
    palette = [c for c, n in counts.most_common() if n / total >= PALETTE_MIN_SHARE]
    return np.array(palette, dtype=np.int32)


def largest_blob(opaque: np.ndarray, work_max: int = 480) -> np.ndarray:
    """Keep only the biggest connected shape, dropping anything detached from it.

    The delivered `play` frames put a grey ball on the *fox* layer as well as the blue
    one on the ball layer, so a clip cut out of them arrives with a ball baked in. The
    fox is one unbroken shape (it has a continuous outline) and the loose ball is
    another, so keeping the largest shape drops the ball wherever the two aren't
    touching — which is any frame before the fox actually reaches it.

    Labelled on a downscaled copy for speed (a 1920x1080 frame is 2M pixels), then grown
    back a little so the thin outline the downscale missed isn't shaved off the edges.
    """
    h, w = opaque.shape
    factor = max(1, int(np.ceil(max(h, w) / work_max)))
    small = opaque[::factor, ::factor]

    seen = np.zeros(small.shape, dtype=bool)
    best: list[tuple[int, int]] = []
    sh, sw = small.shape
    for sy in range(sh):
        for sx in range(sw):
            if not small[sy, sx] or seen[sy, sx]:
                continue
            stack = [(sy, sx)]
            seen[sy, sx] = True
            blob = []
            while stack:
                y, x = stack.pop()
                blob.append((y, x))
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < sh and 0 <= nx < sw and small[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
            if len(blob) > len(best):
                best = blob
    if not best:
        return opaque

    keep_small = np.zeros(small.shape, dtype=bool)
    ys = np.array([p[0] for p in best])
    xs = np.array([p[1] for p in best])
    keep_small[ys, xs] = True

    # Back to full size, then dilated by roughly one downscaled pixel so the outline the
    # coarse pass clipped comes back. Intersected with the real alpha, so the dilation
    # can only ever restore pixels that were drawn.
    keep = np.repeat(np.repeat(keep_small, factor, axis=0), factor, axis=1)[:h, :w]
    if keep.shape != opaque.shape:
        padded = np.zeros(opaque.shape, dtype=bool)
        padded[: keep.shape[0], : keep.shape[1]] = keep
        keep = padded
    for _ in range(factor + 1):
        grown = keep.copy()
        grown[1:, :] |= keep[:-1, :]
        grown[:-1, :] |= keep[1:, :]
        grown[:, 1:] |= keep[:, :-1]
        grown[:, :-1] |= keep[:, 1:]
        keep = grown
    return opaque & keep


def bleed_edges(rgb: np.ndarray, opaque: np.ndarray, rounds: int = 3) -> np.ndarray:
    """Push the drawn colours outwards into the transparent margin.

    Resampling an RGBA image mixes in whatever colour is stored in the fully transparent
    pixels, which is usually black. That paints a dark halo around everything. Growing
    the real colours outwards first means the pixels the resampler reaches for are the
    fox's own, so the edge stays the fox's colour.
    """
    out = rgb.copy()
    filled = opaque.copy()
    for _ in range(rounds):
        if filled.all():
            break
        for axis, shift in ((0, 1), (0, -1), (1, 1), (1, -1)):
            donor = np.roll(filled, shift, axis=axis)
            donor_rgb = np.roll(out, shift, axis=axis)
            # Don't let values wrap around the image edge and reappear on the far side.
            if axis == 0:
                if shift > 0:
                    donor[0, :] = False
                else:
                    donor[-1, :] = False
            else:
                if shift > 0:
                    donor[:, 0] = False
                else:
                    donor[:, -1] = False
            take = donor & ~filled
            out[take] = donor_rgb[take]
            filled |= take
    return out


def snap_to_palette(rgb: np.ndarray, palette: np.ndarray) -> np.ndarray:
    """Replace every pixel with the nearest palette colour, by squared RGB distance.

    int32 throughout, deliberately: a squared channel difference reaches 255^2 = 65025,
    which overflows int16 and wraps negative, so the nearest colour comes out arbitrary
    and the fox turns white.
    """
    flat = rgb.reshape(-1, 3).astype(np.int32)
    pal = palette.astype(np.int32)
    out = np.empty_like(flat)
    # (pixels, 1, 3) - (1, colours, 3) -> (pixels, colours, 3); chunked to bound memory.
    chunk = 200_000
    for start in range(0, len(flat), chunk):
        block = flat[start : start + chunk]
        distance = ((block[:, None, :] - pal[None, :, :]) ** 2).sum(axis=2)
        out[start : start + chunk] = pal[distance.argmin(axis=1)]
    return out.reshape(rgb.shape).astype(np.uint8)


def process_clip(spec: dict, root: Path, src_root: Path | None = None, dry_run: bool = False) -> dict:
    name = spec["name"]
    source = Path(spec["src"])
    if not source.is_absolute():
        # Clip sources are relative to the manifest's src_root — the folder the artist's
        # delivery was unpacked into. Keeping it in one place means a delivery that lands
        # somewhere else only changes that one line.
        source = ((src_root or root) / source).resolve()
    if not source.is_dir():
        raise SystemExit(
            f"[{name}] source folder not found:\n  {source}\n"
            f"Check 'src_root' in the manifest points at the delivery."
        )
    frames = load_frames(source)

    start = int(spec.get("start", 0))
    end = int(spec.get("end", len(frames)))
    step = int(spec.get("step", 1))
    selected = frames[start:end:step]
    if not selected:
        raise SystemExit(f"[{name}] frame range {start}:{end}:{step} selects nothing")

    scale = float(spec.get("scale", 1.0))
    if scale > 1.0 and abs(scale - 1.5) > 1e-6 and not spec.get("allow_rough_upscale"):
        raise SystemExit(
            f"[{name}] scale {scale} enlarges the art, but only x1.5 does so cleanly on "
            f"this set (2px outlines land exactly on 3px). Another factor gives a mix of "
            f"widths and a chewed-looking outline. Set \"allow_rough_upscale\": true to "
            f"do it anyway."
        )

    flip = bool(spec.get("flip", False))
    margin = int(spec.get("margin", 2))
    drop_empty = bool(spec.get("drop_empty", False))

    images = [np.array(Image.open(f).convert("RGBA")) for f in selected]

    if spec.get("isolate"):
        # Before the union box is measured, not after: a ball left in the frame would
        # otherwise stretch the crop across everywhere it rolls.
        for image in images:
            keep = largest_blob(image[:, :, 3] >= ALPHA_CUTOFF)
            image[~keep] = 0

    # One rectangle for the whole clip: the union of every frame's drawn area. This is
    # what keeps the motion — crop each frame to its own content and the fox would be
    # re-centred every frame, which stops it moving at all.
    boxes = [content_bbox(im) for im in images]
    drawn = [b for b in boxes if b is not None]
    if not drawn:
        raise SystemExit(f"[{name}] every selected frame is empty")
    x0 = max(0, min(b[0] for b in drawn) - margin)
    y0 = max(0, min(b[1] for b in drawn) - margin)
    x1 = min(images[0].shape[1], max(b[2] for b in drawn) + margin)
    y1 = min(images[0].shape[0], max(b[3] for b in drawn) + margin)

    if drop_empty:
        keep = [i for i, b in enumerate(boxes) if b is not None]
        images = [images[i] for i in keep]
        selected = [selected[i] for i in keep]

    palette = build_palette(images)

    out_w = max(1, round((x1 - x0) * scale))
    out_h = max(1, round((y1 - y0) * scale))

    out_dir = Path(spec["out"])
    if not out_dir.is_absolute():
        out_dir = (root / out_dir).resolve()

    report = {
        "name": name,
        "source": str(source),
        "frames_in": len(frames),
        "frames_out": len(images),
        "src_canvas": (int(images[0].shape[1]), int(images[0].shape[0])),
        "crop": (x0, y0, x1, y1),
        "scale": scale,
        "out_canvas": (out_w, out_h),
        "palette": len(palette),
        "out_dir": str(out_dir),
        "flip": flip,
    }

    if dry_run:
        return report

    out_dir.mkdir(parents=True, exist_ok=True)
    for existing in out_dir.glob("*.png"):
        existing.unlink()

    written = []
    for index, image in enumerate(images, start=1):
        cropped = image[y0:y1, x0:x1]

        if scale >= 1.0:
            # Growing (or unchanged): nearest, and nothing else. It is already exactly
            # the palette and exactly binary alpha, so there is nothing to fix up —
            # anything smoother would only introduce colours that have to be undone.
            frame = Image.fromarray(cropped, "RGBA").resize((out_w, out_h), Image.NEAREST)
        else:
            opaque = cropped[:, :, 3] >= ALPHA_CUTOFF
            rgb = bleed_edges(cropped[:, :, :3], opaque)

            # Resample colour and coverage separately: the alpha decides the silhouette
            # and gets re-hardened, the RGB only has to be right where the alpha keeps it.
            rgb_small = np.array(
                Image.fromarray(rgb, "RGB").resize((out_w, out_h), Image.LANCZOS)
            )
            alpha_small = np.array(
                Image.fromarray(cropped[:, :, 3], "L").resize((out_w, out_h), Image.LANCZOS)
            )
            mask = alpha_small >= ALPHA_CUTOFF

            snapped = snap_to_palette(rgb_small, palette)
            out = np.zeros((out_h, out_w, 4), dtype=np.uint8)
            out[:, :, :3] = snapped
            out[:, :, 3] = np.where(mask, 255, 0).astype(np.uint8)
            out[~mask, :3] = 0
            frame = Image.fromarray(out, "RGBA")

        if flip:
            frame = frame.transpose(Image.FLIP_LEFT_RIGHT)
        path = out_dir / f"{index:03d}.png"
        frame.save(path)
        written.append(np.array(frame))

    # The anchor FoxV2 feeds to AnimatedSprite2D.offset: the fox's footing in this
    # clip's own output pixels. Taken across the whole clip so it can't drift frame to
    # frame — horizontally the centre of the drawn area, vertically its bottom edge.
    out_boxes = [content_bbox(im) for im in written]
    out_drawn = [b for b in out_boxes if b is not None]
    ax0 = min(b[0] for b in out_drawn)
    ax1 = max(b[2] for b in out_drawn)
    ay1 = max(b[3] for b in out_drawn)
    report["anchor"] = (round((ax0 + ax1) / 2.0, 1), float(ay1))
    report["area"] = float(np.mean([np.sqrt(drawn_area(im)) for im in written]))

    # Deliberately not next to the frames: anything under assets/ gets imported by Godot
    # as a game texture and shipped in the export. build/ is gitignored scratch.
    sheets = root / "build" / "fox_sheets"
    sheets.mkdir(parents=True, exist_ok=True)
    contact_sheet(written, sheets / f"{name}.png")
    report["sheet"] = str(sheets / f"{name}.png")
    return report


def contact_sheet(images: list[np.ndarray], path: Path, cols: int = 8, cell: int = 160):
    rows = (len(images) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cell, rows * cell), (250, 240, 225))
    for i, arr in enumerate(images):
        im = Image.fromarray(arr, "RGBA")
        im.thumbnail((cell - 8, cell - 8), Image.NEAREST)
        x = (i % cols) * cell + (cell - im.width) // 2
        y = (i // cols) * cell + (cell - im.height) // 2
        sheet.paste(im, (x, y), im)
    sheet.save(path)


def write_pack(reports: list[dict], manifest: dict, clips: list[dict], dest: Path) -> None:
    """Assemble a folder to hand back to the artist.

    The frames the game actually uses, at the size it uses them, one folder per clip,
    plus a contact sheet each and a note saying what's worth fixing. The point is that
    she cleans up *these* — the resized and re-cut versions — rather than her originals,
    because her originals are no longer what the game loads.
    """
    import shutil

    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    sheets = dest / "_contact sheets"
    sheets.mkdir()

    by_name = {c["name"]: c for c in clips}
    lines = [
        "FOX ANIMATION PACK",
        "",
        "These are the frames the game is running right now. They started as your files;",
        "what changed is that each clip has been cropped to the fox and resized so that",
        "every clip is the same fox at the same size. Nothing was redrawn.",
        "",
        "If you want to tidy any of it up, please work on THESE files rather than your",
        "originals -- these are the ones the game loads now.",
        "",
        "Each clip also has a contact sheet in '_contact sheets' showing every frame at",
        "once, which is the quickest way to spot a frame that jumps.",
        "",
        "-" * 70,
        "",
    ]

    order = {"reference": 0, "resized": 1, "cut": 2}
    grouped = sorted(reports, key=lambda r: order.get(by_name[r["name"]].get("pack_group", "cut"), 3))

    headings = {
        "reference": ("ALREADY CORRECT -- please don't change these",
                      "These two set the size everything else was matched to."),
        "resized": ("RESIZED -- worth a look, probably fine",
                    "These were drawn smaller than the rest, so they've been scaled up to match.\n"
                    "The scaling was exact (no blurring, no new colours), so they should be clean."),
        "cut": ("CUT FROM 'FOX PLAY 02' -- these are the ones that need you",
                "Your ball animation turned out to contain several poses the game was missing,\n"
                "so it's been cut into separate clips. The cuts were made by measurement, not\n"
                "by eye, so the start and end points are best guesses."),
    }
    seen_group = None
    for report in grouped:
        spec = by_name[report["name"]]
        group = spec.get("pack_group", "cut")
        if group != seen_group:
            title, blurb = headings[group]
            lines += ["", "=" * 70, title, "=" * 70, "", blurb, ""]
            seen_group = group

        src = Path(report["out_dir"])
        target = dest / report["name"]
        target.mkdir()
        for png in sorted(src.glob("*.png"), key=natural_key):
            shutil.copy2(png, target / png.name)
        if report.get("sheet") and Path(report["sheet"]).exists():
            shutil.copy2(report["sheet"], sheets / f"{report['name']}.png")

        size = report["out_canvas"]
        lines.append(f"  {report['name']}/   {report['frames_out']} frames, {size[0]}x{size[1]}")
        for note in spec.get("cleanup", []):
            # One bullet per note, wrapped, with continuations lined up under the text
            # rather than under the dash — several of these run to a short paragraph.
            lines.append(textwrap.fill(note, width=76, initial_indent="      - ",
                                       subsequent_indent="        "))
        lines.append("")

    lines += [
        "",
        "=" * 70,
        "ABOUT LOOPS",
        "=" * 70,
        "",
        "Several notes above mention a clip 'not looping'. What that means: the game plays",
        "these over and over with no gap, so the last frame has to lead straight back into",
        "the first. If you flip between the last and first frame and it looks like a jump,",
        "it'll look like a jump in the game.",
        "",
        "'walk' and 'sleep' both do this correctly and are the best references for it.",
        "",
        "Canvas sizes don't need to match between clips -- the game works out where the",
        "fox's feet are in each one and lines them up itself. So please don't spend time",
        "matching canvases or margins.",
        "",
    ]
    (dest / "README.txt").write_text("\n".join(lines), encoding="utf-8")
    print(f"\nPack written to {dest}")


def probe(folder: Path) -> None:
    frames = load_frames(folder)
    sample = frames[:: max(1, len(frames) // 12)][:12]
    images = [np.array(Image.open(f).convert("RGBA")) for f in sample]
    areas = [np.sqrt(drawn_area(im)) for im in images]
    mean_area = float(np.mean(areas))
    boxes = [b for b in (content_bbox(im) for im in images) if b is not None]
    canvas = images[0].shape
    print(f"folder        {folder}")
    print(f"frames        {len(frames)}")
    print(f"canvas        {canvas[1]} x {canvas[0]}")
    if boxes:
        print(
            f"content union {min(b[0] for b in boxes)},{min(b[1] for b in boxes)} -> "
            f"{max(b[2] for b in boxes)},{max(b[3] for b in boxes)}"
        )
    print(f"palette       {len(build_palette(images))} colours")
    print(f"size metric   {mean_area:.1f}   (mean sqrt of drawn pixels)")
    ratio = REFERENCE_AREA / mean_area
    if ratio >= 1.0:
        print(
            f"suggested     this clip is SMALLER than {SIZE_REFERENCE} — it needs x{ratio:.3f},\n"
            f"              which this script will not do. Either get it re-exported\n"
            f"              larger, or set art_scale = {ratio:.2f} in fox_v2.gd."
        )
    else:
        print(f"suggested     scale {ratio:.4f}  (about 1/{1 / ratio:.2f}) to match {SIZE_REFERENCE}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--manifest", type=Path, help="JSON file describing the clips")
    parser.add_argument("--probe", type=Path, help="measure a source folder and stop")
    parser.add_argument("--only", action="append", help="build just this clip (repeatable)")
    parser.add_argument("--dry-run", action="store_true", help="report without writing")
    parser.add_argument(
        "--pack",
        type=Path,
        nargs="?",
        const=Path("build/fox-art-pack"),
        help="also assemble a folder to send the artist (default build/fox-art-pack)",
    )
    args = parser.parse_args()

    if args.probe:
        probe(args.probe)
        return

    if not args.manifest:
        parser.error("give --manifest or --probe")

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    root = args.manifest.resolve().parent.parent
    src_root = Path(manifest["src_root"]).expanduser() if manifest.get("src_root") else None
    if src_root is not None and not src_root.is_absolute():
        src_root = (root / src_root).resolve()
    clips = manifest["clips"]
    if args.only:
        wanted = set(args.only)
        clips = [c for c in clips if c["name"] in wanted]
        missing = wanted - {c["name"] for c in clips}
        if missing:
            raise SystemExit(f"no such clip(s) in manifest: {', '.join(sorted(missing))}")

    reports = []
    for spec in clips:
        report = process_clip(spec, root, src_root=src_root, dry_run=args.dry_run)
        reports.append(report)
        arrow = "(dry run)" if args.dry_run else "->"
        print(
            f"[{report['name']:<10s}] {report['frames_out']:3d} frames  "
            f"{report['src_canvas'][0]}x{report['src_canvas'][1]} "
            f"crop{report['crop']} x{report['scale']} {arrow} "
            f"{report['out_canvas'][0]}x{report['out_canvas'][1]}"
            + (f"  anchor {report['anchor']}  size {report['area']:.1f}" if "anchor" in report else "")
        )

    if args.dry_run or not reports:
        return

    print("\nPaste into FoxV2.CLIPS (fox_v2.gd):\n")
    for r in reports:
        if "anchor" not in r:
            continue
        print(
            f'\t"{r["name"]}": {{\n'
            f'\t\t"frames": {r["frames_out"]}, "fps": 12.0, "art_scale": 1.0,\n'
            f'\t\t"playback": Playback.LOOP, "anchor": Vector2({r["anchor"][0]}, {r["anchor"][1]}),\n'
            f"\t}},"
        )
    print("\nSize check (all clips should be close to each other):")
    for r in reports:
        if "area" in r:
            print(f'  {r["name"]:<10s} {r["area"]:6.1f}   vs {SIZE_REFERENCE} {REFERENCE_AREA:.1f}')

    if args.pack:
        pack_dir = args.pack if args.pack.is_absolute() else root / args.pack
        if len(reports) != len(manifest["clips"]):
            print("\nSkipping --pack: it needs every clip built, and --only limited this run.")
        else:
            write_pack(reports, manifest, clips, pack_dir)


if __name__ == "__main__":
    main()
