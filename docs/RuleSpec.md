# Rule Specification

This document is the authoritative specification for YAML rules accepted by
the moongrep.

If you are writing your first rule, start with [WritingRules.md](WritingRules.md).

## Scope and Status

This document specifies the current YAML rule file format, validation rules,
and matching semantics.

The keywords "must", "must not", "may", and "currently" describe the behavior
rule authors can rely on today.

Rules use YAML format. Every `shape` value is MoonBit surface syntax. The scanner
matches parsed MoonBit expression structure and does not match raw text.
Whitespace formatting and comments, including documentation comments, are not
significant. Literal source spelling is an exception: constants are compared by
their parser CST kind and preserved source spelling, not by normalized semantic
value. Equivalent values such as `1000` and `1_000` therefore do not necessarily
match. Expression form,
operators, labels, callee names, and argument structure are also significant.
Wildcards and declared metavariables modify these matching requirements as
documented below.

## Rule Files

A rules root is a directory containing YAML rule files.

- Files ending in `.yaml` or `.yml` are discovered recursively below the rules
  root.
- Other files are ignored.
- Discovered rule files are processed in sorted order.
- Symlinked rule directories are followed.
- An empty rules root is invalid.
- Each rule file must contain exactly one YAML document.
- The top-level YAML document must be a mapping.
- Each rule file defines exactly one rule.

Rule ids are derived from the rule file directory and the YAML `id`:

- take the rule file directory relative to the rules root
- read the top-level `id` string from the YAML document
- join the relative directory and `id` with `/`

For rule files directly under the rules root, the final rule id is just `id`.
The rule filename does not contribute to the rule id. The YAML `id` must not be
empty and must not contain `/`; directory ownership is encoded only by file
location.

Example:

```text
rules/example.yaml with id: target-call               -> target-call
rules/security/raw.yaml with id: unsafe-html          -> security/unsafe-html
rules/security/nested/raw.yml with id: unsafe-html    -> security/nested/unsafe-html
```

Rule ids must be unique.

## YAML Schema

### Top-Level Keys

Only these top-level keys are accepted:

- `id` (required): non-empty YAML string that must not contain `/`
- `description` (required): YAML string
- `patterns` (optional for structural rules): non-empty YAML array
- `patterns-not` (optional for structural rules): non-empty YAML array using
  the same object schema as `patterns`
- `inside-expr` (optional for structural rules): non-empty YAML array using the
  same `shape` and optional `guard` object schema as `patterns`; entries are
  ordered alternative outer expression contexts
- `inside-toplevel` (optional for structural rules): non-empty YAML array using
  the same `shape` and optional `guard` keys as `inside-expr`, plus optional
  `match-mode`; each shape is parsed as one MoonBit top-level item
- `taint` (required for taint rules): YAML mapping

Unknown top-level keys are rejected.

Each rule must choose exactly one rule mode:

- structural mode: `patterns`, optionally with `patterns-not`; or
  `inside-expr` or `inside-toplevel` with `patterns`, `patterns-not`, or both
- taint mode: `taint`

`patterns` and `taint` are mutually exclusive. `inside-expr`,
`inside-toplevel`, and `patterns-not` are valid only on structural rules; they
are rejected on taint rules. `inside-expr` and `inside-toplevel` are mutually
exclusive. `patterns-not` must appear with `patterns`, `inside-expr`, or
`inside-toplevel`. An `inside-expr` or `inside-toplevel` rule without
`patterns` must include `patterns-not`.

`id` is the local rule name within its file directory. `description` is also
required and must be a string. Its content is preserved as supplied by YAML,
including trailing newlines produced by block scalars.

### Pattern Objects

Structural entries in `patterns`, `patterns-not`, and `inside-expr` use this
object schema. `inside-toplevel` adds the `match-mode` key described below.

Only these keys are accepted:

- `shape` (required): YAML string containing one MoonBit expression snippet,
  or one top-level item for `inside-toplevel`
- `guard` (optional): YAML mapping from `$`-prefixed capture name to regex string
- `match-mode` (optional, `inside-toplevel` only): `exact` or `partial`

Unknown keys inside a pattern object are rejected.
`match-mode` is rejected in `patterns`, `patterns-not`, `inside-expr`, and
taint clauses.

Taint `sources`, `sinks`, and `sanitizers` use the same `shape` key. A `guard`
is invalid in these entries.

## Shapes

An ordinary `shape` must be a single MoonBit expression snippet. Each
`inside-toplevel` entry's `shape` must be exactly one MoonBit top-level item.

Valid expression shapes include calls, method calls, field accesses,
operators, blocks, conditionals, loops, matches, lambdas, collection literals,
record expressions, and other expression-sized MoonBit syntax. Ordinary
`patterns`, `patterns-not`, and `inside-expr` shapes are not a whole file,
top-level declaration, package fragment, or import list.

Each `inside-toplevel` shape is parsed as one top-level item, such as a
function, top-level `let`, `test`, method `impl`, view, or top-level expression.
It is one item and cannot represent a whole file or import list.

Shapes are structural:

- undeclared identifiers and labels match literally
- constants match by parser CST kind and preserved source spelling; equivalent
  values such as `1000` and `1_000` do not necessarily match
