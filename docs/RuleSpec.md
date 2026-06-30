# Rule Specification

This document is the authoritative specification for YAML rules accepted by
the moongrep.

If you are writing your first rule, start with [WritingRules.md](WritingRules.md).

## Scope and Status

This document specifies the current YAML rule file format, validation rules,
and matching semantics.

The keywords "must", "must not", "may", and "currently" describe the behavior
rule authors can rely on today.

Rules are written as YAML, but every `shape` value is MoonBit surface syntax.
The scanner matches parsed MoonBit expression structure, not raw text. As a
result, formatting and comments are not significant, while expression form,
operators, literal values, labels, callee names, and argument structure are
significant unless a wildcard or declared metavariable says otherwise.

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
- `patterns` (required for ordinary structural rules): non-empty YAML array
- `patterns-not` (optional for structural rules): non-empty YAML array using
  the same object schema as `patterns`
- `inside-expr` (optional for structural rules): YAML string containing one
  MoonBit expression snippet used as an outer context
- `taint` (required for taint rules): YAML mapping

Unknown top-level keys are rejected.

Each rule must choose exactly one rule mode:

- structural mode: `patterns`, or `inside-expr` with `patterns-not`
- taint mode: `taint`

`patterns` and `taint` are mutually exclusive. `inside-expr` and `patterns-not`
are valid only on structural rules; they are rejected on taint rules.
`patterns-not` must appear with `patterns` or `inside-expr`. An `inside-expr`
rule without `patterns` must include `patterns-not`.

`id` is the local rule name within its file directory. `description` is also
required and must be a string. Its content is preserved as supplied by YAML,
including trailing newlines produced by block scalars.

### Pattern Objects

Structural entries in `patterns` and `patterns-not` use this object schema.

Only these keys are accepted:

- `shape` (required): YAML string containing one MoonBit expression snippet
- `guard` (optional): YAML mapping from capture name to regex string

Unknown keys inside a pattern object are rejected.

For taint `sources`, `sinks`, and `sanitizers`, the same `shape` key is used but
`guard` is rejected.

## Shapes

`shape` must be a single MoonBit expression snippet.

Valid shapes include expressions such as calls, method calls, field accesses,
operators, blocks, conditionals, loops, matches, lambdas, collection literals,
record expressions, and other expression-sized MoonBit syntax. A shape is not a
whole file, top-level declaration, package fragment, or import list.

Shapes are structural:

- undeclared identifiers and labels match literally
- constants match by value
- operators match literally
- call and method-call argument kinds, labels, order, and arity must match
- type annotations and type names in matched syntax must match where present
- source locations, formatting, and comments do not participate in matching

The scanner does not type-check shapes and does not resolve names semantically.
For example, two different imported names that refer to the same definition are
still different unless their parsed source spelling matches or a metavariable
captures them.

## Metavariables

Identifiers and labels in a shape are literal by default. A name becomes a
metavariable only when it uses inline metavar syntax inside `shape`, except for
the built-in wildcard forms described below.

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

Only `exp`, `id`, `const`, and `pat` are supported. A name may be repeated
within one kind, but using the same payload across multiple kinds such as
`$(name:exp)`, `$(name:id)`, `$(name:const)`, and `$(name:pat)` in one shape is
invalid.

The old YAML `metavars` key is not supported. Pattern objects that contain it
are rejected as using an unsupported key.

### Reserved Names

These names must not be used as inline metavar names:

- any name made only of two or more underscores, such as `__`, `___`, or
  `____`
- `__TARGET__`
- `__SOURCE__`

`__TARGET__` and `__SOURCE__` keep their existing built-in meanings. `__TARGET__`
is only valid in `inside-expr`; `__SOURCE__` is only valid in taint sink and
sanitizer shapes.

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

Use `$(name:pat)` for a whole pattern AST capture. It is valid only as a simple
pattern variable position:

```yaml
patterns:
  - shape: match input { $(item:pat) => item }
```

### Built-In Wildcards

Names made only of two or more underscores are ignore placeholders when they
appear in binding-capable positions:

```yaml
patterns:
  - shape: foo(__)
```

An ignore placeholder matches anything at that one position. It does not bind a
value, and repeated ignore placeholders are independent:

