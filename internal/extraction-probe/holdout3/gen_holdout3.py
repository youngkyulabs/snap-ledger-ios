#!/usr/bin/env python3
"""Renders the third held-out corpus (phone screenshots and receipt photos) and its truth.json.

Usage: python3 gen_holdout3.py <out_dir>

Output is deterministic: every case draws from its own seeded random.Random.
"""

import json
import math
import os
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

FONT_PATH = "/System/Library/Fonts/AppleSDGothicNeo.ttc"
FACE = {"r": 0, "m": 2, "sb": 4, "b": 6}
W, H = 1179, 2556

BLACK, WHITE = (0, 0, 0), (255, 255, 255)

_fonts = {}


def F(size, weight="r"):
    key = (size, weight)
    if key not in _fonts:
        _fonts[key] = ImageFont.truetype(FONT_PATH, size, index=FACE[weight])
    return _fonts[key]


def E(m, a, d, i=None):
    return {"m": m, "i": i, "a": a, "d": d}


# ---------------------------------------------------------------- basics

def tw(s, f):
    return f.getlength(s)


def wrap(s, f, max_w):
    out = []
    for para in s.split("\n"):
        if para == "":
            out.append("")
            continue
        cur = ""
        for word in para.split(" "):
            cand = word if cur == "" else cur + " " + word
            if tw(cand, f) <= max_w:
                cur = cand
                continue
            if cur:
                out.append(cur)
                cur = ""
            while tw(word, f) > max_w:
                k = len(word)
                while k > 1 and tw(word[:k], f) > max_w:
                    k -= 1
                out.append(word[:k])
                word = word[k:]
            cur = word
        out.append(cur)
    return out


def text(d, xy, s, size, weight="r", fill=BLACK, anchor="la"):
    d.text(xy, s, font=F(size, weight), fill=fill, anchor=anchor)


def para(d, x, y, s, size, weight, fill, max_w, lh):
    for line in wrap(s, F(size, weight), max_w):
        text(d, (x, y), line, size, weight, fill)
        y += lh
    return y


def mix(a, b, t):
    return tuple(int(round(a[k] + (b[k] - a[k]) * t)) for k in range(3))


def vgradient(size, top, bottom):
    mask = Image.linear_gradient("L").resize(size)
    return Image.composite(Image.new("RGB", size, bottom), Image.new("RGB", size, top), mask)


def rounded_mask(size, radius, ss=3):
    w, h = size
    m = Image.new("L", (w * ss, h * ss), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, w * ss - 1, h * ss - 1), radius=radius * ss, fill=255)
    return m.resize((w, h), Image.LANCZOS)


def rrect(img, box, radius, fill):
    x0, y0, x1, y1 = [int(round(v)) for v in box]
    img.paste(fill, (x0, y0), rounded_mask((x1 - x0, y1 - y0), radius))


def shadow(img, box, radius, strength=60, blur=30, dy=12):
    x0, y0, x1, y1 = [int(round(v)) for v in box]
    pad = blur * 3
    m = Image.new("L", (x1 - x0 + pad * 2, y1 - y0 + pad * 2), 0)
    ImageDraw.Draw(m).rounded_rectangle((pad, pad + dy, pad + x1 - x0, pad + dy + y1 - y0), radius=radius, fill=strength)
    m = m.filter(ImageFilter.GaussianBlur(blur))
    img.paste(BLACK, (x0 - pad, y0 - pad), m)


def material(img, box, radius, tint, alpha, blur=34, drop=True):
    x0, y0, x1, y1 = [int(round(v)) for v in box]
    if drop:
        shadow(img, (x0, y0, x1, y1), radius, strength=45, blur=26, dy=10)
    region = img.crop((x0, y0, x1, y1)).filter(ImageFilter.GaussianBlur(blur))
    region = Image.blend(region, Image.new("RGB", region.size, tint), alpha)
    img.paste(region, (x0, y0), rounded_mask(region.size, radius))


def shadow_text(img, xy, s, size, weight, fill, anchor="ma", strength=120):
    f = F(size, weight)
    m = Image.new("L", img.size, 0)
    ImageDraw.Draw(m).text((xy[0], xy[1] + 2), s, font=f, fill=strength, anchor=anchor)
    m = m.filter(ImageFilter.GaussianBlur(3))
    img.paste(BLACK, (0, 0), m)
    ImageDraw.Draw(img).text(xy, s, font=f, fill=fill, anchor=anchor)


def chevron(d, x, y, size, color, width=7, direction="left"):
    s = size
    if direction == "left":
        pts = [(x + s * 0.5, y - s), (x - s * 0.5, y), (x + s * 0.5, y + s)]
    elif direction == "right":
        pts = [(x - s * 0.5, y - s), (x + s * 0.5, y), (x - s * 0.5, y + s)]
    else:
        pts = [(x - s, y - s * 0.5), (x, y + s * 0.5), (x + s, y - s * 0.5)]
    d.line(pts, fill=color, width=width, joint="curve")


def magnifier(d, x, y, r, color, width=6):
    d.ellipse((x - r, y - r, x + r, y + r), outline=color, width=width)
    d.line((x + r * 0.7, y + r * 0.7, x + r * 1.5, y + r * 1.5), fill=color, width=width + 1)


def hamburger(d, x, y, w, color, width=6, gap=18):
    for k in (-1, 0, 1):
        d.line((x - w / 2, y + k * gap, x + w / 2, y + k * gap), fill=color, width=width)


def close_x(d, x, y, r, color, width=6):
    d.line((x - r, y - r, x + r, y + r), fill=color, width=width)
    d.line((x - r, y + r, x + r, y - r), fill=color, width=width)


def bell(d, x, y, color):
    d.pieslice((x - 24, y - 28, x + 24, y + 24), 180, 360, fill=color)
    d.rectangle((x - 24, y - 2, x + 24, y + 14), fill=color)
    d.ellipse((x - 7, y + 14, x + 7, y + 28), fill=color)


def check_mark(d, cx, cy, r, color, width):
    d.line([(cx - r * 0.45, cy + r * 0.02), (cx - r * 0.1, cy + r * 0.35), (cx + r * 0.48, cy - r * 0.3)], fill=color, width=width, joint="curve")


def status_bar(img, time_str, fg, battery=80, pct=False):
    d = ImageDraw.Draw(img)
    text(d, (176, 90), time_str, 51, "sb", fg, "mm")
    d.rounded_rectangle((400, 33, 778, 144), radius=56, fill=BLACK)
    x0, base = 852, 106
    for k in range(4):
        h = 13 + k * 7
        d.rounded_rectangle((x0 + k * 15, base - h, x0 + k * 15 + 10, base), radius=3, fill=fg)
    cx, cy = 968, 110
    for r in (40, 27):
        d.arc((cx - r, cy - r, cx + r, cy + r), 225, 315, fill=fg, width=8)
    d.pieslice((cx - 15, cy - 15, cx + 15, cy + 15), 225, 315, fill=fg)
    bx, by = 1018, 72
    dim = mix(fg, (128, 128, 128), 0.45)
    d.rounded_rectangle((bx, by, bx + 80, by + 38), radius=12, outline=dim, width=3)
    fw = int(70 * battery / 100)
    d.rounded_rectangle((bx + 5, by + 5, bx + 5 + fw, by + 33), radius=8, fill=fg)
    d.rounded_rectangle((bx + 84, by + 12, bx + 89, by + 26), radius=2, fill=dim)
    if pct:
        inv = BLACK if sum(fg) > 380 else WHITE
        text(d, (bx + 40, by + 19), str(battery), 27, "b", inv, "mm")