- operators match literally
- call and method-call argument kinds, labels, order, and arity must match
- type annotations and type names in matched syntax must match where present
- source locations, comments (including docstrings), and whitespace formatting
  do not participate in matching in any mode

The scanner does not type-check shapes and does not resolve names semantically.
For example, two imported names that refer to the same definition compare as
equal only when their parsed source spelling matches or a metavariable captures
them.

### Function Bodies and Explicit Blocks

The braces around a function, method, test, lambda, or local-function body are
matching containers. They are not themselves an explicit block expression
candidate. The statements inside the body form a sequence candidate, and each
contained expression remains independently searchable.

Consequently, `$_` and `$(root:exp)` search the expressions inside a function
body instead of capturing the body's braces. A complete multi-statement shape
can match the body sequence. Its finding range starts at the first matched
statement and ends at the last matched statement, without the body braces.

A block written as an expression inside another body remains an explicit block
candidate. For example, `{ a; b }` does not match the container around
`fn sample { a; b }`, but it does match the nested block in
`fn sample { { a; b } }`. The finding range for that explicit block includes
its braces.

The same candidates and ranges are used by ordinary positive patterns,
`patterns-not`, `inside-expr` target traversal, and expression queries.

### Let Shapes With Omitted Bodies

An ordinary `let` shape without an explicit body is a let-header pattern. For
example, this shape matches the binding pattern and right-hand side. It places
no constraint on the candidate body:

```yaml
patterns:
  - shape: let $(name:id) = $(value:exp)
```

It can match candidates such as:

```moonbit
let item = load()
```

```moonbit
let item = load(); use(item)
```

```moonbit
let item = load(); { trace(item); item }
```

The scanner recognizes this single-statement `let` shape as a let-header
pattern. When the candidate has following statements, the candidate is the
sequence suffix beginning at that `let`; the matcher compares the header and
does not constrain the rest of the suffix.

Write an explicit body when the body matters:

```yaml
patterns:
  - shape: let $(name:id) = $(value:exp); use($(name:id))
```

To capture whichever body the candidate has, write a body metavar explicitly:

```yaml
patterns:
  - shape: let $(name:id) = $(value:exp); $(body:exp)
```

To require a unit body, write an explicit `()` body:

```yaml
patterns:
  - shape: let $(name:id) = $(value:exp); ()
```

This matches an explicit unit body. It is not the same as the omitted-body
shape above, which intentionally ignores the candidate body. Omitted-body-only
matching is not currently expressible as a structural shape.

This shortcut applies only to ordinary `let` expressions. `let mut`, local
function definitions, `letrec`, and `defer` shapes use normal structural
matching. A header-only shape for one of those forms does not match a candidate
with a continuation; write the complete statement sequence when the
continuation matters. `proof_let` is an independent expression candidate, so a
header match covers only the `proof_let` while later expressions remain
searchable.

### Guard Shapes With Omitted Bodies

A `guard` shape without an explicit body is a guard-header pattern. It matches
the condition and `else` expression but places no constraint on the candidate
continuation:

```yaml
patterns:
  - shape: guard ready() else { fallback() }
```

It can match candidates such as:

```moonbit
guard ready() else { fallback() }
```

```moonbit
guard ready() else { fallback() }; continue_work()
```

```moonbit
guard ready() else { fallback() }; { prepare(); finish() }
```

The scanner recognizes this single-statement shape as a guard-header pattern.
When the candidate has following statements, it compares the header with the
sequence suffix beginning at the `guard` and ignores the rest of that suffix.
The condition and `else` expression still use normal recursive structural
matching.

Write an explicit body when the continuation matters:

```yaml
patterns:
  - shape: guard ready() else { fallback() }; continue_work()
```

To capture whichever body the candidate has, write a body metavar explicitly:

```yaml
patterns:
  - shape: guard ready() else { fallback() }; $(body:exp)
```

To require a unit body, write an explicit `()` body:

```yaml
patterns:
  - shape: guard ready() else { fallback() }; ()
```

The explicit unit is matched structurally and is not a wildcard. As with an
omitted `let` body, matching only syntactically omitted guard bodies is not
currently expressible as a structural shape.

## Metavariables

Identifiers and labels in a shape are literal by default. Metavar syntax inside
`shape` turns a name into a metavariable. The built-in wildcard forms described
below retain their documented behavior.

### Syntax

Use `$(name:exp)` for an expression structural capture:

```yaml
patterns:
  - shape: $(left:exp) == $(left:exp)
```

Use `$(name:id)` for a normalized identifier capture:

```yaml
patterns:
  - shape: |
      for $(counter:id) = $(start:exp); $(counter:id) < $(limit:exp); $(counter:id) = $(counter:id) + 1 {
        $(body:exp)
      }
```

For common cases, the kind may be omitted with bare `$name` syntax:

```yaml
patterns:
  - shape: $value + $value
```

The moongrep infers a single kind for all occurrences of the same name. Bare
names used only as expression placeholders infer `exp`; bare names used in
binder, label, constructor, type-name, or qualified-identifier positions infer
`id`; bare names used as whole type nodes infer `type`. For example, in
`for $counter = 0; $counter < $limit; ...`, `$counter` infers `id` from the
binder position and `$limit` infers `exp`; in `let values : Array[$T] = input`,
`$T` infers `type`.

