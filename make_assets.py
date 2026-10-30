"""Generates the app icon and launch images (flat PNGs; iOS 6 adds the icon gloss and rounding itself)."""
import random
from PIL import Image, ImageDraw

def grad(d, box, top, bot):
    x0, y0, x1, y1 = box
    for y in range(y0, y1):
        t = (y - y0) / max(1, y1 - y0 - 1)
        d.line([(x0, y), (x1, y)], fill=tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)))

def icon(n):
    im = Image.new("RGB", (n, n))
    d = ImageDraw.Draw(im)
    grad(d, (0, 0, n, n), (255, 118, 50), (204, 52, 0))
    s = n / 100.0
    # a white speech bubble with an orange up-arrow: an original mark, not the Reddit mascot
    d.rounded_rectangle([18*s, 22*s, 82*s, 66*s], radius=14*s, fill=(255, 255, 255))
    d.polygon([(30*s, 64*s), (30*s, 82*s), (50*s, 64*s)], fill=(255, 255, 255))
    d.polygon([(50*s, 30*s), (66*s, 50*s), (56*s, 50*s), (56*s, 58*s), (44*s, 58*s), (44*s, 50*s), (34*s, 50*s)], fill=(232, 84, 12))
    return im

def launch(w, h, scale):
    random.seed(3)
    im = Image.new("RGB", (w, h), (190, 186, 178))
    d = ImageDraw.Draw(im)
    for y in range(0, h, 2 * scale):
        d.line([(0, y), (w, y)], fill=(200 + random.randint(0, 20),) * 3)
    sb, nb, tb = 20 * scale, 44 * scale, 49 * scale
    d.rectangle([0, 0, w, sb], fill=(0, 0, 0))
    grad(d, (0, sb, w, sb + nb // 2), (238, 126, 48), (222, 100, 24))
    grad(d, (0, sb + nb // 2, w, sb + nb), (208, 80, 8), (192, 64, 0))
    d.line([(0, sb + nb - 1), (w, sb + nb - 1)], fill=(110, 34, 0))
    grad(d, (0, h - tb, w, h - tb // 2), (70, 66, 62), (32, 30, 28))
    grad(d, (0, h - tb // 2, w, h), (14, 13, 12), (0, 0, 0))
    return im

icon(57).save("res/Icon.png")
icon(114).save("res/Icon@2x.png")
launch(320, 480, 1).save("res/Default.png")
launch(640, 960, 2).save("res/Default@2x.png")
launch(640, 1136, 2).save("res/Default-568h@2x.png")
