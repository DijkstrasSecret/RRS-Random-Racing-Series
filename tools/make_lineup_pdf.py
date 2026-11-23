"""Builds docs/design/RRS_car_lineup.pdf: 3 cars per page, livery off / livery on.

Names, classes and livery flags come from scripts/core/car_roster.gd; number
and sponsor from tools/blender_cars.py. Pictures first:
    Godot.exe --path . -s res://tests/screenshot_cars.gd -- --cars=<all ids> --prefix=pdf0 --livery=0 --far --no-chase
    Godot.exe --path . -s res://tests/screenshot_cars.gd -- --cars=<all ids> --prefix=pdf1 --livery=1 --far --no-chase
(windowed, with an override.cfg containing window/size/no_focus=true), then:
    python tools/make_lineup_pdf.py <screenshots folder> [--previews]
"""
import os
import re
import sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "design", "RRS_car_lineup.pdf")
# Colours / pattern of each livery (the rest is read from the generator).
STYLE = {
    "kartal": "white rally stripes", "mirelle": "cup yellow / black", "kerkenez": "yellow rally stripes",
    "atmaca": "red / blue rally", "quadra": "touring white / red", "romola": "Italian red / green",
    "kaze": "red / white", "dingo": "orange / black", "piccolo": "twin bonnet stripes",
    "harcourt": "white centre stripe", "mammoth": "yellow / black", "orion": "teal / white",
    "bavaro": "tricolour stripes", "braxton": "white twin stripes", "ashford": "white / red stripes",
    "bellmont": "white coach lines", "hanlong": "red / white",
    "e30": "M tricolour stripes", "troc": "black / white rally", "passat": "white / blue rally",
}
TIERS = "DCBA"
TIER_COL = {"D": (140, 205, 115), "C": (90, 180, 255), "B": (190, 130, 255), "A": (255, 115, 77)}


def roster():
    src = open(os.path.join(ROOT, "scripts", "core", "car_roster.gd"), encoding="utf-8").read()
    cars = []
    for m in re.finditer(r'\{"id": "([a-z_]+)", "tier": (\d)(, "livery": true)?, "name": "([^"]+)"', src):
        cars.append((m.group(1), m.group(4), TIERS[int(m.group(2))], bool(m.group(3))))
    return cars


def livery_text(cid):
    src = open(os.path.join(ROOT, "tools", "blender_cars.py"), encoding="utf-8").read()
    i = src.find('    "%s": dict(' % cid)
    if i < 0:
        return None
    block = src[i:src.find("\n    ),", i)]
    get = lambda key: (re.search(key + r'="([^"]*)"', block) or [None, ""])[1]
    return "#%s %s  ·  %s" % (get("number"), get("sponsor"), STYLE.get(cid, ""))


PW, PH = 1240, 1754
SQ = 540
MX = (PW - 2 * SQ) // 3
font_h = ImageFont.truetype("arialbd.ttf", 34)
font_n = ImageFont.truetype("arialbd.ttf", 26)
font_s = ImageFont.truetype("arial.ttf", 20)
font_b = ImageFont.truetype("arialbd.ttf", 20)


def square(path):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    side = int(h * 0.8)
    left = (w - side) // 2
    top = min(int(h * 0.56) - side // 2, h - side)
    return im.crop((left, top, left + side, top + side)).resize((SQ, SQ), Image.LANCZOS)


def main():
    shots = sys.argv[1]
    cars = roster()
    pages = []
    count = (len(cars) + 2) // 3
    for p in range(0, len(cars), 3):
        page = Image.new("RGB", (PW, PH), (20, 22, 28))
        d = ImageDraw.Draw(page)
        d.text((MX, 34), "RRS - CAR LINE-UP", fill=(255, 200, 50), font=font_h)
        d.text((PW - MX - 230, 44), "page %d / %d" % (p // 3 + 1, count), fill=(160, 165, 175), font=font_s)
        d.text((MX + SQ // 2 - 70, 100), "LIVERY OFF", fill=(200, 200, 200), font=font_b)
        d.text((2 * MX + SQ + SQ // 2 - 65, 100), "LIVERY ON", fill=(120, 230, 120), font=font_b)
        y = 140
        for cid, name, tier, has_livery in cars[p:p + 3]:
            d.rectangle((MX, y, MX + 30, y + 30), fill=TIER_COL[tier])
            d.text((MX + 8, y + 2), tier, fill=(15, 15, 18), font=font_n)
            d.text((MX + 44, y), name, fill=(255, 255, 255), font=font_n)
            if has_livery:
                sub = livery_text(cid) or ""
            else:
                sub = "no livery (original downloaded model)" if cid == "psx_hatch" else "no livery (by choice)"
            d.text((MX + 44, y + 34), sub, fill=(175, 180, 190), font=font_s)
            top = y + 66
            page.paste(square(os.path.join(shots, "pdf0_game_%s_front.png" % cid)), (MX, top))
            page.paste(square(os.path.join(shots, "pdf1_game_%s_front.png" % cid)), (2 * MX + SQ, top))
            if not has_livery:
                d.rectangle((2 * MX + SQ, top + SQ - 44, 2 * MX + 2 * SQ, top + SQ), fill=(0, 0, 0))
                d.text((2 * MX + SQ + 16, top + SQ - 36), "NO LIVERY FOR THIS CAR", fill=(230, 230, 230), font=font_b)
            y = top + SQ + 22
        pages.append(page)
    if "--previews" in sys.argv:
        for i, pg in enumerate(pages):
            pg.resize((PW // 2, PH // 2)).save(os.path.join(shots, "lineup_p%d.png" % (i + 1)))
    pages[0].save(OUT, save_all=True, append_images=pages[1:], resolution=150.0, quality=88)
    print("pages:", len(pages), "->", OUT)


if __name__ == "__main__":
    main()
