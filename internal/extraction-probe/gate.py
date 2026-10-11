#!/usr/bin/env python3
"""Adoption gates, as fixed in the design documents before measuring.

Usage: python3 gate.py [--gate pr1|mixed] <corpus> <current.jsonl> <new.jsonl> [<alternative.jsonl>]

current     = the app on main
new         = the branch app
alternative = current's raw output replayed through the branch post-processing (see each gate)

Criteria use image-level strict passes summed over runs.
pr1   (image route, strata S1-S4): S1 new >= current + 20%p, S2 >= current - 1, S3 >= current - 2,
      S4 >= current - 1, overall entry precision new >= current. Alternative = "filter alone": ships only if it
      loses no strict pass overall or in any stratum and no entry precision.
mixed (mixed screens, strata B1-B3): B1 new >= current + 20%p, B2 >= current + 10%p, B3 >= current - 1,
      overall entry precision new >= current. Alternative = "post-processing only": ships only if B1 rises,
      B3 does not drop and entry precision does not drop.
"""
import sys

from score import load_records, load_truth, score, summarize

GATES = {
    "pr1": {
        "strata": ["S1", "S2", "S3", "S4"],
        "gain": {"S1": 0.20},
        "slack": {"S2": 1, "S3": 2, "S4": 1},
        "alternative": "filter alone",
    },
    "mixed": {
        "strata": ["B1", "B2", "B3"],
        "gain": {"B1": 0.20, "B2": 0.10},
        "slack": {"B3": 1},
        "alternative": "post-processing only",
    },
}


def by_stratum(rows, strata):
    return {s: summarize([r for r in rows if r["cat"] == s]) for s in strata} | {"ALL": summarize(rows)}


def pct(x):
    return "-" if x is None else f"{x:.1%}"


def rate(s):
    return s["strict"] / s["n"]


def table(label, cur, new, strata):
    print(f"\n== {label}")
    print(f"{'stratum':<8}{'records':>8}{'current':>10}{'new':>10}{'diff':>9}{'routed':>8}"
          f"{'prec cur':>10}{'prec new':>10}{'date cur':>10}{'date new':>10}")
    for s in strata + ["ALL"]:
        c, n = cur[s], new[s]
        if n["n"] == 0 or c["n"] == 0:
            continue
        diff = rate(n) - rate(c)
        print(f"{s:<8}{n['n']:>8}{c['strict']:>10}{n['strict']:>10}{diff * 100:>+8.1f}p{n['routed']:>8}"
              f"{pct(c['precision']):>10}{pct(n['precision']):>10}"
              f"{c['date_ok']}/{c['pairs']:<6}".rjust(10) + f"{n['date_ok']}/{n['pairs']}".rjust(10))


def verdict(ok):
    return "PASS" if ok else "FAIL"


def gate(spec, cur, new):
    results = []
    for s, gain in spec["gain"].items():
        c, n = cur[s], new[s]
        if n["n"] and c["n"]:
            diff = rate(n) - rate(c)
            ok = diff >= gain
            results.append(ok)
            print(f"{verdict(ok)} {s}: {c['strict']}/{c['n']} -> {n['strict']}/{n['n']} "
                  f"({diff * 100:+.1f}%p, need >= +{gain * 100:.0f}%p)")
    for s, slack in spec["slack"].items():
        c, n = cur[s], new[s]
        if n["n"]:
            ok = n["strict"] >= c["strict"] - slack
            results.append(ok)
            print(f"{verdict(ok)} {s}: {c['strict']} -> {n['strict']} (may drop by at most {slack})")
    c, n = cur["ALL"], new["ALL"]
    ok = (n["precision"] or 0) >= (c["precision"] or 0)
    results.append(ok)
    print(f"{verdict(ok)} overall entry precision: {pct(c['precision'])} -> {pct(n['precision'])}")
    missing = [s for s in spec["strata"] if new[s]["n"] == 0]
    if missing:
        results.append(False)
        print(f"FAIL strata without records: {', '.join(missing)}")
    print(f"GATE {verdict(all(results))}")


def alternative(name, strata, cur, alt):
    prec_ok = (alt["ALL"]["precision"] or 0) >= (cur["ALL"]["precision"] or 0)
    if name == "filter alone":
        lost = [s for s in strata + ["ALL"] if alt[s]["n"] and alt[s]["strict"] < cur[s]["strict"]]
        ok = not lost and prec_ok
        detail = f" (strict passes lost in {', '.join(lost)})" if lost else ""
    else:
        rises = alt["B1"]["n"] > 0 and alt["B1"]["strict"] > cur["B1"]["strict"]
        holds = alt["B3"]["strict"] >= cur["B3"]["strict"]
        ok = rises and holds and prec_ok
        detail = "" if ok else f" (B1 rises: {rises}, B3 holds: {holds})"
    print(f"\n{name.upper()} {verdict(ok)}{detail}{'' if prec_ok else ' (entry precision dropped)'}")


def main(argv):
    name = "pr1"
    if "--gate" in argv:
        i = argv.index("--gate")
        name = argv[i + 1]
        argv = argv[:i] + argv[i + 2:]
    spec = GATES[name]
    strata = spec["strata"]
    truth = load_truth(argv[1])
    cur = by_stratum(score(truth, load_records(argv[2])), strata)
    new = by_stratum(score(truth, load_records(argv[3])), strata)
    table("current (main) vs new (branch)", cur, new, strata)
    print("\n== gate")
    gate(spec, cur, new)
    if len(argv) > 4:
        alt = by_stratum(score(truth, load_records(argv[4])), strata)
        table(f"current vs current + {spec['alternative']}", cur, alt, strata)
        alternative(spec["alternative"], strata, cur, alt)


if __name__ == "__main__":
    main(sys.argv)
