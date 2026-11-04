"""Puts a window capture on a dark backdrop at 2880 x 1800, RGB, no alpha.

Capture the window without its shadow (`screencapture -o -l WINDOW_ID raw.png`), then:

    /usr/bin/python3 compose.py RAW.png OUT.png

The test window sits behind other windows while it is captured, so its close, minimize and
zoom buttons are grey. They are drawn in their normal colors, and a soft shadow is added.
"""

import sys

from PIL import Image, ImageDraw, ImageFilter

W, H = 2880, 1800
MARGIN = 110
# Button circles in a 2x capture: 28 px across, centers 46 px apart, top at 18 px.
BUTTONS = [
    ((255, 95, 87), (224, 68, 62)),
    ((254, 188, 46), (222, 161, 35)),
    ((40, 200, 64), (26, 171, 41)),
]


def paint_buttons(win: Image.Image) -> None:
    ss = 4
    for i, (fill, edge) in enumerate(BUTTONS):
        x0, y0, d = 18 + 46 * i, 18, 28
        patch = Image.new("RGBA", (d * ss, d * ss), (0, 0, 0, 0))
        draw = ImageDraw.Draw(patch)
        draw.ellipse((0, 0, d * ss - 1, d * ss - 1), fill=edge)
        draw.ellipse((ss, ss, d * ss - 1 - ss, d * ss - 1 - ss), fill=fill)
        patch = patch.resize((d, d), Image.LANCZOS)
        # Clear the grey circle first so its edge does not show around the new one.
        bg = win.getpixel((x0 + d + 6, y0 + d // 2))
        ImageDraw.Draw(win).ellipse((x0 - 1, y0 - 1, x0 + d, y0 + d), fill=bg)
        win.alpha_composite(patch, (x0, y0))


def main() -> None:
    win = Image.open(sys.argv[1]).convert("RGBA")
    # With Settings in front, the document window's buttons are grey, as on a real Mac.
    if "--keep-buttons" not in sys.argv:
        paint_buttons(win)

    canvas = Image.new("RGB", (W, H))
    top, bottom = (17, 20, 26), (27, 31, 39)
    for y in range(H):
        t = y / (H - 1)
        canvas.paste(tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)), (0, y, W, y + 1))

    scale = min((W - 2 * MARGIN) / win.width, (H - 2 * MARGIN) / win.height)
    win = win.resize((round(win.width * scale), round(win.height * scale)), Image.LANCZOS)
    x, y = (W - win.width) // 2, (H - win.height) // 2

    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    alpha = win.getchannel("A").point(lambda a: a * 0.55)
    shadow.paste((0, 0, 0, 255), (x, y + 24), alpha)
    shadow = shadow.filter(ImageFilter.GaussianBlur(40))
    canvas.paste(shadow, (0, 0), shadow)
    canvas.paste(win, (x, y), win)
    canvas.save(sys.argv[2], optimize=True)
    print(sys.argv[2], canvas.size, canvas.mode)


if __name__ == "__main__":
    main()