Only `exp`, `id`, `const`, `arg`, `pat`, and `type` are supported. A name may be
repeated within one kind. Using the same payload across multiple kinds such as
`$(name:exp)`, `$(name:id)`, `$(name:const)`, `$(name:arg)`,
`$(name:pat)`, and `$(name:type)` in one shape is invalid.

Bare `$name` inference is intentionally conservative. It does not default to
`const`, `arg`, or `pat`. A simple pattern variable such as
`match input { $item => body }` is ambiguous between `id`, `const`, and `pat`;
write `$(item:id)`, `$(item:const)`, or `$(item:pat)` to choose. Bare `$name`
does not infer `arg`; use explicit `$(name:arg)` for whole call arguments.
Bare `$name` in a type annotation can infer `type`; use explicit
`$(name:type)` when the type position is not obvious. An explicit same-name
occurrence also fixes later bare occurrences when the positions are compatible.

The old YAML `metavars` key is not supported. Pattern objects that contain it
are rejected as using an unsupported key.

### Ellipsis Metavariables

`$$$name` captures zero or more consecutive siblings in an ordered untyped-CST
list. `$$$(name:kind)` applies one of `exp`, `id`, `const`, `arg`, `pat`, or
`type` to every captured item. A bare named ellipsis has kind `AnyItem`; if the
same name also has a typed occurrence, that occurrence determines the kind for
all bare occurrences.

```yaml
patterns:
  - shape: inspect($$$args)
  - shape: pair([$$$(items:exp)], [$$$items])
```

The marker must occupy a complete child whose field name is absent in the
untyped CST. Valid examples include argument, expression, parameter, pattern,
and type lists. It cannot occupy the root, a normal named field, a label, or
part of another node. A block's final value has no following
`Syntax_Separator`, so it is not a replaceable statement sequence.

Matching processes pattern items from left to right. At an ellipsis it tries
the shortest possible capture first, starting with the empty sequence, and
backtracks with bindings restored until the remaining pattern succeeds. This
defines the result when one list contains multiple ellipses. Empty captures
satisfy every kind constraint.

In expression lists, `exp`, `id`, and `const` accept the same candidate forms as
their single-node counterparts. In call argument lists, `arg` accepts
positional, labelled, pun, optional-labelled, and optional-pun arguments;
`exp`, `id`, and `const` accept only positional arguments whose values satisfy
that kind. `pat` applies to pattern-list items, `type` to type-list items, and
`id` can capture parameter items that have binders. The captured array always
contains the original complete sibling nodes, such as `Argument`, `Parameter`,
or expression nodes.

Repeating a named ellipsis requires the captured arrays to have equal lengths
and structurally equal nodes after source locations are ignored. A name cannot
be shared by a normal metavar and an ellipsis, and conflicting explicit kinds
are rejected. `$$$_` and `$$$(_:kind)` do not bind and each occurrence is an
independent wildcard. Guards cannot reference ellipsis captures. Inside-context
bindings inherit `Multiple` values just like other bindings; a repeated inner
ellipsis must use the same kind. Taint sink and sanitizer shapes may place
ellipses around their single whole-argument or receiver `__SOURCE__` target.

The public matcher and query APIs expose captures as `BoundValue`. Ordinary
node captures are `Single(Node)`. Ellipsis captures are
`Multiple(Array[Node])`. A terminal named expression metavar or special target
that captures a flattened continuation is `Single` for one statement and
`Multiple` for an empty or multi-statement suffix. `ExprMatch.bindings`,
`ExprQuery::captures`, and
`ExprQuery::captures_from_cst` all use this representation. A terminal `$_`
continuation wildcard is non-binding and therefore produces no `BoundValue`.

### Reserved Names

These names must not be used as metavar names:

- `$_`
- `__TARGET__`
- `__SOURCE__`

`$_` is the ignore placeholder described below. `__TARGET__` and `__SOURCE__`
keep their existing built-in meanings. `__TARGET__` is only valid in
`inside-expr` and `inside-toplevel`; `__SOURCE__` is only valid in taint sink
and sanitizer shapes.

### Where Metavars Can Bind

`$(name:exp)` is valid only as a whole bare identifier expression. It captures the
candidate expression at that position. This is valid:

```yaml
patterns:
  - shape: sink($(value:exp))
```

This is invalid because a pattern binder is not an expression position:

```yaml
patterns:
  - shape: match input { $(item:exp) => item }
```

Use `$(name:id)` for source-level names. It can bind simple variable targets,
binders, bare identifier expressions, qualified function names, constructor
identities, simple variable patterns, and labels such as method names, field
names, labelled argument names, and record field labels.

Use `$(name:const)` for literal constants. It is valid only as a whole bare
identifier expression or as a simple pattern variable position, and it matches
only parsed MoonBit constants. 

Use `$(name:arg)` for a whole function-call argument slot. It is valid only as
an entire bare positional argument in a call pattern:

```yaml
patterns:
  - shape: sink($(arg:arg))
```

The placeholder can match a candidate positional argument, labelled argument,
labelled pun, optional labelled argument, or optional labelled pun. The captured
value is the whole `Argument` CST node, including argument kind, label, and
value.

