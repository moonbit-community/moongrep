# Writing Rules

The `rule/*` packages define the YAML rule format and the runtime loader,
validator, compiler, and applicator used by `moongrep`.

Start here if you want to add or refine a rule.

See also:

- [RuleSpec.md](RuleSpec.md): authoritative YAML rule spec with accepted keys,
  matcher semantics, and failure cases

## Introduction

YAML rule files are scanner input. A rules root can be any directory supplied to
the `moongrep scan` CLI with `--rules` or `-r`. Files ending in `.yaml` or
`.yml` are discovered recursively below that root; other files are ignored. The
discovered files are loaded in sorted order for deterministic output. An empty
rules root is an error.

Rule ids come from the rule file directory plus the YAML `id`. For example,
`rules/security/raw.yaml` with `id: raw-html` becomes `security/raw-html` when
`rules` is the rules root. A file directly under the rules root uses just its
`id`. Filenames do not contribute to rule ids. The YAML `id` must be non-empty
and must not contain `/`; directory ownership is encoded by file location.

Each YAML file must contain exactly one document, and that document must be a
mapping. A complete rule file requires string `id` and `description` fields,
rejects unknown top-level keys, and uses exactly one of these top-level modes:

- `patterns`: structural expression matching
- `taint`: intraprocedural taint modeling compiled to the `taint` package

`patterns` must be a non-empty array.
Unknown keys are rejected at every schema level: top-level rule keys, `taint`
keys, and rule clause keys.

Structural rules may also add an optional top-level `inside-expr` that filters
an outer expression, binds outer inline captures, and then searches the captured
`__TARGET__` expression subtree with the inner `patterns`.

## Mental Model

Write rules against the shape of a single MoonBit expression subtree, not
against a whole file.

`moongrep` parses source files with `moonbitlang/parser`, collects expression
subtrees from top-level function, method, let, test, view, and expression
bodies, and applies structural rules to those expression subtrees.

- `shape` should be the smallest expression snippet that captures the thing you
  want to flag.
- Multiple entries under `patterns` are ordered alternatives. For one
  expression and one rule, the first matching pattern wins and determines
  `pattern_index`.
- All patterns in one rule share the same rule id and `description`.
- Structural pattern objects may use `guard` to regex-filter `id` and `const`
  captures after shape matching.
- If `inside-expr` is present, it runs first on the current expression. If it
  captures `__TARGET__` as an expression, `patterns` are applied to every
  expression inside that target subtree.
- Inline captures declared by `inside-expr` stay visible to inner `patterns`;
  `__TARGET__` only
  selects the expression subtree to traverse and must not be used by inner
  `patterns`.
- Inner patterns must not redeclare names from `inside-expr`.
- Hits from `inside-expr` rules record `outer_loc` for the context expression
  in addition to `loc` for the inner match.

For taint rules:

- `taint` must be a mapping with non-empty `sources` and `sinks` arrays.
  `sanitizers` is optional and defaults to empty; when present it must be an
  array.
- `taint.sources` marks matching call results as tainted values.
- `taint.sinks` reports a hit when the receiver or argument marked by
  `__SOURCE__` is tainted.
- `taint.sanitizers` contributes no return taint and clears stored taint only
  when `__SOURCE__` resolves to a storage path such as an identifier, field, or
  array access. If the same call also matches a source clause, source return
  taint is still produced.
- taint clause shapes use the same inline `$(name:kind)` syntax as
  structural patterns.
- taint clauses do not support `guard`.
- `__SOURCE__` is reserved inside taint rules and must not be used as an inline
  metavar name. It is only valid in sink and sanitizer shapes; source shapes
  must not contain it.
- source, sink, and sanitizer shapes must be call expressions. Sink and
  sanitizer shapes must place `__SOURCE__` as the whole receiver or whole
  argument value.
- YAML taint shapes use direct call or method-call syntax only. Pipe and
  reverse-pipe calls are not expressible by YAML taint rules today.
- Unmatched calls have no effect, so taint is not propagated through arbitrary
  wrapper or helper calls unless those calls match a source, sink, or sanitizer
  clause.
- If one call matches both a sink and a sanitizer, the sink is reported from
  pre-call taint; sanitizer effects only affect later storage reads.
- Taint analysis runs only on function definitions and impl methods with
  bodies.

If you need the exact matcher semantics, read [RuleSpec.md](RuleSpec.md).

## Workflow