```yaml
patterns:
  - shape: pair(__, __)
```

The example above can match `pair(left, right)`.

Only all-underscore names have this built-in behavior. A name such as `__x` is
literal unless it uses inline syntax such as `$(__x:exp)`.

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

Repeated `exp` equality is currently guaranteed for common expression forms,
including identifiers, holes, constants, unit, infix expressions, calls, method
calls, field access, method references, constructor expressions, grouped
expressions, blocks, array literals, tuple literals, and `for` expressions.
Some expression forms can be matched once but are not yet supported for
repeated equality. If a repeated `exp` capture uses an unsupported equality
form, that match fails rather than producing a hit.

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
It compares the parser AST constant kind and value only; it does not type-check
or normalize equivalent values.

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

### `pat`

A `pat` metavar captures the whole candidate `Pattern` AST. It is valid only in
a simple pattern variable position.

Example:

```yaml
patterns:
  - shape: match input { $(item:pat) => body }
```

Repeating the same `pat` name requires the captured patterns to be structurally
equal.

The inner body references the outer constant capture with the plain payload
name, `lit`.

## Guards

Structural pattern objects may include an optional `guard` map. A guard key is a
capture name without `$`, and the value is a regex string:

```yaml
patterns:
  - shape: $(callee:id)($(value:const))
    guard:
      callee: "^@html\\.render$"
      value: "danger|raw"
```

Only `id` and `const` captures can be guarded. A guard key that refers to an
`exp` capture, a `pat` capture, or an unknown name is rejected during rule
compilation. Inner `patterns` may guard `id` and `const` captures established by
`inside-expr`.

Guards are checked after the structural AST match succeeds. All guards in a
single pattern object must match; this is AND semantics. Regex matching uses
contains semantics. Use anchors such as `^...$` when the whole capture value
must match.

For `id` captures, the regex sees the normalized identifier string, such as
`name` or `@pkg.name`. For `const` captures, the regex sees the parser constant
value: string constants without quotes, numeric constants as their source text,
and booleans as `true` or `false`.

## Structural Rules

A structural rule has a non-empty `patterns` array, or has `inside-expr` with
non-empty `patterns-not`.

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
  Match target calls unless they are inside a blocked wrapper.
patterns:
  - shape: target()
patterns-not:
  - shape: blocked($(value:exp))
```

For ordinary structural rules with `patterns`, every candidate expression root
tries the ordered positive patterns first. If a positive pattern matches, the
hit is reported and `patterns-not` is not checked for that candidate. Only when
all positive patterns fail are `patterns-not` entries checked. Negative matching
starts with no bindings. Inline metavars declared only in `patterns-not` bind
independently from inline metavars declared in `patterns`.

If a negative pattern matches after the positive patterns fail, that candidate
produces no hit and its descendants are not searched for that rule. If neither a
positive nor a negative pattern matches, traversal continues into the
candidate's children.

Negative patterns still match only the current candidate root. In the example
above, `target()` inside `blocked(...)` is not searched because the `blocked`
root fails all positive patterns, then matches `patterns-not`, pruning that
branch. A `blocked(...)` node that also matched a positive pattern would be
reported and would not be checked against `patterns-not`; use a narrower
positive pattern when same-root shapes must be excluded.

With `inside-expr`, negative matching starts with the bindings established by
the outer match. If the rule also has `patterns`, each expression in the
captured `__TARGET__` subtree uses the same positive-first ordering: positive
patterns run first, and `patterns-not` is checked only when all positive
patterns fail for that expression. When `inside-expr`, `patterns`, and
`patterns-not` are all present, positive matches cover their whole matched
subtrees, and any negative match found outside those covered positive subtrees
rejects the whole outer `inside-expr` match. `patterns-not` is also valid with
`inside-expr` and no `patterns`; that form is described below.

### `inside-expr`

`inside-expr` restricts a structural rule to matches inside a larger expression
context. It may be used with `patterns`, with `patterns-not`, or with both.

```yaml
id: wrapped-target
description: |
  Match a target call only inside wrapper(...).
inside-expr: wrapper($(prefix:exp), __TARGET__)
patterns:
  - shape: target.call($(prefix:exp))
