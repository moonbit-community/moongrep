# Structural scan sessions

`ScanPlan` contains rule metadata only. Groups use stable array indices; an
entry is identified by its group, positive/negative side, and pattern index.
Capture names have stable integer IDs. Planning uses a work list and computes
each group's transitive capture dependencies bottom up, including guards and
negative patterns. Filtering a plan keeps these IDs unchanged.

Root groups with no `then` and no `inside-toplevel` are marked as plain entries.
If every retained structural entry is plain, application walks the CST directly
and does not create a `SourceIndex` or `ScanSession`. Plain groups try positives,
guards, and negatives in source order with the standalone matcher.

All other plans use one `ScanSession`. Related recursive and top-level-context
rules share its source index, capture interner, environment interner, and
evaluation caches. In a mixed plan, plain entries consume the indexed traversal's
borrowed candidate but still use standalone matching; they never create a
candidate key, environment projection, or evaluation frame. No source node,
binding environment, or evaluation cache survives in `ScanPlan`.

Each structural application creates a private `StructuralFindingCollector`.
Plain, indexed, mixed, and top-level-context publication all use it. Its key is
`(file, rule_id, loc.start.cnum, loc.end.cnum)`. It retains the first complete
finding, including its pattern index and occurrence order. The collector is
local to the parsed block application; independent parses never share it. CLI
text and JSON render the collected findings directly.

## Source regions and scopes

`internal/cst/SourceIndex` assigns IDs to semantic source nodes. A sequence region
is an owning statement list plus start/end offsets, including empty ranges.
Candidates borrow statement views. Shared suffix cursors avoid reconstructing
or rescanning all later statements for each continuation.

`internal/cst/direct_traversal.mbt` defines the candidate boundaries and control
actions for every structural entry point. Its direct adapter creates no node
IDs, span buckets, sequence index, scopes, or cursor cache. Sequence and
continuation candidates use `ArrayView`, so descending through a continuation
does not copy its suffix. Plain plans and `ExprQuery::captures_from_cst` use
this traversal.

The index uses that same kernel for roots and immediate children. Ordinary
scans, nested `then`, and selected top-level targets use the same candidate
relation. Function bodies remain sequence containers, including inside nested
closures; blocks written as expressions remain matchable candidates. Empty and
partial continuation targets retain their exact bounds. Original CST references
flow through the atomic matcher. Spans choose a reference-lookup bucket only;
reference identity determines the node. Binding `__TARGET__` records a
`TargetRef` containing the selected region. The index retains sequence bounds
and resolves the region's entry scope when needed. It never searches for a
matching span after the match.

Lexical scopes are immutable parent chains. Each binder has a distinct binding
ID, and name resolution is cached by scope and name. Scopes are initialized on
first use. Parameters, patterns, condition bindings, loops, local functions,
recursive groups, and statement continuations use the same scope implementation
for traversal and selected targets.

Source cursors contain only `End`, `Visit`, and `Concat`. `scan(region)` enters
the region through `visit(region)`. `Continue` descends, `Prune` skips only the
current candidate's descendants and continues with siblings, and `Return`
stops the whole walk. There are no visitor recovery edges or recovery caches.
Compatibility tests compare complete order, immediate child boundaries,
pruning, and early return. Candidate regions are never merged by source range.

## Capture environments

An environment is an immutable ordered collection of captures. Each capture
stores its original value, a normalized value ID, and identifier provenance from
the successful atomic match. Single identifiers and typed identifier lists
record each name's lexical role and original binding ID (or unbound state).
Binders refer to their declarations; references resolve at their source
positions. Inherited provenance is retained through every child group.
Selecting a target never reconstructs bindings from names. Siblings cannot
mutate one another's environments.

The indexed matcher checks every inherited identifier occurrence, comparing
bindings only when both source and use are lexical variables. Other name roles
keep normalized-name equality. Captures and provenance are copied and rolled
back together during atomic backtracking. Repeated new captures keep their
existing equality rules and first source. Guard reads of inherited lexical
identifiers additionally require visibility at candidate entry.

Environment keys include only captures the group or its descendants read,
including every identifier's binding identity and lexical role.
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
existence and rejection. Shared successor states are essential: caching only
candidates would still repeatedly traverse overlapping subtrees. The explicit
evaluation stack advances into child groups
or source successors, even when a selected target equals its candidate.

Indexed evaluation never appends findings. Nested `then` returns a semantic decision.
Top-level contexts first check their complete region for uncovered negatives,
then publish root findings using cached candidates and the original traversal
order. Plain rules keep their cross-rule publication and pruning order by carrying
only the entries that missed into each directly visited child subtree. Mixed
plans make the same decision per entry during their one indexed root traversal.

## Verification

The regression suite covers direct/indexed traversal compatibility, plain/indexed
finding equivalence, mixed-plan ordering and cache exclusion, continuation bounds,
lexical shadowing, deep capture
dependencies, different values and binding identities at the same region,
ellipsis rollback, priority, negative coverage, and publication order.
A test-only uncached interpreter compares complete findings on 216 generated
sources to verify caching; explicit candidate examples separately constrain
the traversal contract. Closure regressions cover depths zero through six,
single-pattern rules and builtin `catch_all`, nested conditionals and let
initializers, and multiple independent matches. Collector tests distinguish
rules, complete ranges, files, first pattern indices, and independent parses.
Complexity tests vary source and rule chain sizes over 8, 16, 32, and 64
for success, failure, and rejection, including adjacent continuations.

The deterministic gate checks that expansion counts equal cache cardinalities
and that, for a fixed environment and a single-entry rule chain, candidate plus
region expansions are at most twice the group count times the index state count.
Truly distinct capture environments still require distinct states; there is no
depth limit, resource budget, or claim of linear cost for arbitrary rules.
The private publication counter additionally checks that one rule in one
context visits no more candidates than the complete direct traversal. This
guards publication work independently of diagnostic uniqueness.

Benchmarks retain an 84-byte recursive failure fixture and ordinary, builtin,
and public-query cases. Build and run them with:

```sh
moon bench internal/rule/apply/recursive_bench_wbtest.mbt query/query_bench_test.mbt --target native --release
moon bench internal/rule/apply/recursive_bench_wbtest.mbt query/query_bench_test.mbt --target wasm --release
```

Timing is diagnostic; CI relies on state counts. See [BENCHMARKS.md](BENCHMARKS.md)
for the measured comparison and memory methodology.
