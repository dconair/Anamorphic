#!/usr/bin/env python3
"""Erzeugt das App-Icon (iOS 1024 px, macOS-Größen) im Stil der App ("Gate"):
warmes Schwarz, Kamerasensor mit Bayer-Farbfilter, heller 2.39:1-Zuschnitt und ein Bernstein-Doppelpfeil
für Squeeze/Desqueeze.

Aufruf: python3 tools/make_icon.py   (benötigt Pillow und numpy)
"""
import json
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IOS_DIR = os.path.join(ROOT, "Sources", "Icons", "iOS", "Assets.xcassets", "AppIcon.appiconset")
MAC_DIR = os.path.join(ROOT, "Sources", "Icons", "macOS", "Assets.xcassets", "AppIcon.appiconset")

BG = np.array([20, 20, 18], float)
BG_LIFT = np.array([31, 30, 26], float)
DIM = np.array([141, 136, 123], float)
HAIR = np.array([62, 59, 52], float)
AMBER = np.array([217, 150, 52], float)
CORE = np.array([255, 232, 176], float)
BLUE = np.array([88, 150, 255], float)


def mask_img(a, draw_fn):
    im = Image.new("L", (a, a), 0)
    draw_fn(ImageDraw.Draw(im))
    return im


def blur(im, r):
    return np.asarray(im.filter(ImageFilter.GaussianBlur(r)), float) / 255.0


def add(canvas, m, color, strength):
    canvas += m[..., None] * color * strength


# Bayer-Filter (RGGB), gedämpft, damit der Zuschnitt-Ausschnitt heraussticht
CELL_R = np.array([196, 70, 52], float)
CELL_G = np.array([84, 156, 78], float)
CELL_B = np.array([66, 112, 214], float)


def render_art(a):
    """Quadratische Bildfläche a × a, RGB float.

    Motiv: ein Kamerasensor mit Bayer-Farbfilter (RGGB-Raster). Ein heller 2.39:1-Ausschnitt in der Mitte
    steht für den Zuschnitt, der bernsteinfarbene Doppelpfeil darin für Squeeze/Desqueeze.
    """
    yy, xx = np.mgrid[0:a, 0:a].astype(float)
    cx = cy = a / 2
    r = np.sqrt(((xx - cx) / a) ** 2 + ((yy - cy) / a) ** 2) / 0.7
    canvas = BG + (BG_LIFT - BG) * np.clip(1 - r, 0, 1)[..., None] ** 2
    img = Image.fromarray(canvas.astype(np.uint8), "RGB")
    d = ImageDraw.Draw(img)

    n = 13
    size = 0.78 * a
    x0, y0 = cx - size / 2, cy - size / 2
    cell = size / n
    gap = cell * 0.09
    rad = cell * 0.14

    # Sensor-Rahmen
    pad = cell * 0.45
    d.rounded_rectangle([x0 - pad, y0 - pad, x0 + size + pad, y0 + size + pad], radius=cell * 0.5,
                        outline=tuple(int(c) for c in HAIR), width=max(2, int(a * 0.006)))

    # Zuschnitt-Fenster: 13 × 5 Zellen (breites Scope-Format), mittig
    win_c0, win_c1 = 0.0, 13.0
    win_r0, win_r1 = 4, 9

    for row in range(n):
        for col in range(n):
            # RGGB: gerade Zeile R G R G, ungerade Zeile G B G B
            if row % 2 == 0:
                col_rgb = CELL_R if col % 2 == 0 else CELL_G
            else:
                col_rgb = CELL_G if col % 2 == 0 else CELL_B
            inside = win_c0 <= col + 0.5 <= win_c1 and win_r0 <= row < win_r1
            k = 1.0 if inside else 0.30
            c = BG * (1 - k) + col_rgb * k
            xa, ya = x0 + col * cell + gap, y0 + row * cell + gap
            d.rounded_rectangle([xa, ya, xa + cell - 2 * gap, ya + cell - 2 * gap], radius=rad,
                                fill=tuple(int(v) for v in c))

    canvas = np.asarray(img, float)

    # Fensterrahmen in Bernstein mit Eckmarken
    wx0, wx1 = x0 + win_c0 * cell - gap, x0 + win_c1 * cell + gap
    wy0, wy1 = y0 + win_r0 * cell - gap, y0 + win_r1 * cell + gap
    th = max(3, int(a * 0.009))
    frame = mask_img(a, lambda dd: dd.rectangle([wx0, wy0, wx1, wy1], outline=255, width=th))
    add(canvas, blur(frame, a * 0.0007), AMBER, 1.0)
    add(canvas, blur(frame, a * 0.02), AMBER, 0.35)

    # Doppelpfeil (Squeeze/Desqueeze) mit dunkler Kontur für Lesbarkeit auf dem Raster
    L = (wx1 - wx0) * 0.80
    hx0, hx1 = cx - L / 2, cx + L / 2
    head = a * 0.085
    shaft = a * 0.030

    def arrow(dd, grow=0.0, fill=255):
        g = grow
        dd.rectangle([hx0 + head * 0.6, cy - shaft / 2 - g, hx1 - head * 0.6, cy + shaft / 2 + g], fill=fill)
        dd.polygon([(hx0 - g, cy), (hx0 + head + g * 0.6, cy - head * 0.62 - g), (hx0 + head + g * 0.6, cy + head * 0.62 + g)], fill=fill)
        dd.polygon([(hx1 + g, cy), (hx1 - head - g * 0.6, cy - head * 0.62 - g), (hx1 - head - g * 0.6, cy + head * 0.62 + g)], fill=fill)

    outline = mask_img(a, lambda dd: arrow(dd, grow=a * 0.016))
    body = mask_img(a, lambda dd: arrow(dd))
    om = blur(outline, a * 0.003)
    canvas = canvas * (1 - om[..., None] * 0.88) + BG * om[..., None] * 0.88
    bm = blur(body, a * 0.0015)
    arrow_col = CORE * 0.35 + AMBER * 0.65
    canvas = canvas * (1 - bm[..., None]) + arrow_col * bm[..., None]
    add(canvas, blur(body, a * 0.03), AMBER, 0.45)

    return np.clip(canvas, 0, 255)


