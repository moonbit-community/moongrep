# CFG Taint Performance Report

- **Environment**: Linux x86_64, `2026-10-23`, `moon 0.1.20261023`, release
  builds pinned to CPU 0.
- **Methodology**: Baseline is `a2182b6` (previous recursive engine) with the
  same fixture added. Each case ran three times alternating baseline and current
  revisions (median of benchmark means, ten adaptive batches per mean, compiled
  before timing). Machine-readable data is stored in
  [benchmark_results.json](benchmark_results.json).
- **CI policy**: Elapsed timings are host-specific observations; CI checks
  deterministic counts and functional suites instead.

## Taint phase timings

The benchmark fixture in [performance_test.mbt](performance_test.mbt) contains
eight local variables, a reverse-assignment `while` loop, one source, and one
sink. Parsing and spec construction occur outside the timed loop. Because it
uses generic declarative call models instead of YAML matching, it does not
capture YAML match-cache savings.

- **Prepare**: lowering, graph validation, SCC ordering, and value liveness
  (shared across all rules for a function; the baseline had no separate prepare
  phase).
- **Solve**: entry sources, model binding, work-queue propagation, and final
  finding collection.
- **Complete function**: preparation + solving one rule (independently timed
  phases need not sum exactly to the combined run).

| Backend | Operation | Baseline (µs) | CFG (µs) | Ratio | Peak RSS baseline / CFG (MiB) |
| --- | --- | ---: | ---: | ---: | ---: |
| native | prepare | — | 107.54 | — | — / 5.20 |
| native | solve prepared graph | — | 269.20 | — | — / 5.16 |
| native | complete function | 176.65 | 352.31 | 1.994× | 5.11 / 5.15 |
| wasm | prepare | — | 307.41 | — | — / 71.76 |
| wasm | solve prepared graph | — | 848.22 | — | — / 71.09 |
| wasm | complete function | 501.24 | 1237.52 | 2.469× | 71.22 / 61.71 |

For this single-rule fixture, the CFG engine takes ~2.0× baseline on native and
~2.47× on Wasm due to explicit CFG construction, the stronger domain, graph
validation, and the complete-result contract (preparation amortizes across
multiple rules). Peak RSS was captured with `/usr/bin/time -f %M` around
pre-built runners and reflects process startup, JIT/GC, and allocator high-water
marks rather than live bytes per function.

## Structural performance gates

All eight structural benchmark gates pass (candidate bucket merging reuses an
unopposed read-only bucket instead of allocating a new array):

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

Run benchmarks from the repository root:

```sh
moon bench internal/taint/performance_test.mbt --target native --release --no-parallelize
moon bench internal/taint/performance_test.mbt --target wasm --release --no-parallelize
moon bench internal/rule/apply/recursive_bench_wbtest.mbt query/query_bench_test.mbt --target native --release --no-parallelize
moon bench internal/rule/apply/recursive_bench_wbtest.mbt query/query_bench_test.mbt --target wasm --release --no-parallelize
```

To compare against baseline `a2182b6`, copy `performance_fixture` into an
isolated baseline checkout, add the core bench import, and benchmark
`analyze_function_like(node, spec)`. For process RSS, build with `--build-only`
first: native runners accept `performance_test.mbt:0-1`, and Wasm runners accept
`moonrun --test-args` JSON with `package` and `file_and_index`
(`{"start": 0, "end": 1}` from `__blackbox_test_info.json` or
`__whitebox_test_info.json`).

Deterministic tests verify:

- Single function preparation shared across multiple rules, and zero preparation
  for structural-only plans
- Single call-model bind per source call site (including cloned cleanups)
- Unchanged-state scheduling, stable origins, and independence from SCC block
  order
- Suppression of partial findings on budget exhaustion
- Functional acceptance across the nine previously missed cases, nine positive
  controls, clean negatives, and control-flow/domain suites
