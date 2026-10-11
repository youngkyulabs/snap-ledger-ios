# Extraction probe

Measures Foundation Models extraction on this Mac (macOS 27 with Apple Intelligence on) through the same path
the app takes: Vision OCR → payment-signal gate → model → `normalize` → `enrich` → entries (receipt items expanded).
The simulator cannot run the model, so this is how prompt and routing changes are judged. Numbers hold for the
model this Mac runs (AFM 3 Core Advanced); a device with AFM 3 Core may differ.

Rendered images are never committed — the generators recreate them. Run everything from the repository root with a
scratch directory `$W` outside the repo.

## Files

| Path | What it is |
|---|---|
| `build.sh <source-root> <out-dir> [ROUTED]` | Copies the extraction sources from `<source-root>/SnapLedger/Services/`, patches `isAvailable` to `true`, and builds `<out-dir>/probe` and `<out-dir>/replay` for macOS 27. `ROUTED` adds condition R. |
| `probe/main.swift` | `probe <corpus> <out.jsonl> <runs> <conds|ocr> [ids]`. Conditions: `A` text only (the app before the image route), `B1` photo then OCR text, `B2` B1 plus one photo instruction line, `R` the app's own `extract(from:imageURL:)`. `ocr` only writes `<corpus>/ocr/<id>.txt`. |
| `replay/main.swift` | `replay <corpus> <in.jsonl> <out.jsonl> P0\|P1\|P2` re-applies post-processing to recorded raw output without model calls. `P0` = the post-processing compiled in; `P1`/`P2` = the tuning experiments (P2 adds the tuning-time item filter). |
| `score.py` | `python3 score.py <corpus> <records.jsonl> [--route] [--detail]` — entry-level scoring per condition and category. `--route` builds condition R from A and B1 records by the column-split rule. |
| `gate.py` | `python3 gate.py <corpus> <current.jsonl> <new.jsonl> [<current-filtered.jsonl>]` — the adoption gate fixed in the design document, plus the filter-alone verdict. |
| `tuning/gen.py` | The 24-image tuning corpus (multi / noise / receipt / control) the rules were derived from. |
| `holdout/` | The held-out corpus brief and generator (strata S1–S4) used for the gate. |
| `results/` | Raw records and OCR texts of past runs, so numbers can be re-scored without the model. |
| `checks/` | One-off probes: model capabilities, `reasoningLevel` rejection, iOS 27 error types. |

## Reproduce the tuning numbers (design document, 2026-10-11)

The baseline must be built from `main`'s sources: once the branch's item filter is in `normalize`, `replay P0`
from the branch gives "current + filter", not "current".

```bash
P=internal/extraction-probe
mkdir -p $W/main-src && git archive main SnapLedger/Services | tar -x -C $W/main-src
$P/build.sh $W/main-src $W/build
python3 $P/tuning/gen.py $W/tuning
mkdir -p $W/tuning/ocr && cp $P/results/2026-10-11-tuning-ocr/*.txt $W/tuning/ocr/
$W/build/replay $W/tuning $P/results/2026-10-11-tuning.jsonl $W/p0.jsonl P0
$W/build/replay $W/tuning $P/results/2026-10-11-tuning.jsonl $W/p2.jsonl P2
python3 $P/score.py $W/tuning $W/p0.jsonl | grep '^\[A\] ALL'          # pass 32/72, recall 51%, precision 48%
python3 $P/score.py $W/tuning $W/p2.jsonl --route | grep '^\[R\] ALL'  # pass 45/72, recall 84%, precision 75%
```

Copying the committed OCR texts keeps the replay exact; re-running OCR on regenerated receipt photos can differ
slightly because the photo noise is not seeded.

## Gate run (held-out set)

```bash
P=internal/extraction-probe
mkdir -p $W/main-src && git archive main SnapLedger/Services | tar -x -C $W/main-src
$P/build.sh $W/main-src $W/current            # the app on main
$P/build.sh . $W/new ROUTED                   # the branch, with condition R
python3 $P/holdout/gen_holdout.py $W/holdout
$W/current/probe $W/holdout $W/current.jsonl 3 A
$W/new/probe $W/holdout $W/new.jsonl 3 R
$W/new/replay $W/holdout $W/current.jsonl $W/current-filtered.jsonl P0   # current output + branch post-processing
python3 $P/gate.py $W/holdout $W/current.jsonl $W/new.jsonl $W/current-filtered.jsonl
```

A full run takes about 25 minutes. When waiting on it from a script, use `caffeinate -w <pid>` or `pgrep -x probe`;
`pgrep -f` matches the waiting shell's own command line. Rebuild the binaries from the committed sources before a
run, or the numbers will not match the commit. Run each condition at least 3 times.

To see which route each item took, stream the app log while the probe runs:
`log stream --level info --predicate 'subsystem == "com.youngkyu.snapledger" AND category == "extraction"'`.