Use `$(name:type)` for a whole MoonBit type CST node. It is valid only when it
occupies a complete type node, such as an annotation, a type argument, an option
type, a tuple member, or a function type component:

```yaml
patterns:
  - shape: |
      let value : $(T:type) = input
  - shape: |
      let values : Array[$T] = input
```

The captured value is the whole `Type` CST node. Repeating the same `type` name
requires the captured type nodes to be structurally equal, ignoring source
locations. `type` does not capture type-name identity positions such as method
type qualifiers or constructor extra-info; use `id` for those names.

Use `$(name:pat)` for a whole pattern CST capture. It is valid only as a simple
pattern variable position:

```yaml
patterns:
  - shape: match input { $(item:pat) => item }
```

### Built-In Wildcards

The exact spelling `$_` is an ignore placeholder when it appears in a
binding-capable position:

```yaml
patterns:
  - shape: foo($_)
```

Outside the terminal continuation form below, an ignore placeholder matches
anything at exactly one position. It does not bind a value, and repeated ignore
placeholders are independent:

```yaml
patterns:
  - shape: pair($_, $_)
```

The example above can match `pair(left, right)`.

When an expression sequence consists exactly of a continuation owner followed
by terminal `$_`, the placeholder matches the complete remaining suffix: zero,
one, or more expressions. The continuation owners are ordinary `let`,
`let mut`, local function definitions, `letrec`, `guard`, and `defer`. The
placeholder remains non-binding, so neither `$_` nor `_` is added to the
bindings. This rule also applies inside a nested block. It does not apply to a
non-terminal `$_`, an owner with any other sibling pattern, or `proof_let`.
Those uses still match exactly one expression.

Only exact `$_` has this built-in behavior. Names such as `__`, `___`, and
`__x` are literal by default. Inline syntax such as `$__` or `$(__x:exp)` marks
them as metavars.

### `exp`

An `exp` metavar captures the parsed expression at its position. Repeating the
same `exp` name requires later captures to have equal parsed expression
structure, ignoring source locations.

Example:

```yaml
patterns:
  - shape: $(expr:exp) == $(expr:exp)
```

This can match examples such as:

```moonbit
x == x
record.field == record.field
make(value) == make(value)
```

It does not match:

```moonbit
x == y
make(value) == make(other)
```

`exp` is not the right choice when the same source-level name appears in
different syntactic roles, such as once as a binder and later as an identifier
expression. Use `id` for that.

Repeated `exp` equality is currently guaranteed because captured values are
compared as untyped CST nodes by node kind and child values, ignoring source
locations. It is not limited to a fixed list of expression shapes. Semantic
equivalents with different CST structures do not match. A placeholder can
absorb the structural difference.

### `id`

An `id` metavar captures a normalized source-level name. Repeating the same
`id` name requires every occurrence to normalize to the same string.

This is useful when a rule compares a binder with later uses:

```yaml
patterns:
  - shape: |
      for $(counter:id) = $(start:exp); $(counter:id) < $(limit:exp); $(counter:id) = $(counter:id) + 1 {
        $(body:exp)
      }
```

This can match:

```moonbit
for i = 0; i < n; i = i + 1 {
  println(i)
}
```

It does not match when the repeated source-level names differ:

```moonbit
for i = 0; j < n; i = i + 1 {
  println(i)
}
```

Normalization currently succeeds for simple and qualified variable names,
binders, bare identifier expressions, constructor identities, simple variable
patterns, and labels. Qualified function names normalize as `@pkg.name`.
Qualified constructor identities include their extra info, such as `@pkg.Ctor`,
`Type::Ctor`, `@pkg.Type::Ctor`, or `@pkg.Type::@other.Ctor`.

### `const`

A `const` metavar captures a parsed MoonBit constant. In expression position,
it matches `Expr::Constant`; in pattern position, it matches `Pattern::Constant`.
It compares the parser CST constant kind and preserved source spelling; it does
not type-check or normalize equivalent values. For example, `1000` and `1_000`
do not necessarily compare as the same constant.

Example:

```yaml
patterns:
  - shape: $(value:const) + $(value:const)
```

This can match:

```moonbit
1 + 1
"same" + "same"
```

It does not match:

```moonbit
1 + 2
x + x
```

Pattern constants are also supported:

```yaml
patterns:
  - shape: match input { $(lit:const) => lit }
```

The inner body references the outer constant capture with the plain payload
name, `lit`.

### `arg`

An `arg` metavar captures a complete call argument node. It lets a rule accept
any argument spelling in one slot and compare the entire slot on repeated
occurrences.

Example:

```yaml
patterns:
  - shape: sink($(arg:arg))
```

This can match all of these one-argument calls:

```moonbit
sink(value)
sink(label=value)
sink(label~)
sink(label?=value)
sink(label?)
```

Repeating the same `arg` name requires the full argument nodes to be
structurally equal, ignoring source locations. Argument kind, label, and value
must all match. The pattern `sink($(arg:arg), $(arg:arg))` can match
`sink(value, value)` and `sink(label=value, label=value)`. It does not match
`sink(value, other)` or `sink(label=value, other=value)`.

