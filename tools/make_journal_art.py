"""Generates the journal's neutral, tintable UI pieces.

Two shapes so far: the month grid's day cell and the achievement badge. Both are
plaques of the same family, so they share one drawing routine and differ only in size,
corner radius and how strong the bevel is.

Why generated rather than drawn: these are UI primitives with no character to them, and
the code needs many colour variants of each (active/today/out-of-month; earned per
category/locked). Tinting one neutral source beats hand-drawing a dozen near-identical
files, and re-running this script is how the look gets changed.

Two rules make the tinting work, and both are easy to break by eye:
  - the source must stay pale and near-neutral, because Godot's modulate multiplies —
    a saturated source turns every tint muddy;
  - no hard internal edges. The book art is painterly, so a crisp highlight boundary
    reads as foreign next to it. The bevel is a smooth falloff, not a second rectangle.

Colours are sampled from day_tab.png so the results belong to the painted panels.

    python tools/make_journal_art.py
"""

from PIL import Image, ImageDraw, ImageFilter

SS = 8  # supersample factor; everything is drawn at SS and downsampled

OUT_DIR = "assets/journal/journal ui/Main Page"

PANEL_BORDER = (205, 188, 165, 255)  # day_tab.png's own border


def plaque(size, radius, fill, border, highlight_alpha, bevel=0.45, border_w=1):
    """A rounded plaque with a soft top-down bevel, drawn at SS and downsampled."""
    n = size * SS
    r = radius * SS
    bw = border_w * SS

    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, n - 1, n - 1], radius=r, fill=border)
    d.rounded_rectangle([bw, bw, n - 1 - bw, n - 1 - bw], radius=max(1, r - bw), fill=fill)

    # Light comes from the top in this art. A rounded rect of highlight would leave a
    # seam where it ends, so this is a vertical falloff masked to the inner shape.
    gradient = Image.new("L", (1, n))
    for y in range(n):
        t = y / (n - 1)
        gradient.putpixel((0, y), int(highlight_alpha * max(0.0, 1.0 - t / bevel) ** 2))
    gradient = gradient.resize((n, n))

    shape = Image.new("L", (n, n), 0)
    ImageDraw.Draw(shape).rounded_rectangle(
        [bw, bw, n - 1 - bw, n - 1 - bw], radius=max(1, r - bw), fill=255
    )
    shape = shape.filter(ImageFilter.GaussianBlur(SS * 0.5))

    lift = Image.new("RGBA", (n, n), (252, 247, 236, 0))
    lift.putalpha(Image.composite(gradient, Image.new("L", (n, n), 0), shape))
    img = Image.alpha_composite(img, lift)

    return img.resize((size, size), Image.LANCZOS)


def main() -> None:
    # The month grid cell: reads as slightly inset in the panel, so its fill sits just
    # below the panel interior (238,228,210) rather than matching it.
    cell = plaque(34, 7, fill=(233, 222, 202, 255), border=PANEL_BORDER,
                  highlight_alpha=130, bevel=0.62)
    cell.save(f"{OUT_DIR}/day_cell.png")
    print(f"wrote {OUT_DIR}/day_cell.png ({cell.size[0]}x{cell.size[1]})")

    # The achievement badge: a shade lighter and more strongly bevelled than the cell,
    # so it reads as a raised medal rather than a recess, and holds a tint at a glance.
    badge = plaque(48, 11, fill=(240, 231, 214, 255), border=(198, 179, 153, 255),
                   highlight_alpha=165, bevel=0.5, border_w=2)
    badge.save(f"{OUT_DIR}/badge.png")
    print(f"wrote {OUT_DIR}/badge.png ({badge.size[0]}x{badge.size[1]})")


if __name__ == "__main__":
    main()
