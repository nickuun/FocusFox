"""Generates the contact shadow every den find sits on.

One soft ellipse, reused by everything in the room: den.gd scales it to the width of
whatever find it belongs to and throwable_prop.gd fades and shrinks it as the find is
lifted off the floor. Nothing in the room cast a shadow before this, which is most of
why finds read as stickers on the wall rather than objects on a floor.

Why generated rather than drawn: it's one gradient with no character to it, and the
thing that matters — how dark, how soft — is a number worth being able to turn rather
than a file worth repainting. Re-running this script is how the look gets changed.

Deliberately soft-edged even though the finds are pixel art. The room behind them is
painted, with gradients and antialiased edges, so a hard-edged shadow would read as
foreign against the floor it falls on. It's also pure black at low alpha rather than a
tinted grey: the floor warms as it recedes and a fixed brown would go wrong at one end
of the room or the other.

    python tools/make_shadow.py
"""

from PIL import Image, ImageDraw, ImageFilter

SS = 8  # supersample factor; drawn at SS and downsampled

OUT_PATH = "assets/main_menu/environment/find-shadow.png"

# Sized for the narrowest find (the 34px clock) and scaled up from there, so the common
# case scales down. Scaling a blurred gradient up is where softness turns to mush.
WIDTH = 64
HEIGHT = 20
## Peak opacity under the centre. Low: this is a lamp-lit room with no hard sun, and a
## shadow that reads clearly on the pale floor near the window goes to a black smear on
## the darker boards at the far end.
ALPHA = 132
## Blur radius as a fraction of the height. Enough that the rim never shows a seam
## against the floorboards, not so much that the shape stops being an ellipse.
BLUR = 0.22


def make_shadow() -> Image.Image:
    """A WIDTH x HEIGHT sprite whose bounds *are* the shadow, falloff included.

    The ellipse is inset far enough that the blur lands inside the canvas rather than
    clipping at its edge. That keeps the sprite's size meaningful: den.gd scales it by
    `find_width / WIDTH`, which is only true if the art has no invisible margin.
    """
    w, h = WIDTH * SS, HEIGHT * SS
    blur = h * BLUR
    inset = blur

    img = Image.new("L", (w, h), 0)
    ImageDraw.Draw(img).ellipse((inset, inset, w - inset, h - inset), fill=ALPHA)
    img = img.filter(ImageFilter.GaussianBlur(blur))
    img = img.resize((WIDTH, HEIGHT), Image.LANCZOS)

    out = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    out.putalpha(img)
    return out


if __name__ == "__main__":
    shadow = make_shadow()
    shadow.save(OUT_PATH)
    print(f"wrote {OUT_PATH} {shadow.size[0]}x{shadow.size[1]}")