def home_indicator(img, color):
    ImageDraw.Draw(img).rounded_rectangle((W // 2 - 201, H - 39, W // 2 + 201, H - 24), radius=8, fill=color)


def wallpaper(rng, top, bottom, blobs):
    sw, sh = W // 8, H // 8
    layer = vgradient((sw, sh), top, bottom)
    d = ImageDraw.Draw(layer)
    for color in blobs:
        cx, cy = rng.uniform(0, sw), rng.uniform(0, sh)
        r = rng.uniform(sw * 0.35, sw * 0.65)
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=color)
    layer = layer.filter(ImageFilter.GaussianBlur(sw * 0.14))
    return layer.resize((W, H), Image.BICUBIC)


def blank(color):
    return Image.new("RGB", (W, H), color)


# ---------------------------------------------------------------- icons

_icons = {}


def _glyph(d, s, label, fg, ratio=0.36, weight="b", dy=0.0):
    d.text((s / 2, s / 2 + s * dy), label, font=F(max(8, int(s * ratio)), weight), fill=fg, anchor="mm")


def icon(kind, size):
    key = (kind, size)
    if key in _icons:
        return _icons[key]
    s = size * 3
    im = Image.new("RGB", (s, s), WHITE)
    d = ImageDraw.Draw(im)

    def bg(top, bottom=None):
        im.paste(vgradient((s, s), top, bottom or top), (0, 0))

    if kind == "messages":
        bg((110, 230, 110), (30, 190, 60))
        d.ellipse((s * 0.17, s * 0.22, s * 0.83, s * 0.72), fill=WHITE)
        d.polygon([(s * 0.28, s * 0.62), (s * 0.22, s * 0.8), (s * 0.42, s * 0.68)], fill=WHITE)
    elif kind == "kakaotalk":
        bg((254, 229, 0))
        d.ellipse((s * 0.16, s * 0.2, s * 0.84, s * 0.72), fill=(59, 30, 30))
        d.polygon([(s * 0.3, s * 0.64), (s * 0.26, s * 0.8), (s * 0.44, s * 0.69)], fill=(59, 30, 30))
        _glyph(d, s, "TALK", (254, 229, 0), 0.15, "b", -0.04)
    elif kind == "kakaopay":
        bg((255, 235, 0))
        _glyph(d, s, "pay", (25, 25, 25), 0.34, "b", -0.03)
    elif kind == "naverpay":
        bg((3, 199, 90))
        _glyph(d, s, "N", WHITE, 0.36, "b", -0.12)
        _glyph(d, s, "pay", WHITE, 0.2, "b", 0.2)
    elif kind == "naver":
        bg((3, 199, 90))
        _glyph(d, s, "N", WHITE, 0.5, "b")
    elif kind == "toss":
        bg((0, 100, 255), (0, 80, 230))
        _glyph(d, s, "toss", WHITE, 0.3, "b", -0.02)
    elif kind == "shinhan":
        bg((0, 70, 255), (0, 50, 200))
        _glyph(d, s, "SOL", WHITE, 0.3, "b")
    elif kind == "kbcard":
        bg((255, 196, 0))
        _glyph(d, s, "KB", (70, 60, 50), 0.34, "b", -0.08)
        _glyph(d, s, "Pay", (70, 60, 50), 0.2, "b", 0.2)
    elif kind == "kbbank":
        bg((255, 204, 0))
        _glyph(d, s, "KB", (70, 60, 50), 0.36, "b")
    elif kind == "hyundai":
        bg((30, 30, 30), (10, 10, 10))
        _glyph(d, s, "H", WHITE, 0.46, "b")
    elif kind == "hana":
        bg((0, 146, 129))
        _glyph(d, s, "하나", WHITE, 0.27, "b")
    elif kind == "haneul":
        bg((40, 170, 220), (20, 120, 200))
        _glyph(d, s, "하늘", WHITE, 0.27, "b")
    elif kind == "kakaobank":
        bg((255, 228, 0))
        d.rounded_rectangle((s * 0.3, s * 0.24, s * 0.7, s * 0.76), radius=s * 0.08, fill=(60, 40, 30))
        _glyph(d, s, "B", (255, 228, 0), 0.3, "b")
    elif kind == "coupang":
        bg(WHITE)
        _glyph(d, s, "C", (220, 50, 40), 0.5, "b")
    elif kind == "baemin":
        bg((42, 193, 188))
        _glyph(d, s, "배민", WHITE, 0.28, "b")
    elif kind == "carrot":
        bg((255, 126, 54))
        d.ellipse((s * 0.3, s * 0.3, s * 0.7, s * 0.7), fill=WHITE)
    elif kind == "kakaot":
        bg((255, 214, 0))
        _glyph(d, s, "T", (20, 20, 20), 0.5, "b")
    elif kind == "melon":
        bg((0, 205, 60))
        d.ellipse((s * 0.26, s * 0.26, s * 0.74, s * 0.74), outline=WHITE, width=int(s * 0.07))
    elif kind == "youtube":
        bg(WHITE)
        d.rounded_rectangle((s * 0.18, s * 0.3, s * 0.82, s * 0.7), radius=s * 0.1, fill=(255, 0, 0))
        d.polygon([(s * 0.44, s * 0.4), (s * 0.44, s * 0.6), (s * 0.6, s * 0.5)], fill=WHITE)
    elif kind == "instagram":
        bg((150, 60, 200), (250, 150, 50))
        d.rounded_rectangle((s * 0.22, s * 0.22, s * 0.78, s * 0.78), radius=s * 0.16, outline=WHITE, width=int(s * 0.06))
        d.ellipse((s * 0.37, s * 0.37, s * 0.63, s * 0.63), outline=WHITE, width=int(s * 0.06))
    elif kind == "phone":
        bg((110, 230, 110), (30, 190, 60))
        d.arc((s * 0.24, s * 0.24, s * 0.76, s * 0.76), 100, 260, fill=WHITE, width=int(s * 0.12))
    elif kind == "safari":
        bg(WHITE, (225, 235, 245))
        d.ellipse((s * 0.12, s * 0.12, s * 0.88, s * 0.88), fill=(30, 140, 255))
        d.polygon([(s * 0.62, s * 0.38), (s * 0.45, s * 0.45), (s * 0.55, s * 0.55)], fill=(255, 60, 50))
        d.polygon([(s * 0.38, s * 0.62), (s * 0.45, s * 0.45), (s * 0.55, s * 0.55)], fill=WHITE)
    elif kind == "music":
        bg((255, 90, 110), (250, 40, 70))
        d.ellipse((s * 0.28, s * 0.58, s * 0.46, s * 0.74), fill=WHITE)
        d.rectangle((s * 0.41, s * 0.26, s * 0.46, s * 0.66), fill=WHITE)
        d.polygon([(s * 0.41, s * 0.26), (s * 0.7, s * 0.2), (s * 0.7, s * 0.3), (s * 0.46, s * 0.36)], fill=WHITE)
    elif kind == "mail":
        bg((60, 170, 255), (20, 110, 240))
        d.rectangle((s * 0.2, s * 0.3, s * 0.8, s * 0.7), fill=WHITE)
        d.line([(s * 0.2, s * 0.3), (s * 0.5, s * 0.52), (s * 0.8, s * 0.3)], fill=(40, 140, 250), width=int(s * 0.03))
    elif kind == "photos":
        bg(WHITE)
        cols = [(255, 160, 0), (255, 210, 0), (140, 200, 60), (50, 180, 140), (50, 140, 230), (120, 90, 220), (220, 70, 160), (250, 80, 70)]
        for k, c in enumerate(cols):
            a = k * math.pi / 4
            cx, cy = s / 2 + math.cos(a) * s * 0.17, s / 2 + math.sin(a) * s * 0.17
            d.ellipse((cx - s * 0.13, cy - s * 0.13, cx + s * 0.13, cy + s * 0.13), fill=c)
    elif kind == "camera":
        bg((210, 210, 215), (150, 150, 158))
        d.rounded_rectangle((s * 0.18, s * 0.32, s * 0.82, s * 0.74), radius=s * 0.06, fill=(40, 40, 44))
        d.ellipse((s * 0.37, s * 0.39, s * 0.63, s * 0.65), fill=(120, 120, 130))
    elif kind == "weather":
        bg((70, 150, 240), (40, 100, 220))
        d.ellipse((s * 0.22, s * 0.2, s * 0.52, s * 0.5), fill=(255, 210, 40))
        d.ellipse((s * 0.3, s * 0.45, s * 0.6, s * 0.72), fill=WHITE)
        d.ellipse((s * 0.45, s * 0.38, s * 0.8, s * 0.72), fill=WHITE)
    elif kind == "notes":
        bg(WHITE)
        d.rectangle((0, 0, s, s * 0.24), fill=(255, 205, 50))
        for k in range(4):
            y = s * (0.4 + k * 0.12)
            d.line((s * 0.14, y, s * 0.86, y), fill=(210, 210, 210), width=int(s * 0.015))
    elif kind == "settings":
        bg((160, 160, 168), (110, 110, 118))
        c = s / 2
        for k in range(12):
            a = k * math.pi / 6
            d.line((c + math.cos(a) * s * 0.18, c + math.sin(a) * s * 0.18, c + math.cos(a) * s * 0.36, c + math.sin(a) * s * 0.36), fill=(60, 60, 66), width=int(s * 0.08))
        d.ellipse((c - s * 0.27, c - s * 0.27, c + s * 0.27, c + s * 0.27), fill=(60, 60, 66))
        d.ellipse((c - s * 0.12, c - s * 0.12, c + s * 0.12, c + s * 0.12), fill=(150, 150, 158))
    elif kind == "clock":
        bg((20, 20, 20))
        d.ellipse((s * 0.12, s * 0.12, s * 0.88, s * 0.88), fill=WHITE)
        d.line((s / 2, s / 2, s / 2, s * 0.25), fill=BLACK, width=int(s * 0.03))
        d.line((s / 2, s / 2, s * 0.68, s * 0.58), fill=BLACK, width=int(s * 0.03))
    elif kind == "maps":
        bg((230, 240, 220), (200, 225, 200))
        d.line((0, s * 0.7, s, s * 0.3), fill=WHITE, width=int(s * 0.1))
        d.line((0, s * 0.7, s, s * 0.3), fill=(70, 140, 250), width=int(s * 0.04))
        d.ellipse((s * 0.42, s * 0.2, s * 0.62, s * 0.4), fill=(240, 60, 50))
    elif kind == "files":
        bg(WHITE)
        d.rounded_rectangle((s * 0.18, s * 0.28, s * 0.82, s * 0.74), radius=s * 0.05, fill=(40, 130, 250))
    elif kind == "wallet":
        bg((20, 20, 20))
        for k, c in enumerate([(60, 160, 240), (250, 190, 40), (90, 200, 90), (240, 90, 70)]):
            d.rounded_rectangle((s * 0.18, s * (0.24 + k * 0.08), s * 0.82, s * (0.46 + k * 0.08)), radius=s * 0.04, fill=c)
    elif kind == "subway":
        bg((40, 180, 100))
        _glyph(d, s, "M", WHITE, 0.42, "b")
    else:
        raise ValueError(kind)

    out = im.resize((size, size), Image.LANCZOS).convert("RGBA")
    out.putalpha(rounded_mask((size, size), int(size * 0.225)))
    _icons[key] = out
    return out


def calendar_icon(size, weekday, day):
    s = size * 3
    im = Image.new("RGB", (s, s), WHITE)
    d = ImageDraw.Draw(im)
    d.text((s / 2, s * 0.22), weekday, font=F(int(s * 0.17), "sb"), fill=(255, 59, 48), anchor="mm")
    d.text((s / 2, s * 0.6), str(day), font=F(int(s * 0.5), "r"), fill=BLACK, anchor="mm")
    out = im.resize((size, size), Image.LANCZOS).convert("RGBA")
    out.putalpha(rounded_mask((size, size), int(size * 0.225)))
    return out


def paste_icon(img, ic, x, y):
    img.paste(ic, (int(x), int(y)), ic)


# ---------------------------------------------------------------- notifications

B_PAD_X, B_PAD_Y, B_ICON, B_LH = 42, 38, 114, 59


def banner_lines(body, w):
    tmax = w - 2 * B_PAD_X - B_ICON - 34
    return wrap(body, F(45, "r"), tmax), tmax


def banner_height(body, w=1113):
    lines, _ = banner_lines(body, w)
    return B_PAD_Y + 60 + B_LH * len(lines) + B_PAD_Y - 8


def banner(img, y, icon_kind, title, when, body, dark, x=33, w=1113):
    lines, tmax = banner_lines(body, w)
    if len(lines) > 4:
        raise ValueError("banner body over 4 lines: %r" % (lines,))
    if tw(title, F(45, "sb")) + tw(when, F(39, "r")) + 30 > tmax:
        raise ValueError("banner title too long: %r" % title)
    h = banner_height(body, w)
    tint, alpha = ((250, 250, 250), 0.8) if not dark else ((38, 38, 40), 0.82)
    material(img, (x, y, x + w, y + h), 68, tint, alpha)
    paste_icon(img, icon(icon_kind, B_ICON), x + B_PAD_X, y + (h - B_ICON) // 2)
    d = ImageDraw.Draw(img)
    fg = BLACK if not dark else WHITE
    sub = (108, 108, 114) if not dark else (170, 170, 176)
    tx = x + B_PAD_X + B_ICON + 34
    text(d, (tx, y + B_PAD_Y), title, 45, "sb", fg)
    text(d, (x + w - B_PAD_X, y + B_PAD_Y + 4), when, 39, "r", sub, "ra")
    for k, line in enumerate(lines):
        text(d, (tx, y + B_PAD_Y + 60 + k * B_LH), line, 45, "r", fg)
    return y + h


def banners(img, specs, dark, y=168, gap=22):
    for spec in specs:
        y = banner(img, y, *spec[:4], dark=dark) + gap
    return y


def lock_notifications(img, specs, dark, bottom=2200, gap=22):
    x, w = 48, 1083
    hs = [banner_height(s[3], w) for s in specs]
    y = bottom - sum(hs) - gap * (len(specs) - 1)
    for s, h in zip(specs, hs):
        banner(img, y, *s[:4], dark=dark, x=x, w=w)
        y += h + gap


# ---------------------------------------------------------------- home and lock screens

COLS = (81, 358, 635, 912)
ISZ = 186
ROW0 = 222
PITCH = 300


def widget_box(col, row, span_c, span_r=2):
    x0 = COLS[col]
    y0 = ROW0 + row * PITCH
    return x0, y0, COLS[col + span_c - 1] + ISZ, y0 + (span_r - 1) * PITCH + ISZ - 20


def widget_label(img, box, label):
    shadow_text(img, ((box[0] + box[2]) / 2, box[3] + 14), label, 36, "m", WHITE)


def widget_bg(img, box, dark):
    shadow(img, box, 66, strength=40, blur=20, dy=6)
    rrect(img, box, 66, WHITE if not dark else (28, 28, 30))


def w_weather(img, box, dark, city, temp, cond, hi, lo):
    x0, y0, x1, y1 = box
    top, bottom = ((60, 140, 230), (30, 90, 200)) if not dark else ((34, 52, 96), (12, 20, 48))
    grad = vgradient((x1 - x0, y1 - y0), top, bottom)
    shadow(img, box, 66, strength=40, blur=20, dy=6)
    img.paste(grad, (x0, y0), rounded_mask(grad.size, 66))
    d = ImageDraw.Draw(img)
    text(d, (x0 + 48, y0 + 44), city, 45, "sb", WHITE)
    text(d, (x0 + 44, y0 + 104), temp, 132, "r", WHITE)
    d.ellipse((x0 + 48, y1 - 190, x0 + 98, y1 - 140), fill=(255, 210, 40))
    text(d, (x0 + 48, y1 - 128), cond, 39, "sb", WHITE)
    text(d, (x0 + 48, y1 - 76), "최고:%s 최저:%s" % (hi, lo), 39, "sb", WHITE)


def w_calendar(img, box, dark, weekday, day, events):
    widget_bg(img, box, dark)
    x0, y0, x1, y1 = box
    d = ImageDraw.Draw(img)
    fg = BLACK if not dark else WHITE
    text(d, (x0 + 48, y0 + 44), weekday, 42, "sb", (255, 59, 48))
    text(d, (x0 + 44, y0 + 92), str(day), 120, "r", fg)
    y = y0 + 250
    for title, when, color in events:
        d.rounded_rectangle((x0 + 48, y + 4, x0 + 58, y + 92), radius=5, fill=color)
        text(d, (x0 + 78, y), title, 39, "sb", fg)
        text(d, (x0 + 78, y + 50), when, 36, "r", (130, 130, 136))
        y += 112


def w_battery(img, box, dark, items):
    widget_bg(img, box, dark)
    x0, y0, x1, y1 = box
    d = ImageDraw.Draw(img)
    fg = BLACK if not dark else WHITE
    cw = (x1 - x0 - 60) / len(items)
    for k, (label, pct) in enumerate(items):
        cx, cy = x0 + 30 + cw * k + cw / 2, y0 + 170
        r = min(cw / 2 - 14, 100)
        d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=(80, 80, 84) if dark else (220, 220, 224), width=16)
        d.arc((cx - r, cy - r, cx + r, cy + r), -90, -90 + 360 * pct / 100, fill=(52, 199, 89), width=16)
        text(d, (cx, cy), label, 33, "sb", fg, "mm")
        text(d, (cx, y1 - 110), "%d%%" % pct, 51, "sb", fg, "mm")


def w_steps(img, box, dark, steps, km, floors):
    widget_bg(img, box, dark)
    x0, y0, x1, y1 = box
    d = ImageDraw.Draw(img)
    fg = BLACK if not dark else WHITE
    sub = (130, 130, 136) if not dark else (160, 160, 166)
    text(d, (x0 + 48, y0 + 44), "걸음 수", 42, "sb", (255, 69, 58))
    text(d, (x0 + 46, y0 + 104), steps, 102, "sb", fg)
    text(d, (x0 + 48, y0 + 236), "걸음", 39, "r", sub)
    text(d, (x0 + 48, y1 - 140), "거리 %s" % km, 39, "sb", fg)
    text(d, (x0 + 48, y1 - 84), "오른 층 %s" % floors, 39, "sb", fg)


def w_stocks(img, box, dark, rows):
    widget_bg(img, box, dark)
    x0, y0, x1, y1 = box
    d = ImageDraw.Draw(img)
    fg = BLACK if not dark else WHITE
    sub = (130, 130, 136) if not dark else (160, 160, 166)
    text(d, (x0 + 48, y0 + 36), "주식", 42, "b", fg)
    y = y0 + 110
    for name, desc, val, chg in rows:
        text(d, (x0 + 48, y), name, 42, "b", fg)
        text(d, (x0 + 48, y + 50), desc, 33, "r", sub)
        text(d, (x1 - 300, y + 4), val, 42, "sb", fg, "ra")
        col = (52, 199, 89) if chg.startswith("+") else (255, 69, 58)
        d.rounded_rectangle((x1 - 270, y - 2, x1 - 48, y + 62), radius=14, fill=col)
        text(d, (x1 - 159, y + 30), chg, 36, "sb", WHITE, "mm")
        y += 112


def w_screentime(img, box, dark, total, apps):
    widget_bg(img, box, dark)
    x0, y0, x1, y1 = box
    d = ImageDraw.Draw(img)
    fg = BLACK if not dark else WHITE
    sub = (130, 130, 136) if not dark else (160, 160, 166)
    text(d, (x0 + 48, y0 + 44), "스크린 타임", 39, "sb", (100, 100, 235))
    text(d, (x0 + 48, y0 + 100), total, 66, "sb", fg)
    y = y0 + 210
    for name, t in apps:
        text(d, (x0 + 48, y), name, 36, "r", fg)
        text(d, (x1 - 48, y), t, 36, "r", sub, "ra")
        y += 64


def home_screen(img, dark, apps, dock):
    d = ImageDraw.Draw(img)
    for (col, row), spec in apps.items():
        kind, label = spec[0], spec[1]
        badge = spec[2] if len(spec) > 2 else None
        x, y = COLS[col], ROW0 + row * PITCH
        ic = kind if isinstance(kind, Image.Image) else icon(kind, ISZ)
        shadow(img, (x, y, x + ISZ, y + ISZ), 42, strength=30, blur=10, dy=4)
        paste_icon(img, ic, x, y)
        shadow_text(img, (x + ISZ / 2, y + ISZ + 16), label, 36, "m", WHITE)
        if badge:
            bx, by = x + ISZ - 18, y + 12
            bw = max(66, tw(str(badge), F(39, "sb")) + 36)
            d.rounded_rectangle((bx - bw / 2, by - 33, bx + bw / 2, by + 33), radius=33, fill=(255, 59, 48))
            text(d, (bx, by), str(badge), 39, "sb", WHITE, "mm")
    tint, alpha = ((255, 255, 255), 0.32) if not dark else ((60, 60, 64), 0.5)
    material(img, (482, 2112, 697, 2184), 36, tint, alpha, drop=False)
    magnifier(d, 530, 2144, 13, WHITE, 5)
    text(d, (560, 2148), "검색", 36, "sb", WHITE, "lm")
    material(img, (30, 2226, 1149, 2496), 110, tint, alpha, drop=False)
    for col, spec in enumerate(dock):
        kind = spec[0] if isinstance(spec, tuple) else spec
        ic = kind if isinstance(kind, Image.Image) else icon(kind, ISZ)
        paste_icon(img, ic, COLS[col], 2268)
        if isinstance(spec, tuple):
            bx, by = COLS[col] + ISZ - 18, 2280
            d.ellipse((bx - 33, by - 33, bx + 33, by + 33), fill=(255, 59, 48))
            text(d, (bx, by), str(spec[1]), 39, "sb", WHITE, "mm")


def lock_screen(img, fg, date_str, time_str, widgets, dark):
    d = ImageDraw.Draw(img)
    text(d, (W // 2, 262), date_str, 60, "sb", fg, "mm")
    text(d, (W // 2, 455), time_str, 290, "sb", fg, "mm")
    n = len(widgets)
    if n:
        cw = 222
        x = W // 2 - (n * cw + (n - 1) * 30) // 2
        tint, alpha = ((255, 255, 255), 0.35) if not dark else ((20, 20, 24), 0.4)
        for top, bottom in widgets:
            material(img, (x, 640, x + cw, 862), 111, tint, alpha, drop=False)
            text(d, (x + cw // 2, 722), top, 54, "sb", fg, "mm")
            text(d, (x + cw // 2, 800), bottom, 33, "sb", fg, "mm")
            x += cw + 30
    tint, alpha = ((255, 255, 255), 0.35) if not dark else ((20, 20, 24), 0.45)
    for cx in (156, W - 156):
        material(img, (cx - 75, 2268, cx + 75, 2418), 75, tint, alpha, drop=False)
    d.rounded_rectangle((136, 2310, 176, 2378), radius=10, outline=fg, width=6)
    d.rounded_rectangle((W - 196, 2318, W - 116, 2372), radius=10, outline=fg, width=6)
    d.ellipse((W - 170, 2330, W - 142, 2358), outline=fg, width=5)
    home_indicator(img, fg)


LIGHT_APPS = [("kakaotalk", "카카오톡"), ("toss", "토스"), ("naver", "네이버"), ("coupang", "쿠팡"),
              ("photos", "사진"), ("camera", "카메라"), ("calendar", "캘린더"), ("weather", "날씨"),
              ("baemin", "배달의민족"), ("youtube", "YouTube"), ("instagram", "Instagram"), ("maps", "지도"),
              ("notes", "메모"), ("settings", "설정"), ("clock", "시계"), ("shinhan", "신한 SOL")]
DARK_APPS = [("kakaotalk", "카카오톡"), ("toss", "토스"), ("carrot", "당근"), ("baemin", "배달의민족"),
             ("photos", "사진"), ("camera", "카메라"), ("calendar", "캘린더"), ("wallet", "지갑"),
             ("naver", "네이버"), ("coupang", "쿠팡"), ("youtube", "YouTube"), ("melon", "멜론"),
             ("notes", "메모"), ("settings", "설정"), ("subway", "지하철"), ("kakaot", "카카오 T")]


def app_grid(base, badges, calendar=None, swap=None, rows=(2, 3, 4, 5)):
    apps = {}
    for k, (kind, label) in enumerate(base):
        if swap and kind in swap:
            kind, label = swap[kind]
        if kind == "calendar":
            if calendar is None:
                continue
            kind = calendar_icon(ISZ, *calendar)
        spec = (kind, label, badges[label]) if label in badges else (kind, label)
        apps[(k % 4, rows[k // 4])] = spec
    return apps


# ---------------------------------------------------------------- KakaoTalk

def kakao_palette(dark):
    if not dark:
        return dict(bg=(186, 206, 224), fg=BLACK, name=(70, 80, 92), time=(86, 98, 112), other=WHITE, other_fg=BLACK,
                    pill=(160, 180, 200), pill_fg=WHITE, bar=WHITE, field=(242, 242, 244), icon=(90, 90, 96),
                    prof=[(160, 196, 226), (240, 190, 160), (190, 220, 170), (210, 190, 236)])
    return dict(bg=(34, 34, 36), fg=WHITE, name=(180, 180, 186), time=(140, 140, 146), other=(62, 62, 66), other_fg=WHITE,
                pill=(56, 56, 60), pill_fg=(200, 200, 206), bar=(26, 26, 28), field=(48, 48, 52), icon=(170, 170, 176),
                prof=[(90, 120, 160), (150, 110, 90), (100, 140, 100), (130, 110, 160)])


def profile_pic(img, x, y, color, size=117):
    d = ImageDraw.Draw(img)
    rrect(img, (x, y, x + size, y + size), int(size * 0.4), color)
    d.ellipse((x + size * 0.34, y + size * 0.2, x + size * 0.66, y + size * 0.52), fill=WHITE)
    d.pieslice((x + size * 0.18, y + size * 0.56, x + size * 0.82, y + size * 1.2), 180, 360, fill=WHITE)


def kakao_chat(img, dark, room, count, unread, items):
    """items: ("date", s) | ("other", who, [msgs], time) | ("me", [msgs], time, mark) | ("card", who, header, body, button, time)"""
    p = kakao_palette(dark)
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, W, H), fill=p["bg"])
    fg = p["fg"]
    bar_top = H - 236
    fb = F(45, "r")
    maxw = 650
    profiles = {}
    blocks = []
    prev = None
    for it in items:
        if it[0] == "date":
            blocks.append(("date", it[1], 120))
            prev = None
        elif it[0] == "other":
            _, who, msgs, when = it
            lines = [wrap(m, fb, maxw) for m in msgs]
            hs = [len(ls) * 60 + 48 for ls in lines]
            head = prev != who
            blocks.append(("other", (who, lines, when, head), (54 if head else 0) + sum(hs) + 14 * (len(hs) - 1) + 30))
            profiles.setdefault(who, p["prof"][len(profiles) % len(p["prof"])])
            prev = who
        elif it[0] == "me":
            _, msgs, when, mark = it
            lines = [wrap(m, fb, maxw) for m in msgs]
            hs = [len(ls) * 60 + 48 for ls in lines]
            blocks.append(("me", (lines, when, mark), sum(hs) + 14 * (len(hs) - 1) + 30))
            prev = "me"
        elif it[0] == "card":
            _, who, header, body, button, when = it
            lines = wrap(body, F(42, "r"), 640)
            hcard = 96 + len(lines) * 58 + 40 + (110 if button else 0)
            blocks.append(("card", (who, header, lines, button, when), 54 + hcard + 30))
            profiles.setdefault(who, (255, 214, 0))
            prev = None
    y = bar_top - 30 - sum(b[2] for b in blocks)
    for kind, data, bh in blocks:
        if kind == "date":
            wpx = tw(data, F(36, "r")) + 80
            d.rounded_rectangle((W / 2 - wpx / 2, y + 30, W / 2 + wpx / 2, y + 90), radius=30, fill=p["pill"])
            text(d, (W / 2, y + 61), data, 36, "r", p["pill_fg"], "mm")
        elif kind == "other":
            who, lines, when, head = data
            yy = y
            if head:
                profile_pic(img, 36, yy, profiles[who])
                text(d, (180, yy), who, 37, "r", p["name"])
                yy += 54
            for k, ls in enumerate(lines):
                bw = max(tw(line, fb) for line in ls) + 66
                bh2 = len(ls) * 60 + 48
                d.rounded_rectangle((180, yy, 180 + bw, yy + bh2), radius=36, fill=p["other"])
                for j, line in enumerate(ls):
                    text(d, (213, yy + 22 + j * 60), line, 45, "r", p["other_fg"])
                if k == len(lines) - 1:
                    text(d, (180 + bw + 14, yy + bh2 - 6), when, 31, "r", p["time"], "ls")
                yy += bh2 + 14
        elif kind == "me":
            lines, when, mark = data
            yy = y
            for k, ls in enumerate(lines):
                bw = max(tw(line, fb) for line in ls) + 66
                bh2 = len(ls) * 60 + 48
                x1 = W - 36
                d.rounded_rectangle((x1 - bw, yy, x1, yy + bh2), radius=36, fill=(254, 229, 0))
                for j, line in enumerate(ls):
                    text(d, (x1 - bw + 33, yy + 22 + j * 60), line, 45, "r", BLACK)
                if k == len(lines) - 1:
                    text(d, (x1 - bw - 14, yy + bh2 - 6), when, 31, "r", p["time"], "rs")
                    if mark:
                        text(d, (x1 - bw - 14, yy + bh2 - 46), mark, 31, "b", (250, 200, 0), "rs")
                yy += bh2 + 14
        elif kind == "card":
            who, header, lines, button, when = data
            profile_pic(img, 36, y, profiles[who])
            text(d, (180, y), who, 37, "r", p["name"])
            cy, cw, ch = y + 54, 720, bh - 54 - 30
            d.rounded_rectangle((180, cy, 180 + cw, cy + ch), radius=36, fill=WHITE if not dark else (62, 62, 66))
            d.rounded_rectangle((180, cy, 180 + cw, cy + 84), radius=36, fill=(254, 229, 0))
            d.rectangle((180, cy + 50, 180 + cw, cy + 84), fill=(254, 229, 0))
            text(d, (216, cy + 42), header, 39, "b", (40, 30, 20), "lm")
            for j, line in enumerate(lines):
                text(d, (216, cy + 112 + j * 58), line, 42, "r", p["other_fg"])
            if button:
                by = cy + ch - 120
                d.rounded_rectangle((216, by, 180 + cw - 36, by + 84), radius=18, fill=(240, 240, 242) if not dark else (80, 80, 86))
                text(d, (180 + cw / 2, by + 42), button, 39, "r", p["other_fg"], "mm")
            text(d, (180 + cw + 14, cy + ch - 6), when, 31, "r", p["time"], "ls")
        y += bh
    d.rectangle((0, 0, W, 340), fill=p["bg"])
    chevron(d, 62, 252, 26, fg, 7)
    if unread:
        text(d, (96, 252), str(unread), 42, "sb", fg, "lm")
    text(d, (W / 2, 252), room, 51, "b", fg, "mm")
    if count:
        text(d, (W / 2 + tw(room, F(51, "b")) / 2 + 18, 254), str(count), 42, "r", p["name"], "lm")
    magnifier(d, 1000, 244, 22, fg, 6)
    hamburger(d, 1106, 252, 52, fg, 6, 17)
    d.rectangle((0, bar_top, W, H), fill=p["bar"])
    d.line((100, bar_top + 78, 140, bar_top + 78), fill=p["icon"], width=6)
    d.line((120, bar_top + 58, 120, bar_top + 98), fill=p["icon"], width=6)
    d.rounded_rectangle((184, bar_top + 28, 1060, bar_top + 128), radius=50, fill=p["field"])
    d.ellipse((960, bar_top + 52, 1012, bar_top + 104), outline=p["icon"], width=5)
    text(d, (1110, bar_top + 78), "#", 54, "r", p["icon"], "mm")
    home_indicator(img, BLACK if not dark else WHITE)


# ---------------------------------------------------------------- Messages (SMS)

def sms_thread(img, dark, sender, items):
    """items: ("ts", s) | ("in", text)"""
    bg = WHITE if not dark else BLACK
    fg = BLACK if not dark else WHITE
    sub = (138, 138, 142) if not dark else (152, 152, 159)
    bubble = (233, 233, 235) if not dark else (38, 38, 40)
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, W, H), fill=bg)
    fb = F(51, "r")
    blocks = []
    for kind, s in items:
        if kind == "ts":
            blocks.append(("ts", s, 110))
        else:
            lines = wrap(s, fb, 780)
            blocks.append(("in", lines, len(lines) * 66 + 56 + 24))
    bar_top = H - 210
    header_bottom = 460
    y = bar_top - 30 - sum(b[2] for b in blocks)
    if y < header_bottom + 10:
        raise ValueError("SMS thread does not fit: top at %d" % y)
    for kind, data, bh in blocks:
        if kind == "ts":
            text(d, (W / 2, y + 60), data, 36, "m", sub, "mm")
        else:
            bw = max(tw(line, fb) for line in data) + 84
            hh = len(data) * 66 + 56
            d.rounded_rectangle((42, y, 42 + bw, y + hh), radius=54, fill=bubble)
            for j, line in enumerate(data):
                text(d, (84, y + 26 + j * 66), line, 51, "r", fg)
        y += bh
    head = (247, 247, 247) if not dark else (22, 22, 24)
    d.rectangle((0, 0, W, header_bottom), fill=head)
    d.line((0, header_bottom, W, header_bottom), fill=(220, 220, 224) if not dark else (50, 50, 54), width=2)
    blue = (0, 122, 255) if not dark else (10, 132, 255)
    chevron(d, 62, 296, 28, blue, 8)
    cx, cy = W / 2, 282
    av = vgradient((150, 150), (172, 176, 186), (132, 136, 148))
    img.paste(av, (int(cx - 75), int(cy - 75)), rounded_mask((150, 150), 75))
    d.ellipse((cx - 26, cy - 46, cx + 26, cy + 6), fill=WHITE)
    d.pieslice((cx - 50, cy + 14, cx + 50, cy + 104), 180, 360, fill=WHITE)
    text(d, (cx, 405), sender + " >", 36, "m", fg, "mm")
    d.rectangle((0, bar_top, W, H), fill=bg)
    d.ellipse((42, bar_top + 30, 138, bar_top + 126), fill=(233, 233, 235) if not dark else (44, 44, 46))
    d.line((70, bar_top + 78, 110, bar_top + 78), fill=sub, width=6)
    d.line((90, bar_top + 58, 90, bar_top + 98), fill=sub, width=6)
    d.rounded_rectangle((162, bar_top + 30, W - 42, bar_top + 126), radius=48, outline=(200, 200, 204) if not dark else (60, 60, 64), width=3)
    text(d, (204, bar_top + 78), "문자 메시지", 45, "r", sub, "lm")
    home_indicator(img, fg)


# ---------------------------------------------------------------- web pages

def safari_bar(img, dark, domain):
    d = ImageDraw.Draw(img)
    tint, alpha = ((250, 250, 250), 0.88) if not dark else ((44, 44, 46), 0.88)
    material(img, (36, H - 228, W - 36, H - 96), 66, tint, alpha)
    fg = BLACK if not dark else WHITE
    sub = (80, 80, 86) if not dark else (190, 190, 196)
    chevron(d, 116, H - 162, 20, fg, 6)
    text(d, (W / 2 + 10, H - 162), domain, 42, "m", fg, "mm")
    lx = W / 2 + 10 - tw(domain, F(42, "m")) / 2 - 40
    d.rounded_rectangle((lx - 13, H - 168, lx + 13, H - 144), radius=4, fill=sub)
    d.arc((lx - 9, H - 186, lx + 9, H - 158), 180, 360, fill=sub, width=4)
    for k in range(3):
        d.ellipse((W - 150 + k * 24 - 6, H - 168, W - 150 + k * 24 + 6, H - 156), fill=fg)
    home_indicator(img, fg)


# ---------------------------------------------------------------- generic app chrome

def pal(dark):
    if not dark:
        return dict(bg=WHITE, group=(242, 243, 246), card=WHITE, fg=BLACK, sub=(128, 128, 134), sep=(228, 228, 232), fill=(244, 244, 247))
    return dict(bg=(16, 16, 18), group=(16, 16, 18), card=(32, 32, 35), fg=WHITE, sub=(150, 150, 157), sep=(52, 52, 56), fill=(44, 44, 48))


def nav(d, p, title, y=250, right=None, back=True):
    if back:
        chevron(d, 66, y, 24, p["fg"], 7)
    text(d, (W / 2, y), title, 51, "b", p["fg"], "mm")
    if right:
        text(d, (W - 60, y), right, 45, "r", p["fg"], "rm")


def kv(d, p, y, label, value, size=42, bold=False, color=None):
    text(d, (90, y), label, size, "r", p["sub"], "lm")
    text(d, (W - 90, y), value, size, "b" if bold else "m", color or p["fg"], "rm")


def tab_bar(img, p, labels, active=0):
    d = ImageDraw.Draw(img)
    top = H - 250
    d.rectangle((0, top, W, H), fill=p["card"])
    d.line((0, top, W, top), fill=p["sep"], width=2)
    step = W / len(labels)
    for k, label in enumerate(labels):
        cx = step * k + step / 2
        col = p["fg"] if k == active else p["sub"]
        d.rounded_rectangle((cx - 30, top + 36, cx + 30, top + 96), radius=16, fill=col)
        text(d, (cx, top + 132), label, 33, "m", col, "mm")
    home_indicator(img, p["fg"])


# ---------------------------------------------------------------- receipts

PAPER = (247, 245, 238)
INK = (52, 52, 56)


def receipt_paper(rows, width=900):
    margin = 54
    hs = []
    for r in rows:
        if r[0] == "gap":
            hs.append(r[1])
        elif r[0] == "hr":
            hs.append(40)
        else:
            hs.append(int(r[-1] * 1.5))
    paper = Image.new("RGB", (width, sum(hs) + 140), PAPER)
    d = ImageDraw.Draw(paper)
    y = 70
    for r, h in zip(rows, hs):
        kind, mid = r[0], y + h / 2
        if kind == "c":
            text(d, (width / 2, mid), r[1], r[3], r[2], INK, "mm")
        elif kind == "l":
            text(d, (margin, mid), r[1], r[3], r[2], INK, "lm")
        elif kind == "lr":
            text(d, (margin, mid), r[1], r[4], r[3], INK, "lm")
            text(d, (width - margin, mid), r[2], r[4], r[3], INK, "rm")
        elif kind == "item":
            text(d, (margin, mid), r[1], r[4], "r", INK, "lm")
            text(d, (width - 250, mid), r[2], r[4], "r", INK, "rm")
            text(d, (width - margin, mid), r[3], r[4], "r", INK, "rm")
        elif kind == "sub":
            text(d, (margin + 40, mid), r[1], r[3], "r", INK, "lm")
            text(d, (width - margin, mid), r[2], r[3], "r", INK, "rm")
        elif kind == "hr":
            x = margin
            while x < width - margin:
                d.line((x, y + 20, min(x + 14, width - margin), y + 20), fill=INK, width=3)
                x += 24
        y += h
    return paper


def noise(img, rng, amp):
    w, h = img.size[0] // 2, img.size[1] // 2
    n = Image.frombytes("L", (w, h), rng.randbytes(w * h))
    n = n.point(lambda v: 128 + (v - 128) * amp // 128).resize(img.size, Image.BILINEAR)
    return ImageChops.add(img, Image.merge("RGB", (n, n, n)), 1.0, -128)


def table_background(kind, rng, size):
    pw, ph = size
    if kind == "wood":
        sw, sh = pw // 4, ph // 4
        base = vgradient((sw, sh), (150, 104, 68), (122, 82, 52))
        d = ImageDraw.Draw(base)
        for _ in range(170):
            y = rng.uniform(0, sh)
            c = mix((95, 62, 38), (178, 130, 88), rng.random())
            pts = [(sw * k / 8, y + math.sin(k * 0.9 + y) * rng.uniform(0.5, 3)) for k in range(9)]
            d.line(pts, fill=c, width=rng.choice((1, 1, 2)))
        base = base.filter(ImageFilter.GaussianBlur(1.2)).resize(size, Image.BICUBIC)
        return noise(base, rng, 14)
    if kind == "fabric":
        return noise(vgradient((pw, ph), (58, 62, 72), (40, 43, 50)), rng, 26)
    if kind == "desk":
        return noise(vgradient((pw, ph), (222, 220, 212), (196, 192, 182)), rng, 10)
    raise ValueError(kind)


def lighting(size, rng, lo, hi):
    sw, sh = size[0] // 8, size[1] // 8
    cx, cy = rng.uniform(0.2, 0.8), rng.uniform(0.1, 0.45)
    data = []
    for j in range(sh):
        for i in range(sw):
            dist = math.hypot(i / sw - cx, (j / sh - cy) * 0.85)
            data.append(int(hi - (hi - lo) * min(1.0, dist / 0.95)))
    m = Image.new("L", (sw, sh))
    m.putdata(data)
    sx = rng.uniform(0.0, 1.0) * sw
    ImageDraw.Draw(m).ellipse((sx - sw * 0.5, sh * 0.78, sx + sw * 0.6, sh * 1.3), fill=int(lo * 0.85))
    return m.filter(ImageFilter.GaussianBlur(sw * 0.08)).resize(size, Image.BICUBIC)


def receipt_photo(paper, rng, bg_kind, angle, blur, lo=170):
    if not 1 <= abs(angle) <= 4:
        raise ValueError("receipt rotation must be 1-4 degrees")
    pw, ph = 1512, 2016
    photo = table_background(bg_kind, rng, (pw, ph))
    scale = min(pw * 0.7 / paper.width, ph * 0.9 / paper.height)
    paper = paper.resize((int(paper.width * scale), int(paper.height * scale)), Image.LANCZOS)
    paper = ImageChops.multiply(paper, vgradient(paper.size, WHITE, (232, 230, 226)))
    rot = paper.convert("RGBA").rotate(angle, resample=Image.BICUBIC, expand=True)
    px = (pw - rot.width) // 2 + rng.randint(-24, 24)
    py = (ph - rot.height) // 2 + rng.randint(-18, 18)
    alpha = rot.split()[3]
    photo.paste(BLACK, (px + 12, py + 20), alpha.point(lambda v: v * 55 // 100).filter(ImageFilter.GaussianBlur(16)))
    photo.paste(rot, (px, py), rot)
    light = lighting((pw, ph), rng, lo, 255)
    photo = ImageChops.multiply(photo, Image.merge("RGB", (light, light, light)))
    photo = ImageChops.multiply(photo, Image.new("RGB", photo.size, (255, 247, 234)))
    photo = photo.filter(ImageFilter.GaussianBlur(blur))
    return noise(photo, rng, 7)


def receipt_key(store, d, items, total, note):
    return {"accept": [[E(store, a, d, name) for name, a in items]], "lenient": [[E(store, total, d)]], "note": note}


# ================================================================ B1: payment banners over busy screens

def b1_01(rng):
    img = wallpaper(rng, (250, 214, 196), (196, 184, 236), [(255, 236, 200), (186, 214, 250), (240, 190, 220)])
    box_a, box_b = widget_box(0, 1, 2), widget_box(2, 1, 2)
    w_weather(img, box_a, False, "서울", "19°", "맑음", "23°", "13°")
    w_calendar(img, box_b, False, "금요일", 9, [("팀 회의", "오후 3:00–4:00", (255, 149, 0)), ("헬스", "오후 7:30", (52, 199, 89))])
    widget_label(img, box_a, "날씨")
    widget_label(img, box_b, "캘린더")
    home_screen(img, False, app_grid(LIGHT_APPS, {"카카오톡": 12, "쿠팡": 3, "Instagram": 5, "설정": 1}, ("금요일", 9), rows=(0, 3, 4, 5)),
                ["phone", "safari", ("messages", 4), "music"])
    status_bar(img, "2:23", BLACK, 76)
    home_indicator(img, BLACK)
    banners(img, [("messages", "신한카드", "지금",
                   "[Web발신]\n신한카드(1234)승인 김*수 8,700원(일시불)10/09 14:22 스타벅스 역삼역점 누적1,240,500원")], False)
    return img, {"accept": [[E("스타벅스 역삼역점", 8700, "2026-10-09")]],
                 "note": "light home screen (weather, calendar widgets, badges); one Shinhan SMS approval banner with a running total"}


def b1_02(rng):
    img = wallpaper(rng, (22, 26, 52), (6, 6, 14), [(72, 40, 120), (20, 70, 110), (40, 30, 80)])
    box_a, box_b = widget_box(0, 1, 2), widget_box(2, 1, 2)
    w_steps(img, box_a, True, "8,432", "6.2km", "7")
    w_battery(img, box_b, True, [("iPhone", 64), ("AirPods", 82)])
    widget_label(img, box_a, "피트니스")
    widget_label(img, box_b, "배터리")
    home_screen(img, True, app_grid(DARK_APPS, {"카카오톡": 48, "당근": 2}, None, {"calendar": ("files", "파일")}, rows=(0, 3, 4, 5)),
                ["phone", "safari", "messages", ("mail", 7)])
    status_bar(img, "6:41", WHITE, 64)
    home_indicator(img, WHITE)
    banners(img, [("toss", "토스", "지금", "CU 삼성역점에서 6,300원을 결제했어요\n토스뱅크 체크카드 · 잔액 182,350원")], True)
    return img, {"accept": [[E("CU 삼성역점", 6300, "")]],
                 "note": "dark home screen (steps, battery widgets), no date anywhere on screen; one Toss check card banner that also shows a balance"}


def b1_03(rng):
    img = wallpaper(rng, (204, 226, 246), (246, 224, 206), [(255, 240, 220), (200, 230, 255), (250, 214, 226)])
    fg = (34, 34, 44)
    lock_screen(img, fg, "10월 3일 토요일", "1:12", [("21°", "맑음"), ("88%", "배터리"), ("6:00", "저녁 약속")], False)
    status_bar(img, "SKT", fg, 88)
    lock_notifications(img, [
        ("kakaopay", "결제 완료", "2분 전", "올리브영 홍대입구점 32,400원 결제가 완료되었습니다."),
        ("naverpay", "네이버페이 결제", "14분 전", "15,000원 · 롯데시네마 합정"),
    ], False)
    a = [E("올리브영 홍대입구점", 32400, "2026-10-03"), E("롯데시네마 합정", 15000, "2026-10-03")]
    b = [E("올리브영 홍대입구점", 32400, ""), E("롯데시네마 합정", 15000, "")]
    return img, {"accept": [a, b],
                 "note": "light lock screen showing 10월 3일 토요일; Kakao Pay and Naver Pay notifications, neither dated"}


def b1_04(rng):
    p = pal(False)
    img = blank(WHITE)
    d = ImageDraw.Draw(img)
    brand = (0, 82, 164)
    y = 170
    text(d, (60, y + 64), "한빛경제", 66, "b", brand, "lm")
    magnifier(d, 1000, y + 60, 22, BLACK, 6)
    hamburger(d, 1106, y + 64, 50, BLACK, 6, 16)
    y += 136
    d.line((0, y, W, y), fill=p["sep"], width=2)
    x = 60
    for t in ["경제", "금융", "부동산", "산업", "IT·과학", "국제"]:
        on = t == "금융"
        text(d, (x, y + 56), t, 42, "sb" if on else "m", brand if on else (90, 90, 96), "lm")
        if on:
            d.line((x, y + 104, x + tw(t, F(42, "sb")), y + 104), fill=brand, width=6)
        x += tw(t, F(42, "m")) + 58
    y += 110
    d.line((0, y, W, y), fill=p["sep"], width=2)
    y += 56
    text(d, (60, y), "금융", 39, "sb", brand)
    y = para(d, 60, y + 70, "가계 카드 사용액 석 달째 증가… 1인당 월평균 128만원", 72, "b", BLACK, W - 120, 96)
    y = para(d, 60, y + 24, "외식·여가 지출 늘고 해외 결제도 4.2% 증가", 45, "m", (80, 80, 86), W - 120, 64)
    text(d, (60, y + 30), "김지현 기자", 39, "m", (60, 60, 66))
    text(d, (60, y + 88), "입력 2026.10.05 06:00", 36, "r", (128, 128, 134))
    y += 170
    img.paste(vgradient((W - 120, 340), (150, 170, 190), (90, 104, 120)), (60, y))
    for k in range(5):
        d.rectangle((120 + k * 200, y + 80, 260 + k * 200, y + 310), fill=mix((200, 210, 220), (120, 130, 150), k / 5))
    y += 380
    body = [
        "5일 카드업계에 따르면 지난달 개인 신용·체크카드 승인액은 98조 4,000억원으로 1년 전보다 4.2% 늘었다. 1인당 월평균 사용액은 1,284,000원으로 집계됐다.",
        "항목별로는 외식비가 평균 312,000원으로 가장 많았고, 온라인 쇼핑 245,000원, 교통비 118,000원이 뒤를 이었다.",
    ]
    for t in body:
        y = para(d, 60, y, t, 50, "r", (28, 28, 30), W - 120, 84) + 40
    if y + 230 > H - 250:
        raise ValueError("news page ad box runs under the Safari bar")
    d.rounded_rectangle((60, y, W - 60, y + 230), radius=24, fill=(246, 246, 248))
    text(d, (96, y + 36), "광고", 33, "sb", (150, 150, 156))
    text(d, (96, y + 88), "무선청소기 S9 오늘만 28% 할인", 45, "sb", BLACK)
    text(d, (96, y + 152), "459,000원 → 329,000원", 45, "b", (230, 60, 50))
    safari_bar(img, False, "hanbit-econ.co.kr")
    status_bar(img, "11:43", BLACK, 58)
    banners(img, [("kakaotalk", "카카오페이", "지금", "[카카오페이] 결제 완료\n교보문고 광화문점\n결제금액 18,500원\n2026.10.05 11:42")], False)
    return img, {"accept": [[E("교보문고 광화문점", 18500, "2026-10-05")]],
                 "note": "light news article full of spending statistics plus an ad price; KakaoTalk 알림톡 banner from Kakao Pay"}


def b1_05(rng):
    p = pal(True)
    img = blank(p["bg"])
    d = ImageDraw.Draw(img)
    fg, sub = p["fg"], p["sub"]
    chevron(d, 66, 248, 24, fg, 7)
    d.rounded_rectangle((126, 196, 960, 300), radius=30, fill=p["fill"])
    magnifier(d, 180, 244, 18, sub, 5)
    text(d, (226, 248), "에어팟 프로", 45, "r", fg, "lm")
    d.rounded_rectangle((1010, 220, 1090, 282), radius=10, outline=fg, width=6)
    d.ellipse((1072, 190, 1126, 244), fill=(255, 69, 58))
    text(d, (1099, 217), "3", 33, "b", WHITE, "mm")
    img.paste(vgradient((W, 820), (44, 44, 50), (30, 30, 34)), (0, 330))
    rrect(img, (380, 520, 800, 860), 90, (240, 240, 242))
    d.line((380, 640, 800, 640), fill=(205, 205, 210), width=4)
    d.ellipse((580, 740, 600, 760), fill=(120, 200, 120))
    d.rounded_rectangle((W - 220, 1080, W - 60, 1130), radius=25, fill=(60, 60, 66))
    text(d, (W - 140, 1105), "1 / 8", 33, "m", WHITE, "mm")
    y = 1190
    text(d, (60, y), "Apple 공식 스토어  >", 39, "m", sub)
    y = para(d, 60, y + 70, "Apple 에어팟 프로 2세대 USB-C 정품", 57, "sb", fg, W - 120, 76)
    text(d, (60, y + 18), "★★★★★", 39, "r", (255, 196, 0))
    text(d, (290, y + 18), "4.8 (12,384)", 39, "r", sub)
    y += 100
    text(d, (60, y), "17%", 63, "b", (255, 80, 70))
    text(d, (200, y), "239,000원", 66, "b", fg)
    sx = 540
    text(d, (sx, y + 18), "289,000원", 45, "r", sub)
    d.line((sx, y + 46, sx + tw("289,000원", F(45, "r")), y + 46), fill=sub, width=3)
    y += 112
    d.rounded_rectangle((60, y, 170, y + 60), radius=12, fill=(255, 80, 70))
    text(d, (115, y + 30), "쿠폰", 36, "b", WHITE, "mm")
    text(d, (196, y + 30), "쿠폰 적용 시 229,000원", 45, "sb", (255, 110, 100), "lm")
    text(d, (60, y + 96), "최대 2,390원 적립", 42, "r", sub)
    y += 180
    d.line((0, y, W, y), fill=p["sep"], width=2)
    text(d, (60, y + 48), "무료배송 · 10/06(화) 도착 예정", 45, "m", fg)
    text(d, (60, y + 124), "옵션: 화이트 / 1개", 42, "r", sub)
    y += 210
    d.line((0, y, W, y), fill=p["sep"], width=2)
    text(d, (60, y + 40), "함께 보면 좋은 상품", 45, "sb", fg)
    for k, (name, price) in enumerate([("맥세이프 충전기", "59,000원"), ("애플워치 SE 2", "329,000원")]):
        x0 = 60 + k * 560
        rrect(img, (x0, y + 120, x0 + 150, y + 270), 20, (44, 44, 50))
        text(d, (x0 + 175, y + 140), name, 42, "r", fg)
        text(d, (x0 + 175, y + 202), price, 45, "b", fg)
    if y + 290 > H - 270:
        raise ValueError("shop page overflows the buy bar")
    top = H - 270
    d.rectangle((0, top, W, H), fill=p["card"])
    d.rounded_rectangle((48, top + 40, 560, top + 170), radius=24, outline=fg, width=3)
    text(d, (304, top + 105), "장바구니", 48, "sb", fg, "mm")
    d.rounded_rectangle((604, top + 40, W - 48, top + 170), radius=24, fill=(255, 80, 70))
    text(d, (W / 2 + 302, top + 105), "바로구매", 48, "b", WHITE, "mm")
    home_indicator(img, WHITE)
    status_bar(img, "7:21", WHITE, 47)
    banners(img, [("hyundai", "현대카드", "지금", "이*진님 360,000원 3개월 할부 승인\n롯데하이마트 잠실점\n10/04 19:20 · 누적 1,032,700원")], True)
    return img, {"accept": [[E("롯데하이마트 잠실점", 360000, "2026-10-04")]],
                 "note": "dark shopping product page with list, sale and coupon prices; Hyundai Card push for a 3-month installment"}


def b1_06(rng):
    img = blank(BLACK)
    kakao_chat(img, False, "대학 동기 모임", 6, 35, [
        ("date", "2026년 10월 5일 월요일"),
        ("other", "이지현", ["토요일 7시 강남역 맞지?"], "오후 9:40"),
        ("other", "김민수", ["응 11번 출구 앞 고깃집 예약했어"], "오후 9:44"),
        ("date", "2026년 10월 6일 화요일"),
        ("other", "김민수", ["이번 주 토요일 모임 회비 1인당 40,000원이야", "장소 예약금 100,000원은 내가 먼저 냈어"], "오후 7:52"),
        ("other", "이지현", ["오케이 오늘 안에 보낼게!"], "오후 7:58"),
        ("me", ["나 지금 치킨 시켰다 ㅋㅋ", "2차는 내가 쏠게"], "오후 8:10", None),
        ("other", "정하늘", ["회비 계좌 카카오뱅크 3333-01-2345678 맞지?"], "오후 8:13"),
        ("other", "김민수", ["응 맞아 예금주 김민수"], "오후 8:14"),
    ])
    status_bar(img, "8:16", BLACK, 41)
    banners(img, [("messages", "우리카드", "지금", "[Web발신]\n우리(1234)체크승인 박*영\n23,800원 10/06 20:15\n교촌치킨 신촌점")], False)
    return img, {"accept": [[E("교촌치킨 신촌점", 23800, "2026-10-06")]],
                 "note": "light KakaoTalk group chat about dues, a deposit and an account number; Woori check card SMS banner, merchant on its own line"}


def b1_07(rng):
    img = blank(BLACK)
    kakao_chat(img, True, "서연", None, 4, [
        ("date", "2026년 10월 7일 수요일"),
        ("other", "서연", ["내일 점심 같이 먹을 수 있어?"], "오후 9:02"),
        ("me", ["내일은 회의 있어서 안 될 듯 ㅠ"], "오후 9:10", None),
        ("date", "2026년 10월 8일 목요일"),
        ("other", "서연", ["점심 뭐 먹었어?"], "오후 12:31"),
        ("me", ["회사 앞 김치찌개 9,000원", "요즘 점심값 만원 넘는 데 많던데 여긴 착해"], "오후 12:33", None),
        ("other", "서연", ["부럽다 ㅠ 여기 근처는 다 13,000원부터야", "나 어제 택시비 18,000원 나왔어"], "오후 12:35"),
        ("me", ["헐 비싸다", "나 커피 사러 가는 중!"], "오후 12:41", None),
        ("other", "서연", ["ㅋㅋ 맛점해"], "오후 12:42"),
    ])
    status_bar(img, "12:48", WHITE, 72)
    banners(img, [("toss", "4,500원 결제", "지금", "메가MGC커피 역삼점\n토스뱅크 체크카드")], True)
    return img, {"accept": [[E("메가MGC커피 역삼점", 4500, "2026-10-08")], [E("메가MGC커피 역삼점", 4500, "")]],
                 "note": "dark 1:1 chat about lunch and taxi prices; undated Toss check card banner while the chat divider shows 10월 8일 (today)"}


def b1_08(rng):
    img = wallpaper(rng, (12, 18, 40), (2, 4, 10), [(20, 60, 90), (60, 30, 90), (10, 40, 60)])
    box = widget_box(0, 3, 4)
    w_stocks(img, box, True, [("KOSPI", "코스피 지수", "2,612.34", "+0.82%"), ("005930", "삼성전자", "72,400", "-1.20%"),
                              ("USD/KRW", "원/달러 환율", "1,382.50", "+3.10")])
    widget_label(img, box, "주식")
    home_screen(img, True, app_grid(DARK_APPS, {"카카오톡": 7, "당근": 1}, ("금요일", 2), rows=(0, 1, 2, 5)), ["phone", "safari", ("messages", 2), "music"])
    status_bar(img, "8:04", WHITE, 93)
    home_indicator(img, WHITE)
    banners(img, [
        ("messages", "삼성카드", "지금", "[Web발신]\n삼성카드 해외승인 이*진\n17,000원 10/02 08:04\nNETFLIX.COM"),
        ("kbcard", "KB국민카드", "1분 전", "정*호님 4,400원 일시불 승인\nAPPLE.COM/BILL\n10/02 08:03"),
    ], True)
    return img, {"accept": [[E("NETFLIX.COM", 17000, "2026-10-02"), E("APPLE.COM/BILL", 4400, "2026-10-02")]],
                 "note": "dark home with a stocks / exchange-rate widget; Samsung overseas approval in won (NETFLIX.COM) + KB push with an English merchant"}


def b1_09(rng):
    img = blank(WHITE)
    d = ImageDraw.Draw(img)
    green = (3, 170, 80)
    text(d, (60, 236), "blog", 54, "b", green, "lm")
    text(d, (190, 240), "산책하는 캠퍼의 기록", 42, "sb", BLACK, "lm")
    magnifier(d, 1100, 232, 20, BLACK, 6)
    d.line((0, 306, W, 306), fill=(232, 232, 236), width=2)
    y = 360
    text(d, (60, y), "캠핑 일기", 39, "m", green)
    y = para(d, 60, y + 70, "초보 캠퍼 가을 캠핑 준비물 총정리 (가격 포함)", 63, "b", BLACK, W - 120, 86)
    profile_pic(img, 60, y + 30, (200, 220, 190), 96)
    text(d, (180, y + 34), "숲길캠퍼", 39, "sb", BLACK)
    text(d, (180, y + 86), "2026. 10. 2. 21:14", 36, "r", (140, 140, 146))
    y += 170
    d.line((60, y, W - 60, y), fill=(232, 232, 236), width=2)
    y += 50
    y = para(d, 60, y, "드디어 가을 캠핑 시즌! 처음 장비를 마련하면서 쓴 비용을 정리해 봤어요.", 48, "r", (30, 30, 34), W - 120, 80) + 30
    img.paste(vgradient((W - 120, 470), (120, 170, 120), (60, 110, 80)), (60, y))
    d.polygon([(330, y + 400), (590, y + 120), (850, y + 400)], fill=(240, 150, 60))
    y += 510
    for line in ["1. 텐트 (4인용 리빙쉘) 289,000원", "2. 침낭 2개 158,000원", "3. 캠핑 의자 2개 79,800원", "4. LED 랜턴 39,900원"]:
        text(d, (60, y), line, 48, "r", (30, 30, 34))
        y += 80
    text(d, (60, y + 10), "총 예산 약 566,700원", 48, "b", BLACK)
    y += 110
    para(d, 60, y, "중고로 사면 절반 가격이라 초보라면 중고 거래도 추천해요.", 48, "r", (30, 30, 34), W - 120, 80)
    safari_bar(img, False, "blog.campers.kr")
    status_bar(img, "3:35", BLACK, 66)
    banners(img, [("naverpay", "결제 완료", "지금", "캠핑앤 하남점 86,000원 결제 완료\n2026.10.10 15:35")], False)
    return img, {"accept": [[E("캠핑앤 하남점", 86000, "2026-10-10")]],
                 "note": "light blog post listing camping gear prices and a budget total; Naver Pay payment banner"}


def b1_10(rng):
    img = wallpaper(rng, (16, 22, 46), (4, 6, 16), [(40, 60, 120), (80, 40, 100), (20, 30, 60)])
    lock_screen(img, WHITE, "10월 8일 목요일", "12:36", [("16°", "흐림"), ("57%", "배터리"), ("3,214", "걸음")], True)
    status_bar(img, "KT", WHITE, 57)
    lock_notifications(img, [("kbcard", "KB국민카드", "1분 전", "강*민님 7,800원 일시불 승인\n서브웨이 판교점\n10.08 (목) 12:35 · 누적 845,000원")], True)
    return img, {"accept": [[E("서브웨이 판교점", 7800, "2026-10-08")]],
                 "note": "dark lock screen with date and widgets; KB card push, merchant on its own line, date as 10.08 (목)"}


def b1_11(rng):
    img = blank(BLACK)
    kakao_chat(img, False, "우리 가족", 4, 12, [
        ("date", "2026년 10월 10일 토요일"),
        ("other", "아빠", ["다들 주말 잘 보내고 있지?"], "오후 8:20"),
        ("me", ["네 내일 저녁에 갈게요"], "오후 8:31", None),
        ("date", "2026년 10월 11일 일요일"),
        ("other", "엄마", ["추석 때 쓴 돈 정리해 봤어", "장보기 230,000원\n기름값 85,000원\n할머니 용돈 200,000원"], "오후 5:32"),
        ("other", "아빠", ["수고했어 다음 달 생신 선물 예산은 300,000원 어때?"], "오후 5:40"),
        ("me", ["좋아요! 저 지금 마트 왔어요", "필요한 거 있으면 말해줘요"], "오후 5:52", None),
        ("other", "엄마", ["우유랑 계란 사와"], "오후 5:58"),
    ])
    status_bar(img, "6:02", BLACK, 35)
    banners(img, [
        ("messages", "하나카드", "지금", "[Web발신]\n하나(5678)승인 최*우 54,000원 일시불 10/11 18:02 이마트 성수점 누적612,000원"),
        ("kakaopay", "카카오페이", "18분 전", "카카오T 13,200원 결제가 완료되었어요.\n2026.10.11 17:44"),
    ], False)
    return img, {"accept": [[E("이마트 성수점", 54000, "2026-10-11"), E("카카오T", 13200, "2026-10-11")]],
                 "note": "light family chat listing holiday expenses and a gift budget; Hana SMS approval + Kakao Pay banner"}


def b1_12(rng):
    img = wallpaper(rng, (196, 232, 214), (250, 236, 196), [(210, 240, 250), (255, 220, 200), (220, 250, 220)])
    box_a, box_b = widget_box(0, 3, 2), widget_box(2, 3, 2)
    w_calendar(img, box_a, False, "목요일", 1, [("동창 저녁", "오후 7:00", (88, 86, 214)), ("세탁물 찾기", "오후 9:30", (255, 149, 0))])
    w_screentime(img, box_b, False, "3시간 12분", [("YouTube", "1시간 5분"), ("카카오톡", "48분"), ("Instagram", "31분")])
    widget_label(img, box_a, "캘린더")
    widget_label(img, box_b, "스크린 타임")
    home_screen(img, False, app_grid(LIGHT_APPS, {"카카오톡": 3, "YouTube": 1}, ("목요일", 1), rows=(0, 1, 2, 5)), ["phone", "safari", "messages", "mail"])
    status_bar(img, "9:14", BLACK, 22)
    home_indicator(img, BLACK)
    banners(img, [
        ("toss", "토스", "지금", "무신사 스토어에서 59,800원을 결제했어요"),
        ("messages", "롯데카드", "9분 전", "[Web발신]\n롯데 오*림님 52,000원 일시불\n10/01 21:05\nCGV 용산아이파크몰"),
    ], False)
    cgv = E("CGV 용산아이파크몰", 52000, "2026-10-01")
    return img, {"accept": [[E("무신사 스토어", 59800, "2026-10-01"), cgv], [E("무신사 스토어", 59800, ""), cgv]],
                 "note": "light home with a calendar widget (목요일 1) and screen time; undated Toss banner + Lotte SMS with the merchant on its own line"}


# ================================================================ B2: money that is not spending

def b2_01(rng):
    img = wallpaper(rng, (30, 20, 40), (6, 4, 10), [(90, 40, 70), (40, 30, 90), (20, 20, 50)])
    lock_screen(img, WHITE, "10월 9일 금요일", "9:03", [("14°", "맑음"), ("91%", "배터리")], True)
    status_bar(img, "LG U+", WHITE, 91)
    lock_notifications(img, [
        ("kbbank", "KB스타뱅킹", "3분 전", "[KB국민] 10/09 09:00 입금 3,250,000원\n(주)한빛소프트 급여 · 잔액 4,102,330원"),
        ("kakaobank", "카카오뱅크", "1시간 전", "세이프박스 이자 1,234원이 입금되었어요."),
    ], True)
    return img, {"accept": [[]], "note": "dark lock screen with only a salary deposit and a savings-interest notification"}


def b2_02(rng):
    img = wallpaper(rng, (255, 222, 206), (214, 226, 250), [(255, 240, 214), (220, 214, 250), (200, 236, 240)])
    box_a, box_b = widget_box(0, 3, 2), widget_box(2, 3, 2)
    w_weather(img, box_a, False, "부산", "24°", "구름 조금", "26°", "19°")
    w_battery(img, box_b, False, [("iPhone", 52), ("Watch", 77)])
    widget_label(img, box_a, "날씨")
    widget_label(img, box_b, "배터리")
    home_screen(img, False, app_grid(LIGHT_APPS, {"카카오톡": 21, "쿠팡": 1}, ("월요일", 5), rows=(0, 1, 2, 5)), ["phone", "safari", "messages", "music"])
    status_bar(img, "12:31", BLACK, 52)
    home_indicator(img, BLACK)
    banners(img, [
        ("toss", "입금", "지금", "김민지님이 25,000원을 보냈어요\n토스뱅크 통장 · 잔액 207,450원"),
        ("messages", "BC카드", "1분 전", "[Web발신]\nBC카드(5512) 승인 홍*동 12,900원 일시불 10/05 12:30 김밥천국 을지로점"),
    ], False)
    return img, {"accept": [[E("김밥천국 을지로점", 12900, "2026-10-05")]],
                 "note": "light home; Toss notice of money received (not spending) + one BC card approval"}


def b2_03(rng):
    img = blank(BLACK)
    kakao_chat(img, False, "제주 여행", 4, 5, [
        ("date", "2026년 10월 6일 화요일"),
        ("other", "박수아", ["다들 잘 들어갔어?", "사진 앨범에 올려놨어"], "오후 11:12"),
        ("date", "2026년 10월 7일 수요일"),
        ("other", "김지훈", ["여행 경비 정산했어!",
                          "[제주 여행 정산]\n숙소 240,000원\n렌트카 98,000원\n유류비 50,000원\n흑돼지 저녁 132,000원\n합계 520,000원 / 4명 = 130,000원",
                          "토스뱅크 1000-1234-5678 김지훈으로 130,000원씩 보내줘"], "오후 10:03"),
        ("other", "박수아", ["확인! 내일 아침에 보낼게"], "오후 10:10"),
        ("me", ["나 렌트카 보험료 15,000원 따로 냈으니까 빼줘 ㅠ"], "오후 10:15", None),
        ("other", "김지훈", ["오케이 그럼 너는 115,000원만 보내면 돼"], "오후 10:18"),
    ])
    status_bar(img, "10:22", BLACK, 29)
    return img, {"accept": [[]],
                 "note": "light group chat where a friend pasted a trip settlement (items, total, per-person share) and an account; no notification, no spending"}


def b2_04(rng):
    p = pal(True)
    img = blank((12, 12, 14))
    d = ImageDraw.Draw(img)
    fg, sub = p["fg"], p["sub"]
    text(d, (60, 250), "현대카드", 57, "b", fg, "lm")
    bell(d, 1000, 246, fg)
    hamburger(d, 1106, 250, 50, fg, 6, 16)
    card = vgradient((640, 404), (70, 74, 82), (24, 26, 30))
    img.paste(card, ((W - 640) // 2, 360), rounded_mask(card.size, 30))
    text(d, (W // 2 - 270, 420), "M BOOST", 42, "b", WHITE)
    text(d, (W // 2 - 270, 700), "**** 1234", 39, "m", (200, 200, 206))
    y = 830
    text(d, (W / 2, y), "10월 청구 예정 금액", 45, "m", sub, "mm")
    text(d, (W / 2, y + 110), "845,200원", 96, "b", fg, "mm")
    text(d, (W / 2, y + 210), "결제 예정일 2026.10.09 (금) · 신한 110-***-123456", 37, "r", sub, "mm")
    y += 290
    rrect(img, (48, y, W - 48, y + 400), 40, p["card"])
    for k, (label, value) in enumerate([("일시불", "612,400원"), ("할부", "182,800원"), ("해외 이용", "50,000원")]):
        kv(d, p, y + 90 + k * 110, label, value, 45)
    y += 440
    rrect(img, (48, y, W - 48, y + 290), 40, p["card"])
    kv(d, p, y + 90, "이용 가능 한도", "4,154,800원", 45)
    kv(d, p, y + 200, "M포인트", "12,340P", 45)
    y += 340
    for k, label in enumerate(["즉시결제", "분할납부 신청"]):
        x0 = 48 + k * (W - 96 + 24) / 2
        d.rounded_rectangle((x0, y, x0 + (W - 96 - 24) / 2, y + 130), radius=30, outline=(90, 90, 96), width=3)
        text(d, (x0 + (W - 96 - 24) / 4, y + 65), label, 45, "sb", fg, "mm")
    tab_bar(img, p, ["홈", "이용내역", "혜택", "전체"])
    status_bar(img, "11:20", WHITE, 70)
    return img, {"accept": [[]],
                 "note": "dark card app showing next month's bill (청구 예정), its breakdown, credit limit and points; nothing paid"}


def b2_05(rng):
    img = blank(BLACK)
    kakao_chat(img, False, "푸른마을 관리사무소", None, 12, [
        ("date", "2026년 10월 1일 목요일"),
        ("card", "푸른마을 관리사무소", "알림톡 도착", "[안내] 10월 승강기 정기 점검\n점검일: 2026.10.06 (화) 10:00~12:00\n점검 시간에는 계단을 이용해 주세요.", None, "오전 9:00"),
        ("card", "푸른마을 관리사무소", "알림톡 도착", "[공지] 재활용 분리수거 요일 변경\n10월부터 매주 화·금요일 저녁 6시 이후에 배출해 주세요.", None, "오후 2:00"),
        ("date", "2026년 10월 5일 월요일"),
        ("card", "푸른마을 관리사무소", "알림톡 도착",
         "[전자고지] 9월분 관리비 고지서\n101동 1203호\n납부금액: 213,450원\n납부기한: 2026.10.08 (목)\n자동이체 고객은 납부기한에 출금됩니다.", "고지서 보기", "오후 6:30"),
    ])
    status_bar(img, "7:45", BLACK, 60)
    banners(img, [("hana", "하나카드", "지금", "하나카드 승인 6,900원 일시불\n다이소 수원역점 · 10/05 19:44")], False)
    return img, {"accept": [[E("다이소 수원역점", 6900, "2026-10-05")]],
                 "note": "light KakaoTalk channel with a 관리비 e-bill (고지서, not paid yet) + one Hana card approval banner"}


def b2_06(rng):
    p = pal(False)
    img = blank(p["group"])
    d = ImageDraw.Draw(img)
    fg, sub = p["fg"], p["sub"]
    teal = (0, 130, 150)
    text(d, (60, 250), "하늘은행", 57, "b", teal, "lm")
    bell(d, 1000, 246, fg)
    hamburger(d, 1106, 250, 50, fg, 6, 16)
    text(d, (60, 380), "김하늘님, 좋은 아침이에요", 45, "m", fg, "lm")
    y = 450
    rrect(img, (48, y, W - 48, y + 230), 40, WHITE)
    text(d, (96, y + 60), "총 자산", 42, "m", sub, "lm")
    text(d, (96, y + 150), "14,834,567원", 72, "b", fg, "lm")
    y += 270
    rrect(img, (48, y, W - 48, y + 380), 40, WHITE)
    text(d, (96, y + 64), "하늘 자유입출금", 45, "sb", fg, "lm")
    text(d, (96, y + 124), "110-482-339201", 39, "r", sub, "lm")
    text(d, (96, y + 222), "1,234,567원", 72, "b", fg, "lm")
    for k, label in enumerate(["이체", "내역"]):
        x0 = 96 + k * 500
        d.rounded_rectangle((x0, y + 280, x0 + 470, y + 350), radius=20, fill=(238, 244, 246))
        text(d, (x0 + 235, y + 315), label, 42, "sb", teal, "mm")
    y += 420
    for name, num, bal in [("청년도약계좌", "110-517-002468", "3,600,000원"), ("정기예금", "110-903-118842", "10,000,000원")]:
        rrect(img, (48, y, W - 48, y + 200), 40, WHITE)
        text(d, (96, y + 64), name, 45, "sb", fg, "lm")
        text(d, (96, y + 130), num, 39, "r", sub, "lm")
        text(d, (W - 96, y + 100), bal, 54, "b", fg, "rm")
        y += 240
    rrect(img, (48, y, W - 48, y + 150), 40, (232, 246, 248))
    text(d, (96, y + 75), "이번 달 이자 지급 예정", 42, "m", fg, "lm")
    text(d, (W - 96, y + 75), "1,840원", 45, "b", teal, "rm")
    y += 190
    rrect(img, (48, y, W - 48, y + 250), 40, WHITE)
    text(d, (96, y + 56), "광고", 33, "sb", sub, "lm")
    text(d, (96, y + 124), "하늘 자유적금 최고 연 4.5%", 48, "b", fg, "lm")
    text(d, (96, y + 192), "매달 최대 500,000원까지 저축할 수 있어요", 39, "r", sub, "lm")
    if y + 250 > H - 260:
        raise ValueError("bank home overflows the tab bar")
    tab_bar(img, p, ["홈", "자산", "상품", "혜택", "전체"])
    status_bar(img, "10:05", BLACK, 83)
    banners(img, [("haneul", "이자 입금", "지금", "자유입출금 통장에 이자 1,234원이 입금되었어요.\n잔액 1,234,567원")], False)
    return img, {"accept": [[]],
                 "note": "light bank app home with balances, total assets and expected interest; interest-deposit banner"}


def b2_07(rng):
    img = wallpaper(rng, (40, 30, 30), (8, 6, 8), [(110, 50, 40), (60, 40, 90), (30, 50, 60)])
    box_a, box_b = widget_box(0, 3, 2), widget_box(2, 3, 2)
    w_weather(img, box_a, True, "서울", "17°", "흐림", "20°", "12°")
    w_screentime(img, box_b, True, "2시간 47분", [("카카오톡", "52분"), ("YouTube", "44분"), ("네이버", "21분")])
    widget_label(img, box_a, "날씨")
    widget_label(img, box_b, "스크린 타임")
    home_screen(img, True, app_grid(DARK_APPS, {"카카오톡": 9, "배달의민족": 1}, ("수요일", 7), rows=(0, 1, 2, 5)), ["phone", "safari", ("messages", 2), "music"])
    status_bar(img, "5:52", WHITE, 38)
    home_indicator(img, WHITE)
    banners(img, [
        ("messages", "SKT", "지금", "[Web발신]\n[SKT] 9월 이용요금 69,800원이 10/10 등록하신 신한카드로 자동납부될 예정입니다."),
        ("messages", "NH농협카드", "2분 전", "[Web발신]\nNH농협카드승인 한*결 15,000원 일시불 10/07 17:50 롯데마트 서울역점 누적98,500원"),
    ], True)
    return img, {"accept": [[E("롯데마트 서울역점", 15000, "2026-10-07")]],
                 "note": "dark home; SKT auto-pay scheduled for 10/10 (not paid yet) + one NH card approval"}


def b2_08(rng):
    p = pal(True)
    img = blank((14, 14, 16))
    d = ImageDraw.Draw(img)
    fg, sub = p["fg"], p["sub"]
    blue = (49, 130, 246)
    text(d, (60, 250), "토스", 57, "b", fg, "lm")
    bell(d, 1000, 246, fg)
    hamburger(d, 1106, 250, 50, fg, 6, 16)
    y = 360
    rrect(img, (36, y, W - 36, y + 300), 44, p["card"])
    text(d, (84, y + 70), "토스뱅크 통장", 42, "m", sub, "lm")
    text(d, (84, y + 160), "482,310원", 69, "b", fg, "lm")
    d.rounded_rectangle((W - 290, y + 120, W - 84, y + 200), radius=20, fill=(60, 60, 66))
    text(d, (W - 187, y + 160), "송금", 42, "sb", fg, "mm")
    text(d, (84, y + 250), "포인트 1,240원", 39, "r", sub, "lm")
    y += 330
    rrect(img, (36, y, W - 36, y + 220), 44, p["card"])
    text(d, (84, y + 70), "토스증권", 42, "m", sub, "lm")
    text(d, (84, y + 150), "2,315,000원", 60, "b", fg, "lm")
    text(d, (W - 84, y + 150), "+71,800원 (3.2%)", 42, "sb", (240, 68, 82), "rm")
    y += 250
    rrect(img, (36, y, W - 36, y + 330), 44, p["card"])
    text(d, (84, y + 70), "내 소비", 42, "m", sub, "lm")
    text(d, (84, y + 150), "이번 달 1,203,400원 썼어요", 54, "b", fg, "lm")
    d.rounded_rectangle((84, y + 220, W - 84, y + 250), radius=15, fill=(60, 60, 66))
    d.rounded_rectangle((84, y + 220, 84 + (W - 168) * 0.62, y + 250), radius=15, fill=blue)
    text(d, (84, y + 292), "지난달 같은 기간보다 84,000원 덜 썼어요", 37, "r", sub, "lm")
    y += 360
    rrect(img, (36, y, W - 36, y + 200), 44, p["card"])
    text(d, (84, y + 70), "카드값", 42, "m", sub, "lm")
    text(d, (84, y + 145), "결제 예정 312,000원", 51, "b", fg, "lm")
    y += 230
    rrect(img, (36, y, W - 36, y + 170), 44, p["card"])
    text(d, (84, y + 85), "내 신용점수", 42, "m", sub, "lm")
    text(d, (W - 84, y + 85), "912점", 51, "b", blue, "rm")
    tab_bar(img, p, ["홈", "혜택", "토스페이", "증권", "전체"])
    status_bar(img, "2:10", WHITE, 61)
    banners(img, [("toss", "입금", "지금", "박정숙님이 300,000원을 보냈어요\n메모: 용돈")], True)
    return img, {"accept": [[]],
                 "note": "dark Toss home with balances, stocks, a month-to-date spending total and an upcoming card bill; incoming allowance banner"}


# ================================================================ B3: ordinary inputs

def b3_01(rng):
    img = wallpaper(rng, (232, 214, 250), (200, 230, 236), [(250, 230, 240), (214, 240, 222), (226, 214, 250)])
    fg = (30, 30, 40)
    lock_screen(img, fg, "10월 2일 금요일", "7:48", [("18°", "맑음"), ("72%", "배터리")], False)
    status_bar(img, "SKT", fg, 72)
    lock_notifications(img, [("shinhan", "신한카드", "2분 전", "신한카드 승인 32,000원 일시불\n아웃백스테이크하우스 목동점\n2026-10-02 19:46")], False)
    return img, {"accept": [[E("아웃백스테이크하우스 목동점", 32000, "2026-10-02")]],
                 "note": "light lock screen with a single Shinhan card push"}


def b3_02(rng):
    img = blank(WHITE)
    sms_thread(img, False, "KB국민카드", [
        ("ts", "10월 6일 (화) 오후 1:05"),
        ("in", "[Web발신]\nKB국민카드1234승인\n윤*아님\n15,800원 일시불\n10/06 13:05\n명동교자 본점\n누적1,032,400원"),
    ])
    status_bar(img, "9:20", BLACK, 81)
    return img, {"accept": [[E("명동교자 본점", 15800, "2026-10-06")]],
                 "note": "light Messages screen with a single KB SMS approval, one field per line"}


def b3_03(rng):
    img = blank(BLACK)
    sms_thread(img, True, "롯데카드", [
        ("ts", "10월 3일 (토) 오후 6:21"),
        ("in", "[Web발신]\n롯데카드(9876) 승인\n이*준님 42,000원 일시불\n10/03 18:21\n알라딘 중고서점 잠실점"),
        ("ts", "10월 5일 (월) 오후 12:10"),
        ("in", "[Web발신]\n롯데카드(9876) 승인\n이*준님 9,500원 일시불\n10/05 12:10\n본죽 강남역점\n누적 51,500원"),
        ("ts", "10월 7일 (수) 오전 8:42"),
        ("in", "[Web발신]\n롯데카드(9876) 승인\n이*준님 6,200원 일시불\n10/07 08:42\n파리바게뜨 삼성역점\n누적 57,700원"),
    ])
    status_bar(img, "8:45", WHITE, 90)
    return img, {"accept": [[E("알라딘 중고서점 잠실점", 42000, "2026-10-03"), E("본죽 강남역점", 9500, "2026-10-05"),
                             E("파리바게뜨 삼성역점", 6200, "2026-10-07")]],
                 "note": "dark Messages thread with three Lotte approvals on different days (running totals in two)"}


def b3_04(rng):
    p = pal(False)
    img = blank(WHITE)
    d = ImageDraw.Draw(img)
    close_x(d, W - 80, 250, 22, BLACK, 6)
    d.ellipse((W / 2 - 110, 430, W / 2 + 110, 650), fill=(255, 235, 0))
    check_mark(d, W / 2, 540, 110, BLACK, 16)
    text(d, (W / 2, 770), "결제 완료", 66, "b", BLACK, "mm")
    text(d, (W / 2, 862), "이디야커피 판교점", 48, "m", (90, 90, 96), "mm")
    text(d, (W / 2, 980), "5,600원", 96, "b", BLACK, "mm")
    d.line((90, 1100, W - 90, 1100), fill=p["sep"], width=2)
    for k, (label, value) in enumerate([("결제수단", "카카오페이머니"), ("결제일시", "2026.10.07 08:12"), ("승인번호", "41029387"),
                                        ("적립 예정", "페이포인트 56P")]):
        kv(d, p, 1180 + k * 100, label, value)
    d.rounded_rectangle((60, H - 320, W - 60, H - 170), radius=36, fill=(255, 235, 0))
    text(d, (W / 2, H - 245), "확인", 51, "b", BLACK, "mm")
    home_indicator(img, BLACK)
    status_bar(img, "8:13", BLACK, 77)
    return img, {"accept": [[E("이디야커피 판교점", 5600, "2026-10-07")]],
                 "note": "light Kakao Pay payment-complete screen (amount, method, date, approval number, points)"}


def b3_05(rng):
    p = pal(True)
    img = blank(p["bg"])
    d = ImageDraw.Draw(img)
    fg, sub = p["fg"], p["sub"]
    green = (3, 199, 90)
    nav(d, p, "주문완료", back=False)
    close_x(d, W - 80, 250, 22, fg, 6)
    d.ellipse((W / 2 - 80, 360, W / 2 + 80, 520), fill=green)
    check_mark(d, W / 2, 440, 80, WHITE, 12)
    text(d, (W / 2, 600), "주문이 완료되었습니다.", 57, "b", fg, "mm")
    text(d, (W / 2, 680), "주문번호 2026100821447713", 39, "r", sub, "mm")
    y = 760
    rrect(img, (48, y, W - 48, y + 300), 36, p["card"])
    img.paste(vgradient((200, 200), (140, 140, 150), (90, 90, 100)), (90, y + 50))
    text(d, (330, y + 60), "데일리무드", 39, "sb", sub)
    text(d, (330, y + 120), "오버핏 기모 맨투맨", 48, "sb", fg)
    text(d, (330, y + 184), "그레이 / L · 1개", 39, "r", sub)
    text(d, (W - 90, y + 250), "34,000원", 45, "b", fg, "rs")
    y += 350
    rows = [("상품금액", "34,000원"), ("배송비", "+3,000원"), ("쿠폰할인", "-5,000원"), ("포인트 사용", "-2,000원")]
    for k, (label, value) in enumerate(rows):
        kv(d, p, y + k * 96, label, value, 45)
    y += len(rows) * 96 + 10
    d.line((90, y, W - 90, y), fill=p["sep"], width=2)
    text(d, (90, y + 80), "총 결제금액", 51, "b", fg, "lm")
    text(d, (W - 90, y + 80), "30,000원", 63, "b", green, "rm")
    y += 190
    kv(d, p, y, "결제수단", "네이버페이 머니")
    kv(d, p, y + 96, "주문일시", "2026.10.08 21:44")
    kv(d, p, y + 192, "적립 예정 포인트", "300원")
    for k, label in enumerate(["주문 상세보기", "쇼핑 계속하기"]):
        x0 = 48 + k * (W - 96 + 24) / 2
        if k:
            d.rounded_rectangle((x0, H - 330, x0 + (W - 96 - 24) / 2, H - 190), radius=30, fill=green)
        else:
            d.rounded_rectangle((x0, H - 330, x0 + (W - 96 - 24) / 2, H - 190), radius=30, outline=(90, 90, 96), width=3)
        text(d, (x0 + (W - 96 - 24) / 4, H - 260), label, 45, "sb", fg, "mm")
    home_indicator(img, WHITE)
    status_bar(img, "9:46", WHITE, 54)
    return img, {"accept": [[E("데일리무드", 30000, "2026-10-08")], [E("데일리무드", 30000, "2026-10-08", "오버핏 기모 맨투맨")]],
                 "note": "dark Naver Pay order-complete screen; price, shipping, coupon and points lines resolve to one 30,000원 payment"}


def b3_06(rng):
    p = pal(False)
    img = blank(WHITE)
    d = ImageDraw.Draw(img)
    blue = (49, 130, 246)
    d.ellipse((W / 2 - 100, 420, W / 2 + 100, 620), fill=blue)
    check_mark(d, W / 2, 520, 100, WHITE, 16)
    text(d, (W / 2, 760), "김민지님에게", 69, "b", BLACK, "mm")
    text(d, (W / 2, 860), "30,000원을 보냈어요", 69, "b", BLACK, "mm")
    y = 1010
    rrect(img, (60, y, W - 60, y + 560), 40, p["group"])
    for k, (label, value) in enumerate([("받는 분", "김민지"), ("받는 계좌", "카카오뱅크 3333-12-****678"), ("출금 계좌", "토스뱅크 통장"),
                                        ("보낸 일시", "2026.10.10 13:05"), ("메모", "저녁값")]):
        kv(d, p, y + 80 + k * 100, label, value)
    d.rounded_rectangle((60, H - 330, W / 2 - 15, H - 180), radius=30, fill=(232, 243, 255))
    text(d, (W / 4 + 22, H - 255), "공유하기", 48, "sb", blue, "mm")
    d.rounded_rectangle((W / 2 + 15, H - 330, W - 60, H - 180), radius=30, fill=blue)
    text(d, (3 * W / 4 - 22, H - 255), "확인", 48, "b", WHITE, "mm")
    home_indicator(img, BLACK)
    status_bar(img, "1:06", BLACK, 68)
    return img, {"accept": [[E("김민지", 30000, "2026-10-10")]],
                 "note": "light Toss transfer-complete screen: 30,000원 sent to a person"}


def b3_07(rng):
    rows = [
        ("c", "이마트24 판교테크원점", "b", 46),
        ("c", "사업자 220-81-62517  대표 김성영", "r", 30),
        ("c", "경기도 성남시 분당구 분당내곡로 131", "r", 30),
        ("c", "TEL 031-8017-0024", "r", 30),
        ("gap", 16),
        ("l", "[판매] 2026-10-04 (일) 16:22  POS:01-0187", "r", 32),
        ("hr",),
        ("item", "상품명", "수량", "금액", 34),
        ("hr",),
        ("item", "제주삼다수 2L", "1", "1,300", 36),
        ("item", "신라면 멀티팩", "1", "4,480", 36),
        ("item", "바나나맛우유", "2", "3,400", 36),
        ("item", "허니버터칩 60g", "1", "1,700", 36),
        ("hr",),
        ("lr", "합계", "10,880", "b", 40),
        ("lr", "과세물품가액", "9,891", "r", 34),
        ("lr", "부가세", "989", "r", 34),
        ("lr", "받을금액", "10,880", "b", 40),
        ("hr",),
        ("lr", "신용카드", "10,880", "r", 34),
        ("l", "카드번호 5365-12**-****-4821", "r", 32),
        ("l", "승인번호 30017745  일시불", "r", 32),
        ("hr",),
        ("l", "이마트24 멤버십 적립 108P", "r", 32),
        ("c", "교환/환불은 구매 후 14일 이내", "r", 30),
    ]
    img = receipt_photo(receipt_paper(rows), rng, "wood", 2.3, 1.1)
    return img, receipt_key("이마트24 판교테크원점", "2026-10-04",
                            [("제주삼다수 2L", 1300), ("신라면 멀티팩", 4480), ("바나나맛우유", 3400), ("허니버터칩 60g", 1700)], 10880,
                            "convenience store receipt photo on wood: four lines (one with qty 2), tax lines, card and points")


def b3_08(rng):
    rows = [
        ("c", "카페 소담 연남점", "b", 46),
        ("c", "사업자 105-87-11234  대표 이소담", "r", 30),
        ("c", "서울특별시 마포구 연남로 23 1층", "r", 30),
        ("c", "TEL 02-332-1234", "r", 30),
        ("gap", 16),
        ("l", "주문번호 A-042", "b", 36),
        ("l", "2026.10.02 15:31", "r", 32),
        ("hr",),
        ("item", "메뉴", "수량", "금액", 34),
        ("hr",),
        ("item", "아메리카노(ICE)", "2", "9,000", 36),
        ("item", "카페라떼(HOT)", "1", "5,000", 36),
        ("item", "바스크 치즈케이크", "1", "6,500", 36),
        ("hr",),
        ("lr", "합계금액", "20,500", "b", 40),
        ("lr", "공급가액", "18,636", "r", 34),
        ("lr", "부가세", "1,864", "r", 34),
        ("hr",),
        ("lr", "신한카드", "20,500", "r", 34),
        ("l", "승인번호 18273645  일시불", "r", 32),
        ("gap", 20),
        ("c", "오늘도 좋은 하루 보내세요", "r", 30),
    ]
    img = receipt_photo(receipt_paper(rows), rng, "fabric", -3.1, 1.3, lo=150)
    return img, receipt_key("카페 소담 연남점", "2026-10-02",
                            [("아메리카노(ICE)", 9000), ("카페라떼(HOT)", 5000), ("바스크 치즈케이크", 6500)], 20500,
                            "cafe receipt photo on dark fabric: three lines (one with qty 2), supply value and VAT lines")


def b3_09(rng):
    rows = [
        ("c", "롯데슈퍼 망원점", "b", 46),
        ("c", "사업자 214-85-24928  대표 남창희", "r", 30),
        ("c", "서울특별시 마포구 망원로 61", "r", 30),
        ("gap", 16),
        ("l", "2026.10.09 19:12  POS 03  #2081", "r", 32),
        ("hr",),
        ("item", "상품명", "수량", "금액", 34),
        ("hr",),
        ("item", "서울우유 1L", "1", "2,980", 36),
        ("item", "계란 대란 15구", "1", "6,980", 36),
        ("sub", "(행사할인)", "-1,000", 34),
        ("item", "국산콩 두부 300g", "2", "3,600", 36),
        ("item", "대파 1단", "1", "2,490", 36),
        ("hr",),
        ("lr", "총 구매액", "16,050", "r", 36),
        ("lr", "할인 합계", "-1,000", "r", 36),
        ("lr", "결제 대상 금액", "15,050", "b", 40),
        ("lr", "면세물품가액", "15,050", "r", 34),
        ("hr",),
        ("lr", "신용카드", "15,050", "r", 34),
        ("l", "승인번호 77120934  일시불", "r", 32),
        ("l", "L.POINT 적립 75P", "r", 32),
    ]
    img = receipt_photo(receipt_paper(rows), rng, "desk", 1.4, 1.0, lo=160)
    store, d = "롯데슈퍼 망원점", "2026-10-09"
    key = receipt_key(store, d, [("서울우유 1L", 2980), ("계란 대란 15구", 6980), ("국산콩 두부 300g", 3600), ("대파 1단", 2490)], 15050,
                      "supermarket receipt photo on a desk with a (행사할인) -1,000 line under the eggs; printed line amounts, "
                      "or the eggs net of that discount")
    key["accept"].append([E(store, 2980, d, "서울우유 1L"), E(store, 5980, d, "계란 대란 15구"),
                          E(store, 3600, d, "국산콩 두부 300g"), E(store, 2490, d, "대파 1단")])
    return img, key


def b3_10(rng):
    p = pal(True)
    img = blank(p["bg"])
    d = ImageDraw.Draw(img)
    fg, sub = p["fg"], p["sub"]
    nav(d, p, "이용내역", right="필터")
    for k, label in enumerate(["국내", "해외"]):
        on = k == 0
        x0 = 48 + k * 220
        text(d, (x0 + 90, 380), label, 45, "b" if on else "m", fg if on else sub, "mm")
        if on:
            d.line((x0 + 40, 420, x0 + 140, 420), fill=fg, width=6)
    chevron(d, 330, 520, 18, sub, 6)
    text(d, (W / 2, 520), "2026년 10월", 51, "b", fg, "mm")
    chevron(d, W - 330, 520, 18, sub, 6, "right")
    rrect(img, (48, 600, W - 48, 860), 40, p["card"])
    text(d, (96, 660), "10월 이용금액", 42, "m", sub, "lm")
    text(d, (96, 750), "487,300원", 72, "b", fg, "lm")
    text(d, (96, 822), "신한카드 Deep Dream(1234)", 36, "r", sub, "lm")
    groups = [
        ("10.09 (금)", [("스타벅스 강남R점", "14:22 · 일시불", "5,400원"), ("쿠팡", "09:10 · 일시불", "23,900원")]),
        ("10.08 (목)", [("티머니 택시", "23:41 · 일시불", "12,300원"), ("세븐일레븐 역삼점", "18:05 · 일시불", "3,200원")]),
        ("10.07 (수)", [("롯데시네마 월드타워", "20:30 · 일시불", "28,000원")]),
        ("10.06 (화)", [("올리브영 강남타운점", "19:12 · 일시불", "18,700원")]),
    ]
    y = 920
    for date, rows in groups:
        text(d, (60, y + 30), date, 39, "sb", sub, "lm")
        y += 80
        for name, meta, amount in rows:
            text(d, (60, y + 36), name, 48, "sb", fg, "lm")
            text(d, (60, y + 100), meta, 36, "r", sub, "lm")
            text(d, (W - 60, y + 50), amount, 48, "b", fg, "rm")
            y += 150
        y += 20
    if y > H - 80:
        raise ValueError("card list overflows")
    home_indicator(img, WHITE)
    status_bar(img, "10:02", WHITE, 33)
    dd = {"10.09": "2026-10-09", "10.08": "2026-10-08", "10.07": "2026-10-07", "10.06": "2026-10-06"}
    entries = [E(name, int(amount[:-1].replace(",", "")), dd[date[:5]]) for date, rows in groups for name, _, amount in rows]
    return img, {"accept": [entries], "note": "dark card app usage list: six approvals over four days under a monthly usage total"}


def b3_11(rng):
    p = pal(False)
    img = blank(WHITE)
    d = ImageDraw.Draw(img)
    fg, sub = p["fg"], p["sub"]
    teal = (0, 130, 150)
    nav(d, p, "거래내역조회")
    text(d, (60, 400), "하늘 자유입출금", 45, "sb", fg, "lm")
    text(d, (60, 460), "110-482-339201", 39, "r", sub, "lm")
    rows = [  # oldest first: date, time, name, sub, delta
        ("10.06", "08:10", "SK텔레콤", "자동이체", -69800),
        ("10.07", "18:40", "GS25 역삼점", "체크카드", -3200),
        ("10.08", "00:01", "이자", "결산이자", 1234),
        ("10.09", "09:00", "(주)한빛소프트", "급여", 3250000),
        ("10.09", "12:00", "박정호", "이체 · 10월 월세", -550000),
        ("10.10", "11:20", "이서준", "입금", 15000),
        ("10.10", "13:05", "김민지", "이체", -30000),
    ]
    balance = 3284330
    start = balance - sum(r[4] for r in rows)
    if start < 0:
        raise ValueError("negative opening balance")
    bal, shown = start, []
    for r in rows:
        bal += r[4]
        shown.append(r + (bal,))
    text(d, (60, 580), "%s원" % format(balance, ","), 84, "b", fg, "lm")
    d.rounded_rectangle((60, 680, 560, 790), radius=24, fill=teal)
    text(d, (310, 735), "이체", 45, "b", WHITE, "mm")
    d.rounded_rectangle((600, 680, W - 60, 790), radius=24, fill=(240, 242, 245))
    text(d, (W / 2 + 290, 735), "계좌관리", 45, "sb", fg, "mm")
    d.rectangle((0, 840, W, 860), fill=p["group"])
    text(d, (60, 930), "1개월 · 전체 · 최신순", 39, "m", sub, "lm")
    y = 1000
    for date, tm, name, kind, delta, after in reversed(shown):
        text(d, (60, y + 40), date, 39, "m", sub, "lm")
        text(d, (60, y + 92), tm, 33, "r", sub, "lm")
        text(d, (230, y + 40), name, 48, "sb", fg, "lm")
        text(d, (230, y + 98), kind, 36, "r", sub, "lm")
        amount = "%s%s원" % ("+" if delta > 0 else "-", format(abs(delta), ","))
        text(d, (W - 60, y + 40), amount, 48, "b", (30, 110, 230) if delta > 0 else fg, "rm")
        text(d, (W - 60, y + 98), "잔액 %s원" % format(after, ","), 33, "r", sub, "rm")
        d.line((60, y + 150, W - 60, y + 150), fill=p["sep"], width=2)
        y += 172
    if y > H - 60:
        raise ValueError("bank list overflows")
    home_indicator(img, BLACK)
    status_bar(img, "3:15", BLACK, 49)
    entries = [E(name, -delta, "2026-%s" % date.replace(".", "-")) for date, _, name, _, delta in rows if delta < 0]
    return img, {"accept": [entries],
                 "note": "light bank transaction list: outgoing auto-debit, check card, rent transfer and a transfer to a person; incoming salary, interest and a repayment"}


def b3_12(rng):
    img = blank(BLACK)
    kakao_chat(img, True, "삼성카드", None, 3, [
        ("date", "2026년 10월 2일 금요일"),
        ("card", "삼성카드", "알림톡 도착", "[삼성카드] 이벤트 안내\n10월 한 달간 주말 외식 결제 시 최대 30,000원 캐시백!\n응모 기간: 10.01 (목) ~ 10.11 (일)", "응모하기", "오전 10:00"),
        ("date", "2026년 10월 11일 일요일"),
        ("card", "삼성카드", "알림톡 도착",
         "[삼성카드] 승인 안내\n고객명: 이*진\n카드: 삼성카드 taptap O(1234)\n승인금액: 64,000원\n결제방법: 일시불\n가맹점: 롯데월드 어드벤처\n승인일시: 10/11 11:20\n누적 이용금액: 1,096,700원",
         "이용내역 확인", "오전 11:20"),
    ])
    status_bar(img, "11:22", WHITE, 74)
    return img, {"accept": [[E("롯데월드 어드벤처", 64000, "2026-10-11")]],
                 "note": "dark KakaoTalk channel chat: one Samsung Card approval 알림톡 under an older cashback promotion"}


CASES = [
    ("b1-01", "B1", b1_01), ("b1-02", "B1", b1_02), ("b1-03", "B1", b1_03), ("b1-04", "B1", b1_04),
    ("b1-05", "B1", b1_05), ("b1-06", "B1", b1_06), ("b1-07", "B1", b1_07), ("b1-08", "B1", b1_08),
    ("b1-09", "B1", b1_09), ("b1-10", "B1", b1_10), ("b1-11", "B1", b1_11), ("b1-12", "B1", b1_12),
    ("b2-01", "B2", b2_01), ("b2-02", "B2", b2_02), ("b2-03", "B2", b2_03), ("b2-04", "B2", b2_04),
    ("b2-05", "B2", b2_05), ("b2-06", "B2", b2_06), ("b2-07", "B2", b2_07), ("b2-08", "B2", b2_08),
    ("b3-01", "B3", b3_01), ("b3-02", "B3", b3_02), ("b3-03", "B3", b3_03), ("b3-04", "B3", b3_04),
    ("b3-05", "B3", b3_05), ("b3-06", "B3", b3_06), ("b3-07", "B3", b3_07), ("b3-08", "B3", b3_08),
    ("b3-09", "B3", b3_09), ("b3-10", "B3", b3_10), ("b3-11", "B3", b3_11), ("b3-12", "B3", b3_12),
]
PHOTOS = {"b3-07", "b3-08", "b3-09"}


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: gen_holdout3.py <out_dir>")
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    truth = []
    for cid, cat, build in CASES:
        img, key = build(random.Random("holdout3/" + cid))
        if cid in PHOTOS:
            name = cid + ".jpg"
            img.save(os.path.join(out, name), "JPEG", quality=88)
        else:
            if img.size != (W, H):
                raise ValueError("%s: screenshot size %r" % (cid, img.size))
            name = cid + ".png"
            img.save(os.path.join(out, name), "PNG")
        truth.append({"id": cid, "cat": cat, "file": name, "accept": key["accept"],
                      "lenient": key.get("lenient", []), "note": key["note"]})
    with open(os.path.join(out, "truth.json"), "w", encoding="utf-8") as fh:
        json.dump(truth, fh, ensure_ascii=False, indent=1)
        fh.write("\n")


if __name__ == "__main__":
    main()
