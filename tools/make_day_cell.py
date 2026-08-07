"""Generates the journal's month-grid day cell.

One neutral cell, drawn to sit on the light panel and be tinted per state in code —
green for an active day, gold for today, dimmed for out-of-month. Tinting multiplies,
so the source has to stay near-neutral and light or every tint comes out muddy.

Colours are sampled from day_tab.png so the cell belongs to the painted panels rather
than looking like a UI rectangle dropped on top of them. Drawn at 8x and downsampled,
because the book art is painterly with soft edges and a hard-edged cell would read as
foreign next to it.

    python tools/make_day_cell.py
"""

from PIL import Image, ImageDraw, ImageFilter

SIZE = 34
SS = 8  # supersample factor
RADIUS = 7

FILL = (233, 222, 202, 255)      # a touch below the panel interior, so it reads as inset
BORDER = (205, 188, 165, 255)    # the panel's own border colour
HIGHLIGHT = (252, 247, 236, 130)  # soft top-inner lift, the way the panels are lit


def main() -> None:
    n = SIZE * SS
    r = RADIUS * SS

    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Body plus a border drawn as a slightly larger rounded rect underneath.
    d.rounded_rectangle([0, 0, n - 1, n - 1], radius=r, fill=BORDER)
    d.rounded_rectangle([SS, SS, n - 1 - SS, n - 1 - SS], radius=max(1, r - SS), fill=FILL)

    # Light comes from the top in this art. A rounded rect of highlight leaves a visible
    # seam where it ends, so this is a smooth vertical falloff masked to the cell's
    # inner shape instead — the panels have no hard internal edges and neither should
    # the cell.
    gradient = Image.new("L", (1, n))
    for y in range(n):
        t = y / (n - 1)
        gradient.putpixel((0, y), int(HIGHLIGHT[3] * max(0.0, 1.0 - t * 1.6) ** 2))
    gradient = gradient.resize((n, n))

    shape = Image.new("L", (n, n), 0)
    ImageDraw.Draw(shape).rounded_rectangle(
        [SS, SS, n - 1 - SS, n - 1 - SS], radius=max(1, r - SS), fill=255
    )
    shape = shape.filter(ImageFilter.GaussianBlur(SS * 0.5))

    lift = Image.new("RGBA", (n, n), HIGHLIGHT[:3] + (0,))
    lift.putalpha(Image.composite(gradient, Image.new("L", (n, n), 0), shape))
    img = Image.alpha_composite(img, lift)

    out = img.resize((SIZE, SIZE), Image.LANCZOS)
    path = "assets/journal/journal ui/Main Page/day_cell.png"
    out.save(path)
    print(f"wrote {path} ({out.size[0]}x{out.size[1]})")


if __name__ == "__main__":
    main()
