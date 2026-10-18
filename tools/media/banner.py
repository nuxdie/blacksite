#!/usr/bin/env python3
"""Render the README banner and a square logo from the Rajdhani font and the project icon's reticle.

    python3 tools/media/banner.py            # writes docs/media/banner.png and docs/media/logo.png
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
FONT = ROOT / "assets/fonts/Rajdhani-Bold.ttf"
MED = ROOT / "assets/fonts/Rajdhani-Medium.ttf"
OUT = ROOT / "docs/media"
BG, INK, AMBER, DIM = (11, 15, 22), (232, 237, 241), (255, 184, 74), (120, 130, 142)


def reticle(draw, cx, cy, r, w):
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=INK, width=w)
    for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        a = (cx + dx * r * 1.35, cy + dy * r * 1.35)
        b = (cx + dx * r * 0.65, cy + dy * r * 0.65)
        draw.line([a, b], fill=INK, width=w)
    d = r * 0.15
    draw.ellipse([cx - d, cy - d, cx + d, cy + d], fill=AMBER)


def spaced(draw, xy, text, font, fill, spacing):
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=font, fill=fill)
        x += draw.textlength(ch, font=font) + spacing
    return x


def banner():
    W, H = 1600, 420
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    # a faint grid, like the deck
    for x in range(0, W, 40):
        d.line([(x, 0), (x, H)], fill=(14, 19, 27))
    for y in range(0, H, 40):
        d.line([(0, y), (W, y)], fill=(14, 19, 27))
    reticle(d, 190, H // 2, 78, 9)
    title = ImageFont.truetype(str(FONT), 150)
    end = spaced(d, (330, 92), "BLACKSITE", title, INK, 22)
    d.line([(334, 258), (334 + 70, 258)], fill=AMBER, width=5)
    tag = ImageFont.truetype(str(MED), 30)
    spaced(d, (334, 282), "ONE OPERATOR  ·  ONE NIGHT", tag, AMBER, 6)
    sub = ImageFont.truetype(str(MED), 24)
    spaced(d, (334, 330), "A SLOW, TACTICAL STEALTH SHOOTER IN GODOT 4", sub, DIM, 3)
    img.save(OUT / "banner.png", optimize=True)


def logo():
    S = 512
    img = Image.new("RGB", (S, S), BG)
    d = ImageDraw.Draw(img)
    reticle(d, S // 2, S // 2 - 30, 128, 16)
    f = ImageFont.truetype(str(FONT), 64)
    text = "BLACKSITE"
    w = sum(d.textlength(c, font=f) + 8 for c in text) - 8
    spaced(d, ((S - w) / 2, 392), text, f, INK, 8)
    img.save(OUT / "logo.png", optimize=True)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    banner()
    logo()
    print("wrote", OUT / "banner.png", OUT / "logo.png")
