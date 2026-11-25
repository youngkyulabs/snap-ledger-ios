#!/usr/bin/env python3
"""Outcome counts for the screenshot-noise corpus.

Usage: python3 summarize.py <corpus> <records.jsonl> [<records.jsonl> ...] [--detail]
Each run lands in one of four outcomes: gated (no payment signal), empty (passed the gate, no entry),
entry (at least one entry: a false entry, since no image here is a payment) and error (extraction threw).
"entry" and "error" stay in review even when images without a result are discarded (option A).
"""
import collections
import json
import os
import sys

args = [a for a in sys.argv[1:] if not a.startswith("--")]
detail = "--detail" in sys.argv
corpus, paths = args[0], args[1:]
truth = {t["id"]: t for t in json.load(open(os.path.join(corpus, "truth.json"), encoding="utf-8"))}

# Mirrors CandidateHeuristics.paymentKeywords; only used to say why an image passed the gate.
KEYWORDS = ["승인", "일시불", "할부", "일반승인", "결제", "합계", "총액", "총 금액", "결제금액", "영수증",
            "현금영수증", "카드사용", "체크카드", "신용카드"]


def outcome(rec):
    if rec["gated"]:
        return "gated"
    if rec.get("error"):
        return "error"
    return "entry" if rec["entries"] else "empty"


records = []
for path in paths:
    with open(path, encoding="utf-8") as fp:
        records += [json.loads(line) for line in fp if line.strip()]

by_cat = collections.defaultdict(collections.Counter)
by_image = collections.defaultdict(collections.Counter)
entries_seen = collections.defaultdict(collections.Counter)
for rec in records:
    o = outcome(rec)
    by_cat[rec["cat"]][o] += 1
    by_cat["ALL"][o] += 1
    by_image[rec["id"]][o] += 1
    for e in rec["entries"]:
        entries_seen[rec["id"]][f'{e["m"]} {e["i"]} {e["a"]}'.replace("  ", " ")] += 1

print(f"{'cat':<4} {'runs':>4} {'gated':>6} {'empty':>6} {'entry':>6} {'error':>6}  {'A-left':>7}  images(entry|error any run)")
for cat in sorted(c for c in by_cat if c != "ALL") + ["ALL"]:
    c = by_cat[cat]
    runs = sum(c.values())
    left = c["entry"] + c["error"]
    ids = [i for i in by_image if cat in ("ALL", truth[i]["cat"])]
    noisy = sum(1 for i in ids if by_image[i]["entry"] + by_image[i]["error"] > 0)
    print(f"{cat:<4} {runs:>4} {c['gated']:>6} {c['empty']:>6} {c['entry']:>6} {c['error']:>6}  "
          f"{left / runs:>6.1%}  {noisy}/{len(ids)}")

if detail:
    print()
    for i in sorted(by_image):
        c = by_image[i]
        ocr_path = os.path.join(corpus, "ocr", f"{i}.txt")
        text = open(ocr_path, encoding="utf-8").read() if os.path.exists(ocr_path) else ""
        words = [k for k in KEYWORDS if k in text]
        gate = "gated" if c["gated"] else ("keyword " + ",".join(words) if words else "amount only")
        print(f"{i} {truth[i]['cat']} gate={gate} | empty={c['empty']} entry={c['entry']} error={c['error']} | {truth[i]['note']}")
        for text_entry, n in entries_seen[i].most_common():
            print(f"    {n}x {text_entry}")