def squircle(a, radius_ratio=0.2245):
    r = int(a * radius_ratio)
    return mask_img(a, lambda d: d.rounded_rectangle([0, 0, a - 1, a - 1], radius=r, fill=255))


def to_img(arr):
    return Image.fromarray(arr.astype(np.uint8), "RGB")


def make_ios(path):
    art = to_img(render_art(2048)).resize((1024, 1024), Image.LANCZOS)
    art.save(path)


def make_mac():
    S = 2048
    a = int(S * 824 / 1024)
    art = to_img(render_art(a)).convert("RGBA")
    art.putalpha(squircle(a))
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    off = (S - a) // 2
    # weicher Schatten wie in Apples Vorlage
    sh = Image.new("L", (S, S), 0)
    sh.paste(squircle(a), (off, off + int(S * 0.012)))
    sh = sh.filter(ImageFilter.GaussianBlur(S * 0.012)).point(lambda p: int(p * 0.40))
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 255))
    shadow.putalpha(sh)
    canvas = Image.alpha_composite(canvas, shadow)
    canvas.alpha_composite(art, (off, off))
    return canvas.resize((1024, 1024), Image.LANCZOS)


def main():
    os.makedirs(IOS_DIR, exist_ok=True)
    os.makedirs(MAC_DIR, exist_ok=True)

    make_ios(os.path.join(IOS_DIR, "icon-1024.png"))
    with open(os.path.join(IOS_DIR, "Contents.json"), "w") as f:
        json.dump({"images": [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
                   "info": {"author": "xcode", "version": 1}}, f, indent=2)

    master = make_mac()
    images = []
    for base in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = base * scale
            name = f"icon_{base}x{base}@{scale}x.png"
            master.resize((px, px), Image.LANCZOS).save(os.path.join(MAC_DIR, name))
            images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{base}x{base}"})
    with open(os.path.join(MAC_DIR, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)

    # Vorschau fürs Repo / zur Kontrolle
    master.save(os.path.join(ROOT, "tools", "icon-preview.png"))
    print("Icons geschrieben.")


if __name__ == "__main__":
    main()
