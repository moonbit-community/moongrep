# taint Internal Notes

This document records implementation details that are easy to miss when
changing the `taint` package and its rule integration. It is for maintainers of
the analyzer and callers, not for rule authors.

## Package Role

`taint` is a generic intraprocedural taint engine over MoonBit parser CSTs.

The package analyzes one parser `Impl` at a time through:

- `analyze_function_like(node, spec)`
- `analyze_function_like_multi(node, rules)`

Only function-like top-level nodes are executable:

- `Impl_Function` with a `body` child
- `Impl_ImplMethod` whose nested `method` declaration has a `body` child

Declarations without bodies, top-level expressions, tests, type definitions,
traits, and other `Impl` forms raise
`TaintAnalysisError::UnsupportedFunctionLike`. The rule application layer
intentionally catches and ignores that error during file scans.

## Main Flow

Analysis starts in `analyze_single_function_like`:

1. `function_like_from_impl` extracts the function or method name, location,
   parameter roots, and body expression.
2. `EntryPath` sources whose root is a real parameter are written into the
   initial `TaintState`.
3. The body is interpreted by `eval_expr`.
4. Sink findings accumulated during evaluation are returned in `AnalysisResult`.

The engine is not interprocedural. It models calls through `TaintSpec` and
`CallInfo`. It never looks up or analyzes a callee body.

## State and Values

There are two related taint representations:

- `TaintState` stores taint facts for named storage paths.
- `TaintTree` stores taint facts relative to one evaluated expression value.

`TaintState` is an array of private `StateEntry` values:

```text
StoragePath(root, absolute segments) -> origins
```

`TaintTree` is public and represented as `Array[RelativeTaint]`:

```text
relative segments below current value -> origins
```

For example, if `payload.secret` is tainted in storage, the state contains a
path rooted at `payload` with segment `Field("secret")`. Evaluating `payload`
returns a tree with relative path `Field("secret")`; evaluating
`payload.secret` projects that tree to an empty relative path, meaning the
value itself is tainted.

Origins are de-duplicated by structural equality. Merge operations preserve all
unique origins for the same path.

## Storage Paths

`StoragePath` roots are names for local variables or parameters. Segments model
simple projected storage:

- `Field(name)` for record fields and labels
- `TupleIndex(index)` for tuple projections
- `ConstIndex(value)` for array reads with literal integer indices
- `AnyIndex` for unknown array indices and array-wide summaries

`storage_path_from_expr` recognizes only storage-shaped expressions:

- identifiers
- fields
- array gets
- groups and constraints around those forms

Expressions such as calls, infix expressions, constructors, and arbitrary
computations have no storage path. They can carry a `TaintTree` as a temporary
value. Sanitizers and kill effects can remove later storage taint when the
selected value has a `StoragePath`.

Reads and writes deliberately use different prefix semantics:

- reads use `path_prefix_match_for_read`, where `AnyIndex` and `ConstIndex`
  may match each other so dynamic array reads can observe summarized or
  concrete element taint
- writes and kills use `path_prefix_match_for_write`, which requires exact
  segment equality and removes only the written subtree

Writing `x.a` kills existing facts below `x.a` and then writes the new value's
relative tree below `x.a`. Sibling facts such as `x.b` are preserved.

## Expression Evaluation

`eval_expr` interprets supported expression forms in source evaluation order.
It returns an `EvalResult` containing:

- the next storage state
- the expression value taint
- a `FlowExit`

Common value construction shifts child taint into relative subpaths:

- tuple item `i` becomes `TupleIndex(i)`
- array item `i` becomes both `ConstIndex(i)` and `AnyIndex`
- record field `f` becomes `Field(f)`

Path-like expressions prefer storage reads. An expression with a concrete
storage path gets its value from `state_read_path(state, path)`. Field and array
projections without a concrete storage path evaluate the base value and use
`tree_project`.