`arg` is explicit-only. Bare `$arg` in `sink($arg)` follows normal bare
metavar inference. An explicit declaration of the same name elsewhere
determines its kind. With no such declaration, it is an `exp` capture.
`$(arg:arg)` must occupy the whole argument slot; `sink(label=$(arg:arg))`,
`sink($(arg:arg) + 1)`, and a root shape `$(arg:arg)` are invalid.

### `type`

A `type` metavar captures a whole MoonBit `Type` CST node. It can match simple
type names and type variables such as `Int` or `T`, and composite types such as
`Array[Int]`, `T?`, tuples, and function types.

Example:

```yaml
patterns:
  - shape: |
      let left : $(T:type) = input; let right : $(T:type) = input
```

This can match:

```moonbit
let left : Int = input; let right : Int = input
let left : Array[String] = input; let right : Array[String] = input
```

It does not match:

```moonbit
let left : Int = input; let right : String = input
```

`type` captures must occupy a whole type node. These are invalid:

```yaml
patterns:
  - shape: sink($(T:type))
  - shape: $(T:type)(value)
```

### `pat`

A `pat` metavar captures the whole candidate `Pattern` CST. It is valid only in
a simple pattern variable position.

Example:

```yaml
patterns:
  - shape: match input { $(item:pat) => body }
```

Repeating the same `pat` name requires the captured patterns to be structurally
equal.

## Guards

Structural pattern objects may include an optional `guard` map. A guard key is a
`$`-prefixed capture name, and the value is a regex string:

```yaml
patterns:
  - shape: $(callee:id)($(value:const))
    guard:
      $callee: "^@html\\.render$"
      $value: "danger|raw"
```

Only `id` and `const` captures can be guarded. A guard key that refers to an
`exp` capture, an `arg` capture, a `pat` capture, a `type` capture, or an unknown name is
rejected during rule compilation. Inner `patterns` may guard `id` and `const`
captures established by `inside-expr` or `inside-toplevel`.

Guards are checked after the structural CST match succeeds. All guards in a
single pattern object must match; this is AND semantics. Regex matching uses
contains semantics. Use anchors such as `^...$` when the whole capture value
must match.

For `id` captures, the regex sees the normalized identifier string, such as
`name` or `@pkg.name`. For `const` captures, the regex sees the parser constant
value: string constants without quotes, numeric constants as their source text,
and booleans as `true` or `false`.

## Structural Rules

A structural rule has a non-empty `patterns` array, or has `inside-expr` or
`inside-toplevel` with non-empty `patterns`, non-empty `patterns-not`, or both.

```yaml
id: repeated-equality
description: |
  Repeated equality.
patterns:
  - shape: $(expr:exp) == $(expr:exp)
```

Structural rules are applied to expression subtrees collected from source
files. Currently, structural matching searches expression bodies from top-level
expressions, functions, methods, top-level `let` definitions, tests, and views.

Each visited expression is checked against each structural rule. For one
visited expression and one rule:

- `patterns` entries are ordered alternatives
- the first matching positive pattern emits one hit and prunes that candidate
  expression subtree for that rule
- if no positive pattern matches, `patterns-not` entries are checked against the
  candidate expression root
- if a negative pattern then matches, that candidate expression subtree is
  pruned for that rule without emitting a hit
- sibling expression subtrees and other rules continue scanning

The reported pattern index is zero-based and refers to the matching entry in
`patterns`.

All patterns in one rule share the same rule id and `description`.

### `patterns-not`

`patterns-not` is a structural negative constraint. Its entries use the same
`shape` and optional `guard` schema as `patterns`.

```yaml
id: unblocked-target
description: |
  Match target calls outside blocked wrappers.
patterns:
  - shape: target()
patterns-not:
  - shape: blocked($(value:exp))
```

For ordinary structural rules with `patterns`, every candidate expression root
tries the ordered positive patterns first. If a positive pattern matches, the
hit is reported and `patterns-not` is not checked for that candidate. Only when
all positive patterns fail are `patterns-not` entries checked. Negative matching
starts with no bindings. Metavars declared only in `patterns-not` bind
independently from metavars declared in `patterns`.

If a negative pattern matches after the positive patterns fail, that candidate
produces no hit and its descendants are not searched for that rule. If neither a
positive nor a negative pattern matches, traversal continues into the
candidate's children.

Negative patterns match only the current candidate root. In the example
above, `target()` inside `blocked(...)` is not searched because the `blocked`
root fails all positive patterns, then matches `patterns-not`, pruning that
branch. A `blocked(...)` node that also matched a positive pattern would be
reported and would not be checked against `patterns-not`; use a narrower
positive pattern when same-root shapes must be excluded.

With `inside-expr` or `inside-toplevel`, negative matching starts with the
bindings established by the outer match. If the rule also has `patterns`, each
expression in the captured `__TARGET__` subtree uses the same positive-first
ordering: positive patterns run first, and `patterns-not` is checked only when
all positive patterns fail for that expression. When an outer context,
`patterns`, and `patterns-not` are all present, positive matches cover their
whole matched subtrees, and any negative match found outside those covered
positive subtrees rejects the whole outer match. `patterns-not` is also valid
with `inside-expr` or `inside-toplevel` and no `patterns`; that form is
described below.

### `inside-expr`

`inside-expr` restricts a structural rule to matches inside a larger expression
context. It may be used with `patterns`, with `patterns-not`, or with both.

