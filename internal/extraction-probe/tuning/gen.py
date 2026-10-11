#!/usr/bin/env python3
"""Synthetic screenshot / receipt-photo corpus for the image+OCR extraction probe.

Usage: python3 -I gen.py <out_dir>
Writes <id>.png / <id>.jpg and truth.json (acceptable entry sets per image).
"""
import json
import os
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
random.seed(11)

FONT = "/System/Library/Fonts/AppleSDGothicNeo.ttc"
W, H = 1179, 2556
_fonts = {}


def F(size, w="r"):
    idx = {"r": 0, "m": 2, "sb": 4, "b": 6}[w]
    key = (size, idx)
    if key not in _fonts:
        _fonts[key] = ImageFont.truetype(FONT, size, index=idx)
    return _fonts[key]


LIGHT = dict(bg=(242, 242, 247), page=(255, 255, 255), card=(255, 255, 255), text=(0, 0, 0),
             sub=(110, 110, 115), sep=(222, 222, 226), bubble=(233, 233, 235), banner=(248, 248, 250),
             accent=(0, 122, 255), field=(232, 232, 237))
DARK = dict(bg=(0, 0, 0), page=(0, 0, 0), card=(28, 28, 30), text=(255, 255, 255),
            sub=(152, 152, 157), sep=(56, 56, 58), bubble=(38, 38, 40), banner=(46, 46, 48),
            accent=(10, 132, 255), field=(28, 28, 30))

TRUTH = []


def entry(m, a, d, i=None):
    return {"m": m, "i": i, "a": a, "d": d}


def add_truth(cid, cat, accept, note, lenient=None):
    TRUTH.append({"id": cid, "cat": cat, "accept": accept, "lenient": lenient or [], "note": note})


def tw(s, f):
    return f.getlength(s)


def status_bar(d, th, time="9:41"):
    d.text((110, 48), time, font=F(50, "sb"), fill=th["text"])
    for i in range(4):
        bx = W - 335 + i * 17
        bh = 12 + i * 8
        d.rectangle([bx, 98 - bh, bx + 10, 98], fill=th["text"])
    x, y = W - 175, 60
    d.rounded_rectangle([x, y, x + 82, y + 40], radius=11, outline=th["sub"], width=3)
    d.rounded_rectangle([x + 6, y + 6, x + 62, y + 34], radius=6, fill=th["text"])


def wallpaper(dark):
    img = Image.new("RGB", (W, H))
    top = (38, 52, 104) if dark else (118, 158, 228)
    bot = (8, 8, 24) if dark else (232, 182, 202)
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / H
        d.line([(0, y), (W, y)], fill=tuple(int(top[k] * (1 - t) + bot[k] * t) for k in range(3)))
    return img


def app_icon(d, x, y, color, letter, size=112):
    d.rounded_rectangle([x, y, x + size, y + size], radius=int(size * 0.23), fill=color)
    f = F(int(size * 0.40), "b")
    d.text((x + (size - tw(letter, f)) / 2, y + size * 0.27), letter, font=f, fill=(255, 255, 255))