```

`inside-expr` is a YAML string parsed as one MoonBit expression snippet.

Additional rules:

- `inside-expr` must contain exactly one `__TARGET__` occurrence in a
  binding-capable position.
- `__TARGET__` must occupy a whole expression position, such as a whole call
  argument, receiver, or block expression. If it appears only as a label or
  other non-expression value, no target subtree can be searched.
- `__TARGET__` is reserved and must not be used as an inline metavar name.
- Entries in `patterns` and `patterns-not` must not contain `__TARGET__` in a
  binding-capable position.
- Inline metavars declared by `inside-expr` remain visible when matching the
  inner pattern entries; inner shapes reference them by repeating the same
  inline metavar form.
- Inner `patterns` and `patterns-not` must not use a visible `inside-expr`
  metavar name with a different kind.

Runtime behavior:

- the current expression is first matched against `inside-expr`
- if it matches, the subtree captured by `__TARGET__` is searched
- when `patterns` is present, each expression in the captured subtree first
  tries the ordered positive patterns using the bindings established by
  `inside-expr`; a positive hit is reported and its matched subtree covers any
  nested negative matches
- when `patterns` and `patterns-not` are both present, a candidate that fails
  all positive patterns is then checked against `patterns-not` using the
  `inside-expr` bindings; a negative match outside a positive-hit subtree
  rejects the whole outer match
- when `patterns` is absent, every expression in the captured subtree is
  checked against `patterns-not` using the `inside-expr` bindings; if none of
  them match, the outer expression produces one hit
- if an inner positive or negative pattern references an inherited `id` capture
  with the same inline `$(name:id)` form, that candidate is skipped when the
  path from `__TARGET__` to the candidate crosses a lexical binder with the
  same normalized identifier name

With `patterns`, the reported location is the inner positive match location.
With `inside-expr` and only `patterns-not`, the reported location is the outer
expression location. Consumers that expose context locations may also expose
the outer expression location through `outer_loc`.

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

Pipe and reverse-pipe syntax are not valid taint rule shapes today, even though
source programs may contain those calls after parsing.

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

The invalid example nests `__SOURCE__` inside another expression instead of
using it as the whole argument value.

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

- if a call matches both a source and a sanitizer, source return taint is still
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
- `id`, `description`, `inside-expr`, or `shape` is not a YAML string
- `id` is empty or contains `/`
- the rule does not choose structural or taint mode
- `inside-expr` appears on a taint rule
- `inside-expr` is present but is not a string
- `inside-expr` is present without `patterns` or `patterns-not`
- `patterns` is not an array or is empty
- a `patterns` entry is not a mapping
- `patterns-not` is not an array or is empty
- `patterns-not` appears without `patterns` or `inside-expr`
- `patterns-not` appears on a taint rule
- an unsupported top-level key appears
- a `patterns-not` entry is not a mapping
- `taint` is not a mapping
- `taint.sources` or `taint.sinks` is missing, not an array, or empty
- `taint.sanitizers` is present but is not an array
- a taint clause entry is not a mapping
- structural `guard` is present but is not a mapping, or a guard value is not a
  string
- `guard` appears in any taint clause
- `metavars` appears in any pattern object
- `shape` is not valid as one MoonBit expression
- a shape uses an unsupported inline metavar kind
- a shape uses the same inline metavar name across multiple metavar kinds
- an inline metavar uses a reserved name
- `$(name:exp)` appears outside a bare expression position
- `$(name:const)` appears outside a constant expression or constant pattern position
- `$(name:pat)` appears outside a bare pattern position
- a guard key references an unknown, `exp`, or `pat` capture
- a guard regex is invalid
- `inside-expr` does not contain exactly one binding-capable `__TARGET__`
- a structural `patterns` or `patterns-not` entry contains binding-capable
  `__TARGET__`
- a structural `patterns` or `patterns-not` entry uses an inherited
  `inside-expr` metavar name with a different kind
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
inside-expr: unsafe(__TARGET__)
patterns:
  - shape: sink(__)
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
inside-expr: wrapper(__TARGET__)
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
      callee: "^@html\\.render$"
      value: "danger|raw"
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