```yaml
id: wrapped-target
description: |
  Match a target call inside either supported context.
inside-expr:
  - shape: wrapper($(prefix:exp), __TARGET__)
  - shape: container($(prefix:exp), __TARGET__)
patterns:
  - shape: target.call($(prefix:exp))
```

`inside-expr` is a non-empty YAML array of pattern objects. Each `shape` is
parsed as one MoonBit expression snippet, and its optional `guard` filters `id`
and `const` captures declared by that outer shape. Entries are ordered
alternatives.

Additional rules:

- Every `inside-expr` entry must contain exactly one `__TARGET__` occurrence in
  a binding-capable position.
- `__TARGET__` must occupy a whole expression position, such as a whole call
  argument, receiver, or block expression. If it appears only as a label or
  other non-expression value, no target subtree can be searched.
- When terminal `__TARGET__` follows a continuation owner, as in
  `let ...; __TARGET__`, `let mut ...; __TARGET__`, or
  `guard ...; __TARGET__`, it selects the complete remaining candidate suffix.
  That suffix is searched as an expression sequence without synthetic block
  braces. An empty suffix is an empty sequence.
- `__TARGET__` is reserved and must not be used as an metavar name.
- Entries in `patterns` and `patterns-not` must not contain `__TARGET__` in a
  binding-capable position.
- Captures declared by the selected `inside-expr` entry remain visible when
  matching the inner pattern entries; inner shapes reference them by repeating
  the same metavar form.
- Any capture reused by an inner `patterns` or `patterns-not` entry must be
  declared by every `inside-expr` alternative with the same kind. This includes
  named ellipsis captures and their ellipsis kinds. Outer captures that are not
  referenced by an inner entry may differ between alternatives.

Runtime behavior:

- the current expression tries eligible `inside-expr` entries in YAML order
- an entry whose shape does not match, or whose guard fails, falls through to
  the next entry
- the first entry whose shape and guard both match selects the captured
  `__TARGET__` subtree and bindings
- once an entry is selected, later alternatives are not tried even if inner
  matching produces no finding
- when `patterns` is present, each expression in the captured subtree first
  tries the ordered positive patterns using the bindings established by
  the selected outer entry; a positive hit is recorded and its matched subtree
  covers any nested negative matches
- when `patterns` and `patterns-not` are both present, a candidate that fails
  all positive patterns is then checked against `patterns-not` using the
  the selected outer bindings; a negative match outside a positive-hit subtree
  rejects the whole outer match
- when `patterns` is absent, every expression in the captured subtree is
  checked against `patterns-not` using the selected outer bindings; if none of
  them match, the outer expression produces one hit
- if an inner positive or negative pattern references an inherited `id` capture
  with the same inline `$(name:id)` form, that candidate is skipped when the
  path from `__TARGET__` to the candidate crosses a lexical binder with the
  same normalized identifier name

Each successful outer expression produces at most one finding. Its `loc` is
the outer expression location. With `patterns`, the first inner positive hit in
traversal order determines `pattern_index`; later positive hits in the same
outer expression do not produce additional findings. With only `patterns-not`,
`pattern_index` is `0`.

### `inside-toplevel`

`inside-toplevel` restricts a structural rule to matches inside selected
MoonBit top-level items. It is a non-empty ordered array using the same object
schema and target-subtree semantics as `inside-expr`. Each entry's `shape` is
parsed as exactly one top-level item, not as an expression.

```yaml
id: safe-function-target
description: |
  Match calls only in selected top-level functions.
inside-toplevel:
  - shape: |
      fn $(name:id)($(param:id) : Int) -> Int { __TARGET__ }
    guard:
      $name: "^safe_"
patterns:
  - shape: call($(param:id))
```

`match-mode` is resolved independently for every ordered alternative:

| `match-mode` | Shape item | Effective matching |
| --- | --- | --- |
| omitted | function definition | `partial` |
| omitted | any other top-level item | `exact` |
| `exact` | any top-level item | `exact` |
| `partial` | function definition | `partial` |
| `partial` | any other top-level item | compile error |

Exact matching compares every field in the parsed top-level semantic CST:

```yaml
inside-toplevel:
  - shape: |
      fn $(name:id) { __TARGET__ }
    match-mode: exact
```

Docstrings are comments and never constrain a match. Adding, removing, or
changing a docstring has no effect in default, `exact`, or `partial` mode.

Partial matching is limited to function definitions. It always matches the
function name, body, and `__TARGET__` exactly. The following function-header
fields are ignored only when the shape leaves them in their default form:

- type qualifier, `async`, parameter list, type parameters, return type, error
  type, visibility, and attributes
- the top-level `where` clause

Writing any such field keeps it exact. For example, `fn f()` requires an
explicit empty parameter list, `pub fn` requires public visibility, and
`async fn`, a return type, `noraise`, type parameters, attributes, or a `where`
clause constrain the candidate exactly.

Migration note: an older rule that depended on an omitted function-header
field being absent must add `match-mode: exact`. Broad function-context rules
can remain unmarked and use the new partial default.

Additional rules:

- `inside-toplevel` and `inside-expr` are mutually exclusive.
- Every `inside-toplevel` entry must contain exactly one `__TARGET__`
  occurrence in a binding-capable expression position within the top-level
  item.