### 1. Pick the smallest valid `shape`

Start from a concrete source snippet that already looks like the code you want
to flag, then shrink it until only the essential structure remains.

Good starting shapes:

```yaml
patterns:
  - shape: $(conn:exp).read_request()
```

```yaml
patterns:
  - shape: |
      for $(counter:id) = $(start:exp); $(counter:id) < $(limit:exp); $(counter:id) = $(counter:id) + 1 {
        $(body:exp)
      }
```

`shape` is parsed as a single MoonBit expression snippet. If you paste a whole
file or a fragment that only makes sense at module scope, rule compilation will
fail.

### 2. Mark metavars inline in `shape`

Names in `shape` are literal by default, even if they look like placeholders.

This:

```yaml
patterns:
  - shape: _expr == _expr
```

does **not** create a metavariable. It matches the literal identifier name
`_expr` on both sides.

To capture an expression, write `$(name:exp)` directly in the shape:

```yaml
patterns:
  - shape: $(expr:exp) == $(expr:exp)
```

Use `$(name:id)` when the same source-level name must be consistent across
binders, identifier expressions, pattern variables, labels, or simple variable
targets:

```yaml
patterns:
  - shape: |
      for $(counter:id) = $(start:exp); $(counter:id) < $(limit:exp); $(counter:id) = $(counter:id) + 1 {
        $(body:exp)
      }
```

Use `$(name:const)` when the same literal constant must be consistent and
variables should not match:

```yaml
patterns:
  - shape: $(value:const) + $(value:const)
```

The `exp` kind is expression-only. The `const` kind is valid only in constant
expression or constant pattern positions. The `pat` kind is valid only in a
simple pattern variable position. If you need a non-expression source name, use
`id` or leave the name literal. Any other kind is a compile error.

The old YAML `metavars` key is invalid.

The built-in exceptions are names made only of two or more underscores, such as
`__`, `___`, and `____`. They are special ignore placeholders inside `shape`.

```yaml
patterns:
  - shape: foo(__)
```

When one of these names appears in a supported metavar position, it matches
anything there without binding a value or participating in repeated-name
equality. Repeated ignore placeholders are independent wildcards.

### 3. Choose `exp`, `id`, `const`, or `pat`

Use `exp` when you want to match and compare a whole expression. Repeating an
`exp` metavar means the repeated captures must be structurally equal according
to the runtime matcher, ignoring source locations.

```yaml
patterns:
  - shape: $(expr:exp) == $(expr:exp)
```

This is a good fit for supported repeated expression shapes such as:

- `x == x`
- `user.profile.name == user.profile.name`
- `make(value) == make(value)`

Use `id` when you want to compare source-level names across positions that are
not the same raw AST node kind, especially binder positions versus identifier
uses.

```yaml
patterns:
  - shape: |
      for $(counter:id) = $(start:exp); $(counter:id) < $(limit:exp); $(counter:id) = $(counter:id) + 1 {
        $(body:exp)
      }
```

Here `counter` appears as both a binder and later identifier expressions. The
same spelling should match, but the raw AST nodes are different, so
`id` is the right tool.

`id` also works for simple assignment targets represented in the parser
AST as `Var`, so rules like `x = x + 1` can bind the left-hand target by
normalized name instead of treating it as a literal string.

`id` can also compare qualified function names and constructor identities. A
qualified function such as `@int.abs` normalizes to `@int.abs`; a qualified
constructor includes its extra info, such as `@pkg.Ctor` or
`@pkg.Type::Ctor`.

Use `const` when the candidate must be a parsed MoonBit constant. Repeated
`const` captures compare constant kind and value, so `1 + 1` can match while
`1 + 2` and `x + x` do not.

Use `pat` when the candidate must be a whole pattern AST:

```yaml
patterns:
  - shape: match input { $(item:pat) => body }
```

### 3.5 Use `inside-expr` when the interesting node must appear inside a larger context

Reach for `inside-expr` when the thing you want to flag is only meaningful
inside a specific outer expression and you want the inner match to inherit outer
captures.

```yaml
id: wrapped-target
description: |
  Match a call only when it appears inside a specific wrapper.
inside-expr:
  shape: |
    wrapper($(prefix:exp), __TARGET__)
patterns:
  - shape: |
      target.call(prefix)
```

Rules for `inside-expr`:

