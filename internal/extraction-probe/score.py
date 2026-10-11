#!/usr/bin/env python3
"""Score probe/replay records against truth.json at the entry level the user sees.

Usage: python3 score.py <corpus> <records.jsonl> [--detail] [--route]

An entry is {"m": merchant, "i": item name or "", "a": amount, "d": date}. Receipt items are expanded,
so a record passes ("strict") only when its entry set matches one acceptable set exactly: same amounts,
fuzzy-matching labels, nothing missing and nothing extra. An empty acceptable set ([[]]) means the screen
holds no spending, so only an empty result passes.

--route adds condition R built from A and B1 records: B1 where the OCR text in <corpus>/ocr/<id>.txt is
column-split, A elsewhere (how the design document's routed numbers were computed).
"""
import json
import re
import sys
from collections import defaultdict

TODAY = "2026-10-11"
BARE = re.compile(r"^[-+]?[\d,]+(원|P)?$")


def column_split(text, run_length=3):
    """Whether OCR text holds a run of bare-number lines, i.e. Vision split a table into columns."""
    run = 0
    for line in text.splitlines():
        run = run + 1 if BARE.match(line.strip()) else 0
        if run >= run_length:
            return True
    return False


def load_truth(corpus):
    with open(f"{corpus}/truth.json", encoding="utf-8") as fp:
        return {t["id"]: t for t in json.load(fp)}


def load_records(path):
    with open(path, encoding="utf-8") as fp:
        return [json.loads(line) for line in fp if line.strip()]


def _norm(s):
    return re.sub(r"[\s·()\-]", "", (s or "")).lower()


def _fuzzy(a, b):
    a, b = _norm(a), _norm(b)
    if not a and not b:
        return True
    if not a or not b:
        return False
    return a in b or b in a


def _matches(exp, act):
    if int(act["a"]) != exp["a"]:
        return False
    if exp["i"]:
        return bool(act["i"]) and _fuzzy(exp["m"], act["m"]) and _fuzzy(exp["i"], act["i"])
    return not act["i"] and _fuzzy(exp["m"], act["m"])


def _assign(expected, actual):
    used, pairs = set(), []
    for e in expected:
        for k, a in enumerate(actual):
            if k not in used and _matches(e, a):
                used.add(k)
                pairs.append((e, a))
                break
    return pairs, len(expected) - len(pairs), len(actual) - len(pairs)


def _best(sets, actual):
    scored = []
    for s in sets:
        pairs, missing, extra = _assign(s, actual)
        scored.append((missing + extra, -len(pairs), pairs, missing, extra, s))
    scored.sort(key=lambda x: (x[0], x[1]))
    return scored[0]


def _reasons(expected, actual, pairs):
    out = set()
    if len(expected) != len(actual):
        out.add("count")
    matched_e = {id(e) for e, _ in pairs}
    matched_a = {id(a) for _, a in pairs}
    rest_e = [e for e in expected if id(e) not in matched_e]
    rest_a = [a for a in actual if id(a) not in matched_a]
    for e in rest_e:
        if any(int(a["a"]) == e["a"] for a in rest_a):
            out.add("label")
        elif any(_fuzzy(e["m"], a["m"]) and (not e["i"] or _fuzzy(e["i"], a["i"])) for a in rest_a):
            out.add("amount")
    return sorted(out)


def score(truth, records):
    """One row per record: strict pass, matched pairs, expected/actual entry counts, date hits, routed flag."""
    rows = []
    for r in records:
        t = truth[r["id"]]
        actual = r["entries"]
        cost, _, pairs, missing, extra, chosen = _best(t["accept"], actual)
        strict = cost == 0 and not r.get("error")
        lenient = strict or any(_best([s], actual)[0] == 0 for s in t.get("lenient", []))
        date_ok = sum(1 for e, a in pairs if (a["d"] or TODAY) == (e["d"] or TODAY))
        rows.append(dict(
            id=r["id"], cat=r["cat"], cond=r["cond"], run=r["run"], strict=strict, lenient=lenient,
            missing=missing, extra=extra, pairs=len(pairs), expected=len(chosen), actual=len(actual),
            date_ok=date_ok, routed=r.get("routed"), in_tok=r.get("inTok", 0), ms=r.get("ms", 0),
            error=r.get("error"), entries=actual,
            why=[] if strict else (["error"] if r.get("error") else _reasons(chosen, actual, pairs)),
        ))
    return rows