- The top-level item itself may declare `id` and `const` captures, and its
  optional `guard` may filter those captures.
- Captures declared by the selected `inside-toplevel` entry remain visible to
  inner `patterns` and `patterns-not`, using the same all-alternatives
  declaration and kind-consistency rules as `inside-expr`.
- `inside-toplevel` is not supported on taint rules.

The candidate top-level item tries eligible `inside-toplevel` entries in YAML
order. The first entry whose shape and guard both match selects the target and
bindings; later alternatives are not tried after selection. The expression
subtree captured by `__TARGET__` is searched with the same inherited-binding
and negative-coverage behavior as `inside-expr`.
Reporting differs: with `patterns`, every inner positive hit produces a
finding whose `loc` is the inner match location. With only `patterns-not`, one
finding is produced at the matched top-level item location.

## Taint Rules

A taint rule has a top-level `taint` mapping.

Only these keys are accepted inside `taint`:

- `sources` (required): non-empty array
- `sinks` (required): non-empty array
- `sanitizers` (optional): array, defaults to empty

Unknown keys inside `taint` are rejected.

Each array entry is a pattern object with `shape`; `guard` is rejected in taint
clauses.

Example:

```yaml
id: raw-html
description: |
  Raw user input reaches an HTML sink.
taint:
  sources:
    - shape: get_user_input()
  sinks:
    - shape: render_html(__SOURCE__)
  sanitizers:
    - shape: sanitize_html(__SOURCE__)
```

### Taint Shape Restrictions

Every taint `shape` must be a direct call or method call.

Valid forms include:

```moonbit
source()
receiver.method(arg)
sink(label=arg)
```

Pipe and reverse-pipe syntax are not valid taint rule shapes today. Source
programs may contain those calls after parsing.

`__SOURCE__` is reserved in taint clauses:

- source shapes must not contain `__SOURCE__`
- sink shapes must contain exactly one `__SOURCE__`
- sanitizer shapes must contain exactly one `__SOURCE__`
- in sinks and sanitizers, `__SOURCE__` must be the whole receiver or the whole
  argument value

Valid sink and sanitizer targets:

```yaml
taint:
  sources:
    - shape: source()
  sinks:
    - shape: sink(__SOURCE__)
    - shape: sink(label=__SOURCE__)
    - shape: __SOURCE__.dangerous()
```

Invalid target placement:

```yaml
taint:
  sources:
    - shape: source()
  sinks:
    - shape: sink(wrap(__SOURCE__))
```

The invalid example nests `__SOURCE__` inside another expression. A valid shape
uses it as the whole argument value.

### Taint Semantics

Taint analysis is intraprocedural. It currently analyzes function bodies and
method bodies. Top-level lets, tests, views, top-level expressions, and
declarations without bodies are not taint-analyzed.

For one taint rule:

- a matching source call marks the call result as tainted
- a matching sink call reports when the selected `__SOURCE__` receiver or
  argument is tainted
- a matching sanitizer call does not produce tainted return data
- a matching sanitizer clears stored taint for the selected `__SOURCE__` value
  only when that value is a storage path, such as a variable, field access,
  tuple field access, or array access
- unmatched calls have no effect on taint

There is no interprocedural propagation for YAML taint rules today. If tainted
data is passed through a helper call that does not match a source, sink, or
sanitizer clause in the same rule, that helper call does not propagate taint to
its return value.

When one call matches more than one taint clause type, effects are ordered as
follows:

- if a call matches both a source and a sanitizer, source return taint is
  produced
- if a call matches both a sink and a sanitizer, the sink is reported using the
  taint state before sanitizer effects affect later reads

The reported pattern index for taint hits is the zero-based index of the
matching sink entry.

## Error Conditions

A rule set or rule file is rejected when any of these conditions occurs:

- the rules root contains no `.yaml` or `.yml` files
- a rule file contains zero YAML documents or more than one YAML document
- the top-level YAML document is not a mapping
- an unsupported key appears at the top level, inside `taint`, or inside a
  pattern object
- a required key is missing
- `id`, `description`, or `shape` is not a YAML string
- `id` is empty or contains `/`
- the rule does not choose structural or taint mode
- `inside-expr` appears on a taint rule
- `inside-toplevel` appears on a taint rule
- both `inside-expr` and `inside-toplevel` appear
- `inside-expr` or `inside-toplevel` is not an array or is empty
- an `inside-expr` or `inside-toplevel` entry is not a mapping
- `match-mode` appears outside an `inside-toplevel` entry
- `match-mode` is not `exact` or `partial`
- `match-mode: partial` is used with a non-function top-level shape
- `inside-expr` is present without `patterns` or `patterns-not`
- `inside-toplevel` is present without `patterns` or `patterns-not`
- `patterns` is not an array or is empty
- a `patterns` entry is not a mapping
- `patterns-not` is not an array or is empty
- `patterns-not` appears without `patterns`, `inside-expr`, or
  `inside-toplevel`
