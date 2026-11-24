# CFG Taint API Migration Guide

YAML rules and `RuleFinding` records keep their existing format and location
semantics. Callers using the internal generic taint API directly should migrate
as follows.

## API mapping

| Previous API | CFG API |
| --- | --- |
| `analyze_function_like(node, spec)` | `prepare_function_like(node)` followed by `analyze(prepared, spec)` |
| Raised unsupported-function or fixpoint errors | `NotApplicable` / `Unsupported(diagnostics)` from preparation; `Complete` / `Incomplete` from analysis |
| `TaintTree = Array[RelativeTaint]` | Immutable `TaintValue::{clean, source, project, write, sanitize, join, origins}` |
| String `StoragePath.root` | `BindingId`; named parameter entry sources use `ParameterPath` |
| `TaintSpec.max_fixpoint_iterations` | `AnalysisOptions.max_scc_rounds` (default `64`) |
| `custom_transfer_call` | `bind_call`, returning a pure transfer over evaluated `CallInfo` snapshots |
| `return_taint` and `killed_paths` | Optional normal and exceptional `CallOutcome { value, writes }` with `StorageWrite::{Set, Sanitize}` |
| Unconditional normal transfer | `CallTransfer::normal(value, killed_paths?, findings?)` convenience constructor |
| `apply` returning `Array[RuleFinding]` | `TaintScanResult { findings, diagnostics }` |

## Key migration rules

### 1. Split pattern matching from transfer execution

- `bind_call` runs once per source call site and rule with **clean** values.
  Move CST/pattern matching into `bind_call`, and read live taint values only
  inside the returned transfer closure.
- Transfer closures run repeatedly during fixpoint solving and must be pure and
  deterministic. Keep origins stable across iterations by anchoring them to the
  rule, source identifier, and original call location.

### 2. Use resolved storage identities

- Parameter entry sources still configure by name:
  `EntryPath({ root: "input", segments: [] }, "entry", None)`.
- Call arguments and receivers already expose resolved `StoragePath`s; use those
  paths directly for post-call writes rather than rebuilding paths from source
  names.
- Local and parameter call targets expose `CallInfo.callee_binding`; use
  `CallMatcher::CalleeBinding(id)` to handle shadowed callees while globals and
  methods keep existing name and CST matching.

### 3. Propagate incomplete-analysis diagnostics

- Unsupported executable syntax skips the affected function. An incomplete SCC
  suppresses **all** findings for that `(function, rule)` pair, including
  earlier sinks.
- Do not silently turn `Unsupported` or `Incomplete` into empty success results;
  render or propagate their diagnostics. The CLI warns by default and supports
  `--strict-taint` (exiting `8` after the scan finishes).

### 4. Intentional semantic improvements

The CFG engine replaces the legacy recursive evaluator and string-scope
restoration. Intentional behavior updates include:

- Short-circuit path sensitivity
- Augmented and array-element assignments
- Base-record preservation in record updates
- Inherited taint on projections
- Simultaneous loop binding and positional `continue` arguments
- Exit-time `defer` execution and error-only `errdefer` (the previous
  normal-exit `errdefer` finding is removed)