`let` and `let mut` evaluate the right-hand side, bind the pattern with
`bind_pattern`, and continue into the body. Assignment and mutation update
storage through `state_write_path` when the left side can be represented as a
storage path.

Unsupported or less-specific expression forms go through `eval_unknown_expr`.
That function is conservative in the local sense: it evaluates known child
expressions so nested calls can report sinks. It returns the union of child
value taint where a value result is useful. Completely unsupported leaf
forms return no taint.

## Pattern Binding

`bind_pattern` projects the bound value into pattern variables:

- variable and alias patterns write the whole value to the binder
- tuple patterns project by `TupleIndex`
- record patterns project by `Field`
- array patterns project by constant indices or `AnyIndex`
- constructor and special-constructor arguments project by positional tuple
  index or labelled field
- `or` patterns bind both sides and merge the resulting states

Pattern binding is structural and type-agnostic. It does not inspect MoonBit
type declarations, constructor definitions, field definitions, or collection
lengths.

When a whole value is tainted at the empty relative path, destructuring also
copies that whole-value taint into each destructured binder. This lets
`input is Some(item)` treat `item` as derived from a tainted `input` without
resolving constructor payloads through type information.

Lexical binders are restored after their scope. The evaluator records the root
names introduced by `let`, case patterns, catch and try-else patterns,
lex/regex patterns, loop binders, and local function names. After the scoped
body is evaluated, entries for those roots are restored from the pre-scope base
state. Mutations to non-shadowed roots are preserved.

Condition patterns create a separate true-branch state. `is`, `lexmatch?`,
regex matches, grouped conditions, and `&&` expose their binders only to the
true branch or loop body/continue path. Else branches, loop else blocks, and
post-scope expressions use the base state without those condition binders.

## Calls

All call syntaxes are normalized to `CallInfo` before transfer logic runs:

- `Apply`
- `DotApply`
- `Pipe`
- `RevPipe`

`CallInfo` carries:

- the original call CST and location
- a normalized `callee_name` when one can be extracted
- receiver path/site/taint for method-style calls
- evaluated arguments as `CallArgument`

Argument indices are semantic after pipe desugaring:

- ordinary call arguments start at index `0`
- `lhs |> f(arg)` makes `lhs` argument `0` and explicit arguments start at `1`
- `f <| rhs` makes `rhs` argument `0`
- receivers stay separate from arguments

If an argument evaluates to a non-normal flow such as `return`, the call
transfer is not executed. This prevents a sink call from reporting after one of
its arguments has already exited control flow.

## Transfer Ordering

`apply_call_transfer` gives `spec.custom_transfer_call` first chance for every
call. If it returns `Some(transfer)`:

1. `transfer.killed_paths` are removed from storage.
2. `transfer.findings` are appended as-is.
3. `transfer.return_taint` becomes the call value.
4. declared sources, declared call models, and unknown-call policy are skipped.

If the custom transfer returns `None`, `apply_declared_call_transfer` runs:

1. matching `SourceModel::CallReturn` entries add fresh return taint
2. all matching `CallModel`s are applied in array order
3. if nothing matched, `unknown_call_policy` decides the return taint

Declarative model matching is not first-match-wins. Every matching call model
contributes effects.

Sink effects collect origins from the selected value and report only when at
least one origin is present. Custom transfers are responsible for preserving
that invariant themselves; their findings are not filtered by the engine.

Kill effects only affect later storage reads. They do not rewrite the
receiver/argument taint already evaluated for other effects on the same call.

## Control Flow

`FlowExit` tracks whether evaluation continues normally or exits through:

- `return`
- `raise`
- `break`
- `continue`

Sequential evaluation stops on any non-normal flow. This is why a sink after an
unconditional `return` is not reported.

Branches are path-insensitive:

- `if` evaluates the condition once, evaluates the true branch from the
  condition true-state, evaluates the false branch from the base post-condition
  state, restores condition binders, and merges normal branch states and values
- `match` and `catch` bind each case independently, merge normal case states,
  and keep exit states only when no normal case exists
