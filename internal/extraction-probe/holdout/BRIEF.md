# Held-out corpus brief

## Purpose

An evaluation set for a Korean expense app. A user shares a screenshot or a receipt photo; the app turns it into
ledger entries (merchant, amount, date; one entry per purchased line on a receipt). This set measures how well that
works on screens it has never been tuned on. You build the images and the answer key.

## Deliverable

`gen_holdout.py <out_dir>` — Python 3 with Pillow. Fonts: `/System/Library/Fonts/AppleSDGothicNeo.ttc`, face index
0 = Regular, 2 = Medium, 4 = SemiBold, 6 = Bold. It writes every image and `truth.json` into `<out_dir>`, and the
output must be the same each time it runs (seed any randomness you use).

## What to draw

Four strata (field `cat`), with minimum counts. Vary stores, merchants, amounts, item counts and layouts inside each.

- **S1 — at least 8.** Item names and amounts sit in visually separate columns, far apart on the line:
  receipt photos from varied stores (3–15 items, a quantity column, a totals/tax block, a card-approval block,
  points lines), and card or bank app transaction lists whose amounts form a right-aligned column.
- **S2 — at least 6.** Each item name and its amount sit close together on the same line: tight receipts
  (e.g. "아메리카노 4,500" with a short gap), lists or messages with amounts written inline in the sentence.
- **S3 — at least 4.** Screens with runs of numbers that are not purchases: a phone-bill breakdown, a chat where
  someone pasted a list of numbers, a stock watchlist, a balance history. Some have one real card payment
  notification banner on top; others contain no spending at all.
- **S4 — at least 6.** Payment notifications from different apps (card companies, Kakao Pay, Naver Pay, Toss), alone
  or stacked on a lock screen, SMS approval messages, payment-complete screens.

Rendering:
- Mix light and dark mode inside every stratum.
- Screenshots: 1179×2556 PNG with an iOS-style status bar.
- Receipt photos: JPEG of the paper on a background (table, cloth), rotated 1–4°, mild blur, uneven lighting.
- Use realistic, varied Korean merchants and amounts. Print dates between 2026-10-01 and 2026-10-11, in the forms
  real screens use ("10/09 14:22", "2026-10-09 18:32", "10.09 (목)", "2026.10.09").

## Answer key

`truth.json` is a list of cases:

```json
{"id": "s1-01", "cat": "S1", "file": "s1-01.jpg",
 "accept": [[{"m": "이마트 성수점", "i": "서울우유 1L", "a": 2980, "d": "2026-10-09"}]],
 "lenient": [[{"m": "이마트 성수점", "i": null, "a": 43970, "d": "2026-10-09"}]],
 "note": "mart receipt, 8 items"}
```

- `accept` lists every acceptable full answer for the image (usually one). `entry = {"m": merchant or store,
  "i": item name or null, "a": amount in won as an int, "d": "YYYY-MM-DD" or ""}`.
- A card/pay notification, an SMS approval, or a payment-complete screen → one entry (merchant, amount, date).
- A receipt → one entry per purchased line: `m` = store name, `i` = item name, `a` = that line's printed amount.
  Put the single-total alternative `[{"m": store, "i": null, "a": total, "d": date}]` in `lenient`.
- A transaction list → one entry per spending (outflow) row.
- Never an entry: totals, tax lines, card number / approval lines, points and rewards, coupons, change, ads,
  prices mentioned in chats or articles, incoming money (deposits, transfers received), bills not yet paid
  (e.g. "청구 예정"), balances.
- A screen with no spending → `"accept": [[]]`.
- `"d": ""` when the image shows no date for that payment. When the image shows a month/day without a year, the
  year is 2026.
- If a screen can reasonably be read two ways (e.g. an order page as one total or as its items), list both answers
  in `accept`.

## Tools and limits

- To confirm your images render legibly, dump the OCR text the app would see:
  `<probe> <out_dir> /dev/null 1 ocr` writes `<out_dir>/ocr/<id>.txt` (the `<probe>` path is in your instructions).
- Do not open any other file under `internal/extraction-probe/` or `docs/`. You do not need the app's source code.
