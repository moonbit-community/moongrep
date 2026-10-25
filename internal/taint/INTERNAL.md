# Taint engine

The engine performs intraprocedural analysis through semantic lowering, an
explicit CFG, and an SCC work queue. It never executes CST nodes during solving.

- `domain` owns binding identities, paths, immutable taint values and findings.
- `model` owns normalized call facts and deterministic call transfers.
- `cfg` owns blocks, positional block parameters, instructions, terminators,
  graph validation, SCC ordering and temporary-value liveness.
- `lowering` resolves lexical bindings, normalizes parser fields, and builds the
  rule-independent graph. `supports` in `expressions.mbt` is the executable-node
  support table. Unlisted executable syntax and missing required fields produce
  diagnostics, never clean values.
- `engine` binds models once per original call site and rule, then solves and
  collects findings after convergence.

`prepare_function_like(node)` returns `NotApplicable`, `Prepared(function)`, or
`Unsupported(diagnostics)`. Bodyless declarations and non-function items are not
applicable. A prepared function caches graph validation, SCCs, and liveness and
can be shared across all rules. Graph validation errors are internal failures.
The validator checks identities, references, arities, unique definitions, and
value availability on all reachable incoming paths.

`analyze(prepared, spec, options?)` returns `Complete(findings)` or
`Incomplete(diagnostics)`. `AnalysisOptions.max_scc_rounds` defaults to 64.
Components run in topological order. Inside a component, each block runs at most
once per round, in stable order, and only changed inputs schedule successors.
Unreachable states are separate from reachable clean states. Dead temporaries
do not circulate around back edges. There is no widening. Budget exhaustion
suppresses every finding for that function and rule. Completed findings are
deduplicated by sink identity and source range and sorted by range and identity.
Optional `AnalysisMetrics` records cumulative block visits, changed inputs, and
unique bound call sites for deterministic complexity tests and benchmarks.

## Values and storage

`TaintValue` has default origins and explicit child overrides, including clean
overrides. Storage reads, expression projection, destructuring and model subpath
propagation use `project`. Known fields, tuple slots and constant array indexes
use strong updates and retain siblings. An array has a default element summary
and constant overrides. Dynamic reads join possible elements. Dynamic writes
weakly update the summary and existing constant overrides; dynamic sanitizers
cannot clear an element without proving uniqueness. `join` merges effective
values, not override markers. Origins are stable by rule, source identity and
original source location. Equality compares origin sets independently of order.

Storage roots are `BindingId`s. Parameter sources use `ParameterPath` names,
resolved to parameter identities at analysis entry. Shadowed variables have
separate identities. Lexical scopes and binding identities are reused when the
same cleanup syntax is lowered into several exit chains; call-model binding
can therefore be shared across those copies too.

## Control flow

Short-circuit operands have execute and skip edges. Successful condition
patterns expose their binders only on success. Case and guard failure edges
carry their side effects into subsequent cases. There is no general feasibility
analysis or implicit control-flow taint.

Receivers, indexes and right-hand expressions execute once, in source order.
Augmented assignment snapshots the old target value before the right-hand side.
Record updates begin with the base value and replace only specified fields.
Loop initializers execute in the outer environment before introducing binders.
Updates evaluate every right-hand side before committing positional loop
parameters. Normal body completion enters the update block; explicit continue
jumps straight to the next header. Break and outer jumps bypass `nobreak`;
only natural exits enter it.

Defer declarations capture lexical identities. Cleanup expressions execute on
exit, in reverse declaration order, reading exit-time storage. Pending values
and jump parameters become block parameters before cleanup. Errdefer runs only
on exceptional exits. Cleanup errors replace pending results and continue
exceptional propagation through remaining cleanups. Cleanup chains are cached
by scope stack, exit kind and target. Try-bang exceptions terminate in `Abort`
and do not reach outer catches.

These contracts are pinned by `compiler_semantics_test.mbt` against the installed
compiler and the [MoonBit language reference](https://docs.moonbitlang.com/en/latest/language/fundamentals.html#defer-and-errdefer-expressions).
Async cancellation is outside this analysis.

## Calls and rule integration

`TaintSpec.bind_call` receives static call metadata with clean taint values,
once per original source call site and rule. It returns a pure transfer over
`CallInfo` snapshots. That transfer can run repeatedly during solving and once
more during final finding collection. It must not mutate input values, perform
external side effects or introduce iteration-dependent origins. A custom `Some`
transfer overrides declarative models and unknown-call behavior. `None` falls
back to them. Normal and exceptional `CallOutcome`s have separate values and
storage writes. `None` marks an impossible completion. Only explicit raises
and model-declared exceptional outcomes activate exception edges. Unknown calls
never implicitly raise.

YAML format and `RuleFinding` fields are unchanged. Rule lowering caches source,
sanitizer and sink pattern matches before solving. Unmatched YAML calls retain
`NoEffect`. The apply layer prepares each function before iterating rules and
returns findings plus diagnostics. Structural-only plans return without preparing
a CFG. Unsupported functions are skipped for all affected rules; nonconvergence
skips only the affected function/rule pair. The CLI renders `taint_incomplete`
warnings and continues scanning. `--strict-taint` returns status 8 after scanning,
including parse failures that prevented taint analysis.

The analysis does not resolve callees across functions, infer heap aliases,
inspect type declarations, or model async cancellation. Add supported syntax in
lowering with parser-field and behavior tests before enabling its support-table
entry. See [MIGRATION.md](MIGRATION.md) for API changes and [BENCHMARKS.md](BENCHMARKS.md)
for performance measurements.

Resolved local/parameter callees also carry `callee_binding`; generic models can
select that identity with `CalleeBinding`. Name-based and YAML call matching keep
their existing syntax semantics. Diagnostics with the same file, range and reason
are coalesced while preserving all affected rule IDs.
