#!/usr/bin/env python3
"""Everyday screenshots that are not payments, for the screenshot-automation noise measurement.

Usage: python3 gen_noise.py <out_dir>
Writes <id>.png and truth.json ({id, cat, file, note}); every image's correct answer is "no entry".
Strata (cat): N1 chats with prices, N2 shopping and ads before paying, N3 finance screens that are not spending,
N4 comma numbers that are not money, N5 screens without numbers. Deterministic: no randomness.
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)

FONT = "/System/Library/Fonts/AppleSDGothicNeo.ttc"
W, H = 1179, 2556
_fonts = {}


def F(size, w="r"):
    idx = {"r": 0, "m": 2, "sb": 4, "b": 6}[w]
    key = (size, idx)
    if key not in _fonts:
        _fonts[key] = ImageFont.truetype(FONT, size, index=idx)
    return _fonts[key]


LIGHT = dict(page=(255, 255, 255), group=(242, 242, 247), card=(255, 255, 255), text=(0, 0, 0),
             sub=(110, 110, 115), sep=(222, 222, 226), bubble=(233, 233, 235), accent=(0, 122, 255),
             field=(232, 232, 237), red=(230, 50, 50))
DARK = dict(page=(0, 0, 0), group=(0, 0, 0), card=(28, 28, 30), text=(255, 255, 255),
            sub=(152, 152, 157), sep=(56, 56, 58), bubble=(38, 38, 40), accent=(10, 132, 255),
            field=(28, 28, 30), red=(255, 90, 90))

TRUTH = []


def tw(s, f):
    return f.getlength(s)


def save(img, cid, cat, note):
    img.save(os.path.join(OUT, f"{cid}.png"))
    TRUTH.append({"id": cid, "cat": cat, "file": f"{cid}.png", "note": note})


def status_bar(d, th, time="9:41"):
    d.text((110, 48), time, font=F(50, "sb"), fill=th["text"])
    for i in range(4):
        bx = W - 335 + i * 17
        bh = 12 + i * 8
        d.rectangle([bx, 98 - bh, bx + 10, 98], fill=th["text"])
    x, y = W - 175, 60
    d.rounded_rectangle([x, y, x + 82, y + 40], radius=11, outline=th["sub"], width=3)
    d.rounded_rectangle([x + 6, y + 6, x + 62, y + 34], radius=6, fill=th["text"])


def canvas(th, bg="page"):
    img = Image.new("RGB", (W, H), th[bg])
    d = ImageDraw.Draw(img)
    status_bar(d, th)
    return img, d


def nav(d, th, title):
    d.text((40, 150), "‹", font=F(100), fill=th["accent"])
    d.text(((W - tw(title, F(52, "sb"))) / 2, 172), title, font=F(52, "sb"), fill=th["text"])
    d.line([(0, 290), (W, 290)], fill=th["sep"], width=2)
    return 330


def big_title(d, th, title, y=180):
    d.text((48, y), title, font=F(92, "b"), fill=th["text"])
    return y + 150


def right(d, x1, y, s, f, fill):
    d.text((x1 - tw(s, f), y), s, font=f, fill=fill)


def button(d, th, label, y, fill=None):
    d.rounded_rectangle([48, y, W - 48, y + 140], radius=32, fill=fill or th["accent"])
    d.text(((W - tw(label, F(52, "sb"))) / 2, y + 38), label, font=F(52, "sb"), fill=(255, 255, 255))


def group_rows(d, th, y, rows, title=None):
    """rows: (left, right, sub); returns bottom y."""
    if title:
        d.text((80, y), title, font=F(40), fill=th["sub"])
        y += 70
    h = sum(150 if r[2] else 120 for r in rows)
    d.rounded_rectangle([40, y, W - 40, y + h], radius=36, fill=th["card"])
    ry = y
    for k, (left, value, sub) in enumerate(rows):
        rh = 150 if sub else 120
        d.text((90, ry + (24 if sub else 36)), left, font=F(46), fill=th["text"])
        if sub:
            d.text((90, ry + 86), sub, font=F(36), fill=th["sub"])
        if value:
            right(d, W - 90, ry + (rh - 52) / 2, value, F(46, "m"), th["text"])
        if k < len(rows) - 1:
            d.line([(90, ry + rh), (W - 40, ry + rh)], fill=th["sep"], width=2)
        ry += rh
    return y + h + 50


def kakao(title, msgs, members=None):
    """msgs: (who, [lines], time); who is 'me' or a sender name."""
    img = Image.new("RGB", (W, H), (186, 206, 224))
    d = ImageDraw.Draw(img)
    status_bar(d, LIGHT)
    d.text((40, 150), "‹", font=F(100), fill=(0, 0, 0))
    d.text((150, 168), title, font=F(54, "sb"), fill=(0, 0, 0))
    if members:
        d.text((160 + tw(title, F(54, "sb")), 176), members, font=F(44), fill=(90, 90, 100))
    y = 340
    f = F(46)
    for who, lines, time in msgs:
        width = max(tw(line, f) for line in lines) + 64
        h = 60 * len(lines) + 36
        if who == "me":
            x1 = W - 40
            d.rounded_rectangle([x1 - width, y, x1, y + h], radius=30, fill=(254, 229, 0))
            for k, line in enumerate(lines):
                d.text((x1 - width + 32, y + 18 + k * 60), line, font=f, fill=(0, 0, 0))
            d.text((x1 - width - 16 - tw(time, F(30)), y + h - 44), time, font=F(30), fill=(80, 90, 100))
            y += h + 40
        else:
            d.rounded_rectangle([40, y, 150, y + 110], radius=40, fill=(150, 170, 200))
            d.text((180, y), who, font=F(38), fill=(60, 60, 70))
            by = y + 56
            d.rounded_rectangle([180, by, 180 + width, by + h], radius=30, fill=(255, 255, 255))
            for k, line in enumerate(lines):
                d.text((212, by + 18 + k * 60), line, font=f, fill=(0, 0, 0))
            d.text((196 + width, by + h - 44), time, font=F(30), fill=(80, 90, 100))
            y = by + h + 40
    d.rectangle([0, H - 200, W, H], fill=(255, 255, 255))
    d.rounded_rectangle([140, H - 170, W - 140, H - 80], radius=45, fill=(240, 240, 240))
    return img


def imessage(dark, sender, items):
    """items: ('time', text) | ('in', [lines]) | ('me', [lines])"""
    th = DARK if dark else LIGHT
    img, d = canvas(th)
    d.text((40, 150), "‹", font=F(110), fill=th["accent"])
    d.ellipse([W / 2 - 62, 150, W / 2 + 62, 274], fill=(150, 150, 158))
    d.text(((W - tw(sender, F(38))) / 2, 290), sender, font=F(38), fill=th["text"])
    d.line([(0, 360), (W, 360)], fill=th["sep"], width=2)
    y = 410
    f = F(46)
    for kind, val in items:
        if kind == "time":
            d.text(((W - tw(val, F(34))) / 2, y), val, font=F(34), fill=th["sub"])
            y += 70
            continue
        width = max(tw(line, f) for line in val) + 72
        h = 60 * len(val) + 44
        if kind == "me":
            x0 = W - 40 - width
            d.rounded_rectangle([x0, y, W - 40, y + h], radius=46, fill=th["accent"])
            color = (255, 255, 255)
        else:
            x0 = 40
            d.rounded_rectangle([x0, y, x0 + width, y + h], radius=46, fill=th["bubble"])
            color = th["text"]
        for k, line in enumerate(val):
            d.text((x0 + 36, y + 22 + k * 60), line, font=f, fill=color)
        y += h + 36
    d.rounded_rectangle([150, H - 190, W - 40, H - 100], radius=45, outline=th["sep"], width=3)
    d.text((190, H - 172), "iMessage", font=F(42), fill=th["sub"])
    return img


def article(dark, outlet, headline, paragraphs, meta):
    th = DARK if dark else LIGHT
    img, d = canvas(th)
    d.rounded_rectangle([40, 140, W - 40, 230], radius=28, fill=th["field"])
    d.text((90, 160), outlet, font=F(42), fill=th["sub"])
    y = 290
    for line in headline:
        d.text((60, y), line, font=F(68, "b"), fill=th["text"])
        y += 92
    d.text((60, y + 10), meta, font=F(38), fill=th["sub"])
    y += 100
    d.rectangle([60, y, W - 60, y + 520], fill=(120, 130, 140))
    y += 580
    for para in paragraphs:
        for line in para:
            d.text((60, y), line, font=F(46), fill=th["text"])
            y += 72
        y += 40
    return img


# ================= N1: chats that mention prices =================

save(kakao("우리 동기", [
    ("민지", ["어제 회식 정산할게요!"], "오전 10:12"),
    ("민지", ["총 192,000원 나왔고", "6명이라 1인당 32,000원씩", "보내주세요"], "오전 10:13"),
    ("준호", ["넵 바로 보낼게"], "오전 10:20"),
    ("me", ["나도 저녁에 보낼게!"], "오전 10:31"),
], "6"), "n1-01", "N1", "group chat: dinner split request")

save(kakao("중고나라 판매자", [
    ("판매자", ["아이패드 에어 아직 있어요"], "오후 2:02"),
    ("판매자", ["450,000원이고 직거래만 해요"], "오후 2:02"),
    ("me", ["430,000원 가능할까요?"], "오후 2:05"),
    ("판매자", ["440,000원까지 해드릴게요"], "오후 2:11"),
]), "n1-02", "N1", "second-hand price negotiation")

save(imessage(False, "등산 동호회 총무", [
    ("time", "11월 3일 (월) 오전 9:00"),
    ("in", ["11월 회비 안내드립니다", "회비 30,000원", "25일까지 입금 부탁드려요"]),
    ("in", ["12월 송년회 참가비는", "별도로 20,000원입니다"]),
    ("me", ["확인했습니다 감사해요"]),
]), "n1-03", "N1", "club fee notice in iMessage")

save(kakao("엄마 생신 선물", [
    ("누나", ["엄마 선물 패딩으로 하자"], "오후 8:40"),
    ("누나", ["259,000원인데 셋이서", "86,000원씩 내면 될 듯"], "오후 8:41"),
    ("형", ["좋아 나는 찬성"], "오후 8:55"),
    ("me", ["나도 좋아"], "오후 9:02"),
], "3"), "n1-04", "N1", "family gift split proposal")

save(kakao("지수", [
    ("지수", ["나 어제 운동화 샀다"], "오후 6:15"),
    ("지수", ["129,000원이었는데 세일해서", "103,200원에 샀어"], "오후 6:15"),
    ("me", ["오 잘 샀네 색 예쁘다"], "오후 6:22"),
]), "n1-05", "N1", "friend's own purchase mentioned in chat")

save(imessage(True, "아빠", [
    ("time", "어제 오후 7:30"),
    ("in", ["용돈 보냈다", "100,000원 확인해 봐라"]),
    ("me", ["고마워요 아빠!"]),
    ("in", ["밥 잘 챙겨 먹고"]),
]), "n1-06", "N1", "pocket money received, dark mode")

save(kakao("강남 점심 맛집", [
    ("방장", ["신논현역 파스타집 추천해요"], "오전 11:40"),
    ("방장", ["런치 세트 13,900원이고", "음료는 2,000원 추가예요"], "오전 11:41"),
    ("익명의 라이언", ["웨이팅 있나요?"], "오전 11:52"),
    ("방장", ["12시 전엔 괜찮아요"], "오전 11:55"),
], "128"), "n1-07", "N1", "open chat restaurant recommendation with prices")

save(imessage(True, "여행 준비", [
    ("time", "11월 20일 (목) 오후 10:05"),
    ("in", ["제주 숙소 찾았어", "1박 189,000원 오션뷰"]),
    ("in", ["2박에 378,000원이니까", "4명이면 94,500원씩"]),
    ("me", ["좋다 여기로 하자"]),
]), "n1-08", "N1", "trip planning cost split, dark mode")

# ================= N2: shopping and ads before paying =================


def product_page(dark, shop, name, original, price, rate, extras, cta, cid, note):
    th = DARK if dark else LIGHT
    img, d = canvas(th)
    y = nav(d, th, shop)
    d.rectangle([0, y, W, y + 1000], fill=(205, 210, 218))
    y += 1060
    d.text((60, y), name, font=F(58, "sb"), fill=th["text"])
    y += 100
    d.text((60, y), original, font=F(44), fill=th["sub"])
    d.line([(60, y + 28), (60 + tw(original, F(44)), y + 28)], fill=th["sub"], width=3)
    y += 70
    d.text((60, y), rate, font=F(64, "b"), fill=th["red"])
    d.text((80 + tw(rate, F(64, "b")), y), price, font=F(64, "b"), fill=th["text"])
    y += 120
    for line in extras:
        d.text((60, y), line, font=F(42), fill=th["sub"])
        y += 64
    button(d, th, cta, H - 260)
    save(img, cid, "N2", note)


product_page(False, "애플 공식 리셀러", "AirPods Pro 3", "359,000원", "323,100원", "10%",
             ["★ 4.8 (12,345)", "무료배송 · 내일 도착 예정", "카드 무이자 할부 최대 6개월"], "구매하기",
             "n2-01", "product detail with discount")

th = LIGHT
img, d = canvas(th, "group")
y = big_title(d, th, "장바구니")
y = group_rows(d, th, y, [
    ("유기농 바나나 1.2kg", "5,980원", "수량 1"),
    ("그릭요거트 플레인 4개입", "12,900원", "수량 2"),
    ("핸드드립 원두 500g", "24,000원", "수량 1"),
], "로켓배송 상품")
y = group_rows(d, th, y, [
    ("총 상품금액", "55,780원", ""),
    ("배송비", "0원", ""),
    ("총 결제 예정 금액", "55,780원", ""),
])
button(d, th, "55,780원 결제하기", H - 260)
save(img, "n2-02", "N2", "cart before checkout with a pay button")

th = LIGHT
img, d = canvas(th, "group")
y = big_title(d, th, "쿠폰함")
for title, cond, until in [("신규 가입 축하 쿠폰 5,000원", "10,000원 이상 구매 시", "12월 31일까지"),
                           ("배달 할인 3,000원", "15,000원 이상 주문 시", "11월 30일까지"),
                           ("무료배송 쿠폰", "모든 상품", "12월 15일까지")]:
    d.rounded_rectangle([40, y, W - 40, y + 260], radius=36, fill=th["card"])
    d.text((90, y + 40), title, font=F(52, "sb"), fill=th["text"])
    d.text((90, y + 120), cond, font=F(42), fill=th["sub"])
    d.text((90, y + 180), until, font=F(40), fill=th["accent"])
    y += 300
save(img, "n2-03", "N2", "coupon box")

th = LIGHT
img, d = canvas(th)
d.rectangle([0, 140, W, 760], fill=(20, 20, 30))
d.text((70, 260), "BLACK FRIDAY", font=F(96, "b"), fill=(255, 255, 255))
d.text((70, 400), "최대 70% 할인 · 11월 28일까지", font=F(54, "sb"), fill=(255, 210, 0))
d.text((70, 500), "전 상품 무료배송", font=F(46), fill=(220, 220, 220))
y = 820
for name, price, before in [("울 블렌드 코트", "89,000원", "298,000원"), ("캐시미어 머플러", "29,900원", "79,000원"),
                            ("다운 패딩 조끼", "49,000원", "139,000원"), ("니트 비니", "9,900원", "25,000원")]:
    d.rectangle([60, y, 360, y + 300], fill=(210, 214, 220))
    d.text((400, y + 40), name, font=F(50, "sb"), fill=th["text"])
    d.text((400, y + 120), before, font=F(42), fill=th["sub"])
    d.text((400, y + 190), price, font=F(56, "b"), fill=th["red"])
    y += 360
save(img, "n2-04", "N2", "sale ad page")

th = LIGHT
img, d = canvas(th)
d.rounded_rectangle([40, 150, W - 40, 260], radius=30, fill=th["field"])
d.text((100, 178), "무선 청소기", font=F(48), fill=th["text"])
y = 320
for name, price, review in [("다이슨 V15 디텍트", "1,049,000원", "리뷰 3,214"),
                            ("LG 코드제로 A9S", "689,000원", "리뷰 12,087"),
                            ("삼성 비스포크 제트", "799,000원", "리뷰 8,456"),
                            ("샤오미 무선청소기 G11", "289,000원", "리뷰 1,523")]:
    d.rectangle([40, y, 400, y + 360], fill=(214, 218, 224))
    d.text((440, y + 30), name, font=F(50, "sb"), fill=th["text"])
    d.text((440, y + 120), price, font=F(58, "b"), fill=th["text"])
    d.text((440, y + 210), "★ 4.7 · " + review, font=F(40), fill=th["sub"])
    d.text((440, y + 270), "무료배송", font=F(40), fill=th["accent"])
    y += 420
save(img, "n2-05", "N2", "search results with prices")

th = LIGHT
img, d = canvas(th)
y = nav(d, th, "BBQ 역삼점")
d.text((60, y + 20), "최소주문금액 15,000원 · 배달팁 3,000원", font=F(42), fill=th["sub"])
y += 120
for name, price, desc in [("황금올리브 치킨", "23,000원", "BBQ 대표 메뉴"), ("양념 치킨", "24,500원", "달콤한 양념"),
                          ("치킨 반반", "24,500원", "후라이드 + 양념"), ("치즈볼 5개", "6,000원", "사이드"),
                          ("콜라 1.25L", "3,000원", "음료")]:
    d.text((60, y), name, font=F(52, "sb"), fill=th["text"])
    d.text((60, y + 76), desc, font=F(40), fill=th["sub"])
    d.text((60, y + 136), price, font=F(48, "m"), fill=th["text"])
    d.rectangle([W - 360, y, W - 60, y + 220], fill=(214, 218, 224))
    d.line([(60, y + 250), (W - 60, y + 250)], fill=th["sep"], width=2)
    y += 280
button(d, th, "메뉴를 담아 주세요", H - 260, fill=(140, 140, 150))
save(img, "n2-06", "N2", "delivery app menu before ordering")

th = DARK
img, d = canvas(th)
y = nav(d, th, "서울 → 도쿄")
d.text((60, y + 10), "12월 20일 – 12월 23일 · 성인 1명", font=F(44), fill=th["sub"])
y += 110
for airline, times, price in [("대한항공", "08:30 – 10:55 직항", "412,300원"), ("아시아나항공", "09:10 – 11:30 직항", "398,700원"),
                              ("제주항공", "07:05 – 09:25 직항", "289,000원"), ("티웨이항공", "13:40 – 16:00 직항", "276,400원")]:
    d.rounded_rectangle([40, y, W - 40, y + 260], radius=36, fill=th["card"])
    d.text((90, y + 40), airline, font=F(50, "sb"), fill=th["text"])
    d.text((90, y + 120), times, font=F(42), fill=th["sub"])
    right(d, W - 90, y + 110, "왕복 " + price + "~", F(52, "b"), th["text"])
    y += 300
save(img, "n2-07", "N2", "flight search results, dark mode")

th = LIGHT
img, d = canvas(th, "group")
y = big_title(d, th, "찜한 상품")
d.rounded_rectangle([40, y, W - 40, y + 200], radius=36, fill=(255, 240, 240))
d.text((90, y + 40), "찜한 상품 가격이 내려갔어요", font=F(50, "sb"), fill=th["text"])
d.text((90, y + 120), "지금 사면 20,000원 아껴요", font=F(42), fill=th["red"])
y += 260
for name, now, was in [("오버핏 울 코트", "59,000원", "79,000원"), ("러닝화 페가수스", "119,000원", "139,000원"),
                       ("가죽 카드지갑", "32,000원", "45,000원")]:
    d.rounded_rectangle([40, y, W - 40, y + 300], radius=36, fill=th["card"])
    d.rectangle([80, y + 40, 300, y + 260], fill=(214, 218, 224))
    d.text((340, y + 50), name, font=F(50, "sb"), fill=th["text"])
    d.text((340, y + 130), was, font=F(42), fill=th["sub"])
    d.text((340, y + 190), now, font=F(54, "b"), fill=th["red"])
    y += 340
save(img, "n2-08", "N2", "wishlist price drop")

# ================= N3: finance screens that are not spending =================

th = LIGHT
img, d = canvas(th, "group")
y = big_title(d, th, "자산")
d.rounded_rectangle([40, y, W - 40, y + 240], radius=36, fill=th["card"])
d.text((90, y + 40), "총 자산", font=F(44), fill=th["sub"])
d.text((90, y + 110), "12,345,678원", font=F(80, "b"), fill=th["text"])
y += 290
y = group_rows(d, th, y, [
    ("입출금 통장", "1,234,567원", "토스뱅크"),
    ("자유 적금", "3,000,000원", "카카오뱅크"),
    ("청약 저축", "4,800,000원", "국민은행"),
    ("CMA", "3,311,111원", "미래에셋증권"),
], "계좌")
save(img, "n3-01", "N3", "asset overview with balances")


def lock_banners(dark, notifs, cid, note):
    th = DARK
    img = Image.new("RGB", (W, H), (30, 44, 90) if dark else (110, 150, 220))
    d = ImageDraw.Draw(img)
    status_bar(d, th)
    d.text(((W - tw("11월 25일 화요일", F(56, "sb"))) / 2, 250), "11월 25일 화요일", font=F(56, "sb"), fill=(255, 255, 255))
    d.text(((W - tw("9:41", F(300, "sb"))) / 2, 300), "9:41", font=F(300, "sb"), fill=(255, 255, 255))
    y = 760
    for title, time, body in notifs:
        h = 44 + 58 + 58 * len(body) + 34
        d.rounded_rectangle([34, y, W - 34, y + h], radius=58, fill=(58, 58, 60) if dark else (250, 250, 252))
        d.rounded_rectangle([72, y + (h - 112) // 2, 184, y + (h - 112) // 2 + 112], radius=26, fill=(0, 100, 200))
        text = (255, 255, 255) if dark else (0, 0, 0)
        sub = (170, 170, 175) if dark else (120, 120, 125)
        d.text((218, y + 40), title, font=F(46, "sb"), fill=text)
        right(d, W - 78, y + 44, time, F(40), sub)
        for k, line in enumerate(body):
            d.text((218, y + 100 + k * 58), line, font=F(45), fill=text)
        y += h + 22
    save(img, cid, "N3", note)


lock_banners(False, [
    ("국민은행", "지금", ["[입금] 11/25 09:00", "(주)한빛소프트 급여 2,850,000원", "잔액 3,012,345원"]),
    ("카카오뱅크", "1시간 전", ["이자가 입금되었어요", "세이프박스 이자 1,234원"]),
], "n3-02", "salary and interest deposit banners on lock screen")

th = LIGHT
img, d = canvas(th, "group")
y = nav(d, th, "자유 적금")
d.rounded_rectangle([40, y + 20, W - 40, y + 300], radius=36, fill=th["card"])
d.text((90, y + 60), "현재 잔액", font=F(44), fill=th["sub"])
d.text((90, y + 130), "3,000,000원", font=F(80, "b"), fill=th["text"])
y += 350
group_rows(d, th, y, [
    ("만기 예상 금액", "6,123,456원", "세전 기준"),
    ("예상 이자", "123,456원", "연 3.5%"),
    ("다음 자동이체", "500,000원", "12월 1일 입출금 통장에서"),
    ("만기일", "2027년 5월 31일", ""),
], "적금 정보")
save(img, "n3-03", "N3", "savings account detail")

th = LIGHT
img, d = canvas(th, "group")
y = big_title(d, th, "포인트")
d.rounded_rectangle([40, y, W - 40, y + 240], radius=36, fill=th["card"])
d.text((90, y + 40), "사용 가능한 포인트", font=F(44), fill=th["sub"])
d.text((90, y + 110), "12,340P", font=F(80, "b"), fill=th["text"])
y += 290
group_rows(d, th, y, [
    ("출석 체크 적립", "+50P", "11월 25일"),
    ("영수증 리뷰 적립", "+1,230P", "11월 24일"),
    ("캐시백 적립", "+500P", "11월 22일"),
    ("친구 초대 보상", "+3,000P", "11월 20일"),
], "적립 내역")
save(img, "n3-04", "N3", "points balance and earnings")

th = LIGHT
img, d = canvas(th, "group")
y = nav(d, th, "결제수단 관리")
y = group_rows(d, th, y + 20, [
    ("신한카드 Deep Dream", "기본", "체크카드 · 등록일 2025.03.14"),
    ("현대카드 ZERO", "", "신용카드 · 등록일 2024.11.02"),
    ("토스뱅크 통장", "", "계좌 · 등록일 2025.07.21"),
], "등록된 결제수단")
group_rows(d, th, y, [
    ("결제수단 추가하기", "›", ""),
    ("결제 비밀번호 변경", "›", ""),
    ("간편결제 해지", "›", ""),
])
save(img, "n3-05", "N3", "payment method settings")

th = DARK
img, d = canvas(th)
y = nav(d, th, "삼성전자")
d.text((60, y + 20), "71,500원", font=F(96, "b"), fill=th["text"])
d.text((60, y + 160), "+900원 (+1.27%)", font=F(48), fill=th["red"])
y += 260
d.line([(60, y + 400), (W - 60, y + 120)], fill=th["red"], width=6)
y += 500
group_rows(d, th, y, [
    ("보유 수량", "10주", ""),
    ("평균 단가", "68,200원", ""),
    ("평가 금액", "715,000원", ""),
    ("평가 손익", "+33,000원", ""),
], "내 투자")
save(img, "n3-06", "N3", "stock holding, dark mode")

th = LIGHT
img, d = canvas(th)
y = nav(d, th, "알림")
d.rounded_rectangle([40, y + 40, W - 40, y + 640], radius=36, fill=th["group"])
lines = ["결제 비밀번호가 변경되었습니다.", "", "변경 일시: 11월 25일 오전 8:12", "변경 기기: iPhone",
         "", "본인이 변경하지 않았다면", "고객센터로 바로 연락해 주세요."]
ty = y + 90
for line in lines:
    d.text((90, ty), line, font=F(46), fill=th["text"])
    ty += 72
button(d, th, "확인", H - 260)
save(img, "n3-07", "N3", "payment password changed notice (keyword only)")

th = LIGHT
img, d = canvas(th, "group")
y = big_title(d, th, "연말정산 미리보기")
d.rounded_rectangle([40, y, W - 40, y + 260], radius=36, fill=th["card"])
d.text((90, y + 40), "예상 환급액", font=F(44), fill=th["sub"])
d.text((90, y + 110), "312,000원", font=F(84, "b"), fill=th["accent"])
y += 310
group_rows(d, th, y, [
    ("총급여", "41,200,000원", ""),
    ("신용카드 등 사용액 공제", "1,850,000원", ""),
    ("기납부 세액", "1,420,000원", ""),
    ("결정 세액", "1,108,000원", ""),
], "계산 내역")
save(img, "n3-08", "N3", "year-end tax refund preview")

# ================= N4: comma numbers that are not money =================

th = DARK
img, d = canvas(th)
d.rectangle([0, 140, W, 800], fill=(40, 40, 46))
y = 840
for line in ["겨울 캠핑 장비 추천 TOP 10", "| 초보 캠퍼 필수템"]:
    d.text((40, y), line, font=F(56, "sb"), fill=th["text"])
    y += 78
d.text((40, y + 10), "조회수 1,234,567회 · 3주 전", font=F(40), fill=th["sub"])
y += 100
d.ellipse([40, y, 150, y + 110], fill=(120, 120, 130))
d.text((180, y + 10), "캠핑하는 곰", font=F(46, "sb"), fill=th["text"])
d.text((180, y + 66), "구독자 482,000명", font=F(38), fill=th["sub"])
y += 170
d.text((40, y), "좋아요 12,345 · 댓글 1,024", font=F(44), fill=th["text"])
save(img, "n4-01", "N4", "video page with view counts, dark mode")

th = LIGHT
img, d = canvas(th, "group")
y = big_title(d, th, "요약")
for label, value, sub in [("걸음", "8,532 걸음", "오늘"), ("걷기 + 달리기 거리", "6.1km", "오늘"),
                          ("활동 에너지", "1,284kcal", "오늘"), ("이번 주 평균 걸음", "10,241 걸음", "일평균")]:
    d.rounded_rectangle([40, y, W - 40, y + 260], radius=36, fill=th["card"])
    d.text((90, y + 40), label, font=F(46, "sb"), fill=(230, 90, 40))
    right(d, W - 90, y + 44, sub, F(40), th["sub"])
    d.text((90, y + 130), value, font=F(76, "b"), fill=th["text"])
    y += 300
save(img, "n4-02", "N4", "health summary with step counts")

th = LIGHT
img, d = canvas(th)
d.text((60, 170), "daily_hana", font=F(58, "b"), fill=th["text"])
d.ellipse([60, 300, 320, 560], fill=(200, 160, 170))
for k, (num, label) in enumerate([("1,234", "게시물"), ("12,345", "팔로워"), ("567", "팔로잉")]):
    x = 400 + k * 250
    d.text((x, 360), num, font=F(54, "b"), fill=th["text"])
    d.text((x, 440), label, font=F(42), fill=th["text"])
d.text((60, 600), "서울 · 카페 투어 · 필름 사진", font=F(44), fill=th["text"])
y = 760
for row in range(3):
    for col in range(3):
        d.rectangle([col * 393, y + row * 393, col * 393 + 389, y + row * 393 + 389], fill=(180 + col * 15, 190, 200 - row * 10))
save(img, "n4-03", "N4", "social profile with follower counts")

save(article(False, "한빛일보", ["영화 '겨울 항구' 개봉 3주 만에", "누적 관객 1,234,567명"],
             [["배급사에 따르면 '겨울 항구'는 개봉 3주 차", "주말에만 312,400명을 더 모았다."],
              ["전국 2,345개 상영관에서 상영 중이며,", "좌석 점유율은 41%로 집계됐다."]],
             "입력 2026.11.24 09:12 · 기자 김하늘"), "n4-04", "N4", "news article with audience statistics")

th = LIGHT
img, d = canvas(th)
d.rounded_rectangle([60, 160, 320, 420], radius=60, fill=(60, 140, 240))
d.text((360, 190), "가계부 메이트", font=F(60, "b"), fill=th["text"])
d.text((360, 280), "금융 · 생산성", font=F(42), fill=th["sub"])
y = 500
for k, (num, label) in enumerate([("4.8", "평가 12,345개"), ("1,000,000+", "다운로드"), ("4+", "연령")]):
    x = 60 + k * 370
    d.text((x, y), num, font=F(56, "b"), fill=th["text"])
    d.text((x, y + 80), label, font=F(38), fill=th["sub"])
d.line([(60, y + 170), (W - 60, y + 170)], fill=th["sep"], width=2)
y += 230
for line in ["새로운 기능", "· 위젯에서 오늘 기록을 바로 볼 수 있어요", "· 다크 모드 색상을 다듬었어요"]:
    d.text((60, y), line, font=F(46), fill=th["text"])
    y += 76
save(img, "n4-05", "N4", "app store page with rating counts")

th = DARK
img, d = canvas(th)
y = big_title(d, th, "러닝 기록")
for label, value in [("총 거리", "1,234.5km"), ("총 활동", "1,024회"), ("평균 페이스", "5'42\""), ("최장 거리", "21.1km")]:
    d.rounded_rectangle([40, y, W - 40, y + 220], radius=36, fill=th["card"])
    d.text((90, y + 40), label, font=F(44), fill=th["sub"])
    d.text((90, y + 110), value, font=F(72, "b"), fill=(180, 255, 80))
    y += 260
save(img, "n4-06", "N4", "running app totals, dark mode")

th = LIGHT
img, d = canvas(th, "group")
y = nav(d, th, "시즌 랭킹")
d.rounded_rectangle([40, y + 20, W - 40, y + 300], radius=36, fill=th["card"])
d.text((90, y + 60), "내 점수", font=F(44), fill=th["sub"])
d.text((90, y + 130), "12,345점 · 1,234위", font=F(72, "b"), fill=th["text"])
y += 350
group_rows(d, th, y, [
    ("1위  별빛사냥꾼", "98,765점", ""),
    ("2위  고양이대장", "95,120점", ""),
    ("3위  새벽러너", "91,004점", ""),
    ("4위  초코칩", "88,310점", ""),
], "전체 순위")
save(img, "n4-07", "N4", "game ranking with scores")

th = LIGHT
img, d = canvas(th)
y = nav(d, th, "자유게시판")
d.text((60, y + 20), "겨울에 가기 좋은 국내 여행지 추천해 주세요", font=F(52, "sb"), fill=th["text"])
d.text((60, y + 110), "여행좋아 · 조회 12,345 · 추천 1,234 · 댓글 567", font=F(40), fill=th["sub"])
y += 220
for line in ["가족이랑 3박 4일 정도 생각 중이에요.", "눈 구경할 수 있는 곳이면 좋겠어요.", "", "댓글",
             "· 강원도 평창 추천합니다", "· 전주 한옥마을도 좋아요", "· 제주도는 겨울에도 따뜻해요"]:
    d.text((60, y), line, font=F(46), fill=th["text"])
    y += 76
save(img, "n4-08", "N4", "community post with view counts")

# ================= N5: screens without numbers =================

save(kakao("서연", [
    ("서연", ["이번 주말에 볼까?"], "오후 3:12"),
    ("me", ["좋아 어디서 볼래"], "오후 3:15"),
    ("서연", ["성수동 카페 어때", "새로 생긴 데 있대"], "오후 3:16"),
    ("me", ["오 좋아 거기로 가자"], "오후 3:20"),
]), "n5-01", "N5", "plain chat, no numbers")

th = LIGHT
img = Image.new("RGB", (W, H), (236, 232, 222))
d = ImageDraw.Draw(img)
status_bar(d, th)
for k in range(14):
    d.line([(0, 300 + k * 160), (W, 200 + k * 170)], fill=(255, 255, 255), width=24)
for k in range(8):
    d.line([(120 + k * 140, 140), (60 + k * 150, H)], fill=(250, 250, 250), width=18)
for name, x, y in [("서울숲", 200, 700), ("성수역", 640, 980), ("뚝섬역", 300, 1300), ("언더스탠드에비뉴", 520, 1540)]:
    d.ellipse([x - 18, y - 18, x + 18, y + 18], fill=(230, 60, 60))
    d.text((x + 30, y - 30), name, font=F(44, "sb"), fill=(40, 40, 40))
d.rounded_rectangle([40, H - 620, W - 40, H - 80], radius=50, fill=(255, 255, 255))
d.text((90, H - 560), "성수동 카페거리", font=F(60, "b"), fill=th["text"])
d.text((90, H - 470), "서울특별시 성동구 성수동", font=F(44), fill=th["sub"])
d.text((90, H - 390), "도보 경로 · 대중교통 · 자동차", font=F(44), fill=th["accent"])
save(img, "n5-02", "N5", "map with place names")

th = LIGHT
img, d = canvas(th, "group")
y = big_title(d, th, "설정")
y = group_rows(d, th, y, [("에어플레인 모드", "", ""), ("Wi-Fi", "집", ""), ("Bluetooth", "켬", "")])
group_rows(d, th, y, [("알림", "›", ""), ("사운드 및 햅틱", "›", ""), ("집중 모드", "›", ""), ("스크린 타임", "›", "")])
save(img, "n5-03", "N5", "settings screen")

th = LIGHT
img, d = canvas(th, "page")
y = nav(d, th, "메모")
d.text((60, y + 20), "장보기 목록", font=F(64, "b"), fill=th["text"])
y += 140
for line in ["· 우유", "· 계란", "· 대파", "· 두부", "· 사과", "· 키친타월", "", "주말에 할 일",
             "· 세탁소 들르기", "· 화분 분갈이", "· 책 반납하기"]:
    d.text((60, y), line, font=F(50), fill=th["text"])
    y += 84
save(img, "n5-04", "N5", "memo without numbers")

save(imessage(True, "동생", [
    ("time", "어제 오후 9:14"),
    ("in", ["언니 내 충전기 봤어?"]),
    ("me", ["거실 소파 옆에 있던데"]),
    ("in", ["찾았다 고마워"]),
    ("me", ["내일 아침에 같이 나가자"]),
]), "n5-05", "N5", "plain iMessage, dark mode")

save(article(False, "생활과 과학", ["겨울철 실내 습도,", "어떻게 관리할까"],
             [["난방을 시작하면 실내 공기가 금방 건조해진다.", "가습기를 쓰거나 젖은 수건을 널어 두면"],
              ["습도를 높이는 데 도움이 된다.", "환기는 짧게 자주 하는 편이 좋다."]],
             "생활 · 기자 박서준"), "n5-06", "N5", "article without numbers")

th = DARK
img, d = canvas(th)
d.rounded_rectangle([110, 260, W - 110, 1220], radius=40, fill=(90, 70, 120))
d.text((110, 1320), "밤편지", font=F(64, "b"), fill=th["text"])
d.text((110, 1410), "아이유", font=F(50), fill=th["sub"])
d.rounded_rectangle([110, 1560, W - 110, 1572], radius=6, fill=(90, 90, 96))
d.rounded_rectangle([110, 1560, 520, 1572], radius=6, fill=(220, 220, 225))
for cx, direction in [(360, -1), (W - 360, 1)]:
    for off in (0, 60):
        x = cx + direction * off
        d.polygon([(x - direction * 50, 1700), (x - direction * 50, 1800), (x + direction * 10, 1750)], fill=th["text"])
d.rectangle([W / 2 - 50, 1690, W / 2 - 15, 1810], fill=th["text"])
d.rectangle([W / 2 + 15, 1690, W / 2 + 50, 1810], fill=th["text"])
save(img, "n5-07", "N5", "music player, dark mode")

th = LIGHT
img, d = canvas(th)
y = big_title(d, th, "받은 편지함")
for sender, subject, preview in [("박지훈", "회의록 공유드립니다", "어제 회의에서 나온 내용 정리했어요"),
                                 ("도서관", "예약하신 도서가 도착했습니다", "대출 가능 기간 안에 방문해 주세요"),
                                 ("김민지", "주말 등산 일정", "토요일 아침에 출발하는 걸로 할까요"),
                                 ("뉴스레터", "이번 주 읽을거리", "겨울 여행지와 독서 추천")]:
    d.text((60, y), sender, font=F(50, "sb"), fill=th["text"])
    d.text((60, y + 72), subject, font=F(46), fill=th["text"])
    d.text((60, y + 136), preview, font=F(42), fill=th["sub"])
    d.line([(60, y + 210), (W, y + 210)], fill=th["sep"], width=2)
    y += 240
save(img, "n5-08", "N5", "mail inbox without numbers")

TRUTH.sort(key=lambda t: t["id"])
with open(os.path.join(OUT, "truth.json"), "w", encoding="utf-8") as fp:
    json.dump(TRUTH, fp, ensure_ascii=False, indent=1)
print(len(TRUTH), "cases")
