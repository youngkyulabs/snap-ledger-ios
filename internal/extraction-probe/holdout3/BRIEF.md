# Third held-out corpus brief

## Purpose

An evaluation set for a Korean expense app. A user shares a screenshot or a receipt photo; the app turns it into
ledger entries (merchant, amount, date; one entry per purchased line on a receipt). The most common shared screen
is a phone screen — the home screen, a web page or a KakaoTalk chat — at the moment a payment notification banner
appears on top of it. This set measures how well the app picks out only the money that was actually spent. You
build the images and the answer key.

## Deliverable

`gen_holdout3.py <out_dir>` — Python 3 with Pillow. Fonts: `/System/Library/Fonts/AppleSDGothicNeo.ttc`, face index
0 = Regular, 2 = Medium, 4 = SemiBold, 6 = Bold. It writes every image and `truth.json` into `<out_dir>`, and the
output must be the same each time it runs (seed any randomness you use).

## What to draw

Three strata (field `cat`), with minimum counts. Vary apps, merchants, amounts, layouts and wording inside each.

- **B1 — at least 10.** A home screen (app icons, widgets with numbers such as weather, battery, steps, a calendar),
  a web page (an article or a shopping page with prices) or a KakaoTalk chat (messages that mention money), with one
  or two payment notification banners on top — from card companies, Kakao Pay, Naver Pay and Toss. Mix the banner
  styles real apps use, for example `[신한카드] 승인 김*수 12,000원 일시불 10/09 14:22 스타벅스 강남점 누적 1,240,500원`,
  `12,000원 · 씨네Q 신도림`, `GS25 선릉역점에서 4,600원을 결제했어요`, and others you know: the merchant on its own line,
  English merchant names, an installment, a check card, an overseas purchase in won.
- **B2 — at least 7.** Amounts that are not spending: an incoming transfer, a salary or interest deposit, a balance,
  a bill that is not paid yet ("청구 예정", "납부 예정", a 고지서), numbers someone pasted into a chat. Some of these
  screens also have one real payment banner; others contain no spending at all.
- **B3 — at least 10.** Ordinary inputs: a single payment notification, an SMS approval message, a payment-complete
  screen, a receipt photo, a card or bank transaction list.

Rendering:
- Mix light and dark mode inside every stratum.
- Screenshots: 1179×2556 PNG with an iOS-style status bar. Banners look like iOS notifications (rounded card, app
  icon, title, time, body).
- Receipt photos: JPEG of the paper on a background, rotated 1–4°, mild blur, uneven lighting.
- Print dates between 2026-10-01 and 2026-10-11, in the forms real screens use ("10/09 14:22", "2026-10-09 18:32",
  "10.09 (금)", "2026.10.09"). Use the real weekday for each date.

## Answer key

`truth.json` is a list of cases:

```json
{"id": "b1-01", "cat": "B1", "file": "b1-01.png",
 "accept": [[{"m": "스타벅스 강남점", "i": null, "a": 12000, "d": "2026-10-09"}]],
 "lenient": [],
 "note": "home screen, one Shinhan approval banner"}
```

- `accept` lists every acceptable full answer for the image (usually one). `entry = {"m": merchant or store,
  "i": item name or null, "a": amount in won as an int, "d": "YYYY-MM-DD" or ""}`.
- Every payment, transfer, auto-debit or withdrawal that has already left the user's account is an entry —
  **including money sent to a person**. A card or pay notification, an SMS approval or a payment-complete screen →
  one entry.
- A KakaoTalk 알림톡 or channel message that reports a payment is a payment notice, not chat content.
- A receipt → one entry per purchased line: `m` = store name, `i` = item name, `a` = that line's printed amount.
  Put the single-total alternative `[{"m": store, "i": null, "a": total, "d": date}]` in `lenient`.
- A transaction list → one entry per row where money went out.
- Never an entry: incoming money (deposits, transfers received, salary, interest), balances, bills not paid yet,
  amounts mentioned in chats or articles, prices in ads or shopping pages, totals, tax lines, points, coupons.
- A screen with no spending → `"accept": [[]]`.
- `"d": ""` when the image shows no date for that payment. When a lock or home screen shows today's date but the
  banner itself has none, list both answers in `accept` (with that date and with `""`).
- If a screen can reasonably be read two ways, list both answers in `accept`.

## Tools and limits

- To confirm your images render legibly, dump the OCR text the app would see:
  `<probe> <out_dir> /dev/null 1 ocr` writes `<out_dir>/ocr/<id>.txt` (the `<probe>` path is in your instructions).
- Do not open any other file under `internal/extraction-probe/` or `docs/`. You do not need the app's source code.