- it uses the same inline metavar syntax as one structural pattern
- it must place exactly one supported `__TARGET__`; place it where a whole
  expression is expected so runtime traversal can search that subtree
- `__TARGET__` is reserved and must not be used as an inline metavar name
- inner `patterns` must not contain `__TARGET__`; the target placeholder
  selects the subtree to search, but it is not a binding available to inner
  shapes
- inner `patterns` must not redeclare names already declared by `inside-expr`;
  reference outer captures with their plain payload name, such as `prefix`

### 4. Use `guard` for id and const filters

Use `guard` when the shape is right but an `id` or `const` capture needs a
regex filter:

```yaml
patterns:
  - shape: $(callee:id)($(value:const))
    guard:
      callee: "^@html\\.render$"
      value: "danger|raw"
```

Guard keys are capture names without `$`. Values are regex strings with
contains semantics; use `^...$` for whole-value matching. `id` guards see
normalized names such as `name` or `@pkg.name`. `const` guards see parser
constant values, such as `raw` for `"raw"`, `42` for `42`, and `true` for
`true`.

Guards cannot filter `exp` or `pat` captures, and taint clauses do not support
`guard`.

### 5. Add more `patterns` when the message is shared

If several surface forms deserve the same rule id and description, put them in
one rule file.

```yaml
id: request-lifecycle
description: |
  These HTTP parser entrypoints accept messages where `Content-Length` and
  `Transfer-Encoding` may coexist.
patterns:
  - shape: |
      $(conn:exp).read_request()
  - shape: |
      $(client:exp).end_request()
```

Use separate rule files only when the rule id, message, or ownership should be
different.

### 6. Run the scanner

Run `moongrep` from the module root with a rules directory:

```bash
moon run . -- scan [--verbose] --rules <rules-root> [scan-root]
```

`--rules=<rules-root>` and `-r <rules-root>` are accepted as equivalent forms.
If `scan-root` is omitted, the scanner uses `.`. `--verbose` prints directory
traversal progress before warnings and match results.

## Worked Examples

### Repeated expression equality

```yaml
id: repeated-equality
description: |
  Repeated expression equality.
patterns:
  - shape: $(expr:exp) == $(expr:exp)
```

Why it works:

- `expr` is declared inline as an `exp` metavar
- both occurrences must bind to equal parser AST nodes for a repeated expression
  form supported by the current equality helper
- the rule can match more than simple names

### Binder and use must share one source-level name

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

Why it works:

- `counter` is compared by normalized identifier name, not by raw AST equality
- `start`, `limit`, and `body` are matched as parser AST nodes

### Same rule, multiple shapes

```yaml
id: collect-output
description: |
  These helpers collect full child-process output into memory before returning.
patterns:
  - shape: $(command:exp).output_collect($(args:exp))
  - shape: $(command:exp).stderr_collect($(args:exp))
```

Why it works:

- each pattern is an ordered alternative
- either form emits the same rule metadata
- the hit records which alternative matched through `pattern_index`

## Debugging Checklist

### Rule compilation says `shape` is invalid

Your snippet is not accepted by the MoonBit expression parser. Reduce it to one
valid expression-sized shape, then build back up carefully.

### Rule compilation rejects an inline metavar

Check, in order:

- the kind annotation is exactly `exp`, `id`, `const`, or `pat`
- `$(name:exp)` appears as a whole bare expression placeholder
- `$(name:const)` appears only where a constant expression or constant pattern can match
- `$(name:pat)` appears only as a whole bare pattern placeholder
- the same payload name is not used across multiple metavar kinds
- the payload is not a reserved name such as `__`, `__TARGET__`, or `__SOURCE__`

### An `id` rule looks right but never hits

The repeated captures may normalize to different source-level names. For
example, `abs` and `@int.abs` are different normalized identifiers. Review the
exact supported normalization cases in [RuleSpec.md](RuleSpec.md).

### A rule with `guard` fails to load

Check that `guard` is under a structural `patterns` or `inside-expr` object,
that it is a mapping, and that every key names an `id` or `const` capture
visible to that pattern. `guard` is still rejected in taint clauses.

## Testing Workflow

After changing a rule or rule behavior:

1. run the scanner on a focused fixture with
   `moon run . -- scan --rules <rules-root> <fixture-root>`
2. add or update focused tests under `rule/`
3. cover both a positive case and at least one nearby negative case

Keep tests narrow. A good rule test proves the intended match and at least one
non-match that would be easy to regress.
