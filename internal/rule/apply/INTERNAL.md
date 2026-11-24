# Structural Scan Sessions

This document describes how `internal/rule/apply` plans, caches, evaluates, and
publishes structural rules.

## Plans, sessions, and execution modes

`ScanPlan` stores rule metadata only (never source nodes, environments, or
evaluation caches):

- Rule groups use stable array indices; each pattern entry is identified by
  `(group, positive/negative side, pattern index)`.
- Capture names map to stable integer IDs.
- A work-list pass computes each group's transitive capture dependencies bottom
  up (including guards and negative patterns). Filtering a plan preserves these
  IDs.

Execution mode is chosen per application:

| Plan shape | Execution path | Shared state / caches |
| --- | --- | --- |
| Only **plain** entries (no `inside-toplevel`, no `then` on any positive root pattern) | Direct CST traversal + standalone matcher | None (`SourceIndex` and `ScanSession` are not created). |
| Any recursive (`then`) or `inside-toplevel` entry | Single `ScanSession` | One `SourceIndex`, capture interner, environment interner, and evaluation caches shared across related rules. In a mixed plan, plain entries read borrowed candidates from the indexed walk with standalone matching and never allocate candidate keys, environment projections, or frames. |

### Finding deduplication

Each structural application owns a private `StructuralFindingCollector` (scoped
to one parsed source block; never shared across independent parses). Plain,
indexed, mixed, and top-level-context runs all publish through it:

- Key: `(file, rule_id, loc.start.cnum, loc.end.cnum)`.
- Retains the first complete finding (including `pattern_index` and occurrence
  order).
- CLI text and JSON renderers consume the collected findings directly.

## Source regions, traversal, and lexical scopes

### Direct vs. indexed traversal

- `internal/cst/direct_traversal.mbt` defines the single semantic kernel for
  candidate boundaries and control actions (`Continue` descends, `Prune` skips
  only current descendants, `Return` stops the walk).
- Its direct adapter creates no node IDs, span buckets, sequence index, scopes,
  or cursor caches, and uses `ArrayView` for sequences and continuations so
  descending does not copy suffixes. Plain plans and
  `ExprQuery::captures_from_cst` run on this direct path.
- `internal/cst/SourceIndex` reuses the exact same kernel for roots and
  immediate children, assigning stable IDs to semantic nodes and representing
  sequence regions as `(owning statement list, start, end)` (including empty
  ranges) with shared suffix cursors (`End`, `Visit`, `Concat`).
- Function bodies stay sequence containers (including inside nested closures),
  while explicit expression blocks remain matchable candidates. Candidate
  regions are never merged by source range.
- Original CST references flow through the atomic matcher (spans choose only a
  lookup bucket; reference identity identifies the node). Binding `__TARGET__`
  records a `TargetRef` with its exact region bounds and resolves entry scope
  from `SourceIndex` on demand without span-based rescanning.

### Lexical scopes

- Scopes are immutable parent chains initialized on first use, with a distinct
  binding ID per binder and per-`(scope, name)` resolution caching.
- Parameters, patterns, condition bindings, loops, local functions, recursive
  groups, and statement continuations share one scope implementation across
  traversal and selected targets.

## Capture environments and provenance

An environment is an immutable ordered capture set storing, per capture:

1. Original `BoundValue`
2. Interned normalized value ID (`ValueInterner` — matching atomic matcher
   equality for names, constructors, semantic child labels, and
   `Single`/`Multiple`, checking full equality on hash collisions)
3. Identifier provenance (lexical role and original binding ID or unbound state)
   for single `id` captures and typed `id` ellipses

Key invariants:

- Binders record their declarations; references resolve at their source
  positions. Provenance propagates unchanged through every child group without
  re-resolving names when a target is selected, and siblings never mutate one
  another's environments.
- Inherited `id` checks compare lexical bindings only when both source and use
  are lexical variables; other name roles keep normalized-name equality. Guards
  reading an inherited lexical `id` also require visibility at candidate entry.
- Captures and provenance copy and roll back together during atomic ellipsis
  backtracking.
- Environment projection keys include only the captures read by a group or its
  descendants (including each identifier's binding identity and lexical role).

## Cached evaluation and publication

- **Candidate states**: keyed by `(group_id, region_id, projected_env_id)`.
  Evaluates positive entries (shape, guard, `then`) in order, then negatives. A
  failed child permits trying the next positive entry without retrying an
  atomic ellipsis partition. Success, failure, and negative outcomes are cached.
- **Region states**: keyed by `(group_id, cursor_id, projected_env_id)`.
  Combines cached candidates with successor cursors to record positive
  existence and negative rejection while avoiding repeated walks of overlapping
  subtrees. An explicit evaluation stack advances into child groups or source
  successors even when a selected target equals its candidate.
- **Publication**: indexed evaluation never appends findings directly; nested
  `then` returns a semantic decision. Top-level contexts first verify the whole
  region has no uncovered negatives, then publish root findings in original
  traversal order from cached candidates. Plain rules preserve cross-rule
  publication and pruning order by passing only missed entries into child
  subtrees; mixed plans make the same per-entry decision during the single
  indexed root walk.

## Verification and benchmarks

### Regression and complexity coverage

- Functional regressions cover direct/indexed traversal compatibility,
  plain/indexed equivalence, mixed-plan ordering and cache exclusion,
  continuation bounds, lexical shadowing, deep capture dependencies, differing
  values/bindings at the same region, ellipsis rollback, priority, negative
  coverage, closure depths `0`–`6`, `catch_all`, nested conditionals/`let`
  initializers, and collector deduplication.
- A test-only uncached reference interpreter cross-checks complete findings
  across `216` generated sources.
- Deterministic CI gates (at chain sizes `8`, `16`, `32`, and `64`) assert:
  - Expansion counts equal cache cardinalities.
  - For a fixed environment and single-entry rule chain, `candidate + region`
    expansions are at most `2 * group_count * index_state_count` (distinct
    capture environments still require distinct states).
  - A rule in one context visits no more candidates during publication than a
    complete direct traversal.

### Running benchmarks

```sh
moon bench internal/rule/apply/recursive_bench_wbtest.mbt query/query_bench_test.mbt --target native --release
moon bench internal/rule/apply/recursive_bench_wbtest.mbt query/query_bench_test.mbt --target wasm --release
```

Elapsed timings are diagnostic only; CI gates on deterministic state counts.
See [BENCHMARKS.md](BENCHMARKS.md) for historical measurements and RSS
methodology.
