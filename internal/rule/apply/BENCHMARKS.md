# Structural & Recursive Scan Benchmarks

This log tracks release benchmark comparisons for `internal/rule/apply` and
`query`. Timings are host-specific diagnostics; CI gates on deterministic state
and expansion counts (`8`, `16`, `32`, and `64` chain sizes, bounded by
`2 × group count × index state count` for a fixed environment).

## 2026-10-23: CFG taint refactor follow-up

- **Environment**: Linux, `moon 0.1.20261023`, release builds, pinned to CPU 0,
  three alternating runs against baseline `a2182b6`.
- **Change**: Candidate bucket merging reuses a read-only bucket when its
  partner is empty.
- **Outcome**: All 8 structural gates pass. Full taint phase timings and RSS
  are in [internal/taint/BENCHMARKS.md](../../taint/BENCHMARKS.md).

| Backend | Case | Baseline | Current | Ratio | Limit |
| --- | --- | ---: | ---: | ---: | ---: |
| native | builtin structural | 63.50 µs | 57.18 µs | 0.900× | 1.05× |
| native | recursive failure | 275.02 µs | 284.92 µs | 1.036× | 1.10× |
| native | ordinary structural | 26.32 µs | 26.39 µs | 1.003× | 1.15× |
| native | query captures | 21.48 µs | 21.19 µs | 0.987× | 1.15× |
| wasm | builtin structural | 181.15 µs | 187.62 µs | 1.036× | 1.05× |
| wasm | recursive failure | 934.91 µs | 885.12 µs | 0.947× | 1.10× |
| wasm | ordinary structural | 84.06 µs | 79.88 µs | 0.950× | 1.15× |
| wasm | query captures | 77.41 µs | 75.29 µs | 0.973× | 1.15× |

## 2026-10-22: Unified structural traversal follow-up

- **Environment**: Linux, `moon 0.1.20261016`, pinned to CPU 2 with
  `--no-parallelize` (sequential runs reduced variance seen under default
  parallel runs). Median of three alternating benchmark means against pre-fix
  commit `60117bc`; parsing and planning run outside timed loops.
- **Outcome**: All 8 ratios pass.

| Backend | Case | Before | After | Ratio | Limit |
| --- | --- | ---: | ---: | ---: | ---: |
| native | ordinary structural scan | 23.65 µs | 24.38 µs | 1.03× | 1.15× |
| native | query captures from CST | 21.54 µs | 21.94 µs | 1.02× | 1.15× |
| native | recursive failure bytes=84 depth=8 | 365.56 µs | 282.16 µs | 0.77× | 1.10× |
| native | builtin structural scan | 55.71 µs | 57.90 µs | 1.04× | 1.05× |
| wasm | ordinary structural scan | 91.32 µs | 94.72 µs | 1.04× | 1.15× |
| wasm | query captures from CST | 81.62 µs | 83.41 µs | 1.02× | 1.15× |
| wasm | recursive failure bytes=84 depth=8 | 1.62 ms | 1.01 ms | 0.62× | 1.10× |
| wasm | builtin structural scan | 214.03 µs | 202.77 µs | 0.95× | 1.05× |

## 2026-09-14: Lightweight plain-entry execution

- **Change**: Plans with only plain entries (no `inside-toplevel` and no `then`)
  use direct CST traversal and standalone matching; mixed plans keep one
  `SourceIndex` for recursive entries while plain entries skip environment
  projection and caches. Public CST queries share the same direct kernel.
- **Environment**: Windows, `moon 0.1.20260907`, median of three alternating
  runs. Ordinary/query baseline is `8050e53` (pre-index); recursive/builtin
  baseline is `dd6fb20` (indexed).
- **Acceptance budgets**: ordinary & query `<= 1.15×` pre-index baseline;
  recursive failure `<= 1.10×` indexed baseline; builtin mixed `<= 1.05×`
  indexed baseline. All 8 pass.

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

## Historical baseline: Indexed evaluator introduction

- **Environment**: Linux, `moon 0.1.20260907`, release builds, ten batches after
  warmup, comparing commit `8050e53` before and after introducing the indexed
  evaluator (mean ± standard deviation).
- **Summary**: Recursive failure improved ~800× (native) and ~850× (wasm);
  small ordinary/query/builtin cases initially slowed 2–3× due to index setup,
  which the 2026-09-14 lightweight path subsequently resolved.

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

## Reproducing timings and RSS

- Run the `moon bench` commands from [INTERNAL.md](INTERNAL.md) with
  `--no-parallelize` and matching CPU affinity, alternating baseline and current
  trees three times and taking the median mean.
- For peak RSS, build first with `--build-only`, then run a single benchmark
  binary under `/usr/bin/time -f %M`:
  - **Native**: `_build/<target>/release/bench/...` with `filename.mbt:start-end`.
  - **Wasm**: `moonrun --test-args` with JSON specifying `package` and
    `file_and_index` (lookup indices in `__whitebox_test_info.json` or
    `__blackbox_test_info.json`).
- Process RSS includes runtime startup, warmup, and allocator/GC high-water
  marks (not live bytes per scan).
