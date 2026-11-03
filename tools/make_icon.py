#!/usr/bin/env python3
"""Erzeugt das App-Icon (iOS 1024 px, macOS-Größen) im Stil der App ("Gate"):
warmes Schwarz, Sucher-Eckmarken, 2.39:1-Rahmenlinie, ein ovales Anamorphot-Bokeh in Tungsten-Bernstein
und ein horizontaler blauer Streak, der durch das Bokeh läuft.

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


def render_art(a):
    """Quadratische Bildfläche a × a, RGB float."""
    yy, xx = np.mgrid[0:a, 0:a].astype(float)
    cx = cy = a / 2
    u = (xx - cx) / a
    v = (yy - cy) / a

    # Hintergrund: sehr leichte Aufhellung zur Mitte
    r = np.sqrt(u * u + v * v) / 0.7
    canvas = BG + (BG_LIFT - BG) * np.clip(1 - r, 0, 1)[..., None] ** 2

    # 2.39:1-Rahmenlinie
    fw, fh = 0.66 * a, 0.66 * a / 2.39
    t = max(1, int(a * 0.005))
    frame = mask_img(a, lambda d: d.rectangle([cx - fw / 2, cy - fh / 2, cx + fw / 2, cy + fh / 2], outline=255, width=t))
    add(canvas, blur(frame, a * 0.0008), HAIR, 1.0)

    # Sucher-Eckmarken
    inset, ln, th = 0.15 * a, 0.075 * a, max(2, int(a * 0.011))

    def marks(d):
        for sx in (0, 1):
            for sy in (0, 1):
                x = inset if sx == 0 else a - inset
                y = inset if sy == 0 else a - inset
                dx = ln if sx == 0 else -ln
                dy = ln if sy == 0 else -ln
                d.rectangle([min(x, x + dx), y - th / 2, max(x, x + dx), y + th / 2], fill=255)
                d.rectangle([x - th / 2, min(y, y + dy), x + th / 2, max(y, y + dy)], fill=255)

    add(canvas, blur(mask_img(a, marks), a * 0.0008), DIM, 0.85)

    # Zwei kleine, blasse Bokeh-Ovale als Tiefenhinweis
    for (ox, oy, s, al) in [(-0.26, 0.085, 0.5, 0.30), (0.27, -0.075, 0.38, 0.22)]:
        rx, ry = 0.17 * a * s, 0.17 * a * s / 1.7
        m = mask_img(a, lambda d, ox=ox, oy=oy, rx=rx, ry=ry: d.ellipse(
            [cx + ox * a - rx, cy + oy * a - ry, cx + ox * a + rx, cy + oy * a + ry], fill=255))
        add(canvas, blur(m, a * 0.002), AMBER, al)

    # Großes ovales Bokeh mit hellem Rand und heißem Kern
    rx, ry = 0.175 * a, 0.175 * a / 1.7
    oval = mask_img(a, lambda d: d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=255))
    om = blur(oval, a * 0.002)
    dn = np.sqrt((u * a / rx) ** 2 + (v * a / ry) ** 2)
    fill = CORE[None, None, :] * 0 + (CORE + (AMBER - CORE) * np.clip(dn, 0, 1)[..., None] ** 1.3)
    rim = np.exp(-((dn - 0.93) / 0.07) ** 2)[..., None] * 0.35
    body = fill * (0.80 + rim)
    canvas = canvas * (1 - om[..., None]) + body * om[..., None]
    add(canvas, blur(oval, a * 0.035), AMBER, 0.55)

    # Horizontaler Streak, läuft durch das Bokeh
    sy = a * 0.0055

    def line(d):
        d.rectangle([a * 0.05, cy - sy, a * 0.95, cy + sy], fill=255)

    fade = np.clip(1 - np.abs(u * 2 / 0.9) ** 3, 0, 1)
    core = blur(mask_img(a, line), a * 0.0012) * fade
    add(canvas, core, BLUE * 0.6 + 255 * 0.4, 1.0)
    add(canvas, blur(mask_img(a, line), a * 0.012) * fade, BLUE, 0.9)
    add(canvas, blur(mask_img(a, line), a * 0.04) * fade, BLUE, 0.45)

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