def summarize(sel):
    """Aggregates over a row selection; precision and recall are sums over all rows, not per-row averages."""
    n = len(sel)
    pairs = sum(r["pairs"] for r in sel)
    expected = sum(r["expected"] for r in sel)
    actual = sum(r["actual"] for r in sel)
    timed = [r for r in sel if not r["error"] and r["ms"] > 0]
    return dict(
        n=n, strict=sum(r["strict"] for r in sel), lenient=sum(r["lenient"] for r in sel),
        over=sum(1 for r in sel if r["extra"] > 0), under=sum(1 for r in sel if r["missing"] > 0),
        pairs=pairs, expected=expected, actual=actual,
        recall=pairs / expected if expected else None, precision=pairs / actual if actual else None,
        date_ok=sum(r["date_ok"] for r in sel), routed=sum(1 for r in sel if r["routed"]),
        in_tok=sum(r["in_tok"] for r in timed) / len(timed) if timed else 0,
        ms=sum(r["ms"] for r in timed) / len(timed) if timed else 0,
        errors=sum(1 for r in sel if r["error"]),
    )


def _fmt(s):
    if s["n"] == 0:
        return "-"
    rec = f"{s['pairs']}/{s['expected']}={s['recall']:.0%}" if s["expected"] else "-"
    prec = f"{s['pairs']}/{s['actual']}={s['precision']:.0%}" if s["actual"] else "-"
    return (f"pass {s['strict']}/{s['n']} lenient {s['lenient']}/{s['n']} over {s['over']} under {s['under']} "
            f"recall {rec} precision {prec} date {s['date_ok']}/{s['pairs']} "
            f"in~{s['in_tok']:.0f}tok {s['ms'] / 1000:.1f}s err {s['errors']}")


def routed_records(corpus, truth, records):
    """Condition R synthesized from A and B1: B1 where the OCR text is column-split, A elsewhere."""
    split = {}
    for cid in truth:
        with open(f"{corpus}/ocr/{cid}.txt", encoding="utf-8") as fp:
            split[cid] = column_split(fp.read())
    out = [dict(r, cond="R", routed=split[r["id"]]) for r in records
           if (split[r["id"]] and r["cond"] == "B1") or (not split[r["id"]] and r["cond"] == "A")]
    return out, sorted(cid for cid, v in split.items() if v)


def main(argv):
    corpus, path = argv[1], argv[2]
    truth = load_truth(corpus)
    records = load_records(path)
    if "--route" in argv:
        extra, fired = routed_records(corpus, truth, records)
        records += extra
        print("routed to image:", fired)
    rows = score(truth, records)
    conds = sorted({r["cond"] for r in rows})
    cats = sorted({r["cat"] for r in rows})

    print("== by condition x category (strict pass = exact entry set; over/under = records with extra/missing entries)")
    for c in conds:
        print(f"[{c}] ALL      ", _fmt(summarize([r for r in rows if r["cond"] == c])))
        for cat in cats:
            print(f"[{c}] {cat:<9}", _fmt(summarize([r for r in rows if r["cond"] == c and r["cat"] == cat])))

    print("\n== per case strict passes (runs) " + " | ".join(conds))
    by = defaultdict(lambda: defaultdict(list))
    for r in rows:
        by[r["id"]][r["cond"]].append(r)
    for cid in sorted(by):
        cells = []
        for c in conds:
            rs = by[cid][c]
            if not rs:
                cells.append(f"{'-':<22}")
                continue
            whys = sorted({w for r in rs for w in r["why"]})
            cells.append(f"{sum(r['strict'] for r in rs)}/{len(rs)} {','.join(whys):<18}")
        print(f"{cid:<4}", " | ".join(cells))

    if "--detail" in argv:
        print("\n== failing records")
        for r in rows:
            if not r["strict"]:
                ents = "; ".join(f"{e['m']}{(' - ' + e['i']) if e['i'] else ''} {e['a']} {e['d']}" for e in r["entries"])
                print(f"{r['id']} {r['cond']} run{r['run']} why={r['why']} :: {ents}"
                      f"{(' ERR ' + r['error']) if r['error'] else ''}")


if __name__ == "__main__":
    main(sys.argv)