def banner(d, y, title, time, body, color, letter, dark):
    """iOS notification banner; returns its bottom y."""
    x0, x1 = 34, W - 34
    lh = 58
    h = 44 + 58 + lh * len(body) + 34
    fill = (58, 58, 60) if dark else (250, 250, 252)
    d.rounded_rectangle([x0, y, x1, y + h], radius=58, fill=fill)
    app_icon(d, x0 + 38, y + (h - 112) // 2, color, letter)
    tx = x0 + 38 + 112 + 34
    text = (255, 255, 255) if dark else (0, 0, 0)
    sub = (170, 170, 175) if dark else (120, 120, 125)
    d.text((tx, y + 40), title, font=F(46, "sb"), fill=text)
    d.text((x1 - 44 - tw(time, F(40)), y + 44), time, font=F(40), fill=sub)
    for k, line in enumerate(body):
        d.text((tx, y + 40 + 60 + k * lh), line, font=F(45), fill=text)
    return y + h


def lock_screen(dark, date_text, notifs):
    img = wallpaper(dark)
    d = ImageDraw.Draw(img)
    th = DARK
    status_bar(d, th)
    d.text(((W - tw(date_text, F(56, "sb"))) / 2, 250), date_text, font=F(56, "sb"), fill=(255, 255, 255))
    clock = "9:41"
    d.text(((W - tw(clock, F(300, "sb"))) / 2, 300), clock, font=F(300, "sb"), fill=(255, 255, 255))
    y = 760
    for n in notifs:
        y = banner(d, y, *n, dark) + 22
    return img


# ---------- screen builders ----------

def messages_thread(dark, sender, items):
    """items: ('time', text) or ('in', [lines])"""
    th = DARK if dark else LIGHT
    img = Image.new("RGB", (W, H), th["page"])
    d = ImageDraw.Draw(img)
    status_bar(d, th)
    d.text((40, 150), "‹", font=F(110), fill=th["accent"])
    d.ellipse([W / 2 - 62, 150, W / 2 + 62, 274], fill=(150, 150, 158))
    d.text(((W - tw(sender, F(38))) / 2, 290), sender, font=F(38), fill=th["text"])
    d.line([(0, 360), (W, 360)], fill=th["sep"], width=2)
    y = 410
    for kind, val in items:
        if kind == "time":
            d.text(((W - tw(val, F(34))) / 2, y), val, font=F(34), fill=th["sub"])
            y += 70
        else:
            f = F(46)
            width = max(tw(line, f) for line in val) + 72
            h = 60 * len(val) + 44
            d.rounded_rectangle([40, y, 40 + width, y + h], radius=46, fill=th["bubble"])
            for k, line in enumerate(val):
                d.text((76, y + 22 + k * 60), line, font=f, fill=th["text"])
            y += h + 36
    d.rounded_rectangle([150, H - 190, W - 40, H - 100], radius=45, outline=th["sep"], width=3)
    d.text((190, H - 172), "문자 메시지", font=F(42), fill=th["sub"])
    return img


def messages_inbox(dark, rows):
    """rows: (sender, time, [preview lines])"""
    th = DARK if dark else LIGHT
    img = Image.new("RGB", (W, H), th["page"])
    d = ImageDraw.Draw(img)
    status_bar(d, th)
    d.text((48, 190), "메시지", font=F(100, "b"), fill=th["text"])
    d.rounded_rectangle([40, 340, W - 40, 440], radius=28, fill=th["field"])
    d.text((110, 362), "검색", font=F(46), fill=th["sub"])
    y = 490
    for sender, time, preview in rows:
        d.ellipse([40, y + 10, 170, y + 140], fill=(140, 140, 150))
        d.text((200, y), sender, font=F(48, "sb"), fill=th["text"])
        d.text((W - 60 - tw(time, F(40)), y + 6), time, font=F(40), fill=th["sub"])
        for k, line in enumerate(preview):
            d.text((200, y + 66 + k * 56), line, font=F(44), fill=th["sub"])
        y += 66 + 56 * len(preview) + 40
        d.line([(200, y - 18), (W, y - 18)], fill=th["sep"], width=2)
    return img


def kakao_chat(friend, msgs, top_banner=None):
    """msgs: ('friend'|'me', text, time)"""
    img = Image.new("RGB", (W, H), (186, 206, 224))
    d = ImageDraw.Draw(img)
    status_bar(d, LIGHT)
    d.text((40, 150), "‹", font=F(100), fill=(0, 0, 0))
    d.text((150, 168), friend, font=F(54, "sb"), fill=(0, 0, 0))
    y = 340
    f = F(46)
    for who, text, time in msgs:
        width = tw(text, f) + 64
        if who == "friend":
            d.rounded_rectangle([40, y, 150, y + 110], radius=40, fill=(150, 170, 200))
            d.text((180, y), friend, font=F(38), fill=(60, 60, 70))
            by = y + 56
            d.rounded_rectangle([180, by, 180 + width, by + 96], radius=30, fill=(255, 255, 255))
            d.text((212, by + 22), text, font=f, fill=(0, 0, 0))
            d.text((196 + width, by + 52), time, font=F(30), fill=(80, 90, 100))
            y = by + 96 + 40
        else:
            x1 = W - 40
            d.rounded_rectangle([x1 - width, y, x1, y + 96], radius=30, fill=(254, 229, 0))
            d.text((x1 - width + 32, y + 22), text, font=f, fill=(0, 0, 0))
            d.text((x1 - width - 16 - tw(time, F(30)), y + 52), time, font=F(30), fill=(80, 90, 100))
            y += 96 + 40
    d.rectangle([0, H - 200, W, H], fill=(255, 255, 255))
    d.rounded_rectangle([140, H - 170, W - 140, H - 80], radius=45, fill=(240, 240, 240))
    if top_banner:
        banner(d, 70, *top_banner, False)
    return img


def card_history(dark, title, summary, groups):
    """summary: [(label, value)], groups: (date header, [(merchant, amount, sub)])"""
    th = DARK if dark else LIGHT
    img = Image.new("RGB", (W, H), th["page"])
    d = ImageDraw.Draw(img)
    status_bar(d, th)
    d.text((40, 150), "‹", font=F(100), fill=th["text"])
    d.text(((W - tw(title, F(54, "sb"))) / 2, 168), title, font=F(54, "sb"), fill=th["text"])
    d.rounded_rectangle([40, 300, W - 40, 300 + 110 * len(summary) + 60], radius=36, fill=th["card"] if dark else th["bg"])
    y = 330
    for label, value in summary:
        d.text((90, y + 14), label, font=F(44), fill=th["sub"])
        d.text((W - 90 - tw(value, F(56, "b")), y), value, font=F(56, "b"), fill=th["text"])
        y += 110
    y += 100
    for header, rows in groups:
        d.text((48, y), header, font=F(42, "sb"), fill=th["sub"])
        y += 80
        for merchant, amount, sub in rows:
            d.ellipse([48, y + 6, 148, y + 106], fill=(120, 140, 170))
            d.text((180, y), merchant, font=F(48, "m"), fill=th["text"])
            d.text((180, y + 66), sub, font=F(38), fill=th["sub"])
            d.text((W - 60 - tw(amount, F(50, "sb")), y + 6), amount, font=F(50, "sb"), fill=th["text"])
            y += 160
        y += 30
    return img


# ---------- receipts ----------

def receipt_paper(rows, width=880):
    """rows: ('c', text, size, weight) | ('lr', left, right) | ('item', name, qty, amount) | ('sep',) | ('gap',)"""
    lh = {"c": 58, "lr": 50, "item": 50, "sep": 34, "gap": 30}
    height = 90 + sum(lh[r[0]] if r[0] != "c" else max(58, r[2] + 16) for r in rows) + 90
    paper = Image.new("RGB", (width, height), (250, 248, 241))
    d = ImageDraw.Draw(paper)
    ink = (38, 38, 42)
    f = F(36)
    y = 90
    for r in rows:
        if r[0] == "c":
            ff = F(r[2], r[3])
            d.text(((width - tw(r[1], ff)) / 2, y), r[1], font=ff, fill=ink)
            y += max(58, r[2] + 16)
        elif r[0] == "lr":
            d.text((50, y), r[1], font=f, fill=ink)
            d.text((width - 50 - tw(r[2], f), y), r[2], font=f, fill=ink)
            y += lh["lr"]
        elif r[0] == "item":
            d.text((50, y), r[1], font=f, fill=ink)
            d.text((width - 270 - tw(r[2], f), y), r[2], font=f, fill=ink)
            d.text((width - 50 - tw(r[3], f), y), r[3], font=f, fill=ink)
            y += lh["item"]
        elif r[0] == "sep":
            for x in range(40, width - 40, 22):
                d.line([(x, y + 14), (x + 11, y + 14)], fill=ink, width=2)
            y += lh["sep"]
        else:
            y += lh["gap"]
    return paper


def photo(paper, angle, bg, blur, light_dir):
    pad = 260
    canvas = Image.new("RGB", (paper.width + pad * 2, paper.height + pad * 2), bg)
    rot = paper.rotate(angle, expand=True, resample=Image.BICUBIC, fillcolor=bg)
    canvas.paste(rot, ((canvas.width - rot.width) // 2, (canvas.height - rot.height) // 2))
    grad = Image.linear_gradient("L").rotate(light_dir).resize(canvas.size)
    grad = grad.point(lambda v: int(150 + v * 105 / 255))
    canvas = ImageChops.multiply(canvas, Image.merge("RGB", [grad, grad, grad]))
    noise = Image.effect_noise(canvas.size, 22).point(lambda v: 228 + v // 9)
    canvas = ImageChops.multiply(canvas, Image.merge("RGB", [noise, noise, noise]))
    canvas = canvas.filter(ImageFilter.GaussianBlur(blur))
    return canvas.resize((int(canvas.width * 0.85), int(canvas.height * 0.85)), Image.LANCZOS)


def won(n):
    return f"{n:,}"


def receipt_case(cid, store, branch_lines, date_line, items, extra_tail, angle, bg, blur, light, note, cat="receipt"):
    total = sum(a for _, _, a in items)
    rows = [("c", store, 50, "b")] + [("c", s, 32, "r") for s in branch_lines] + [("gap",), ("lr", date_line, "POS 02-0137"), ("sep",),
            ("item", "상품명", "수량", "금액"), ("sep",)]
    for name, qty, amount in items:
        rows.append(("item", name, str(qty), won(amount)))
    vat = round(total / 11)
    rows += [("sep",), ("lr", "합계", won(total)), ("lr", "과세물품가액", won(total - vat)), ("lr", "부가세", won(vat)), ("sep",),
             ("lr", "신용카드", won(total)), ("lr", "카드번호", "5310-****-****-1234"), ("lr", "할부", "일시불"),
             ("lr", "승인금액", won(total)), ("lr", "승인번호", "30012345")]
    rows += extra_tail
    img = photo(receipt_paper(rows), angle, bg, blur, light)
    img.save(os.path.join(OUT, f"{cid}.jpg"), quality=62)
    date = "2026-" + date_line[5:10]
    entries = [entry(store, a, date, i=name) for name, _, a in items]
    add_truth(cid, cat, [entries], note, lenient=[[entry(store, total, date)]])


def save(img, cid):
    img.save(os.path.join(OUT, f"{cid}.png"))


# ================= (a) several payments in one screenshot =================
SH = ((0, 70, 160), "S")
HD = ((20, 20, 20), "H")
KB = ((255, 188, 0), "K")
SS = ((20, 80, 200), "S")
KP = ((255, 220, 0), "k")
CP = ((230, 60, 40), "C")
TS = ((0, 100, 255), "t")
NP = ((3, 199, 90), "N")

save(lock_screen(False, "10월 9일 목요일", [
    ("신한 SOL페이", "2시간 전", ["[신한카드] 승인 김O규님", "5,800원 일시불", "10/09 14:22 스타벅스 강남점", "누적 1,240,500원"], *SH),
    ("현대카드", "1시간 전", ["현대카드 승인 김*규", "32,000원 일시불", "10/09 15:10 교보문고 광화문점", "누적 1,272,500원"], *HD),
    ("신한 SOL페이", "지금", ["[신한카드] 승인 김O규님", "12,900원 일시불", "10/09 16:03 올리브영 강남역점", "누적 1,285,400원"], *SH),
]), "a1")
add_truth("a1", "multi", [[entry("스타벅스 강남점", 5800, "2026-10-09"), entry("교보문고 광화문점", 32000, "2026-10-09"),
                           entry("올리브영 강남역점", 12900, "2026-10-09")]], "lock screen, 3 card notifications")

save(lock_screen(True, "10월 10일 금요일", [
    ("KB Pay", "12:31", ["KB국민카드 승인", "18,500원 일시불", "10/10 12:31 버거킹 역삼점"], *KB),
    ("삼성카드", "08:12", ["삼성카드 승인 김O규", "4,500원 일시불", "10/10 08:12 메가커피 선릉점"], *SS),
    ("KB Pay", "19:45", ["KB국민카드 승인", "54,000원 일시불", "10/10 19:45 홈플러스 강서점", "누적 802,000원"], *KB),
    ("카카오페이", "21:00", ["결제 완료", "넷플릭스 9,900원", "10/10 21:00"], *KP),
]), "a2")
add_truth("a2", "multi", [[entry("버거킹 역삼점", 18500, "2026-10-10"), entry("메가커피 선릉점", 4500, "2026-10-10"),
                           entry("홈플러스 강서점", 54000, "2026-10-10"), entry("넷플릭스", 9900, "2026-10-10")]],
          "dark lock screen, 4 payment notifications from 3 apps")

save(card_history(False, "이용내역", [("이번 달 이용금액", "486,300원"), ("결제예정금액(10/25)", "1,120,000원")], [
    ("10.10 (금)", [("배달의민족", "23,000원", "일시불 · 18:20"), ("GS25 역삼점", "3,200원", "일시불 · 08:41")]),
    ("10.09 (목)", [("쿠팡", "45,800원", "일시불 · 22:10"), ("SK에너지 서초주유소", "60,000원", "일시불 · 07:55")]),
    ("10.08 (수)", [("CGV 강남", "28,000원", "일시불 · 20:05")]),
]), "a3")
add_truth("a3", "multi", [[entry("배달의민족", 23000, "2026-10-10"), entry("GS25 역삼점", 3200, "2026-10-10"),
                           entry("쿠팡", 45800, "2026-10-09"), entry("SK에너지 서초주유소", 60000, "2026-10-09"),
                           entry("CGV 강남", 28000, "2026-10-08")]], "card app history list with month totals")

save(card_history(True, "카드 이용내역", [("10월 이용금액", "29,300원")], [
    ("10.10 (금)", [("스타벅스 역삼역점", "6,300원", "일시불 · 08:40"), ("스타벅스 역삼역점", "5,800원", "일시불 · 15:20"),
                   ("이마트24 역삼점", "2,500원", "일시불 · 21:02")]),
    ("10.09 (목)", [("카카오T 택시", "14,700원", "일시불 · 23:48")]),
]), "a4")
add_truth("a4", "multi", [[entry("스타벅스 역삼역점", 6300, "2026-10-10"), entry("스타벅스 역삼역점", 5800, "2026-10-10"),
                           entry("이마트24 역삼점", 2500, "2026-10-10"), entry("카카오T 택시", 14700, "2026-10-09")]],
          "dark card history, same merchant twice")

save(messages_thread(False, "15447200", [
    ("time", "2026년 10월 8일 (수) 오후 12:10"),
    ("in", ["[Web발신]", "신한카드(1234)승인", "김O규", "8,900원(일시불)", "10/08 12:10", "김밥천국 역삼점", "누적1,102,300원"]),
    ("time", "2026년 10월 9일 (목) 오후 7:30"),
    ("in", ["[Web발신]", "신한카드(1234)승인", "김O규", "15,000원(일시불)", "10/09 19:30", "교촌치킨 역삼점", "누적1,117,300원"]),
    ("time", "오늘 오전 8:55"),
    ("in", ["[Web발신]", "신한카드(1234)승인", "김O규", "4,000원(일시불)", "10/10 08:55", "파리바게뜨 역삼점", "누적1,121,300원"]),
]), "a5")
add_truth("a5", "multi", [[entry("김밥천국 역삼점", 8900, "2026-10-08"), entry("교촌치킨 역삼점", 15000, "2026-10-09"),
                           entry("파리바게뜨 역삼점", 4000, "2026-10-10")]], "SMS thread, 3 approvals")

save(lock_screen(True, "10월 10일 금요일", [
    ("현대카드", "10:02", ["현대카드 승인 김*규", "19,800원 일시불", "10/10 10:02 쿠팡"], *HD),
    ("현대카드", "22:15", ["현대카드 승인 김*규", "7,900원 일시불", "10/10 22:15 쿠팡"], *HD),
]), "a6")
add_truth("a6", "multi", [[entry("쿠팡", 19800, "2026-10-10"), entry("쿠팡", 7900, "2026-10-10")]],
          "two payments, same merchant, different times")

# ================= (b) unrelated content around the payment =================
save(kakao_chat("민수", [
    ("friend", "오늘 점심 뭐 먹지?", "오전 11:52"),
    ("me", "김치찌개 ㄱㄱ", "오전 11:53"),
    ("friend", "어제 치킨값 18,000원 보내줘~", "오후 12:30"),
    ("me", "ㅇㅋ 저녁에 보낼게", "오후 12:31"),
    ("friend", "영화 예매했어 2장 28,000원", "오후 12:35"),
], top_banner=("현대카드", "지금", ["현대카드 승인 김*규", "9,000원 일시불", "10/10 12:41 찌개애감동"], *HD)), "b1")
add_truth("b1", "noise", [[entry("찌개애감동", 9000, "2026-10-10")]], "chat with money talk + one card banner")

save(messages_inbox(True, [
    ("1588-0000", "오후 2:03", ["[Web발신] 인증번호 [482913]을", "입력해주세요. 타인 노출 금지"]),
    ("CJ대한통운", "오후 1:20", ["고객님의 상품이 배송완료", "되었습니다. (문 앞)"]),
    ("롯데마트", "오전 11:00", ["(광고) 이번 주 최대 50,000원", "할인 쿠폰 도착! 무료수신거부"]),
    ("현대카드", "어제", ["[Web발신] 현대카드 승인 김*규", "43,000원 일시불 10/08 19:41 교보문고"]),
    ("KT", "어제", ["[KT] 10월 이용요금 52,340원이", "10/25 청구될 예정입니다."]),
]), "b2")
add_truth("b2", "noise", [[entry("교보문고", 43000, "2026-10-08")]], "SMS inbox: OTP, delivery, ad, bill notice + one approval")

img = Image.new("RGB", (W, H), LIGHT["page"])
d = ImageDraw.Draw(img)
status_bar(d, LIGHT)
d.text((48, 170), "KB국민은행", font=F(60, "b"), fill=(0, 0, 0))
d.rounded_rectangle([40, 300, W - 40, 760], radius=40, fill=(245, 241, 230))
d.text((90, 340), "KB국민ONE통장-보통예금", font=F(44), fill=(90, 90, 90))
d.text((90, 400), "123-456-789012", font=F(40), fill=(120, 120, 120))
d.text((90, 490), "잔액", font=F(44), fill=(90, 90, 90))
d.text((90, 550), "1,301,600원", font=F(90, "b"), fill=(0, 0, 0))
d.rounded_rectangle([90, 660, 540, 730], radius=24, fill=(255, 204, 0))
d.text((270, 670), "이체", font=F(44, "sb"), fill=(0, 0, 0))
d.rounded_rectangle([600, 660, W - 90, 730], radius=24, fill=(230, 230, 230))
d.text((800, 670), "내역", font=F(44, "sb"), fill=(0, 0, 0))
d.rounded_rectangle([40, 810, W - 40, 990], radius=36, fill=(255, 246, 214))
d.text((90, 850), "이번 주 최대 30,000원 캐시백 이벤트 ›", font=F(46, "sb"), fill=(120, 80, 0))
d.text((90, 920), "포인트리 3,420P 사용 가능", font=F(40), fill=(140, 110, 40))
d.text((48, 1060), "최근 거래내역", font=F(52, "b"), fill=(0, 0, 0))
y = 1160
for date, title, amount, sub, color in [
    ("10.10", "급여", "+2,500,000원", "입금", (0, 90, 220)),
    ("10.09", "이마트 성수점", "-68,400원", "체크카드", (0, 0, 0)),
    ("10.09", "관리비 자동이체", "-182,000원", "자동이체", (0, 0, 0)),
]:
    d.text((48, y + 8), date, font=F(40), fill=(130, 130, 130))
    d.text((200, y), title, font=F(48, "m"), fill=(0, 0, 0))
    d.text((200, y + 64), sub, font=F(38), fill=(130, 130, 130))
    d.text((W - 60 - tw(amount, F(50, "sb")), y + 4), amount, font=F(50, "sb"), fill=color)
    y += 170
save(img, "b3")
add_truth("b3", "noise", [[entry("이마트 성수점", 68400, "2026-10-09"), entry("관리비 자동이체", 182000, "2026-10-09")]],
          "bank home: balance, points, cashback ad, salary deposit + two outflows")

th = DARK
img = Image.new("RGB", (W, H), th["page"])
d = ImageDraw.Draw(img)
status_bar(d, th)
d.text((48, 170), "쿠팡", font=F(60, "b"), fill=(255, 255, 255))
d.text((48, 290), "주문이 완료되었습니다", font=F(64, "b"), fill=(255, 255, 255))
d.text((48, 380), "2026.10.10 주문 · 내일(토) 도착 예정", font=F(42), fill=th["sub"])
y = 490
for name, price in [("탐사 생수 2L x 12개", "8,990원"), ("네이처리퍼블릭 수분크림 80ml", "21,900원")]:
    d.rounded_rectangle([48, y, 228, y + 180], radius=20, fill=(70, 70, 74))
    d.text((260, y + 10), name, font=F(46, "m"), fill=(255, 255, 255))
    d.text((260, y + 76), "수량 1개", font=F(40), fill=th["sub"])
    d.text((260, y + 126), price, font=F(46, "sb"), fill=(255, 255, 255))
    y += 230
d.line([(48, y), (W - 48, y)], fill=th["sep"], width=2)
y += 40
for label, value in [("상품금액", "30,890원"), ("배송비", "무료"), ("총 결제금액", "30,890원"), ("결제수단", "현대카드 (일시불)")]:
    bold = label == "총 결제금액"
    d.text((48, y), label, font=F(46, "b" if bold else "r"), fill=(255, 255, 255))
    d.text((W - 48 - tw(value, F(46, "b" if bold else "r")), y), value, font=F(46, "b" if bold else "r"), fill=(255, 255, 255))
    y += 80
y += 60
d.text((48, y), "이런 상품은 어때요?", font=F(52, "b"), fill=(255, 255, 255))
y += 90
for k, (name, price) in enumerate([("에어팟 프로 2", "289,000원"), ("다우니 섬유유연제 4L", "15,900원")]):
    x = 48 + k * 560
    d.rounded_rectangle([x, y, x + 520, y + 420], radius=24, fill=(70, 70, 74))
    d.text((x, y + 450), name, font=F(42), fill=(230, 230, 230))
    d.text((x, y + 510), price, font=F(46, "b"), fill=(255, 255, 255))
save(img, "b4")
add_truth("b4", "noise", [
    [entry("쿠팡", 30890, "2026-10-10")],
    [entry("쿠팡", 8990, "2026-10-10", i="탐사 생수 2L x 12개"), entry("쿠팡", 21900, "2026-10-10", i="네이처리퍼블릭 수분크림 80ml")],
], "order complete page with recommended-product prices")

save(lock_screen(False, "10월 10일 금요일", [
    ("카카오톡", "6:02", ["엄마", "저녁 먹고 들어오니?"], *KP),
    ("날씨", "5:30", ["오후 9시부터 비 소식이 있어요. 우산 챙기세요."], (60, 150, 230), "W"),
    ("쿠팡", "5:00", ["(광고) 오늘의 특가!", "다이슨 무선청소기 399,000원"], *CP),
    ("삼성카드", "6:22", ["삼성카드 승인 김O규", "27,500원 일시불", "10/10 18:22 아웃백 강남점"], *SS),
]), "b5")
add_truth("b5", "noise", [[entry("아웃백 강남점", 27500, "2026-10-10")]], "lock screen: chat, weather, ad push + one approval")

img = Image.new("RGB", (W, H), LIGHT["page"])
d = ImageDraw.Draw(img)
status_bar(d, LIGHT)
y = 420
d.text((48, y), "아이폰 18 Pro 국내 출시…", font=F(66, "b"), fill=(0, 0, 0))
d.text((48, y + 90), "가격은 1,550,000원부터", font=F(66, "b"), fill=(0, 0, 0))
d.text((48, y + 200), "입력 2026.10.10 09:30  |  IT 데스크", font=F(38), fill=(120, 120, 120))
para = ["애플이 아이폰 18 Pro를 국내에 정식 출시했다.", "기본 모델은 1,550,000원, 256GB 모델은",
        "1,700,000원이다. 통신사들은 사전예약 고객에게", "최대 100,000원 상당의 혜택을 제공한다.",
        "업계는 전작 대비 출고가가 50,000원 올랐다며", "소비자 부담이 커졌다고 분석했다."]
for k, line in enumerate(para):
    d.text((48, y + 300 + k * 72), line, font=F(46), fill=(30, 30, 30))
d.rounded_rectangle([40, H - 200, W - 40, H - 100], radius=50, fill=(235, 235, 240))
d.text((420, H - 180), "news.example.com", font=F(42), fill=(60, 60, 60))
banner(d, 70, "토스", "지금", ["토스페이 결제 완료", "12,000원 · 씨네Q 신도림"], *TS, False)
save(img, "b6")
add_truth("b6", "noise", [[entry("씨네Q 신도림", 12000, "")]], "news article with prices + payment banner without a date")

save(lock_screen(True, "10월 10일 금요일", [
    ("네이버페이", "20:11", ["결제 완료", "34,500원 · 무신사", "10/10 20:11"], *NP),
    ("토스뱅크", "19:02", ["입금 50,000원", "김민수 → 내 통장"], *TS),
    ("카카오톡", "18:40", ["동아리 단톡방", "이번 달 회비 30,000원씩 입금 부탁해요"], *KP),
    ("신한 SOL페이", "17:05", ["[신한카드] 승인 김O규님", "7,800원 일시불", "10/10 17:05 이디야커피 역삼점"], *SH),
]), "b7")
add_truth("b7", "noise", [[entry("무신사", 34500, "2026-10-10"), entry("이디야커피 역삼점", 7800, "2026-10-10")]],
          "two payments + incoming transfer + dues request")

# ================= (c) receipts with many items (photos) =================
receipt_case("c1", "이마트 성수점", ["서울 성동구 뚝섬로 379", "사업자 206-86-50913  T.02-6918-1234"], "2026-10-09 18:32", [
    ("서울우유 1L", 1, 2980), ("신라면 5입", 1, 4480), ("햇반 210g*3", 1, 4990), ("풀무원 두부", 1, 1980),
    ("바나나 1송이", 1, 3980), ("계란 30구", 1, 7980), ("삼겹살 600g", 1, 14800), ("코카콜라 1.5L", 1, 2780),
], [("sep",), ("lr", "신세계포인트 적립", "439P"), ("lr", "누적 포인트", "12,840P")], 2.5, (112, 86, 60), 1.2, 35,
    "mart receipt, 8 items, points block")

receipt_case("c2", "블루보틀 성수", ["서울 성동구 아차산로 7", "T.02-000-0000"], "2026-10-10 10:14", [
    ("아메리카노", 2, 11000), ("카페라떼", 1, 6000), ("크루아상", 1, 4800),
], [], -3.0, (60, 60, 64), 1.4, 120, "cafe receipt, qty 2 line")

receipt_case("c3", "본죽 역삼점", ["서울 강남구 테헤란로 152", "T.02-555-0000"], "2026-10-08 12:47", [
    ("전복죽", 1, 15000), ("소고기야채죽", 1, 11000), ("단호박죽", 1, 10000), ("음료", 1, 2000),
], [("sep",), ("c", "다음 방문시 사용 가능 쿠폰 1,000원 할인", 30, "r")], 4.0, (30, 30, 34), 1.6, 250,
    "restaurant receipt, coupon line, strong tilt")

receipt_case("c4", "CU 역삼중앙점", ["서울 강남구 역삼로 180", "T.02-501-0000"], "2026-10-10 21:15", [
    ("삼각김밥 참치마요", 1, 1400), ("바나나우유", 1, 1700), ("컵라면 육개장", 1, 1500), ("생수 500ml", 1, 1000),
    ("젤리 하리보", 1, 1500), ("봉투", 1, 20),
], [("sep",), ("lr", "CU멤버십 적립", "71P"), ("lr", "다음 방문시 쿠폰", "1,000원 할인")], -2.0, (150, 120, 90), 1.0, 300,
    "convenience store, 20-won bag item, coupon line")

receipt_case("c5", "온누리약국", ["서울 강남구 논현로 508", "T.02-563-0000"], "2026-10-09 09:20", [
    ("타이레놀 500mg", 1, 3500), ("박카스D", 3, 3000),
], [], 1.5, (90, 90, 100), 1.2, 80, "pharmacy, 2 items")

receipt_case("c6", "다이소 강남역점", ["서울 강남구 강남대로 396", "T.02-3482-0000"], "2026-10-10 16:05", [
    ("수납박스 대", 2, 6000), ("멀티탭 4구", 1, 5000), ("주방세제 1L", 1, 2000), ("수세미 3입", 1, 1000),
    ("물티슈 100매", 2, 2000), ("건전지 AA 4입", 1, 2000), ("포스트잇", 1, 1000), ("볼펜 3입", 1, 1000),
    ("옷걸이 10입", 1, 3000), ("텀블러", 1, 5000), ("방향제", 1, 2000), ("휴지통", 1, 3000),
], [("sep",), ("c", "교환/환불은 30일 이내 영수증 지참", 30, "r")], -1.5, (120, 100, 80), 1.1, 200,
    "long receipt, 12 items")

# ================= (d) single-payment controls =================
save(lock_screen(True, "10월 10일 금요일", [
    ("신한 SOL페이", "09:05", ["[신한카드] 승인 김O규님", "5,800원 일시불", "10/10 09:05 스타벅스 선릉점", "누적 1,302,200원"], *SH),
]), "d1")
add_truth("d1", "control", [[entry("스타벅스 선릉점", 5800, "2026-10-10")]], "single banner")

save(messages_thread(False, "15888900", [
    ("time", "2026년 10월 9일 (목) 오후 8:11"),
    ("in", ["[Web발신]", "삼성카드 승인 김O규", "23,000원 일시불", "10/09 20:11", "배달의민족", "누적 845,000원"]),
]), "d2")
add_truth("d2", "control", [[entry("배달의민족", 23000, "2026-10-09")]], "single SMS")

for cid, dark, brand, merchant, amount, when, method, extra in [
    ("d3", False, "카카오페이", "스타벅스 코리아", "6,300원", "2026.10.10 11:20", "카카오페이머니", ("적립", "카카오페이 포인트 63P")),
    ("d5", True, "토스페이", "무신사 스토어", "59,000원", "2026.10.08 22:47", "토스머니", ("혜택", "토스포인트 590원 적립 예정")),
]:
    th = DARK if dark else LIGHT
    img = Image.new("RGB", (W, H), th["page"])
    d = ImageDraw.Draw(img)
    status_bar(d, th)
    d.text((48, 170), brand, font=F(56, "b"), fill=th["text"])
    d.ellipse([W / 2 - 110, 420, W / 2 + 110, 640], fill=(255, 220, 0) if not dark else (0, 100, 255))
    d.text(((W - tw("결제 완료", F(70, "b"))) / 2, 700), "결제 완료", font=F(70, "b"), fill=th["text"])
    d.text(((W - tw(merchant, F(50))) / 2, 820), merchant, font=F(50), fill=th["sub"])
    d.text(((W - tw(amount, F(100, "b"))) / 2, 900), amount, font=F(100, "b"), fill=th["text"])
    y = 1140
    for label, value in [("결제일시", when), ("결제수단", method), extra]:
        d.text((90, y), label, font=F(44), fill=th["sub"])
        d.text((W - 90 - tw(value, F(44)), y), value, font=F(44), fill=th["text"])
        y += 100
    d.rounded_rectangle([48, H - 260, W - 48, H - 120], radius=30, fill=th["accent"])
    d.text(((W - tw("확인", F(52, "sb"))) / 2, H - 222), "확인", font=F(52, "sb"), fill=(255, 255, 255))
    save(img, cid)
    add_truth(cid, "control", [[entry(merchant, int(amount[:-1].replace(",", "")), "2026-" + when[5:10].replace(".", "-"))]],
              f"{brand} completion screen")

receipt_case("d4", "파리바게뜨 역삼점", ["서울 강남구 테헤란로 129", "T.02-000-0000"], "2026-10-10 08:31", [
    ("소보로빵", 1, 2300), ("우유식빵", 1, 4200),
], [], 1.0, (100, 80, 60), 1.0, 60, "simple bakery receipt, 2 items", cat="control")

TRUTH.sort(key=lambda t: t["id"])
for t in TRUTH:
    t["file"] = next(f for f in os.listdir(OUT) if f.startswith(t["id"] + "."))
with open(os.path.join(OUT, "truth.json"), "w", encoding="utf-8") as fp:
    json.dump(TRUTH, fp, ensure_ascii=False, indent=1)
print(len(TRUTH), "cases")
