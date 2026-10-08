"""Resize the supplied basket and wool with nearest-neighbour pixel sampling."""
from pathlib import Path
from PIL import Image

SOURCE = Path.home() / "Downloads"
DEST = Path(__file__).resolve().parents[1] / "assets/main_menu/environment/wool"


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    for name in ["empty-wool-basket", "green-wool", "blue-wool", "red-wool", "white-wool"]:
        im = Image.open(SOURCE / (name + ".png")).convert("RGBA")
        im = im.crop(im.getchannel("A").getbbox())
        # The previous set was about 50% oversized: regenerate at two thirds
        # directly from the delivery, rather than downsampling the resized art.
        width = 96 if name == "empty-wool-basket" else 31
        im = im.resize((width, round(im.height * width / im.width)), Image.Resampling.NEAREST)
        im.save(DEST / (name + ".png"))
        if name == "empty-wool-basket":
            # The front lip occludes the lower wool, while the back stays behind it.
            front = im.copy()
            front.paste((0, 0, 0, 0), (0, 0, im.width, round(im.height * 0.46)))
            front.save(DEST / "basket-front.png")
        print(name, im.size)
    icon = Image.new("RGBA", (96, 74))
    basket = Image.open(DEST / "empty-wool-basket.png")
    icon.alpha_composite(basket, (0, 9))
    for colour, x, y in [("white", 15, 6), ("blue", 39, 3), ("red", 26, 18), ("green", 55, 16)]:
        icon.alpha_composite(Image.open(DEST / (colour + "-wool.png")), (x, y))
    icon.alpha_composite(Image.open(DEST / "basket-front.png"), (0, 9))
    icon.save(DEST / "icon.png")


if __name__ == "__main__":
    main()
