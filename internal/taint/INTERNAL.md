# Taint Engine Internals

`internal/taint` performs intraprocedural taint analysis per function by
lowering MoonBit CST into an explicit control-flow graph (CFG) and solving it
with a work queue over strongly connected components (SCCs). The solver never
inspects raw CST nodes.

## Package architecture

| Subpackage | Responsibility |
| --- | --- |
| `domain` | Binding identities (`BindingId`), storage paths, immutable `TaintValue`, origins, and sink findings. |
| `model` | Normalized call facts (`CallInfo`), declarative call models, and pure call transfers. |
| `cfg` | Basic blocks, positional block parameters, instructions, terminators, graph validator, Tarjan SCC schedule, and temporary liveness. |
| `lowering` | Lexical binding resolution, parser-field normalization, and rule-independent CFG construction. `supports` in `expressions.mbt` is the executable-node support table; unlisted syntax or missing required fields emit diagnostics rather than clean values. |
| `engine` | Per-call-site model binding (once per original call site and rule), SCC fixpoint solver, and post-convergence finding collection. |

## Preparation and analysis lifecycle

### 1. Preparation (`prepare_function_like(node)`)

- Returns `NotApplicable` (bodyless declarations and non-function items),
  `Prepared(function)`, or `Unsupported(diagnostics)`.
- Caches graph validation, topological SCC ordering, and temporary-value
  liveness so one `PreparedFunction` is shared across all rules.
- Graph validation errors are internal failures (`InvalidGraph`); the validator
  checks identities, references, arities, unique definitions, and definite value
  availability on all reachable incoming paths.

### 2. Solving (`analyze(prepared, spec, options?)`)

- Returns `Complete(findings)` or `Incomplete(diagnostics)`.
- `AnalysisOptions.max_scc_rounds` defaults to `64` (no widening).
- SCCs run in topological order. Within an SCC, each block executes at most once
  per round in stable order, scheduling successors only when inputs change.
- Unreachable states stay distinct from reachable clean states, and liveness
  keeps dead temporaries from circulating around back edges.
- Exhausting the round budget suppresses **all** findings for that
  `(function, rule)` pair.
- Completed findings are deduplicated by `(sink_id, source range)` and sorted by
  range and identity.
- Optional `AnalysisMetrics` records cumulative block visits, changed inputs,
  and unique bound call sites for deterministic complexity tests and benchmarks.

## Values and storage domain

- `TaintValue` stores default inherited origins plus explicit child overrides
  (including clean overrides). Storage reads, projections, destructuring, and
  model subpath propagation all share `project`.
- **Strong vs. weak updates**:
  - Known struct fields, tuple slots, and constant array indexes use strong
    updates and preserve sibling paths.
  - Arrays carry a default element summary plus constant-index overrides.
    Dynamic reads join possible elements; dynamic writes weakly update both the
    summary and existing constant overrides; dynamic sanitizers never clear an
    element without proving uniqueness.
- `join` merges effective values rather than override markers. Origins are
  stable by `(rule, source identity, original source location)`, and equality
  compares origin sets regardless of order.
- Storage roots are `BindingId`s (shadowed variables get distinct IDs).
  Parameter sources use named `ParameterPath` resolved at entry. Cloned cleanup
  chains reuse lexical scopes and binding IDs, allowing call-model bindings to
  be shared across exit copies.

## Control-flow semantics

These contracts are verified against the installed compiler in
`compiler_semantics_test.mbt` and match the [MoonBit language
reference](https://docs.moonbitlang.com/en/latest/language/fundamentals.html#defer-and-errdefer-expressions)
(async cancellation is out of scope):

- **Short-circuit & branching**: short-circuit operands use separate execute and
  skip edges; condition bindings stay visible only on success edges; failed case
  and guard edges propagate side effects into subsequent cases. No general
  feasibility analysis or implicit control-flow taint is performed.
- **Evaluation order & updates**: receivers, indexes, and RHS expressions
  evaluate once in source order; augmented assignment snapshots the old target
  value before the RHS; record updates start from the base value and replace
  only specified fields.
- **Loops**: initializers evaluate in the outer environment before introducing
  loop binders; updates evaluate all RHS expressions before committing
  positional loop parameters; normal body completion enters the update block
  while explicit `continue` jumps straight to the next header; `break` and outer
  jumps bypass `nobreak` (entered only on natural loop exit).
- **Cleanups & errors**: `defer` captures lexical identities at declaration and
  runs in reverse declaration order at exit using exit-time storage (pending
  values and jump args become block parameters before cleanup). `errdefer` runs
  only on exceptional exits; cleanup errors replace pending results and keep
  propagating through remaining cleanups. Cleanup chains are cached by
  `(scope stack, exit kind, target)`. `try!` exceptions terminate in `Abort` and
  never reach outer `catch` blocks.

## Calls and YAML rule integration

- `TaintSpec.bind_call` runs **once** per original source call site and rule
  with static metadata and clean taint values, returning a pure transfer over
  evaluated `CallInfo` snapshots. Transfers run repeatedly during solving and
  once more during final finding collection, so they must have no external side
  effects, never mutate inputs, and produce iteration-stable origins.
- Returning `Some(transfer)` overrides declarative models and
  `unknown_call_policy`; `None` falls back to them.
- Normal and exceptional `CallOutcome`s carry separate values and storage writes
  (`None` marks an impossible completion). Only explicit `raise` and
  model-declared exceptional outcomes activate exception edges; unknown calls
  never implicitly raise.
- Resolved local/parameter callees expose `callee_binding`, selectable via
  `CallMatcher::CalleeBinding`.
- **YAML rules**: `internal/rule/taint_lowering` caches source/sanitizer/sink
  matches during binding and keeps `NoEffect` for unmatched calls.
  `internal/rule/apply` prepares each function once before iterating rules
  (structural-only plans never prepare CFGs), skips unsupported functions for
  all affected rules, skips only the affected `(function, rule)` pair on
  nonconvergence, and coalesces diagnostics sharing `(file, range, reason)`
  while preserving all affected rule IDs. The CLI emits `taint_incomplete`
  warnings and exits `8` when `--strict-taint` is enabled.

## Boundaries and extension notes

Out of scope: interprocedural resolution, general heap aliasing, type
declaration inspection, and async cancellation.

When supporting new executable syntax, implement lowering plus parser-field and
behavior tests before enabling its entry in `expressions.mbt`'s `supports`
table. See [MIGRATION.md](MIGRATION.md) for API migration notes and
[BENCHMARKS.md](BENCHMARKS.md) for performance data.
