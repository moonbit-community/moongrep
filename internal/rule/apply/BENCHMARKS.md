# Recursive scan benchmark comparison

## Lightweight execution follow-up

A root structural entry is plain when it has no `inside-toplevel` clause and no
positive root pattern has `then`. A plan containing only plain structural entries
uses direct CST traversal and standalone matching. Mixed plans retain one source
index for recursive entries, while plain entries bypass environment projection
and candidate/region caches. Public CST queries use the same direct traversal.
Direct traversal and ordinary indexed traversal share one private semantic
kernel; the indexed adapter maps its candidates back to cached source regions.

Release timing is a publication check, not a CI gate. Compare alternating builds
on the same host and MoonBit toolchain, run each build three times, and use the
median benchmark mean. Ordinary structural and query cases must remain within
1.15 times the pre-index baseline. Recursive failure must remain within 1.10
times the indexed baseline, and the builtin mixed case within 1.05 times that
baseline. CI checks findings, order, candidate traversal compatibility, and cache
expansion counts instead of elapsed time.

Measured on Windows on 2026-09-14 with `moon 0.1.20260907`. Runs alternated
between extracted baseline trees and the working tree. The ordinary and query
baseline is `8050e53`; the recursive and builtin baseline is indexed commit
`dd6fb20`. Each value below is the median of three benchmark means.

| Backend | Case | Baseline | Working tree | Ratio | Limit |
| --- | --- | ---: | ---: | ---: | ---: |
| native | ordinary structural scan | 76.17 µs | 67.73 µs | 0.89× | 1.15× |
| native | query captures from CST | 56.88 µs | 55.89 µs | 0.98× | 1.15× |
| native | recursive failure bytes=84 depth=8 | 930.12 µs | 941.61 µs | 1.01× | 1.10× |
| native | builtin structural scan | 174.66 µs | 143.17 µs | 0.82× | 1.05× |
| wasm | ordinary structural scan | 66.49 µs | 57.32 µs | 0.86× | 1.15× |
| wasm | query captures from CST | 57.05 µs | 51.60 µs | 0.90× | 1.15× |
| wasm | recursive failure bytes=84 depth=8 | 857.34 µs | 853.53 µs | 1.00× | 1.10× |
| wasm | builtin structural scan | 183.10 µs | 138.18 µs | 0.75× | 1.05× |

All eight acceptance ratios pass. These numbers describe this host only; the
historical Linux measurements below remain useful for the indexed evaluator's
original before/after comparison.

## Indexed evaluator baseline

Measured on Linux with `moon 0.1.20260907` using release builds. The baseline is
commit `8050e53` with the same benchmark fixtures added. Each case ran before/after
in its own process, with parsing and rule planning outside the timed loop.
The benchmark reports ten batches after warmup. Times below are mean ± standard
deviation; they are observations, not CI thresholds.

| Backend | Case | Before | After | Process peak RSS before / after |
| --- | --- | ---: | ---: | ---: |
| native | builtin structural scan | 23.22 ± 0.28 µs | 66.05 ± 1.07 µs | 7.38 / 7.50 MiB |
| native | recursive failure bytes=84 depth=8 | 276.22 ± 3.21 ms | 345.57 ± 3.89 µs | 7.55 / 7.45 MiB |
| native | ordinary structural scan | 25.48 ± 1.21 µs | 54.09 ± 2.61 µs | 5.39 / 5.50 MiB |
| native | query captures from CST | 20.99 ± 0.25 µs | 45.17 ± 0.64 µs | 4.93 / 4.99 MiB |
| wasm | builtin structural scan | 75.02 ± 0.72 µs | 237.04 ± 6.78 µs | 131.55 / 144.78 MiB |
| wasm | recursive failure bytes=84 depth=8 | 1072.80 ± 16.70 ms | 1.26 ± 0.08 ms | 59.55 / 98.28 MiB |
| wasm | ordinary structural scan | 89.63 ± 1.09 µs | 187.10 ± 4.92 µs | 82.73 / 84.61 MiB |
| wasm | query captures from CST | 77.73 ± 0.93 µs | 165.11 ± 2.03 µs | 58.89 / 93.57 MiB |

The recursive failure case improved by about 800× on native and 850× on wasm.
The small ordinary and query cases take about twice as long, and the builtin
fixture about three times as long. They pay the index and cache setup cost with
little repeated work to eliminate. The state-count guarantee addresses repeated
semantic evaluations; it does not promise lower latency for every short scan.

RSS was measured with `/usr/bin/time -f %M` around the already-built native
test executable or `moonrun`, not around compilation. It includes rule parsing,
runtime startup, benchmark warmup, and allocator/GC high-water marks. Faster cases
use larger batches; these are process measurements, not live bytes per scan.
Wasm process RSS also includes the runtime and can rise despite shorter scans.

To repeat the timings, use the `moon bench` commands in [INTERNAL.md](INTERNAL.md).
For RSS, first add `--build-only`, then run one benchmark from the generated
`_build/<target>/release/bench/...` test runner under `/usr/bin/time`. Native
runners take `filename.mbt:start-end`. For wasm, `moonrun --test-args` takes JSON
with `package` and `file_and_index` containing the file and start/end range.
The generated `__whitebox_test_info.json` or `__blackbox_test_info.json` supplies
the benchmark index. Rebuilding the fixtures before each comparison keeps the
test runner and metadata consistent.

CI uses deterministic expansion-count tests at chain sizes 8, 16, 32, and 64.
Every completed candidate and region key is expanded once. Total expansions
for a fixed environment are bounded by `2 × group count × index state count`.
Timing and RSS do not gate CI.
