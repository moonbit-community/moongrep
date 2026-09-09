# Structural scan sessions

`ScanPlan` contains rule metadata only. Groups use stable array indices; an
entry is identified by its group, positive/negative side, and pattern index.
Capture names have stable integer IDs. Planning uses a work list and computes
each group's transitive capture dependencies bottom up, including guards and
negative patterns. Filtering a plan keeps these IDs unchanged.

Each call to structural application owns a `ScanSession`. Related rules share
its source index, capture interner, environment interner, and evaluation caches.
No source node, binding environment, or evaluation cache survives in `ScanPlan`.

## Source regions and scopes

`internal/cst/SourceIndex` assigns IDs to semantic source nodes. A sequence region
is an owning statement list plus start/end offsets, including empty ranges.
Candidates borrow statement views. Shared suffix cursors avoid reconstructing
or rescanning all later statements for each continuation.

The index distinguishes function body containers from explicit blocks and keeps
the previous candidates, locations, and order. Original CST references flow
through the atomic matcher. Spans choose a reference-lookup bucket only; reference
identity determines the node. Binding `__TARGET__` records a `TargetRef` directly,
including the sequence bounds and entry scope. It never searches for a matching
span after the match.

Lexical scopes are immutable parent chains. Each binder has a distinct binding
ID, and name resolution is cached by scope and name. Scopes are initialized on
first use. Parameters, patterns, condition bindings, loops, local functions,
recursive groups, and statement continuations use the same scope implementation
for traversal and selected targets.

The old full visitor could resume expression traversal after a matching visitor
returned Continue. These control edges are represented by `AfterContinue` and
`Finish` cursors. This preserves additional candidates and repeated findings
inside top-level contexts. Ordinary query/root traversal uses the same child
selection rules without those resume edges. The compatibility snapshots were
recorded from the implementation before this refactor.

## Capture environments

An environment is an immutable ordered collection of captures. Each capture
stores its original value, a normalized value ID, and, for identifiers, the
name and lexical binding ID at its scope anchor. Inherited anchors are retained
through every child group; only newly introduced captures start at the selected
target's entry scope. Candidate entry resolution determines whether an inherited
identifier is shadowed. Siblings cannot mutate one another's environments.

Environment keys include only captures the group or its descendants read.
Normalization follows the atomic matcher's equality, including constructor/name
normalization, semantic child labels, and Single/Multiple distinctions. Hash
collisions are checked by equality, never by source location or hash alone.

## Evaluation and publication

Candidate states are keyed by group ID, region ID, and projected environment ID.
They try positive entries in order, including guards and `then`, then negatives.
A failed child permits the next positive entry, but does not retry an atomic
ellipsis partition. Candidate success, failure, and negative matches are cached.

Region states are keyed by group ID, cursor ID, and projected environment ID.
They combine cached candidates and successor cursors, recording positive
existence, rejection, and the visitor's completion action. Shared successor
states are essential: caching only candidates would still repeatedly traverse
overlapping subtrees. The explicit evaluation stack advances into child groups
or source successors, even when a selected target equals its candidate.

Evaluation never appends findings. Nested `then` returns a semantic decision.
Top-level contexts first check their complete region for uncovered negatives,
then publish root findings using cached candidates and the original traversal
order. Ordinary rules keep their cross-rule publication and pruning order.

## Verification

The regression suite covers continuation bounds, lexical shadowing, deep capture
dependencies, different values and binding identities at the same region,
ellipsis rollback, priority, negative coverage, and legacy publication order.
A test-only uncached interpreter compares complete findings on 216 generated
sources. Complexity tests vary source and rule chain sizes over 8, 16, 32, and 64
for success, failure, and rejection, including adjacent continuations.

The deterministic gate checks that expansion counts equal cache cardinalities
and that, for a fixed environment and a single-entry rule chain, candidate plus
region expansions are at most twice the group count times the index state count.
Truly distinct capture environments still require distinct states; there is no
depth limit, resource budget, or claim of linear cost for arbitrary rules.

Benchmarks retain an 84-byte recursive failure fixture and ordinary, builtin,
and public-query cases. Build and run them with:

```sh
moon bench internal/rule/apply/recursive_bench_wbtest.mbt query/query_bench_test.mbt --target native --release
moon bench internal/rule/apply/recursive_bench_wbtest.mbt query/query_bench_test.mbt --target wasm --release
```

Timing is diagnostic; CI relies on state counts. See [BENCHMARKS.md](BENCHMARKS.md)
for the measured comparison and memory methodology.