- `patterns-not` appears on a taint rule
- an unsupported top-level key appears
- a `patterns-not` entry is not a mapping
- `taint` is not a mapping
- `taint.sources` or `taint.sinks` is missing, not an array, or empty
- `taint.sanitizers` has a non-array value
- a taint clause entry is not a mapping
- a structural `guard` has a non-mapping value, or a guard value is not a string
- `guard` appears in any taint clause
- `metavars` appears in any pattern object
- `shape` is not valid as one MoonBit expression
- an `inside-toplevel` entry's `shape` is not exactly one valid MoonBit
  top-level item
- a shape uses an unsupported metavar kind
- a shape uses the same metavar name across multiple metavar kinds
- a bare `$name` cannot be inferred to one compatible kind
- a bare `$name` appears only as an ambiguous simple pattern variable
- an metavar uses a reserved name
- `$(name:exp)` appears outside a bare expression position
- `$(name:const)` appears outside a constant expression or constant pattern position
- `$(name:arg)` appears outside a bare argument position
- `$(name:pat)` appears outside a bare pattern position
- `$(name:type)` appears outside a whole type position
- a guard key is not `$`-prefixed, or references an unknown, `exp`, `arg`,
  `pat`, `type`, or ellipsis capture
- an ellipsis does not occupy a complete unnamed ordered-list item
- an ellipsis kind is incompatible with its list position, conflicts with
  another typed occurrence, or shares a name with a normal metavar
- a guard regex is invalid
- an `inside-expr` entry does not contain exactly one binding-capable
  `__TARGET__`
- an `inside-toplevel` entry does not contain exactly one binding-capable
  `__TARGET__`
- a structural `patterns` or `patterns-not` entry contains binding-capable
  `__TARGET__`
- a structural `patterns` or `patterns-not` entry uses an inherited
  `inside-expr` or `inside-toplevel` metavar name with a different kind
- a capture reused by `patterns` or `patterns-not` is missing from any outer
  alternative, or a named ellipsis is declared with a different ellipsis kind
- a taint source contains binding-capable `__SOURCE__`
- a taint sink or sanitizer does not contain exactly one binding-capable
  `__SOURCE__`
- a taint sink or sanitizer does not place `__SOURCE__` as the whole receiver
  or whole argument value
- a taint source, sink, or sanitizer shape is not a direct call or method call

## Examples

### Ordered Structural Alternatives

```yaml
id: collect-output
description: |
  These helpers collect full child-process output before returning.
patterns:
  - shape: $(command:exp).output_collect($(args:exp))
  - shape: $(command:exp).stderr_collect($(args:exp))
```

Both alternatives emit the same rule id and description. The reported pattern
index distinguishes which shape matched.

### Binder and Use Name Comparison

```yaml
id: counter-loop
description: |
  C-style `for` loop.
patterns:
  - shape: |
      for $(counter:id) = $(start:exp); $(counter:id) < $(limit:exp); $(counter:id) = $(counter:id) + 1 {
        $(body:exp)
      }
```

`counter` is compared by source-level name across binder, condition, and update
positions. `start`, `limit`, and `body` are expression captures.

### Context-Restricted Structural Match

```yaml
id: unsafe-wrapper
description: |
  Match a sink only under an unsafe wrapper.
inside-expr:
  - shape: unsafe(__TARGET__)
patterns:
  - shape: sink($_)
```

The rule first finds `unsafe(...)`, then searches only the expression captured
by `__TARGET__` for `sink(...)`.

### Negative Structural Constraint

```yaml
id: unblocked-target
description: |
  Match target calls outside blocked wrappers.
patterns:
  - shape: target()
patterns-not:
  - shape: blocked($(value:exp))
```

The rule tries `patterns` before `patterns-not` at each candidate root, so
`patterns-not` is useful for pruning branches whose root does not itself match
the positive patterns. In this example, `blocked(target())` does not report the
nested `target()` because the `blocked(...)` root fails the positive pattern,
matches `patterns-not`, and prunes its children. The negative pattern binds its
own `value`; it does not reuse any positive pattern capture.

### Context Without a Positive Inner Pattern

```yaml
id: wrapper-without-danger
description: |
  Match wrappers whose payload contains no danger call.
inside-expr:
  - shape: wrapper(__TARGET__)
patterns-not:
  - shape: danger()
```

The rule first finds `wrapper(...)`, then scans the `__TARGET__` subtree for
`danger()`. If no negative pattern matches inside that subtree, the wrapper
itself is reported.

### Guarded Structural Match

```yaml
id: guarded-render
description: |
  Raw-looking constants rendered through html.
patterns:
  - shape: $(callee:id)($(value:const))
    guard:
      $callee: "^@html\\.render$"
      $value: "danger|raw"
```

The shape captures any one-argument call with a constant argument. The guards
then keep only calls whose normalized callee is `@html.render` and whose
constant value contains `danger` or `raw`.

### Taint Source, Sink, and Sanitizer

```yaml
id: raw-html
description: |
  Raw user input reaches an HTML sink.
taint:
  sources:
    - shape: get_user_input()
  sinks:
    - shape: render_html(__SOURCE__)
  sanitizers:
    - shape: sanitize_html(__SOURCE__)
```

`get_user_input()` taints its result. `render_html(__SOURCE__)` reports when
its argument is tainted. `sanitize_html(__SOURCE__)` prevents that selected
value from contributing taint to later reads when the selected value can be
tracked as storage.
