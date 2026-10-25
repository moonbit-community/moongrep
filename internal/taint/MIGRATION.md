# CFG API migration

YAML rules and finding records keep their existing format and location meaning.
The generic internal taint API changes as follows:

| Previous API | CFG API |
| --- | --- |
| `analyze_function_like(node, spec)` | `prepare_function_like(node)`, then `analyze(prepared, spec)` |
| Raised unsupported-function or fixpoint errors | `NotApplicable` / `Unsupported(diagnostics)` during preparation; `Complete` / `Incomplete` during analysis |
| `TaintTree = Array[RelativeTaint]` | Immutable `TaintValue::clean/source`, `project`, `write`, `sanitize`, `join`, `origins` |
| String `StoragePath.root` | `BindingId`; named parameter configuration uses `ParameterPath` |
| `TaintSpec.max_fixpoint_iterations` | `AnalysisOptions.max_scc_rounds`, default 64 |
| `custom_transfer_call` | `bind_call`, returning a deterministic transfer over evaluated snapshots |
| `return_taint` and `killed_paths` | Optional normal and exceptional `CallOutcome { value, writes }`; `StorageWrite::Set/Sanitize` |
| Unconditional normal transfer | `CallTransfer::normal(value, killed_paths?, findings?)` convenience constructor |
| Apply returns findings | `TaintScanResult { findings, diagnostics }` |

Call binders run once per source call site and rule with clean values. Transfer
functions may run repeatedly and must have no external side effects. Move
pattern matching to the binder, and read actual taint from the transfer argument.
Call origins must stay stable across iterations; using the original location
with the rule and source identifier provides that identity.

A parameter source still uses a name:
`EntryPath({ root: "input", segments: [] }, "entry", None)`. Call arguments and
receivers expose resolved storage identities. Use those paths for post-call
writes rather than reconstructing a path from a source name.

Unsupported executable syntax skips the affected function. An incomplete SCC
suppresses that rule's findings for the entire function, including earlier
sinks. Do not convert these results to an empty successful result. Render or
propagate their diagnostics. The CLI warns by default and supports
`--strict-taint` with exit code 8 after the rest of the scan finishes.

Intentional behavior changes include short-circuit paths, augmented and array
assignments, base-record preservation, inherited projection taint, simultaneous
loop binding, positional continue arguments, exit-time defer execution, and
errdefer running only on errors. The previous normal-exit errdefer finding is
removed. There is no legacy recursive evaluator or string-scope restoration.

Local and parameter call targets expose `CallInfo.callee_binding`. Use
`CallMatcher::CalleeBinding(id)` to distinguish shadowed call targets. Global
and method names retain their existing name matching and CST rule matching.