- `try` propagates `return`, `break`, and `continue` immediately; `raise`
  dispatches to catch cases
- when a `try` body completes normally, catch and try-else case bodies are also
  evaluated as possible normal branches from the post-body state

Loops use a bounded fixpoint controlled by `spec.max_fixpoint_iterations`.
`while`, `for`, and `foreach` repeatedly evaluate the body from the current
joined state until another pass adds no new taint facts or the bound is reached.
`return` and `raise` escape immediately. `break` joins the break state and then
leaves the loop. `continue` is treated as a loop-body exit and participates in
the join path.

`foreach` binds loop variables to the collection's `AnyIndex` projection before
the body fixpoint starts.

## YAML Rule Integration

YAML taint rules are compiled outside this package:

1. `rule/compile` validates taint clauses and records `TaintTarget`.
2. `matching` matches compiled source, sink, and sanitizer call patterns.
3. `rule/taint_lowering` builds a `TaintSpec` with `custom_transfer_call`.
4. `rule/apply` runs `@taint.analyze_function_like` and maps sink findings to
   scanner `RuleFinding`s.

The lowering layer implements YAML taint semantics as a custom transfer:

- matching source calls add fresh return taint
- matching sanitizer calls kill the selected target path if it has one
- matching sink calls report when the selected target value is tainted

The `rule/compile` layer guarantees that `__SOURCE__` appears exactly once in a
sink or sanitizer and is the whole receiver or whole argument. Because of that,
`rule/taint_lowering` can select the target directly from `CallInfo` without
walking arbitrary subexpressions.

Lowered YAML taint specs use:

- no entry-path sources
- no declarative call models
- `unknown_call_policy = NoEffect`
- `max_fixpoint_iterations = 6`

This is intentionally narrower than the generic `taint` API. Direct users of
`TaintSpec` can model entry sources, propagating unknown calls, and declarative
call effects that YAML rules do not expose today.

## Important Limits

The analyzer is path-sensitive for simple storage paths. Other cases are
path-insensitive and type-agnostic.

It does not:

- analyze across function boundaries
- resolve imports, overloads, methods, fields, constructors, or types
- prove branch feasibility
- model aliases; explicit storage writes and value copies provide the available
  alias behavior
- represent arbitrary subexpressions as killable storage
- guarantee full semantics for unsupported CST forms

These limits are deliberate for the current scanner. If a change needs stronger
semantics, add focused tests at the package boundary and at the YAML rule
integration boundary.

## Maintenance Checklist

When adding a new storage-shaped expression:

1. update `storage_path_from_expr`
2. update read/projection behavior in `eval_expr` if needed
3. add domain tests for read, write, kill, and merge behavior
4. add taint tests showing sink behavior through the new path form

When adding a new value-producing expression:

1. evaluate children in source order
2. stop immediately on non-normal `FlowExit`
3. shift child taint into relative paths when the expression constructs a
   compound value
4. add tests for both direct sink reporting and storage after `let`

When changing call semantics:

1. update `CallInfo` construction for every call syntax that should share the
   behavior
2. preserve pipe argument indexing rules
3. check `CallMatcher` behavior for `CalleeName`, `MethodName`, and `AnyCall`
4. add direct `taint/taint_test.mbt` coverage
5. add `rule/apply` or `rule/taint_lowering` tests if YAML behavior changes

When changing YAML taint behavior:

1. update validation in `rule/compile`
2. update target extraction or transfer generation in `rule/taint_lowering`
3. keep `matching/INTERNAL.md` placeholder notes in sync if `__SOURCE__`
   matching behavior changes
4. update rule-author docs only for user-visible semantics
5. add integration tests under `rule/apply` or `rule/taint_lowering`

For package-local engine work, `moon test taint` is the tight loop. For changes
visible through YAML rules, also run the relevant `rule/compile`,
`rule/taint_lowering`, and `rule/apply` tests.
