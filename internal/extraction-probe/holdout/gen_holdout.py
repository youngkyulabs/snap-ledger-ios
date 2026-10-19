#!/usr/bin/env python3
"""Render the held-out extraction corpus: every image plus truth.json, deterministically.

Usage: python3 gen_holdout.py <out_dir> [case_id ...]
"""
from __future__ import annotations

import datetime
import json
import os
import random
import re
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont, ImageOps

FONT_PATH = "/System/Library/Fonts/AppleSDGothicNeo.ttc"
FACES = {"r": 0, "m": 2, "sb": 4, "b": 6}
SW, SH = 1179, 2556
YEAR, MONTH = 2026, 10
WEEKDAYS = "월화수목금토일"
WHITE, BLACK = (255, 255, 255), (0, 0, 0)

_fonts: dict = {}


def font(size, weight="r"):
    key = (int(size), weight)
    if key not in _fonts:
        _fonts[key] = ImageFont.truetype(FONT_PATH, int(size), index=FACES[weight])
    return _fonts[key]


def textlen(s, size, weight="r"):
    return font(size, weight).getlength(s)


def iso(day):
    return f"{YEAR}-{MONTH:02d}-{day:02d}"


def weekday(day):
    return WEEKDAYS[datetime.date(YEAR, MONTH, day).weekday()]


def won(n):
    return f"{n:,}"


def entry(m, a, d="", i=None):
    return {"m": m, "i": i, "a": int(a), "d": d}


def mix(c1, c2, k):
    return tuple(int(round(a + (b - a) * k)) for a, b in zip(c1, c2))


def scale(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c)


def wrap(s, size, weight, maxw):
    """Break text at spaces, or inside a run that is wider than maxw."""
    f = font(size, weight)
    out = []
    for para in s.split("\n"):
        line = ""
        for word in re.split(r"(\s+)", para):
            if not word:
                continue
            if f.getlength(line + word) <= maxw:
                line += word
                continue
            if line.strip():
                out.append(line.rstrip())
                line = word.lstrip()
            else:
                line = word
            while f.getlength(line) > maxw:
                k = len(line)
                while k > 1 and f.getlength(line[:k]) > maxw:
                    k -= 1
                out.append(line[:k])
                line = line[k:]
        out.append(line.rstrip())
    return out


# ---------------------------------------------------------------- screenshots

LIGHT = {
    "dark": False, "bg": (255, 255, 255), "grouped": (242, 242, 247), "card": (255, 255, 255),
    "text": (0, 0, 0), "text2": (60, 60, 67), "sub": (128, 128, 133), "sep": (222, 222, 227),
    "blue": (0, 122, 255), "red": (236, 52, 52), "fill": (235, 235, 240),
    "up": (230, 54, 54), "down": (38, 110, 235),
}
DARK = {
    "dark": True, "bg": (0, 0, 0), "grouped": (0, 0, 0), "card": (28, 28, 30),
    "text": (255, 255, 255), "text2": (226, 226, 232), "sub": (146, 146, 152), "sep": (56, 56, 60),
    "blue": (64, 156, 255), "red": (255, 90, 80), "fill": (44, 44, 48),
    "up": (255, 82, 82), "down": (80, 150, 255),
}


