"""Lays a second window capture (Settings, a panel) over the main window capture.

    /usr/bin/python3 overlay.py MAIN.png PANEL.png DX DY OUT.png

DX and DY are the panel's offset from the main window in points (2x pixels are used).
"""
import sys

from PIL import Image, ImageFilter

from compose import paint_buttons

main = Image.open(sys.argv[1]).convert("RGBA")
panel = Image.open(sys.argv[2]).convert("RGBA")
# The panel is the window in front, so its buttons are in color.
paint_buttons(panel)
dx, dy = int(float(sys.argv[3]) * 2), int(float(sys.argv[4]) * 2)
shadow = Image.new("RGBA", main.size, (0, 0, 0, 0))
shadow.paste((0, 0, 0, 255), (dx, dy + 16), panel.getchannel("A").point(lambda a: a * 0.6))
shadow = shadow.filter(ImageFilter.GaussianBlur(28))
out = Image.alpha_composite(main, shadow)
out.alpha_composite(panel, (dx, dy))
# Keep the main window's own rounded corners.
out.putalpha(main.getchannel("A"))
out.save(sys.argv[5])
