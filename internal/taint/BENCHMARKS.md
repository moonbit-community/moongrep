# CFG taint performance

Measured on Linux x86_64 on 2026-10-23 with `moon 0.1.20261023`, release
builds, pinned to CPU 0. The baseline is `a2182b6`, using the recursive engine.
The same fixture was added to the baseline checkout. Each revision ran three
times per case, with baseline/current order alternating; values below are the
median benchmark mean. Each benchmark mean contains ten adaptive batches.
Compilation ran before measurement. Results describe this host, not a CI timer.

## Taint phases

The fixture in [performance_test.mbt](performance_test.mbt) has eight local
variables, a reverse-assignment while loop, one source and one sink. Parsing and
spec construction happen outside the timed loop. The generic declarative call
models avoid YAML matching, so these timings do not measure the production
match-cache benefit.

Preparation includes lowering, graph validation, SCC ordering and value
liveness. Solving includes entry sources, model binding, work-queue propagation
and final finding collection. Complete-function time includes preparation and
one rule. The baseline has no separate CFG preparation phase.

| Backend | Operation | Baseline (µs) | CFG (µs) | Ratio | Peak RSS baseline / CFG (MiB) |
| --- | --- | ---: | ---: | ---: | ---: |
| native | prepare | — | 107.54 | — | — / 5.20 |
| native | solve prepared graph | — | 269.20 | — | — / 5.16 |
| native | complete function | 176.65 | 352.31 | 1.994× | 5.11 / 5.15 |
| wasm | prepare | — | 307.41 | — | — / 71.76 |
| wasm | solve prepared graph | — | 848.22 | — | — / 71.09 |
| wasm | complete function | 501.24 | 1237.52 | 2.469× | 71.22 / 61.71 |

This single-rule fixture costs about 2.0× the baseline on native and 2.47× on
Wasm. The explicit graph, stronger domain, validation and complete-result
contract add work. Preparation is shared by all rules for a function. No taint
latency threshold was specified; this increase is a remaining performance cost.
Independently measured phases need not sum exactly to complete-function time.

RSS comes from `/usr/bin/time -f %M` around each already-built runner. It includes
runtime startup, fixture preparation, batch allocations, JIT/GC and allocator
high-water marks. Wasm memory varies considerably between runs. These values do
not establish a reduction in live bytes per function.

## Structural performance gates

The existing structural benchmarks retain their acceptance limits. The matching
path reuses a planned bucket when the other bucket is empty, avoiding repeated
array allocation while preserving pattern order. All eight comparisons pass.

| Backend | Case | Baseline (µs) | CFG tree (µs) | Ratio | Limit |
| --- | --- | ---: | ---: | ---: | ---: |
| native | builtin structural | 63.50 | 57.18 | 0.900× | 1.05× |
| native | recursive failure | 275.02 | 284.92 | 1.036× | 1.10× |
| native | ordinary structural | 26.32 | 26.39 | 1.003× | 1.15× |
| native | query captures | 21.48 | 21.19 | 0.987× | 1.15× |
| wasm | builtin structural | 181.15 | 187.62 | 1.036× | 1.05× |
| wasm | recursive failure | 934.91 | 885.12 | 0.947× | 1.10× |
| wasm | ordinary structural | 84.06 | 79.88 | 0.950× | 1.15× |
| wasm | query captures | 77.41 | 75.29 | 0.973× | 1.15× |

## Reproduction and deterministic checks

Build and run the benchmarks from the project root:

```sh
moon bench internal/taint/performance_test.mbt --target native --release --no-parallelize
moon bench internal/taint/performance_test.mbt --target wasm --release --no-parallelize
moon bench internal/rule/apply/recursive_bench_wbtest.mbt query/query_bench_test.mbt --target native --release --no-parallelize
moon bench internal/rule/apply/recursive_bench_wbtest.mbt query/query_bench_test.mbt --target wasm --release --no-parallelize
```

For a baseline comparison, add the same `performance_fixture` to an isolated
`a2182b6` checkout and benchmark `analyze_function_like(node, spec)` in place of
prepare/analyze. Add the core bench import to that checkout's taint test imports.
Use `--build-only` before process RSS measurement. Native generated runners take
`performance_test.mbt:0-1`; Wasm runners use `moonrun --test-args` with a package
and `file_and_index` containing `{"start": 0, "end": 1}` ranges. Select indexes
from the generated `__blackbox_test_info.json` or `__whitebox_test_info.json`.
The [machine-readable results](benchmark_results.json) contain exact medians and
peak RSS for every phase and structural case.

Deterministic tests verify one function preparation across multiple rules,
zero preparation for structural-only plans, one model bind per source call site
(including cloned cleanups), unchanged-state scheduling, stable origins, result
independence from SCC block order, and suppression of partial results on budget
exhaustion. Functional acceptance uses the report's nine missed examples, nine
positive controls, clean negatives and the broader control-flow/domain suite.