class Screen:
    """A 1179x2556 iPhone screenshot canvas."""

    def __init__(self, theme, bg=None):
        self.t = theme
        self.img = Image.new("RGB", (SW, SH), self.c(bg or "bg"))
        self.d = ImageDraw.Draw(self.img)

    def c(self, color):
        if color is None:
            return self.t["text"]
        if isinstance(color, str):
            return self.t[color]
        return color

    def text(self, x, y, s, size, weight="r", fill=None, anchor="ls"):
        self.d.text((x, y), s, font=font(size, weight), fill=self.c(fill), anchor=anchor)
        return textlen(s, size, weight)

    def box(self, x0, y0, x1, y1, fill, r=0, outline=None, width=1):
        self.d.rounded_rectangle((x0, y0, x1, y1), radius=r, fill=self.c(fill) if fill else None,
                                 outline=self.c(outline) if outline else None, width=width)

    def hline(self, y, x0=63, x1=SW, fill="sep", width=2):
        self.d.line((x0, y, x1, y), fill=self.c(fill), width=width)

    def glass(self, x0, y0, x1, y1, rgba, r, blur=0):
        if blur:
            region = (int(x0), int(y0), int(x1), int(y1))
            self.img.paste(self.img.crop(region).filter(ImageFilter.GaussianBlur(blur)), region[:2])
        layer = Image.new("RGBA", self.img.size, (0, 0, 0, 0))
        ImageDraw.Draw(layer).rounded_rectangle((x0, y0, x1, y1), radius=r, fill=rgba)
        self.img = Image.alpha_composite(self.img.convert("RGBA"), layer).convert("RGB")
        self.d = ImageDraw.Draw(self.img)

    def chevron_left(self, x, y, fill="blue", size=27, width=7):
        self.d.line((x + size, y - size, x, y, x + size, y + size), fill=self.c(fill), width=width, joint="curve")

    def chevron_right(self, x, y, fill="sub", size=14, width=4):
        self.d.line((x - size, y - size, x, y, x - size, y + size), fill=self.c(fill), width=width, joint="curve")

    def cross(self, cx, cy, r=24, fill=None, width=6):
        c = self.c(fill)
        self.d.line((cx - r, cy - r, cx + r, cy + r), fill=c, width=width)
        self.d.line((cx - r, cy + r, cx + r, cy - r), fill=c, width=width)

    def check(self, cx, cy, r, fill, width=12):
        self.d.line((cx - r * 0.45, cy, cx - r * 0.1, cy + r * 0.35, cx + r * 0.48, cy - r * 0.3),
                    fill=self.c(fill), width=width, joint="curve")

    def magnifier(self, cx, cy, fill=None):
        c = self.c(fill)
        self.d.ellipse((cx - 24, cy - 24, cx + 16, cy + 16), outline=c, width=6)
        self.d.line((cx + 12, cy + 12, cx + 30, cy + 30), fill=c, width=7)

    def burger(self, cx, cy, fill=None):
        for dy in (-18, 0, 18):
            self.d.line((cx - 26, cy + dy, cx + 26, cy + dy), fill=self.c(fill), width=6)

    def status_bar(self, time=None, carrier=None, fg=None, battery=0.78, island=True):
        fg = self.c(fg or "text")
        if time:
            self.text(178, 100, time, 51, "sb", fg, anchor="ms")
        if carrier:
            self.text(84, 100, carrier, 45, "sb", fg)
        if island:
            self.box(SW // 2 - 189, 33, SW // 2 + 189, 144, BLACK, r=56)
        x = 884
        for k, h in enumerate((13, 20, 28, 36)):
            self.box(x + k * 17, 99 - h, x + k * 17 + 11, 99, fg, r=3)
        cx, cy = 1000, 101
        for r in (40, 27):
            self.d.arc((cx - r, cy - r, cx + r, cy + r), 226, 314, fill=fg, width=8)
        self.d.pieslice((cx - 14, cy - 14, cx + 14, cy + 14), 226, 314, fill=fg)
        dim = mix(fg, self.img.getpixel((1080, 86)), 0.55)
        self.d.rounded_rectangle((1040, 70, 1116, 103), radius=11, outline=dim, width=3)
        self.box(1046, 76, 1046 + int(64 * battery), 97, fg, r=6)
        self.box(1120, 81, 1125, 93, dim, r=2)

    def home_indicator(self, fill=None):
        self.box(SW // 2 - 210, SH - 36, SW // 2 + 210, SH - 21, self.c(fill or "text"), r=8)

    def nav(self, title, y=232, back=True, back_label=None, fill="blue", size=51):
        if back:
            self.chevron_left(48, y - 17, fill)
            if back_label:
                self.text(96, y, back_label, 51, "r", fill)
        if title:
            self.text(SW // 2, y, title, size, "sb", anchor="ms")

    def icon(self, x, y, s, bg, label="", fg=WHITE, size=None, weight="b", r=None):
        self.box(x, y, x + s, y + s, bg, r=r if r is not None else int(s * 0.23))
        if label:
            size = size or int(s * (0.4 if len(label) <= 2 else 0.28))
            self.text(x + s / 2, y + s / 2, label, size, weight, fg, anchor="mm")

    def tag(self, x, y, s, fill, fg, size=36):
        w = textlen(s, size, "sb") + 36
        self.box(x, y, x + w, y + size + 26, fill, r=14)
        self.text(x + w / 2, y + (size + 26) / 2, s, size, "sb", fg, anchor="mm")
        return x + w

    def kv(self, y, label, value, size=45, lw="r", vw="sb", lfill="sub", vfill=None, x0=63, x1=SW - 63):
        self.text(x0, y, label, size, lw, lfill)
        self.text(x1, y, value, size, vw, vfill, anchor="rs")


def text_block(scr, x, y, rows, size, weight, fill, lh):
    for k, row in enumerate(rows):
        scr.text(x, y + k * lh, row, size, weight, fill, anchor="la")
    return y + (len(rows) - 1) * lh + size


def notification(scr, x, y, w, icon, title, body, when, dark, body_size=45):
    """iOS notification card; icon = (bg, label). Returns the bottom y."""
    pad, s = 40, 114
    tx = x + pad + s + 34
    maxw = x + w - pad - tx
    rows = []
    for para in body:
        rows += wrap(para, body_size, "r", maxw)
    lh = int(body_size * 1.3)
    h = max(pad + 56 + (len(rows) - 1) * lh + body_size + pad, s + 2 * pad)
    fill = (38, 38, 40, 215) if dark else (246, 246, 248, 222)
    scr.glass(x, y, x + w, y + h, fill, 66, blur=30)
    fg = WHITE if dark else BLACK
    sub = (172, 172, 178) if dark else (104, 104, 110)
    bg, label = icon
    scr.icon(x + pad, y + pad, s, bg, label)
    scr.text(tx, y + pad, title, 45, "sb", fg, anchor="la")
    if when:
        scr.text(x + w - pad, y + pad + 2, when, 39, "r", sub, anchor="ra")
    text_block(scr, tx, y + pad + 56, rows, body_size, "r", fg, lh)
    return y + h


def wallpaper(top, bottom, blobs=()):
    g = Image.linear_gradient("L").resize((SW, SH), Image.BILINEAR)
    img = ImageOps.colorize(g, top, bottom)
    for color, cx, cy, r, k in blobs:
        m = Image.radial_gradient("L").resize((2 * r, 2 * r), Image.BILINEAR).point(lambda v, k=k: (255 - v) * k)
        img.paste(Image.new("RGB", (2 * r, 2 * r), color), (cx - r, cy - r), m)
    return img.filter(ImageFilter.GaussianBlur(40))


def lock_screen(theme, wall, date_label, clock, notes, carrier="SKT", top=1110):
    scr = Screen(theme)
    scr.img.paste(wall)
    scr.status_bar(carrier=carrier, fg=WHITE)
    scr.text(SW // 2, 352, date_label, 66, "sb", WHITE, anchor="ms")
    scr.text(SW // 2, 652, clock, 300, "b", WHITE, anchor="ms")
    y = top
    for icon, title, body, when in notes:
        y = notification(scr, 39, y, SW - 78, icon, title, body, when, theme["dark"]) + 24
    assert y < 2250, f"notifications overflow the lock screen controls ({y})"
    for cx in (168, SW - 168):
        scr.glass(cx - 76, 2262, cx + 76, 2414, (20, 20, 24, 110), 76)
    scr.box(156, 2300, 180, 2376, WHITE, r=8)
    scr.box(SW - 206, 2314, SW - 130, 2364, WHITE, r=10)
    scr.d.ellipse((SW - 182, 2324, SW - 154, 2352), fill=(60, 60, 64))
    scr.home_indicator(WHITE)
    return scr


HOME_APPS = [
    ("메시지", (52, 199, 89)), ("캘린더", (250, 250, 250)), ("사진", (245, 245, 245)), ("카메라", (120, 120, 126)),
    ("날씨", (64, 140, 230)), ("시계", (24, 24, 26)), ("지도", (110, 190, 120)), ("메모", (250, 205, 40)),
    ("카카오톡", (254, 229, 0)), ("토스", (24, 100, 245)), ("네이버", (3, 199, 90)), ("쿠팡", (245, 245, 245)),
    ("배달의민족", (42, 193, 188)), ("유튜브", (240, 240, 240)), ("당근", (255, 138, 61)), ("카카오맵", (60, 140, 250)),
    ("설정", (130, 130, 136)), ("App Store", (20, 130, 250)), ("건강", (245, 245, 245)), ("지갑", (24, 24, 26)),
]
DOCK_APPS = [(52, 199, 89), (20, 130, 250), (52, 199, 89), (250, 45, 72)]


def home_screen(theme, wall, time):
    scr = Screen(theme)
    scr.img.paste(wall)
    scr.status_bar(time, fg=WHITE)
    xs, s = (81, 360, 639, 918), 180
    for k, (name, color) in enumerate(HOME_APPS):
        x, y = xs[k % 4], 196 + (k // 4) * 300
        scr.icon(x, y, s, color)
        ring = mix(color, WHITE if sum(color) < 600 else BLACK, 0.6)
        scr.d.ellipse((x + 58, y + 58, x + 122, y + 122), outline=ring, width=10)
        scr.text(x + s / 2, y + s + 50, name, 36, "r", WHITE, anchor="ms")
    scr.glass(SW // 2 - 118, 1990, SW // 2 + 118, 2066, (255, 255, 255, 60), 38)
    scr.text(SW // 2, 2028, "검색", 39, "sb", WHITE, anchor="mm")
    scr.glass(30, 2170, SW - 30, 2470, (255, 255, 255, 52), 110)
    for k, color in enumerate(DOCK_APPS):
        scr.icon(xs[k], 2230, s, color)
        scr.d.ellipse((xs[k] + 58, 2288, xs[k] + 122, 2352), outline=WHITE, width=10)
    scr.home_indicator(WHITE)
    return scr


def sms_screen(theme, time, sender, msgs):
    scr = Screen(theme)
    scr.status_bar(time)
    scr.chevron_left(48, 250, "blue")
    cx, av = SW // 2, 150
    avatar = Image.new("RGB", (av, av), (164, 168, 178) if not theme["dark"] else (100, 102, 110))
    ad = ImageDraw.Draw(avatar)
    ad.ellipse((av // 2 - 30, 28, av // 2 + 30, 88), fill=WHITE)
    ad.ellipse((av // 2 - 58, 98, av // 2 + 58, 210), fill=WHITE)
    mask = Image.new("L", (av, av), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, av - 1, av - 1), fill=255)
    scr.img.paste(avatar, (cx - av // 2, 172), mask)
    w = scr.text(cx, 380, sender, 39, "r", anchor="ms")
    scr.chevron_right(cx + w / 2 + 34, 367, "sub", 10, 4)
    scr.hline(420, 0, SW, "sep", 1)
    bubble = (233, 233, 235) if not theme["dark"] else (38, 38, 41)
    y = 470
    for kind, s in msgs:
        if kind == "stamp":
            scr.text(cx, y + 50, s, 36, "sb", "sub", anchor="ms")
            y += 86
            continue
        rows = wrap(s, 51, "r", 760)
        lh = 66
        bw = max(textlen(r, 51) for r in rows) + 84
        bh = (len(rows) - 1) * lh + 51 + 52
        scr.box(42, y, 42 + bw, y + bh, bubble, r=54)
        text_block(scr, 84, y + 24, rows, 51, "r", "text", lh)
        y += bh + 22
    scr.box(42, SH - 190, 140, SH - 92, "fill", r=49)
    scr.text(91, SH - 141, "+", 66, "r", "sub", anchor="mm")
    scr.box(168, SH - 190, SW - 42, SH - 92, None, r=49, outline="sep", width=3)
    scr.text(210, SH - 141, "문자 메시지", 45, "r", "sub", anchor="lm")
    scr.home_indicator()
    return scr


KAKAO_BG = {False: (186, 206, 224), True: (31, 34, 39)}


def kakao_screen(dark, time, title, count, items):
    theme = DARK if dark else LIGHT
    scr = Screen(theme, bg=KAKAO_BG[dark])
    scr.status_bar(time)
    scr.chevron_left(48, 232, "text")
    w = scr.text(118, 250, title, 51, "sb")
    if count:
        scr.text(118 + w + 20, 250, str(count), 45, "r", (110, 118, 128) if not dark else "sub")
    scr.magnifier(SW - 190, 226, "text")
    scr.burger(SW - 76, 230, "text")
    y = 330
    for draw in items:
        y = draw(scr, y, dark)
    assert y < SH - 230, f"chat overflows the input bar ({y})"
    bar = (255, 255, 255) if not dark else (44, 46, 50)
    scr.box(0, SH - 230, SW, SH, bar)
    scr.text(70, SH - 150, "+", 72, "r", "sub", anchor="mm")
    scr.box(130, SH - 196, SW - 130, SH - 104, (240, 240, 242) if not dark else (60, 62, 66), r=46)
    scr.home_indicator()
    return scr


def k_date(label):
    def draw(scr, y, dark):
        w = textlen(label, 36) + 70
        scr.glass(SW / 2 - w / 2, y + 16, SW / 2 + w / 2, y + 84,
                  (40, 50, 60, 60) if not dark else (255, 255, 255, 26), 34)
        scr.text(SW / 2, y + 50, label, 36, "r", WHITE if not dark else (200, 200, 204), anchor="mm")
        return y + 118
    return draw


def kakao_bubble(scr, x, y, text, dark, mine=False, size=48, maxw=690):
    rows = wrap(text, size, "r", maxw)
    lh = int(size * 1.34)
    bw = int(max(textlen(r, size) for r in rows)) + 64
    bh = (len(rows) - 1) * lh + size + 50
    if mine:
        fill, fg, x = (254, 229, 0), BLACK, x - bw
    else:
        fill, fg = ((255, 255, 255), BLACK) if not dark else ((58, 61, 66), (236, 236, 238))
    scr.box(x, y, x + bw, y + bh, fill, r=36)
    text_block(scr, x + 32, y + 23, rows, size, "r", fg, lh)
    return y + bh, x, x + bw


def k_in(name, avatar, parts, when):
    """Incoming messages; parts are strings (bubbles) or card drawers fn(scr, x, y, dark) -> (bottom, right)."""
    def draw(scr, y, dark):
        bg, label = avatar
        scr.icon(30, y, 112, bg, label, fg=BLACK if bg == (254, 229, 0) else WHITE, r=42)
        scr.text(168, y + 4, name, 39, "r", (70, 80, 90) if not dark else (190, 190, 196), anchor="la")
        y += 60
        for k, p in enumerate(parts):
            if callable(p):
                bottom, right = p(scr, 168, y, dark)
            else:
                bottom, _, right = kakao_bubble(scr, 168, y, p, dark)
            if k == len(parts) - 1 and when:
                scr.text(right + 14, bottom - 4, when, 33, "r", (90, 100, 112) if not dark else (150, 150, 156))
            y = bottom + 14
        return y + 26
    return draw


def k_me(text, when):
    def draw(scr, y, dark):
        bottom, left, _ = kakao_bubble(scr, SW - 36, y, text, dark, mine=True)
        scr.text(left - 14, bottom - 4, when, 33, "r", (90, 100, 112) if not dark else (150, 150, 156), anchor="rs")
        return bottom + 40
    return draw


def alimtalk(channel, lines, button=None, w=780):
    """KakaoTalk business message: yellow band, white body, optional button."""
    def draw(scr, x, y, dark):
        body_bg = WHITE if not dark else (52, 55, 60)
        fg = BLACK if not dark else (236, 236, 238)
        rows = []
        for line in lines:
            rows += wrap(line, 45, "r", w - 72)
        lh = 62
        band = 96
        h = band + 40 + (len(rows) - 1) * lh + 45 + 44 + (130 if button else 0)
        scr.box(x, y, x + w, y + h, (254, 229, 0), r=34)
        scr.box(x, y + band, x + w, y + h, body_bg, r=34)
        scr.box(x, y + band, x + w, y + band + 40, body_bg)
        scr.text(x + 36, y + band / 2, "알림톡 도착", 39, "b", (58, 29, 29), anchor="lm")
        scr.text(x + w - 36, y + band / 2, channel, 33, "r", (90, 70, 40), anchor="rm")
        text_block(scr, x + 36, y + band + 40, rows, 45, "r", fg, lh)
        if button:
            by = y + h - 130
            scr.box(x + 30, by, x + w - 30, by + 100, (240, 240, 242) if not dark else (70, 73, 78), r=18)
            scr.text(x + w / 2, by + 50, button, 42, "sb", fg, anchor="mm")
        return y + h, x + w
    return draw


def pay_card(header, title, amount, rows, w=780):
    """Kakao Pay style message card."""
    def draw(scr, x, y, dark):
        bg = WHITE if not dark else (52, 55, 60)
        fg = BLACK if not dark else (236, 236, 238)
        sub = (120, 120, 126) if not dark else (160, 160, 166)
        h = 270 + len(rows) * 62 + 30
        scr.box(x, y, x + w, y + h, bg, r=34)
        scr.text(x + 40, y + 40, header, 36, "sb", sub, anchor="la")
        scr.text(x + 40, y + 96, title, 48, "b", fg, anchor="la")
        scr.text(x + 40, y + 160, amount, 76, "b", fg, anchor="la")
        ry = y + 270
        for label, value in rows:
            scr.text(x + 40, ry, label, 39, "r", sub, anchor="la")
            scr.text(x + 250, ry, value, 39, "r", fg, anchor="la")
            ry += 62
        return y + h, x + w
    return draw


# ---------------------------------------------------------------- receipts

PAPER = (247, 246, 241)


class Receipt:
    """Thermal receipt drawn top to bottom on a tall strip; finish() crops it."""

    def __init__(self, rng, width=920, size=30, margin=44, paper=PAPER):
        self.rng = rng
        self.w, self.size, self.margin = width, size, margin
        self.img = Image.new("RGB", (width, 9000), paper)
        self.d = ImageDraw.Draw(self.img)
        self.y = margin + 16

    def ink(self):
        v = self.rng.randint(24, 56)
        return (v, v, v + 3)

    def gap(self, px=None):
        self.y += self.size // 2 if px is None else px

    def row(self, cells, size=None, weight="r", lh=1.42):
        """cells: [(text, x, align)]; x < 0 counts from the right edge; align is l/r/c."""
        size = size or self.size
        ink = self.ink()
        base = self.y + int(size * 1.02)
        for s, x, align in cells:
            if x < 0:
                x = self.w + x
            anchor = {"l": "ls", "r": "rs", "c": "ms"}[align]
            self.d.text((x, base), s, font=font(size, weight), fill=ink, anchor=anchor)
        self.y += int(size * lh)

    def center(self, s, size=None, weight="r", lh=1.42):
        self.row([(s, self.w // 2, "c")], size, weight, lh)

    def left(self, s, size=None, weight="r", indent=0, lh=1.42):
        self.row([(s, self.margin + indent, "l")], size, weight, lh)

    def lr(self, left, right, size=None, weight="r", indent=0, lh=1.42):
        self.row([(left, self.margin + indent, "l"), (right, -self.margin, "r")], size, weight, lh)

    def rule(self, ch="-"):
        n = int((self.w - 2 * self.margin) / textlen(ch, self.size))
        self.row([(ch * n, self.w // 2, "c")], lh=1.2)

    def barcode(self, digits, height=96):
        x, x1 = self.margin * 3, self.w - self.margin * 3
        top = self.y + 8
        ink = self.ink()
        while x < x1:
            bw = self.rng.choice((2, 2, 3, 4, 5, 7))
            self.d.rectangle((x, top, min(x + bw, x1) - 1, top + height), fill=ink)
            x += bw + self.rng.choice((2, 3, 3, 4, 6))
        self.y += height + 16
        self.center(digits, int(self.size * 0.8))

    def finish(self):
        return self.img.crop((0, 0, self.w, self.y + self.margin + 24))


def receipt_items(store, items, day):
    """items: [(name, unit, qty, ...)] -> one entry per line with the printed line amount."""
    return [entry(store, unit * qty, iso(day), name) for name, unit, qty, *_ in items]


# ---------------------------------------------------------------- photos

def noise(rng, w, h):
    return Image.frombytes("L", (w, h), rng.randbytes(w * h))


def smooth_noise(rng, w, h, cell):
    return noise(rng, max(2, w // cell), max(2, h // cell)).resize((w, h), Image.BICUBIC)


def bg_wood(rng, size, base, vertical=False):
    w, h = size
    if vertical:
        w, h = h, w
    grain = noise(rng, 4, max(8, h // 5)).resize((w, h), Image.BICUBIC)
    knots = smooth_noise(rng, w, h, 90)
    g = ImageOps.autocontrast(Image.blend(grain, knots, 0.3), cutoff=1)
    img = ImageOps.colorize(g, scale(base, 0.7), scale(base, 1.2))
    d = ImageDraw.Draw(img)
    y = rng.randint(60, 300)
    while y < h:
        d.line((0, y, w, y), fill=scale(base, 0.42), width=5)
        y += rng.randint(380, 560)
    if vertical:
        img = img.transpose(Image.ROTATE_90)
    return img.filter(ImageFilter.GaussianBlur(0.7))


def bg_cloth(rng, size, base, pitch=6):
    w, h = size
    a = Image.new("L", (w, h), 128)
    da = ImageDraw.Draw(a)
    for x in range(0, w, pitch):
        da.line((x, 0, x, h), fill=rng.randint(70, 190), width=pitch // 2)
    b = Image.new("L", (w, h), 128)
    db = ImageDraw.Draw(b)
    for y in range(0, h, pitch):
        db.line((0, y, w, y), fill=rng.randint(70, 190), width=pitch // 2)
    weave = Image.blend(a, b, 0.5)
    wrinkles = ImageOps.autocontrast(smooth_noise(rng, w, h, 150))
    g = Image.blend(weave, wrinkles, 0.55)
    return ImageOps.colorize(g, scale(base, 0.72), scale(base, 1.12)).filter(ImageFilter.GaussianBlur(0.6))


def bg_gingham(rng, size, color, cell=118):
    w, h = size
    v = Image.new("L", (w, h), 0)
    dv = ImageDraw.Draw(v)
    for x in range(0, w, cell * 2):
        dv.rectangle((x, 0, x + cell - 1, h), fill=128)
    hz = Image.new("L", (w, h), 0)
    dh = ImageDraw.Draw(hz)
    for y in range(0, h, cell * 2):
        dh.rectangle((0, y, w, y + cell - 1), fill=127)
    img = ImageOps.colorize(ImageChops.add(v, hz), (236, 232, 224), color)
    tex = bg_cloth(rng, size, (220, 220, 220), pitch=5).convert("L").point(lambda p: 150 + p * 105 // 255)
    return ImageChops.multiply(img, Image.merge("RGB", (tex, tex, tex)))


def bg_marble(rng, size):
    w, h = size
    clouds = ImageOps.autocontrast(smooth_noise(rng, w, h, 110))
    img = ImageOps.colorize(clouds, (200, 200, 204), (242, 241, 240))
    veins = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(veins)
    for _ in range(7):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        dx, dy = rng.uniform(-1, 1), rng.uniform(-1, 1)
        pts = []
        for _ in range(90):
            dx += rng.uniform(-0.35, 0.35)
            dy += rng.uniform(-0.35, 0.35)
            x += dx * 18
            y += dy * 18
            pts.append((x, y))
        d.line(pts, fill=rng.randint(60, 140), width=rng.randint(2, 5))
    veins = veins.filter(ImageFilter.GaussianBlur(2.5))
    return Image.composite(Image.new("RGB", (w, h), (120, 120, 126)), img, veins)


def bg_plain(rng, size, base, grain=10):
    w, h = size
    fine = noise(rng, w, h).filter(ImageFilter.GaussianBlur(1.2))
    blotch = ImageOps.autocontrast(smooth_noise(rng, w, h, 200))
    g = Image.blend(ImageOps.autocontrast(fine), blotch, 0.5)
    return ImageOps.colorize(g, scale(base, 1 - grain / 100), scale(base, 1 + grain / 100))


def lighting(rng, size, depth):
    w, h = size
    g = Image.radial_gradient("L").resize((w * 2, h * 2), Image.BILINEAR)
    cx, cy = int(w * rng.uniform(0.3, 0.7)), int(h * rng.uniform(0.15, 0.55))
    m = g.crop((w - cx, h - cy, 2 * w - cx, 2 * h - cy)).point(lambda v: 255 - v * depth)
    return Image.merge("RGB", (m, m, m))


def cast_shadow(rng, size, depth):
    """A soft shadow (phone or hand) over one side of the frame."""
    w, h = size
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    side = rng.choice(("left", "right", "bottom"))
    if side == "left":
        d.polygon(((0, h * 0.35), (w * 0.3, h * 0.55), (w * 0.22, h), (0, h)), fill=255)
    elif side == "right":
        d.polygon(((w, h * 0.5), (w * 0.72, h * 0.68), (w * 0.8, h), (w, h)), fill=255)
    else:
        d.polygon(((0, h * 0.86), (w, h * 0.8), (w, h), (0, h)), fill=255)
    m = m.filter(ImageFilter.GaussianBlur(min(w, h) * 0.07)).point(lambda v: 255 - v * depth)
    return Image.merge("RGB", (m, m, m))


def photograph(paper, rng, background, angle, blur=0.9, light=0.3, shadow=0.2,
               cast=(1.0, 0.975, 0.93)):
    """Place a receipt on a surface, rotate it, and add lighting, shadow and blur."""
    pw, ph = paper.size
    tex = ImageOps.autocontrast(smooth_noise(rng, pw, ph, 60)).point(lambda v: 238 + v * 17 // 255)
    paper = ImageChops.multiply(paper, Image.merge("RGB", (tex, tex, tex)))
    rot = paper.convert("RGBA").rotate(angle, resample=Image.BICUBIC, expand=True)
    cw, ch = rot.width + int(pw * 0.4) + 140, rot.height + int(ph * 0.1) + 180
    if ch < cw * 4 // 3:
        ch = cw * 4 // 3
    else:
        cw = max(cw, ch * 3 // 4)
    size = (cw, ch)
    canvas = background(rng, size).convert("RGBA")
    ox = (cw - rot.width) // 2 + rng.randint(-40, 40)
    oy = (ch - rot.height) // 2 + rng.randint(-30, 30)
    shade = Image.new("L", size, 0)
    shade.paste(rot.split()[3], (ox + 12, oy + 18))
    shade = shade.filter(ImageFilter.GaussianBlur(24)).point(lambda v: v * 0.5)
    canvas = Image.composite(Image.new("RGBA", size, (0, 0, 0, 255)), canvas, shade)
    canvas.alpha_composite(rot, (ox, oy))
    img = ImageChops.multiply(canvas.convert("RGB"), lighting(rng, size, light))
    if shadow:
        img = ImageChops.multiply(img, cast_shadow(rng, size, shadow))
    img = Image.merge("RGB", [ch.point(lambda v, k=k: min(255, v * k)) for ch, k in zip(img.split(), cast)])
    return img.filter(ImageFilter.GaussianBlur(blur))


def receipt_result(paper, rng, background, angle, store, items, day, total, **kw):
    """Photo of a paper receipt: line items are the answer, the paid total is the lenient answer."""
    return {"img": photograph(paper, rng, background, angle, **kw), "ext": "jpg", "receipt": True,
            "accept": [receipt_items(store, items, day)], "lenient": [[entry(store, total, iso(day))]]}


def screen_result(scr, *accept):
    return {"img": scr.img, "ext": "png", "accept": list(accept) or [[]], "lenient": []}


# ---------------------------------------------------------------- cases

CASES = []


def case(cid, cat, note):
    def register(fn):
        CASES.append((cid, cat, note, fn))
        return fn
    return register


# S1: names and amounts in separate columns -----------------------------------

@case("s1-01", "S1", "E-mart receipt photo on a wood table: 10 items in unit/qty/amount columns, "
      "tax-exempt and VAT block, card approval, Shinsegae points")
def s1_01(rng):
    store, day = "이마트 왕십리점", 9
    items = [
        ("매일우유 900ml", 2650, 1, True),
        ("풀무원 부침두부 300g", 2180, 2, False),
        ("CJ 햇반 210g*12", 13980, 1, False),
        ("농심 신라면 5입", 4480, 1, False),
        ("대파 1단", 2980, 1, True),
        ("깐양파 1kg", 4990, 1, True),
        ("노브랜드 감자칩 110g", 1580, 3, False),
        ("한우 국거리 300g", 16800, 1, True),
        ("무항생제 계란 30구", 8990, 1, True),
        ("코카콜라 500ml", 2280, 2, False),
    ]
    exempt = sum(u * q for _, u, q, ex in items if ex)
    taxed = sum(u * q for _, u, q, ex in items if not ex)
    vat = round(taxed / 11)
    total = exempt + taxed
    r = Receipt(rng, width=920, size=30)
    r.center("E-MART", 64, "b")
    r.center(store, 38, "sb")
    r.center("(주)이마트 206-86-50913 대표 한채양", 26)
    r.center("서울 성동구 왕십리광장로 17  T.02-2200-1234", 26)
    r.gap(10)
    r.lr(f"[구매] {iso(day)} 18:32", "POS:0012-4471", 28)
    r.rule()
    r.row([("상 품 명", r.margin, "l"), ("단 가", 600, "r"), ("수량", 700, "r"), ("금 액", -r.margin, "r")])
    r.rule()
    for k, (name, unit, qty, ex) in enumerate(items, 1):
        r.row([(f"{k:02d} {'*' if ex else ' '}{name}", r.margin, "l"), (won(unit), 600, "r"),
               (str(qty), 700, "r"), (won(unit * qty), -r.margin, "r")])
    r.rule()
    r.lr("        총 품목 수량", str(sum(q for _, _, q, _ in items)))
    r.lr("     (*) 면 세  물 품", won(exempt))
    r.lr("         과 세  물 품", won(taxed - vat))
    r.lr("         부   가   세", won(vat))
    r.lr("합          계", won(total), 34, "b")
    r.lr("결 제 대 상 금 액", won(total), 30, "sb")
    r.rule()
    r.lr("0024 신한카드", won(total))
    r.left("카드번호 : 4518-42**-****-7731")
    r.left("승인번호 : 30961247 (일시불)")
    r.rule()
    r.center("[신세계포인트 적립]")
    r.left("홍*동 고객님의 포인트 현황입니다")
    r.lr("금회발생포인트", f"{total // 1000}")
    r.lr("누계(가용)포인트", "4,312(4,237)")
    r.left("*신세계포인트 유효기간은 2년입니다.", 26)
    r.rule()
    r.barcode("2026100918320012447103")
    return receipt_result(r.finish(), rng, lambda g, s: bg_wood(g, s, (150, 104, 66)), -2.4,
                          store, items, day, total, blur=0.9, light=0.3, shadow=0.18)


@case("s1-02", "S1", "Daiso receipt photo on linen: 5 items, each name line followed by a barcode "
      "line carrying unit/qty/amount, card approval, membership points")
def s1_02(rng):
    store, day = "다이소 강남신사점", 3
    items = [
        ("수납바구니(대)", 3000, 2, "8809461230456"),
        ("주방세제 리필 1L", 1000, 1, "8801046273312"),
        ("극세사 행주 3P", 2000, 1, "8809573104529"),
        ("멀티탭 4구 1m", 5000, 1, "8806355281170"),
        ("A4 클리어파일", 1000, 3, "8809018226741"),
    ]
    total = sum(u * q for _, u, q, _ in items)
    vat = round(total / 11)
    r = Receipt(rng, width=860, size=30)
    r.center("Daiso", 60, "b")
    r.center("(주)아성다이소 " + store.split()[1], 34, "sb")
    r.center("사업자 214-81-37719  대표 김기호", 26)
    r.center("서울 강남구 압구정로 128  T.02-541-7701", 26)
    r.gap(8)
    r.lr(f"{YEAR}.{MONTH:02d}.{day:02d}({weekday(day)}) 13:05", "No.0412-0087", 28)
    r.rule("=")
    r.row([("상품명", r.margin, "l"), ("단가", 520, "r"), ("수량", 640, "r"), ("금액", -r.margin, "r")])
    r.rule()
    for name, unit, qty, code in items:
        r.left(name, lh=1.25)
        r.row([(code, r.margin + 24, "l"), (won(unit), 520, "r"), (str(qty), 640, "r"),
               (won(unit * qty), -r.margin, "r")], size=28)
    r.rule()
    r.lr("과세물품가액", won(total - vat))
    r.lr("부  가  세", won(vat))
    r.lr("합      계", won(total), 34, "b")
    r.rule()
    r.lr("신용카드(KB국민)", won(total))
    r.left("카드번호: 9490-80**-****-1123")
    r.left("승인번호: 18273645  할부: 일시불")
    r.rule()
    r.left("다이소멤버십 적립포인트       17P")
    r.left("사용가능 포인트            1,284P")
    r.rule()
    r.center("교환/환불은 구매 후 14일 이내, 영수증 지참", 26)
    r.barcode("041200872026100313050")
    return receipt_result(r.finish(), rng, lambda g, s: bg_cloth(g, s, (196, 190, 178)), 1.3,
                          store, items, day, total, blur=0.8, light=0.26, shadow=0.0)


@case("s1-03", "S1", "Olive Young receipt photo on marble: 4 items in qty/amount columns, "
      "receipt-level coupon discount, VAT, card approval, CJ ONE points")
def s1_03(rng):
    store, day = "올리브영 홍대입구역점", 5
    items = [
        ("라운드랩 독도 토너 200ml", 18000, 1),
        ("닥터지 그린 마일드 선크림", 14900, 1),
        ("메디힐 티트리 마스크 10매", 10000, 2),
        ("클리오 킬커버 쿠션 리필", 15000, 1),
    ]
    subtotal = sum(u * q for _, u, q in items)
    coupon = 5000
    total = subtotal - coupon
    vat = round(total / 11)
    r = Receipt(rng, width=900, size=30)
    r.center("OLIVE YOUNG", 54, "b")
    r.center(store, 34, "sb")
    r.center("(주)씨제이올리브영 809-81-01574", 26)
    r.center("서울 마포구 양화로 160  T.02-3141-6203", 26)
    r.gap(8)
    r.lr(f"{YEAR}/{MONTH:02d}/{day:02d} 16:48:22", "POS 03-1188", 28)
    r.rule()
    r.row([("상품명", r.margin, "l"), ("수량", 640, "r"), ("금액", -r.margin, "r")])
    r.rule()
    for name, unit, qty in items:
        r.row([(name, r.margin, "l"), (str(qty), 640, "r"), (won(unit * qty), -r.margin, "r")])
    r.rule()
    r.lr("상품합계", won(subtotal))
    r.lr("CJ ONE 앱쿠폰 할인", f"-{won(coupon)}")
    r.lr("결제금액", won(total), 34, "b")
    r.lr("(과세물품가액", f"{won(total - vat)})", 26)
    r.lr("(부가세", f"{won(vat)})", 26)
    r.rule()
    r.lr("삼성카드 / 일시불", won(total))
    r.left("카드번호 5310-12**-****-8844")
    r.left("승인번호 71520394")
    r.rule()
    r.left("CJ ONE 회원 김*은")
    r.lr("적립 포인트", f"{total // 100}P")
    r.lr("가용 포인트", "3,140P")
    r.rule()
    r.barcode("0305188226100516482")
    return receipt_result(r.finish(), rng, bg_marble, 3.2, store, items, day, total,
                          blur=1.0, light=0.24, shadow=0.22, cast=(1.0, 0.99, 0.97))


@case("s1-04", "S1", "galbi restaurant receipt photo on dark wood: 5 menu lines in qty/amount columns, "
      "supply value/VAT, card approval, OK cashbag points")
def s1_04(rng):
    store, day = "연남숯불갈비", 2
    items = [
        ("돼지갈비(1인분)", 16000, 3),
        ("물냉면", 8000, 2),
        ("공기밥", 1000, 2),
        ("참이슬", 5000, 2),
        ("콜라", 2000, 1),
    ]
    total = sum(u * q for _, u, q in items)
    vat = round(total / 11)
    r = Receipt(rng, width=820, size=31)
    r.center("[영 수 증]", 36, "b")
    r.center(store, 42, "b")
    r.center("사업자 105-21-77881  대표 이정숙", 26)
    r.center("서울 마포구 동교로 241  02-332-0941", 26)
    r.rule()
    r.lr(f"일시 {iso(day)} 20:14", "테이블 7", 28)
    r.lr("인원 3명", "담당 01", 28)
    r.rule()
    r.row([("메뉴", r.margin, "l"), ("수량", 560, "r"), ("금액", -r.margin, "r")], weight="sb")
    r.rule()
    for name, unit, qty in items:
        r.row([(name, r.margin, "l"), (str(qty), 560, "r"), (won(unit * qty), -r.margin, "r")])
    r.rule()
    r.lr("공급가액", won(total - vat))
    r.lr("부가세", won(vat))
    r.lr("합계금액", won(total), 36, "b")
    r.rule()
    r.left("[카드승인]  현대카드")
    r.left("카드번호 4092-21**-****-6630")
    r.lr("할부 일시불", f"승인금액 {won(total)}")
    r.left("승인번호 00981247  가맹점 72215580")
    r.rule()
    r.lr("OK캐쉬백 적립", f"{total // 100}P")
    r.rule()
    r.center("감사합니다. 또 오세요!", 30, "sb")
    return receipt_result(r.finish(), rng, lambda g, s: bg_wood(g, s, (88, 58, 38), vertical=True), -1.2,
                          store, items, day, total, blur=1.1, light=0.34, shadow=0.25, cast=(1.0, 0.95, 0.86))


@case("s1-05", "S1", "Lotte Mart receipt photo on a gingham cloth: 15 items in unit/qty/amount columns, "
      "'#' tax-exempt markers and VAT block, card approval, L.POINT points")
def s1_05(rng):
    store, day = "롯데마트 잠실점", 10
    items = [  # (name, unit, qty, tax-exempt)
        ("서울우유 1L", 2890, 1, True), ("비비고 왕교자", 11980, 1, False), ("오뚜기 진라면 순한맛 5입", 3980, 1, False),
        ("제주 감귤 2kg", 9900, 1, True), ("바나나 1송이", 3990, 1, True), ("국산 콩나물 300g", 1480, 2, True),
        ("청정원 고추장 500g", 6480, 1, False), ("동원 참치 85g*4", 8980, 1, False), ("삼다수 2L*6", 5880, 1, False),
        ("하기스 물티슈 70매", 2490, 3, False), ("롯데 빼빼로 오리지널", 1700, 4, False),
        ("오리온 초코파이 12입", 5280, 1, False), ("냉동 삼겹살 500g", 12900, 1, True), ("깐마늘 200g", 2980, 1, True),
        ("페리오 치약 3입", 6900, 1, False),
    ]
    exempt = sum(u * q for _, u, q, ex in items if ex)
    taxed = sum(u * q for _, u, q, ex in items if not ex)
    vat = round(taxed / 11)
    total = exempt + taxed
    r = Receipt(rng, width=900, size=28)
    r.center("LOTTE Mart", 56, "b")
    r.center(store, 34, "sb")
    r.center("롯데쇼핑(주) 219-85-00014  대표 강성현", 25)
    r.center("서울 송파구 올림픽로 240  T.02-411-8025", 25)
    r.lr(f"{YEAR}.{MONTH:02d}.{day:02d} 11:27", "POS 0031 / 2207", 27)
    r.rule()
    r.row([("상품명", r.margin, "l"), ("단가", 590, "r"), ("수량", 680, "r"), ("금액", -r.margin, "r")])
    r.rule()
    for name, unit, qty, ex in items:
        r.row([(("#" if ex else " ") + name, r.margin, "l"), (won(unit), 590, "r"), (str(qty), 680, "r"),
               (won(unit * qty), -r.margin, "r")], lh=1.38)
    r.rule()
    r.lr("(#)면세물품가액", won(exempt))
    r.lr("과세물품가액", won(taxed - vat))
    r.lr("부가세", won(vat))
    r.lr("판매총액", won(total), 32, "b")
    r.lr("롯데카드", won(total), 30, "sb")
    r.left("카드번호: 5389-20**-****-4417  일시불")
    r.left("승인번호: 27711904")
    r.rule()
    r.left("L.POINT 회원 박*희")
    r.lr("금회적립", f"{total // 1000}점")
    r.lr("가용 L.POINT", "2,830점")
    r.rule()
    r.barcode("0031220720261010112748")
    return receipt_result(r.finish(), rng, lambda g, s: bg_gingham(g, s, (196, 52, 48)), 1.6,
                          store, items, day, total, blur=0.85, light=0.28, shadow=0.15)


@case("s1-06", "S1", "CU convenience-store receipt photo on a desk: 3 items in qty/amount columns, "
      "cash paid with change, cash-receipt approval line, membership points")
def s1_06(rng):
    store, day = "CU 역삼센터점", 7
    items = [("전주비빔 삼각김밥", 1500, 1), ("바나나맛우유 240ml", 1700, 2), ("비타500 100ml", 1200, 1)]
    total = sum(u * q for _, u, q in items)
    paid = 10000
    vat = round(total / 11)
    r = Receipt(rng, width=740, size=29, margin=40)
    r.center("CU", 64, "b")
    r.center(store, 34, "sb")
    r.center("(주)비지에프리테일 220-81-24901", 24)
    r.center("서울 강남구 테헤란로 152  T.02-555-0612", 24)
    r.lr(f"{iso(day)} 08:41", "POS 01-0315", 26)
    r.rule()
    r.row([("상품명", r.margin, "l"), ("수량", 480, "r"), ("금액", -r.margin, "r")])
    r.rule()
    for name, unit, qty in items:
        r.row([(name, r.margin, "l"), (str(qty), 480, "r"), (won(unit * qty), -r.margin, "r")])
    r.rule()
    r.lr("과세매출", won(total - vat))
    r.lr("부가세", won(vat))
    r.lr("합계", won(total), 34, "b")
    r.lr("받을금액", won(total))
    r.lr("현금", won(paid))
    r.lr("거스름돈", won(paid - total), 30, "sb")
    r.rule()
    r.left("현금영수증(소득공제)")
    r.left("식별번호 010-****-5678")
    r.left("승인번호 162839471")
    r.rule()
    r.lr("CU멤버십 적립", f"{total // 100}P")
    r.barcode("0315202610070841")
    return receipt_result(r.finish(), rng, lambda g, s: bg_plain(g, s, (206, 208, 212), 8), -3.6,
                          store, items, day, total, blur=1.0, light=0.38, shadow=0.24, cast=(0.97, 0.98, 1.0))


def list_screen(theme, time, title, header, sections, amount_prefix=""):
    """Card/bank app transaction list; sections: [(day, [(name, sub, amount, kind, extra)])]."""
    scr = Screen(theme)
    scr.status_bar(time)
    scr.nav(title, fill="text")
    y = header(scr, 300)
    for day, rows in sections:
        y += 40
        scr.text(63, y + 46, f"{MONTH:02d}.{day:02d} ({weekday(day)})", 42, "sb", "sub")
        y += 78
        for name, sub, amount, kind, extra in rows:
            scr.text(63, y + 60, name, 49, "m")
            scr.text(63, y + 120, sub, 40, "r", "sub")
            sign = "+" if kind == "+" else amount_prefix
            scr.text(SW - 63, y + 60, f"{sign}{won(amount)}원", 50, "sb", "blue" if kind == "+" else "text",
                     anchor="rs")
            if extra:
                scr.text(SW - 63, y + 120, extra, 40, "r", "sub", anchor="rs")
            y += 168
        scr.hline(y + 10, 63, SW - 63)
        y += 12
    scr.home_indicator()
    return scr


@case("s1-07", "S1", "KB card app usage list (light): merchants left, amounts in a right-aligned column, "
      "date headers, '결제 예정 금액' bill summary on top")
def s1_07(rng):
    sections = [
        (10, [("쿠팡", "일시불 · 14:22", 23900), ("배스킨라빈스 망원점", "일시불 · 11:05", 9800)]),
        (9, [("메가박스 상암월드컵경기장", "일시불 · 19:10", 28000), ("서브웨이 홍대점", "일시불 · 12:31", 8900)]),
        (8, [("GS칼텍스 망원주유소", "일시불 · 08:47", 60000)]),
        (7, [("교촌치킨 망원점", "일시불 · 20:12", 23000)]),
    ]
    due = 412350

    def header(scr, y):
        scr.text(63, y + 50, "KB국민 My WE:SH 카드 (3*7*)", 45, "sb")
        y += 100
        scr.box(63, y, SW - 63, y + 300, "grouped", r=36)
        scr.text(111, y + 84, "결제 예정 금액", 42, "r", "sub")
        scr.text(111, y + 184, f"{won(due)}원", 84, "b")
        scr.text(111, y + 256, "결제일 25일 · 국민 ****-123 출금", 39, "r", "sub")
        y += 340
        scr.text(63, y + 46, "10월 이용내역", 51, "b")
        scr.text(SW - 63, y + 46, "최신순", 42, "r", "sub", anchor="rs")
        return y + 70

    rows = [(d, [(n, s, a, "-", None) for n, s, a in rs]) for d, rs in sections]
    scr = list_screen(LIGHT, "9:14", "이용내역", header, rows)
    return screen_result(scr, [entry(n, a, iso(d)) for d, rs in sections for n, _, a in rs])


@case("s1-08", "S1", "bank account history (dark): signed amounts in a right column over running balances, "
      "salary and interest deposits mixed with check-card spending")
def s1_08(rng):
    balance = 3412580
    rows = [  # newest first: (day, time, name, amount, kind)
        (9, "18:22", "홈플러스 합정점", 54320, "-"),
        (8, "12:10", "김밥천국 여의도점", 8500, "-"),
        (8, "09:00", "급여 (주)한결테크", 2850000, "+"),
        (6, "19:05", "다이소 합정역점", 12000, "-"),
        (5, "13:44", "CU 망원한강점", 3700, "-"),
        (4, "00:15", "예금이자", 1203, "+"),
    ]
    sections, bal = [], balance
    for day, tm, name, amount, kind in rows:
        row = (name, f"{'체크카드' if kind == '-' else '입금'} · {tm}", amount, kind, f"잔액 {won(bal)}원")
        bal += amount if kind == "-" else -amount
        if sections and sections[-1][0] == day:
            sections[-1][1].append(row)
        else:
            sections.append((day, [row]))
    assert bal > 0

    def header(scr, y):
        scr.text(63, y + 50, "생활비 통장", 45, "sb", "sub")
        scr.text(63, y + 150, f"{won(balance)}원", 96, "b")
        scr.text(63, y + 220, "입출금 3333-12-******", 40, "r", "sub")
        scr.box(63, y + 270, SW // 2 - 15, y + 390, "fill", r=30)
        scr.box(SW // 2 + 15, y + 270, SW - 63, y + 390, "fill", r=30)
        scr.text(SW // 4 + 24, y + 344, "이체하기", 45, "sb", anchor="ms")
        scr.text(SW * 3 // 4 - 24, y + 344, "가져오기", 45, "sb", anchor="ms")
        y += 450
        scr.text(63, y + 46, "거래내역", 51, "b")
        scr.text(SW - 63, y + 46, "1개월 · 전체", 42, "r", "sub", anchor="rs")
        return y + 70

    scr = list_screen(DARK, "8:03", "", header, sections, amount_prefix="-")
    return screen_result(scr, [entry(n, a, iso(d)) for d, _, n, a, kind in rows if kind == "-"])


@case("s1-09", "S1", "Hyundai card usage list (dark): date column, merchant, right-aligned amounts, "
      "one 3-month installment, month total marked '청구 예정'")
def s1_09(rng):
    rows = [
        (4, "에버랜드", "할부 3개월", 112000),
        (3, "빕스 목동점", "일시불", 68400),
        (2, "넷플릭스", "일시불 · 정기결제", 17000),
        (2, "이디야커피 목동점", "일시불", 4800),
        (1, "SK에너지 목동주유소", "일시불", 70000),
    ]
    total = sum(a for *_, a in rows)
    scr = Screen(DARK)
    scr.status_bar("10:41")
    scr.nav("이용내역", fill="text")
    scr.text(63, 360, "현대카드 M (6*0*)", 45, "sb", "sub")
    scr.text(63, 450, "10월 이용금액", 48, "m")
    scr.text(63, 575, f"{won(total)}원", 96, "b")
    scr.tag(63 + textlen(f"{won(total)}원", 96, "b") + 30, 520, "청구 예정", (50, 50, 56), (190, 190, 198))
    scr.text(63, 650, "결제일 12일 · 일시불/할부 전체", 40, "r", "sub")
    scr.hline(720, 63, SW - 63)
    y = 760
    for day, name, sub, amount in rows:
        scr.text(63, y + 62, f"{MONTH:02d}.{day:02d}", 42, "r", "sub")
        scr.text(250, y + 62, name, 49, "m")
        scr.text(250, y + 124, sub, 40, "r", "sub")
        scr.text(SW - 63, y + 62, f"{won(amount)}원", 50, "sb", anchor="rs")
        y += 186
        scr.hline(y - 14, 250, SW - 63, "sep", 1)
    scr.box(63, y + 50, SW - 63, y + 170, "fill", r=30)
    scr.text(SW // 2, y + 110, "이전 내역 더보기", 45, "sb", "sub", anchor="mm")
    scr.home_indicator()
    return screen_result(scr, [entry(n, a, iso(d)) for d, n, _, a in rows])


# S2: name and amount close together on one line ------------------------------

@case("s2-01", "S2", "Twosome Place narrow receipt photo on light wood: 4 items printed as "
      "'name amount' with a short gap, card approval, CJ ONE points")
def s2_01(rng):
    store, day = "투썸플레이스 신촌점", 8
    items = [("아메리카노(R)", 4500, 1), ("카페라떼(R)", 5000, 1), ("스트로베리 생크림", 7500, 1),
             ("아이스 바닐라라떼", 5800, 2)]
    total = sum(u * q for _, u, q in items)
    r = Receipt(rng, width=600, size=30, margin=36)
    r.center("A TWOSOME PLACE", 36, "b")
    r.center(store, 30, "sb")
    r.center("사업자 211-88-61452", 24)
    r.left(f"{iso(day)} 15:12  POS 02", 26)
    r.rule()
    for name, unit, qty in items:
        r.left(f"{name}{f' x{qty}' if qty > 1 else ''}  {won(unit * qty)}")
    r.rule()
    r.left(f"합계  {won(total)}", 32, "b")
    r.left(f"부가세  {won(round(total / 11))}")
    r.rule()
    r.left(f"신한카드 일시불  {won(total)}")
    r.left("9410-61**-****-2210")
    r.left("승인 40528817")
    r.rule()
    r.left(f"CJ ONE 적립  {total // 100}P")
    r.left("주문번호 A-217", 26)
    return receipt_result(r.finish(), rng, lambda g, s: bg_wood(g, s, (196, 160, 118), vertical=True), 2.0,
                          store, items, day, total, blur=0.8, light=0.25, shadow=0.12)


@case("s2-02", "S2", "Paris Baguette narrow receipt photo on denim: 4 bakery items as 'name amount', "
      "paid in cash with change, Happy Point line")
def s2_02(rng):
    store, day = "파리바게뜨 망원역점", 1
    items = [("소금버터롤", 2800, 2), ("단팥빵", 2300, 1), ("우유식빵", 4200, 1), ("아이스아메리카노", 3800, 1)]
    total = sum(u * q for _, u, q in items)
    paid = 20000
    r = Receipt(rng, width=580, size=30, margin=34)
    r.center("PARIS BAGUETTE", 34, "b")
    r.center(store, 30, "sb")
    r.left(f"{YEAR}.{MONTH:02d}.{day:02d} 07:52", 26)
    r.rule()
    for name, unit, qty in items:
        r.left(f"{name}{f' x{qty}' if qty > 1 else ''} {won(unit * qty)}")
    r.rule()
    r.left(f"합계 {won(total)}", 32, "b")
    r.left(f"받은돈(현금) {won(paid)}")
    r.left(f"거스름돈 {won(paid - total)}")
    r.rule()
    r.left(f"해피포인트 적립 {total // 200}P", 28)
    r.left("현금영수증 자진발급 010-000-1234", 24)
    return receipt_result(r.finish(), rng, lambda g, s: bg_cloth(g, s, (70, 92, 132), pitch=5), -1.4,
                          store, items, day, total, blur=0.9, light=0.3, shadow=0.0)


@case("s2-03", "S2", "Notes app expense memo (light): one spending per line as 'M/D place amount원', "
      "plus a total line and a remaining-budget line")
def s2_03(rng):
    lines = [(1, "택시", 12300), (2, "크린토피아", 8000), (3, "온누리약국", 4500), (5, "준오헤어", 25000),
             (7, "망원시장", 9000)]
    total = sum(a for *_, a in lines)
    budget = 600000
    scr = Screen(LIGHT)
    scr.status_bar("9:12")
    accent = (214, 156, 10)
    scr.chevron_left(48, 215, accent)
    scr.text(96, 233, "메모", 51, "r", accent)
    scr.d.ellipse((SW - 112, 186, SW - 52, 246), outline=accent, width=5)
    for dx in (-14, 0, 14):
        scr.d.ellipse((SW - 82 + dx - 4, 212, SW - 82 + dx + 4, 220), fill=accent)
    scr.text(SW // 2, 350, f"{YEAR}년 {MONTH}월 8일 오후 9:12", 39, "r", "sub", anchor="ms")
    scr.text(63, 500, "10월 지출 메모", 84, "b")
    y = 640
    for day, place, amount in lines:
        scr.text(63, y, f"{MONTH}/{day} {place} {won(amount)}원", 54, "r")
        y += 88
    y += 40
    scr.text(63, y, f"합계 {won(total)}원", 54, "sb")
    y += 88
    scr.text(63, y, f"이번 달 예산 {won(budget)}원 / 남은 돈 {won(budget - total)}원", 48, "r", "text2")
    scr.home_indicator()
    return screen_result(scr, [entry(p, a, iso(d)) for d, p, a in lines])


@case("s2-04", "S2", "KakaoTalk Baemin order notice (dark): menu lines with amounts inline, total, "
      "and a later coupon notice; order read as items or as one total")
def s2_04(rng):
    store, day = "BHC 합정점", 4
    menu = [("뿌링클", 21000), ("치즈볼", 5000), ("제로콜라 500ml", 2500)]
    total = sum(a for _, a in menu)
    order = alimtalk("배달의민족", [
        "[배달의민족] 주문이 접수되었어요!",
        f"가게명: {store}",
        "주문메뉴:",
        *[f"· {n} 1개 {won(a)}원" for n, a in menu],
        "배달팁: 0원 (무료배달)",
        f"결제금액: {won(total)}원",
        f"주문일시: {YEAR}.{MONTH:02d}.{day:02d} 19:22",
    ], "주문 상세 보기")
    coupon = alimtalk("배달의민족", [
        "[배달의민족] 3,000원 할인쿠폰이 도착했어요!",
        "10/11까지 15,000원 이상 주문 시 사용 가능",
    ], "쿠폰함 가기")
    avatar = ((42, 193, 188), "배민")
    scr = kakao_screen(True, "7:23", "배달의민족", None, [
        k_date(f"{YEAR}년 {MONTH}월 {day}일 {weekday(day)}요일"),
        k_in("배달의민족", avatar, [order], "오후 7:22"),
        k_in("배달의민족", avatar, [coupon], "오후 7:23"),
    ])
    items = [entry(store, a, iso(day), n) for n, a in menu]
    return screen_result(scr, items, [entry(store, total, iso(day))])


@case("s2-05", "S2", "takeout order detail screen (light): 'menu 1개 amount원' lines, order and payment "
      "totals; order read as items or as one total")
def s2_05(rng):
    store, day = "홍콩반점0410 신림점", 6
    menu = [("짜장면", 7000), ("짬뽕", 8500), ("탕수육(소)", 15000)]
    total = sum(a for _, a in menu)
    scr = Screen(LIGHT)
    scr.status_bar("6:07")
    scr.nav("주문상세", fill="text")
    scr.tag(63, 330, "포장 완료", (232, 245, 238), (24, 140, 80), 39)
    scr.text(63, 480, store, 63, "b")
    scr.text(63, 560, f"주문일시 {YEAR}.{MONTH:02d}.{day:02d} 18:05", 42, "r", "sub")
    scr.text(63, 620, "주문번호 B2Q4-91AX", 42, "r", "sub")
    scr.box(0, 680, SW, 704, "grouped")
    scr.text(63, 800, "주문 메뉴", 51, "b")
    y = 900
    for name, amount in menu:
        scr.text(63, y, f"{name} 1개 {won(amount)}원", 51, "r")
        y += 84
    scr.text(63, y + 10, "요청사항: 단무지 많이 주세요", 42, "r", "sub")
    y += 90
    scr.box(0, y, SW, y + 24, "grouped")
    y += 120
    scr.text(63, y, "결제 정보", 51, "b")
    y += 100
    scr.kv(y, "주문금액", f"{won(total)}원")
    scr.kv(y + 80, "포장 할인", "0원")
    scr.hline(y + 130, 63, SW - 63)
    scr.kv(y + 220, "총 결제금액", f"{won(total)}원", 54, "b", "b", "text")
    scr.kv(y + 300, "결제수단", "신한카드 (일시불)")
    scr.box(63, SH - 300, SW - 63, SH - 150, "fill", r=30)
    scr.text(SW // 2, SH - 225, "가게 리뷰 쓰기", 48, "sb", anchor="mm")
    scr.home_indicator()
    items = [entry(store, a, iso(day), n) for n, a in menu]
    return screen_result(scr, items, [entry(store, total, iso(day))])


@case("s2-06", "S2", "SMS e-receipt from a convenience store (dark Messages): item lines with amounts inline, "
      "total and card line")
def s2_06(rng):
    store, day = "이마트24 역삼센터점", 6
    items = [("삼각김밥(참치마요)", 1500, 1), ("바나나우유", 1700, 1), ("컵라면(육개장)", 1300, 1)]
    total = sum(u * q for _, u, q in items)
    msg = "\n".join([
        "[Web발신]", "[이마트24 전자영수증]", store, f"{iso(day)} 08:12",
        *[f"{n} {won(u * q)}원" for n, u, q in items],
        f"합계 {won(total)}원", "결제 신한카드 일시불 승인",
    ])
    scr = sms_screen(DARK, "8:13", "1577-4410", [("stamp", f"{MONTH}월 {day}일 ({weekday(day)}) 오전 8:12"),
                                                  ("in", msg)])
    return {"img": scr.img, "ext": "png", "receipt": True, "accept": [receipt_items(store, items, day)],
            "lenient": [[entry(store, total, iso(day))]]}


@case("s2-07", "S2", "gimbap kiosk receipt photo on a dark slate counter: 4 menu lines as 'name amount', "
      "Kakao Pay approval")
def s2_07(rng):
    store, day = "바르다김선생 여의도점", 11
    items = [("바른김밥", 4500, 1), ("매운제육김밥", 5500, 1), ("라볶이", 6000, 1), ("어묵탕", 4000, 1)]
    total = sum(u * q for _, u, q in items)
    r = Receipt(rng, width=560, size=30, margin=34)
    r.center("[주문번호 117]", 40, "b")
    r.center(store, 30, "sb")
    r.left(f"{iso(day)} 12:20", 26)
    r.rule()
    for name, unit, qty in items:
        r.left(f"{name} {won(unit * qty)}")
    r.rule()
    r.left(f"합계 {won(total)}", 32, "b")
    r.left(f"카카오페이 승인 {won(total)}")
    r.left("승인번호 51190388", 26)
    r.rule()
    r.left("매장식사 / 키오스크 2번", 26)
    return receipt_result(r.finish(), rng, lambda g, s: bg_plain(g, s, (62, 64, 70), 14), 3.0,
                          store, items, day, total, blur=1.0, light=0.3, shadow=0.16, cast=(0.98, 0.98, 1.0))


# S3: number runs that are not purchases --------------------------------------

@case("s3-01", "S3", "phone bill breakdown (light, '청구 예정') under a Shinhan card approval banner; "
      "only the banner is spending")
def s3_01(rng):
    plan, discount, extra, device = 69000, 17250, 3300, 32700
    vat = (plan - discount + extra) // 10
    raw = plan - discount + extra + device + vat
    total = raw - raw % 10
    scr = Screen(LIGHT)
    scr.status_bar("8:12")
    scr.nav("요금 안내", fill="text")
    scr.text(63, 380, "010-****-5821 · 5GX 프라임", 42, "r", "sub")
    scr.text(63, 470, "10월 청구요금 (9월 사용분)", 48, "m")
    scr.text(63, 600, f"{won(total)}원", 100, "b")
    scr.tag(63 + textlen(f"{won(total)}원", 100, "b") + 30, 540, "청구 예정", (232, 240, 255), (30, 100, 220))
    scr.text(63, 680, "매월 21일 신한카드 자동이체 예정", 40, "r", "sub")
    scr.box(0, 740, SW, 764, "grouped")
    y = 870
    scr.text(63, y, "요금 상세", 51, "b")
    y += 110
    for label, value in [("월정액 (5GX 프라임)", plan), ("선택약정 할인", -discount), ("부가서비스 (V컬러링)", extra),
                         ("단말기 할부금 (14/24회)", device), ("부가가치세", vat), ("10원 미만 할인", -(raw % 10))]:
        scr.kv(y, label, f"{'-' if value < 0 else ''}{won(abs(value))}원", 45, "r", "m", "text2")
        y += 96
    scr.hline(y - 30, 63, SW - 63)
    scr.kv(y + 50, "합계", f"{won(total)}원", 51, "b", "b", "text")
    scr.box(63, y + 160, SW - 63, y + 290, "fill", r=30)
    scr.text(SW // 2, y + 225, "청구서 다시 받기", 45, "sb", anchor="mm")
    scr.home_indicator()
    notification(scr, 24, 150, SW - 48, ((0, 70, 160), "신한"), "신한카드",
                 ["신한카드(5*1*)승인 한*수 6,100원(일시불)10/09 08:12 스타벅스 여의도IFC점 누적412,000원"],
                 "지금", False)
    return screen_result(scr, [entry("스타벅스 여의도IFC점", 6100, iso(9))])


@case("s3-02", "S3", "KakaoTalk group chat (dark) where a member pasted a dues list with amounts, an account "
      "number and a planned field fee; no spending")
def s3_02(rng):
    members = [("김도윤", True), ("박서준", True), ("이하준", True), ("최민재", False), ("정우진", True),
               ("강지호", True), ("윤시우", False)]
    fee, rental = 30000, 120000
    paid = sum(fee for _, ok in members if ok)
    pasted = "\n".join(["[10월 회비 납부 현황]"] + [
        f"{k}. {n} {won(fee) + ' (완료)' if ok else '미납'}" for k, (n, ok) in enumerate(members, 1)
    ] + ["----------", f"입금 합계 {won(paid)}원", f"구장 대관료 {won(rental)}원 (토요일 결제 예정)"])
    avatar = ((120, 160, 220), "도윤")
    day = 7
    scr = kakao_screen(True, "11:05", "망원 풋살 모임", 12, [
        k_date(f"{YEAR}년 {MONTH}월 {day}일 {weekday(day)}요일"),
        k_in("김도윤", avatar, ["10월 회비 정리해서 올립니다", pasted], "오전 10:52"),
        k_in("박서준", ((230, 150, 110), "서준"), ["계좌 다시 알려주세요~"], "오전 10:58"),
        k_in("김도윤", avatar, ["카카오뱅크 3333-08-5512947 김도윤"], "오전 10:59"),
        k_me("확인했어요 감사합니다", "오전 11:04"),
    ])
    return screen_result(scr)


@case("s3-03", "S3", "stock watchlist (dark) with prices and percent changes under a Samsung card "
      "approval banner; only the banner is spending")
def s3_03(rng):
    stocks = [("삼성전자", "005930", 61400, 1.32), ("SK하이닉스", "000660", 187300, -0.85),
              ("NAVER", "035420", 172500, 0.29), ("카카오", "035720", 38950, -1.14),
              ("현대차", "005380", 214000, 2.15), ("LG에너지솔루션", "373220", 351500, -0.42),
              ("KODEX 200", "069500", 35120, 0.77), ("TIGER 미국S&P500", "360750", 19885, 0.31)]
    scr = Screen(DARK)
    scr.status_bar("9:05")
    scr.text(63, 330, "관심종목", 84, "b")
    scr.text(63, 480, "국내", 48, "b")
    scr.text(190, 480, "해외", 48, "sb", "sub")
    for k, (name, val, chg) in enumerate([("코스피", "2,618.34", 0.84), ("코스닥", "742.15", -0.31)]):
        x0 = 63 + k * 540
        scr.box(x0, 530, x0 + 513, 700, "card", r=30)
        scr.text(x0 + 36, 595, name, 42, "r", "sub")
        scr.text(x0 + 36, 665, val, 51, "b")
        scr.text(x0 + 477, 665, f"{chg:+.2f}%", 42, "sb", "up" if chg > 0 else "down", anchor="rs")
    scr.text(63, 780, "10.08 장마감 기준", 39, "r", "sub")
    y = 830
    for name, code, price, chg in stocks:
        scr.text(63, y + 64, name, 49, "m")
        scr.text(63, y + 124, code, 38, "r", "sub")
        scr.text(SW - 63, y + 64, won(price), 50, "sb", anchor="rs")
        move = round(price * chg / 100 / 5) * 5
        scr.text(SW - 63, y + 124, f"{'+' if chg > 0 else '-'}{won(abs(move))} ({chg:+.2f}%)", 40, "r",
                 "up" if chg > 0 else "down", anchor="rs")
        y += 176
    scr.home_indicator()
    notification(scr, 24, 150, SW - 48, ((20, 60, 160), "삼성"), "삼성카드",
                 ["삼성카드 승인 윤*호님 19,800원 일시불 10/10 21:05 쿠팡이츠 누적1,034,700원"], "지금", True)
    return screen_result(scr, [entry("쿠팡이츠", 19800, iso(10))])


@case("s3-04", "S3", "account balance history (light): balance chart and a list of daily closing balances, "
      "interest button; no spending")
def s3_04(rng):
    balances = [(11, 3214560), (10, 3214560), (9, 3187240), (8, 3233880), (7, 412640), (6, 461230),
                (5, 498700), (4, 503150)]
    scr = Screen(LIGHT)
    scr.status_bar("10:30")
    scr.nav("잔액 내역", fill="text")
    scr.text(63, 380, "토스뱅크 통장", 45, "sb", "sub")
    scr.text(63, 490, f"{won(balances[0][1])}원", 96, "b")
    x0, x1, y0, y1 = 90, SW - 90, 560, 900
    lo, hi = min(b for _, b in balances), max(b for _, b in balances)
    pts = []
    for k, (_, b) in enumerate(reversed(balances)):
        pts.append((x0 + (x1 - x0) * k / (len(balances) - 1), y1 - (y1 - y0) * (b - lo) / (hi - lo)))
    scr.d.line(pts, fill=(49, 130, 246), width=8, joint="curve")
    for p in pts:
        scr.d.ellipse((p[0] - 10, p[1] - 10, p[0] + 10, p[1] + 10), fill=(49, 130, 246))
    scr.text(x0, 960, f"{MONTH}.{balances[-1][0]:02d}", 36, "r", "sub", anchor="ls")
    scr.text(x1, 960, f"{MONTH}.{balances[0][0]:02d}", 36, "r", "sub", anchor="rs")
    scr.box(0, 1010, SW, 1034, "grouped")
    y = 1080
    scr.text(63, y + 60, "일별 마감 잔액", 51, "b")
    y += 110
    for day, b in balances:
        scr.text(63, y + 64, f"{MONTH:02d}.{day:02d} ({weekday(day)})", 46, "r")
        scr.text(SW - 63, y + 64, f"{won(b)}원", 48, "sb", anchor="rs")
        y += 118
    scr.box(63, y + 40, SW - 63, y + 170, (232, 242, 255), r=30)
    scr.text(SW // 2, y + 105, "지금 이자 받기  128원", 45, "sb", (30, 100, 220), anchor="mm")
    scr.home_indicator()
    return screen_result(scr)


@case("s3-05", "S3", "apartment maintenance-fee bill (dark): itemized charges with a 'payable' total "
      "not yet paid; no spending")
def s3_05(rng):
    fees = [("일반관리비", 48320), ("청소비", 11800), ("경비비", 31200), ("소독비", 1100), ("승강기유지비", 3600),
            ("수선유지비", 9900), ("장기수선충당금", 17560), ("세대전기료", 58740), ("세대수도료", 21480),
            ("TV수신료", 2500), ("음식물처리비", 3280)]
    total = sum(a for _, a in fees)
    scr = Screen(DARK)
    scr.status_bar("7:48")
    scr.nav("관리비", fill="text")
    scr.text(63, 380, "한빛마을 2단지 105동 1102호", 42, "r", "sub")
    scr.text(63, 470, "9월분 관리비", 48, "m")
    scr.text(63, 600, f"{won(total)}원", 100, "b")
    scr.tag(63 + textlen(f"{won(total)}원", 100, "b") + 30, 540, "납부 전", (70, 40, 40), (255, 150, 140))
    scr.text(63, 680, "이번 달 말일까지 납부해 주세요", 40, "r", "sub")
    scr.kv(780, "전월 대비", "+12,340원", 42)
    scr.kv(850, "동일 면적 평균", "198,200원", 42)
    scr.box(0, 910, SW, 934, (20, 20, 22))
    y = 1040
    scr.text(63, y, "부과 내역", 51, "b")
    y += 100
    for label, amount in fees:
        scr.kv(y, label, f"{won(amount)}원", 45, "r", "m", "text2")
        y += 92
    scr.hline(y - 30, 63, SW - 63)
    scr.kv(y + 46, "납부할 금액", f"{won(total)}원", 51, "b", "b", "text")
    scr.home_indicator()
    return screen_result(scr)


# S4: payment notifications, SMS approvals, payment-complete screens ----------

@case("s4-01", "S4", "lock screen (light notifications on a coral wallpaper): Shinhan and Hyundai card "
      "approvals, a Coupang delivery notice, and a Naver Pay payment without a date in its body")
def s4_01(rng):
    day = 10
    wall = wallpaper((240, 128, 112), (116, 86, 170),
                     [((255, 190, 120), 300, 700, 600, 0.8), ((90, 70, 160), 900, 1900, 700, 0.7)])
    notes = [
        (((0, 70, 160), "신한"), "신한카드", ["신한카드(1*3*)승인 김*진 32,000원(일시불)10/10 12:41 교보문고 광화문점 "
                                         "누적1,284,300원"], "24분 전"),
        (((20, 20, 20), "H"), "현대카드", ["현대카드 ZERO 승인", "김*진 8,900원 일시불", "10/10 11:58 메가MGC커피 종로점",
                                       "누적 386,400원"], "1시간 전"),
        (((92, 52, 24), "쿠팡"), "쿠팡", ["고객님이 주문하신 상품이 문 앞에 배송 완료되었습니다."], "2시간 전"),
        (((3, 199, 90), "N"), "네이버페이", ["결제 완료", "오늘의집에서 25,800원이 결제되었습니다."], "3시간 전"),
    ]
    scr = lock_screen(LIGHT, wall, f"10월 {day}일 {weekday(day)}요일", "13:05", notes, top=960)
    cards = [entry("교보문고 광화문점", 32000, iso(day)), entry("메가MGC커피 종로점", 8900, iso(day))]
    return screen_result(scr, cards + [entry("오늘의집", 25800, iso(day))], cards + [entry("오늘의집", 25800, "")])


@case("s4-02", "S4", "home screen (dark wallpaper) with a single Lotte card approval banner")
def s4_02(rng):
    wall = wallpaper((24, 30, 58), (6, 6, 12),
                     [((60, 40, 120), 200, 600, 700, 0.7), ((20, 90, 110), 1000, 1700, 600, 0.6)])
    scr = home_screen(DARK, wall, "7:24")
    notification(scr, 24, 150, SW - 48, ((220, 30, 40), "LOTTE"), "롯데카드",
                 ["롯데카드 승인 박*우님 57,800원 일시불 10/08 19:22 아웃백스테이크하우스 잠실점 누적734,500원"],
                 "지금", True)
    return screen_result(scr, [entry("아웃백스테이크하우스 잠실점", 57800, iso(8))])


@case("s4-03", "S4", "Messages thread from a KB card number (light): a bill-amount notice and two approval "
      "SMS with cumulative totals")
def s4_03(rng):
    msgs = [
        ("stamp", f"10월 2일 ({weekday(2)}) 오전 10:00"),
        ("in", "[Web발신]\nKB국민카드 10월 결제예정금액 안내\n412,300원 (결제일 14일)\n자세한 내용은 KB Pay에서 확인하세요."),
        ("stamp", f"10월 5일 ({weekday(5)}) 오후 12:31"),
        ("in", "[Web발신]\nKB국민카드1*2*승인\n이*현님\n14,500원 일시불\n10/05 12:31\n본죽&비빔밥 서초점\n누적128,700원"),
        ("stamp", f"10월 9일 ({weekday(9)}) 오후 7:47"),
        ("in", "[Web발신]\nKB국민카드1*2*승인\n이*현님\n89,000원 일시불\n10/09 19:47\n무신사스토어\n누적217,700원"),
    ]
    scr = sms_screen(LIGHT, "7:50", "15881688", msgs)
    return screen_result(scr, [entry("본죽&비빔밥 서초점", 14500, iso(5)), entry("무신사스토어", 89000, iso(9))])


@case("s4-04", "S4", "Messages thread from a Hana card number (dark): one approval SMS and a "
      "verification-code SMS")
def s4_04(rng):
    msgs = [
        ("stamp", f"10월 6일 ({weekday(6)}) 오후 6:05"),
        ("in", "[Web발신]\n하나(7*3*)승인 최*영\n23,400원 일시불\n10/06 18:05\n세븐일레븐 역삼점\n누적642,100원"),
        ("stamp", f"10월 7일 ({weekday(7)}) 오전 9:12"),
        ("in", "[Web발신]\n[하나카드] 인증번호 [482915]\n본인확인을 위해 입력해주세요. 타인에게 절대 알려주지 마세요."),
    ]
    scr = sms_screen(DARK, "9:13", "1800-1111", msgs)
    return screen_result(scr, [entry("세븐일레븐 역삼점", 23400, iso(6))])


@case("s4-05", "S4", "Kakao Pay payment-complete screen (light): paid amount, order amount, coupon "
      "discount and points lines")
def s4_05(rng):
    merchant, day = "컬리", 6
    order, coupon = 49700, 3000
    paid = order - coupon
    scr = Screen(LIGHT)
    scr.status_bar("9:15")
    scr.cross(SW - 90, 225, 26, "text", 6)
    scr.d.ellipse((SW // 2 - 90, 400, SW // 2 + 90, 580), fill=(254, 229, 0))
    scr.check(SW // 2, 490, 90, BLACK, 14)
    scr.text(SW // 2, 730, "결제가 완료되었어요", 66, "b", anchor="ms")
    scr.text(SW // 2, 820, merchant, 51, "r", "sub", anchor="ms")
    scr.text(SW // 2, 980, f"{won(paid)}원", 112, "b", anchor="ms")
    scr.box(63, 1080, SW - 63, 1700, "grouped", r=36)
    rows = [("주문금액", f"{won(order)}원"), ("쿠폰 할인", f"-{won(coupon)}원"), ("결제금액", f"{won(paid)}원"),
            ("결제수단", "카카오페이머니"), ("결제일시", f"{YEAR}.{MONTH:02d}.{day:02d} 21:14"),
            ("적립 예정 포인트", f"{paid // 100}P")]
    y = 1180
    for label, value in rows:
        scr.kv(y, label, value, 45, "r", "sb", "sub", None, 111, SW - 111)
        y += 96
    scr.box(63, SH - 300, SW - 63, SH - 150, (254, 229, 0), r=36)
    scr.text(SW // 2, SH - 225, "확인", 51, "b", BLACK, anchor="mm")
    scr.home_indicator()
    return screen_result(scr, [entry(merchant, paid, iso(day))])


@case("s4-06", "S4", "Naver Pay order-complete screen (dark): one store, two products with prices, "
      "free shipping, total and points; read as one total or as its items")
def s4_06(rng):
    store, day = "데일리홈 스토어", 4
    products = [("극세사 무릎담요", "옵션: 그레이", 19900), ("수면양말 3켤레", "옵션: 랜덤", 12000)]
    total = sum(a for *_, a in products)
    green = (3, 199, 90)
    scr = Screen(DARK)
    scr.status_bar("10:23")
    scr.cross(SW - 90, 225, 26, "text", 6)
    scr.d.ellipse((SW // 2 - 75, 330, SW // 2 + 75, 480), fill=green)
    scr.check(SW // 2, 405, 75, WHITE, 12)
    scr.text(SW // 2, 610, "주문이 완료되었습니다", 63, "b", anchor="ms")
    scr.text(SW // 2, 690, f"{YEAR}.{MONTH:02d}.{day:02d} 10:22 주문", 42, "r", "sub", anchor="ms")
    scr.box(0, 760, SW, 784, (22, 22, 24))
    y = 880
    w = scr.text(63, y, store, 51, "b")
    scr.chevron_right(63 + w + 40, y - 17, "sub", 12, 5)
    y += 60
    for name, option, amount in products:
        scr.box(63, y, 243, y + 180, "card", r=20)
        scr.text(285, y + 54, name, 48, "m")
        scr.text(285, y + 112, option, 39, "r", "sub")
        scr.text(285, y + 172, f"{won(amount)}원 · 1개", 45, "b")
        y += 230
    scr.text(63, y + 30, "배송비 무료", 42, "r", "sub")
    scr.box(0, y + 90, SW, y + 114, (22, 22, 24))
    y += 220
    scr.kv(y, "상품금액", f"{won(total)}원")
    scr.kv(y + 86, "배송비", "0원")
    scr.hline(y + 136, 63, SW - 63)
    scr.kv(y + 226, "총 결제금액", f"{won(total)}원", 54, "b", "b", "text", green)
    scr.kv(y + 310, "결제수단", "네이버페이 머니")
    scr.kv(y + 390, "네이버페이 포인트 적립 예정", f"{won(total // 100)}원", 42)
    scr.box(63, SH - 300, SW // 2 - 15, SH - 150, "fill", r=30)
    scr.box(SW // 2 + 15, SH - 300, SW - 63, SH - 150, green, r=30)
    scr.text(SW // 4 + 24, SH - 225, "주문상세 보기", 45, "sb", anchor="mm")
    scr.text(SW * 3 // 4 - 24, SH - 225, "쇼핑 계속하기", 45, "sb", WHITE, anchor="mm")
    scr.home_indicator()
    items = [entry(store, a, iso(day), n) for n, _, a in products]
    return screen_result(scr, [entry(store, total, iso(day))], items)


@case("s4-07", "S4", "lock screen (dark notifications): Toss Pay payment without a date in its body, "
      "Woori card approval, and a KakaoBank incoming transfer")
def s4_07(rng):
    day = 11
    wall = wallpaper((14, 24, 48), (2, 2, 6),
                     [((40, 70, 140), 950, 500, 650, 0.7), ((70, 30, 90), 150, 1800, 650, 0.6)])
    notes = [
        (((0, 100, 255), "toss"), "토스", ["토스페이 결제 완료", "GS25 선릉역점에서 4,600원을 결제했어요."], "지금"),
        (((0, 120, 200), "우리"), "우리카드", ["우리카드(9*0*)승인 정*아님 15,000원 일시불 10/11 08:47 카카오T 택시 "
                                         "누적389,200원"], "25분 전"),
        (((254, 229, 0), "K"), "카카오뱅크", ["입금 50,000원", "김민수 → 내 입출금통장(1234)"], "1시간 전"),
    ]
    scr = lock_screen(DARK, wall, f"10월 {day}일 {weekday(day)}요일", "9:12", notes)
    taxi = entry("카카오T 택시", 15000, iso(day))
    return screen_result(scr, [entry("GS25 선릉역점", 4600, iso(day)), taxi],
                         [entry("GS25 선릉역점", 4600, ""), taxi])


@case("s4-08", "S4", "KakaoTalk Kakao Pay channel (light): two payment-complete cards and one "
      "money-received card")
def s4_08(rng):
    avatar = ((254, 229, 0), "pay")
    cgv = pay_card("카카오페이 결제", "결제 완료", "12,900원",
                   [("결제처", "CGV 용산아이파크몰"), ("결제일시", "2026.10.03 19:41"), ("결제수단", "카카오페이머니")])
    blue = pay_card("카카오페이 결제", "결제 완료", "6,500원",
                    [("결제처", "블루보틀 성수"), ("결제일시", "2026.10.05 08:12"), ("결제수단", "신한카드")])
    recv = pay_card("카카오페이 송금", "송금 받기 완료", "20,000원",
                    [("보낸 사람", "김지훈"), ("받은 일시", "2026.10.05 13:20")])
    scr = kakao_screen(False, "1:25", "카카오페이", None, [
        k_date(f"{YEAR}년 {MONTH}월 3일 {weekday(3)}요일"),
        k_in("카카오페이", avatar, [cgv], "오후 7:41"),
        k_date(f"{YEAR}년 {MONTH}월 5일 {weekday(5)}요일"),
        k_in("카카오페이", avatar, [blue], "오전 8:12"),
        k_in("카카오페이", avatar, [recv], "오후 1:20"),
    ])
    return screen_result(scr, [entry("CGV 용산아이파크몰", 12900, iso(3)), entry("블루보틀 성수", 6500, iso(5))])


# ---------------------------------------------------------------- main

def check(truth, out, receipts):
    ids = set()
    for c in truth:
        assert c["id"] not in ids, c["id"]
        ids.add(c["id"])
        assert os.path.exists(os.path.join(out, c["file"])), c["file"]
        assert c["accept"] and all(isinstance(alt, list) for alt in c["accept"]), c["id"]
        for alt in c["accept"] + c["lenient"]:
            for e in alt:
                assert set(e) == {"m", "i", "a", "d"}, (c["id"], e)
                assert isinstance(e["a"], int) and e["a"] > 0, (c["id"], e)
                assert e["d"] == "" or re.fullmatch(r"2026-10-(0[1-9]|1[01])", e["d"]), (c["id"], e)
                assert e["m"], (c["id"], e)
        if c["id"] in receipts:
            assert all(e["i"] for e in c["accept"][0]), c["id"]
            assert len(c["lenient"]) == 1 and len(c["lenient"][0]) == 1, c["id"]


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: gen_holdout.py <out_dir> [case_id ...]")
    out, only = sys.argv[1], set(sys.argv[2:])
    os.makedirs(out, exist_ok=True)
    truth, receipts = [], set()
    for cid, cat, note, fn in CASES:
        if only and cid not in only:
            continue
        res = fn(random.Random(cid))
        name = f"{cid}.{res['ext']}"
        path = os.path.join(out, name)
        if res["ext"] == "jpg":
            res["img"].save(path, "JPEG", quality=90)
        else:
            res["img"].save(path, "PNG")
        if res.get("receipt"):
            receipts.add(cid)
        truth.append({"id": cid, "cat": cat, "file": name, "accept": res["accept"],
                      "lenient": res.get("lenient", []), "note": note})
    check(truth, out, receipts)
    with open(os.path.join(out, "truth.json"), "w", encoding="utf-8") as fh:
        json.dump(truth, fh, ensure_ascii=False, indent=1)
        fh.write("\n")
    print(f"{len(truth)} cases -> {out}")


if __name__ == "__main__":
    main()
