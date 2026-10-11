#!/usr/bin/env python3
"""Adoption gate for the image route, as fixed in the design document before measuring.

Usage: python3 gate.py <corpus> <current.jsonl> <new.jsonl> [<current-filtered.jsonl>]

current          = the app on main (condition A records)
new              = the branch app (condition R records: image route + item filter)
current-filtered = current's raw output replayed through the branch post-processing (filter alone)

Criteria (image-level strict passes summed over runs):
  S1 new >= current + 20%p, S2 new >= current - 1, S3 new >= current - 2, S4 new >= current - 1,
  overall entry precision new >= current.
Filter alone ships only if it loses no strict pass overall or in any stratum and no entry precision.
"""
import sys

from score import load_records, load_truth, score, summarize

STRATA = ["S1", "S2", "S3", "S4"]
SLACK = {"S2": 1, "S3": 2, "S4": 1}


def by_stratum(rows):
    return {s: summarize([r for r in rows if r["cat"] == s]) for s in STRATA} | {"ALL": summarize(rows)}


def pct(x):
    return "-" if x is None else f"{x:.1%}"


def table(label, cur, new):
    print(f"\n== {label}")
    print(f"{'stratum':<8}{'records':>8}{'current':>10}{'new':>10}{'diff':>9}{'routed':>8}"
          f"{'prec cur':>10}{'prec new':>10}{'date cur':>10}{'date new':>10}")
    for s in STRATA + ["ALL"]:
        c, n = cur[s], new[s]
        if n["n"] == 0 or c["n"] == 0:
            continue
        diff = n["strict"] / n["n"] - c["strict"] / c["n"]
        date_c = f"{c['date_ok']}/{c['pairs']}"
        date_n = f"{n['date_ok']}/{n['pairs']}"
        print(f"{s:<8}{n['n']:>8}{c['strict']:>10}{n['strict']:>10}{diff * 100:>+8.1f}p{n['routed']:>8}"
              f"{pct(c['precision']):>10}{pct(n['precision']):>10}{date_c:>10}{date_n:>10}")


def verdict(ok):
    return "PASS" if ok else "FAIL"


def main(argv):
    corpus = argv[1]
    truth = load_truth(corpus)
    cur = by_stratum(score(truth, load_records(argv[2])))
    new = by_stratum(score(truth, load_records(argv[3])))
    table("current (main) vs new (image route + filter)", cur, new)

    print("\n== gate")
    results = []
    c, n = cur["S1"], new["S1"]
    if n["n"] and c["n"]:
        diff = n["strict"] / n["n"] - c["strict"] / c["n"]
        ok = diff >= 0.20
        results.append(ok)
        print(f"{verdict(ok)} S1: {c['strict']}/{c['n']} -> {n['strict']}/{n['n']} ({diff * 100:+.1f}%p, need >= +20%p)")
    for s, slack in SLACK.items():
        c, n = cur[s], new[s]
        if n["n"]:
            ok = n["strict"] >= c["strict"] - slack
            results.append(ok)
            print(f"{verdict(ok)} {s}: {c['strict']} -> {n['strict']} (may drop by at most {slack})")
    c, n = cur["ALL"], new["ALL"]
    ok = (n["precision"] or 0) >= (c["precision"] or 0)
    results.append(ok)
    print(f"{verdict(ok)} overall entry precision: {pct(c['precision'])} -> {pct(n['precision'])}")
    missing = [s for s in STRATA if new[s]["n"] == 0]
    if missing:
        results.append(False)
        print(f"FAIL strata without records: {', '.join(missing)}")
    print(f"GATE {verdict(all(results))}")

    if len(argv) > 4:
        filt = by_stratum(score(truth, load_records(argv[4])))
        table("current vs current + filter (filter alone)", cur, filt)
        lost = [s for s in STRATA + ["ALL"] if filt[s]["n"] and filt[s]["strict"] < cur[s]["strict"]]
        prec_ok = (filt["ALL"]["precision"] or 0) >= (cur["ALL"]["precision"] or 0)
        ok = not lost and prec_ok
        print(f"\nFILTER ALONE {verdict(ok)}"
              f"{' (strict passes lost in ' + ', '.join(lost) + ')' if lost else ''}"
              f"{'' if prec_ok else ' (entry precision dropped)'}")


if __name__ == "__main__":
    main(sys.argv)
