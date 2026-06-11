# Rule Specification

This document is the authoritative specification for YAML rules in the
`rules` package.

If you are writing your first rule, start with [README.md](README.md).

## Scope and Status

This document specifies the current rule file format, loader/compiler
validation, and runtime matcher semantics implemented by the `rules` package.

Unless stated otherwise, the keywords "must", "must not", "may", and
"currently" describe the behavior of the current implementation.

The current implementation is a runtime AST matcher. It parses rule shapes into
`moonbitlang/parser/syntax` nodes and matches those nodes directly against
parsed source files. It does not generate matcher source code and does not use a
JSON AST intermediate representation.

## Rule File Model

- `load_rules(rules_root)` recursively scans the rules root for files ending in
  `.yaml` or `.yml`.
- If no YAML rule files are found, loading is rejected.
- Each rule file must contain exactly one YAML document.
- The top-level YAML document must be a mapping.
- Each rule file defines exactly one rule.

Rule ids are derived from the rule file path relative to the rules root:

- the relative path is computed against `<rules-root>/`
- the trailing `.yaml` or `.yml` suffix is removed
- the remaining relative path becomes the rule id

Example:

- `rules/security/raw-html.yaml` -> `security/raw-html`

## YAML Schema

### Top-Level Keys

Only these keys are accepted:

- `package` (required): YAML string
- `description` (required): YAML string
- `inside-expr` (optional): one structural pattern object used as an outer
  context filter for `patterns`
- exactly one of:
  `patterns` (non-empty YAML array)
  `taint` (YAML mapping)

Any other top-level key is rejected.

No semantic validation is performed on `package` or `description` beyond
requiring them to be YAML strings. `description` is stored verbatim in
`MatchHit.description`; if YAML block-scalar syntax preserves a trailing
newline, that newline is preserved in the stored value.

`inside-expr` is only supported together with `patterns`. It is rejected for
`taint` rules.

### Structural Pattern Objects

Each entry in `patterns` must be a mapping.

Only these keys are recognized:

- `shape` (required): YAML string
- `metavars` (optional): YAML mapping
- `guard`: recognized only to reject it in runtime AST mode

Any other key inside a pattern object is rejected.

`guard` is not supported by the current runtime AST matcher. If a `guard` key is
present, loading is rejected before shape compilation.

### `inside-expr`

`inside-expr` uses the same object schema as one structural pattern:

- `shape` (required): YAML string
- `metavars` (optional): YAML mapping
- `guard`: recognized only to reject it in runtime AST mode

Additional validation and runtime behavior:

- `inside-expr.shape` must contain exactly one supported `__TARGET__`
  occurrence according to the current name-position counter
- the runtime applicator only traverses the target when `__TARGET__` binds as
  an expression, so rule authors should place `__TARGET__` where a whole
  expression is expected
- `__TARGET__` must not be declared under `metavars`
- names declared in `inside-expr.metavars` remain visible to all inner
  `patterns`
- inner `patterns` must not redeclare a name already visible from
  `inside-expr`
- inner `patterns` must not contain a supported `__TARGET__` occurrence
  according to the current name-position counter. Unsupported textual
  occurrences are not target placeholders and are matched literally.

### Taint Rule Objects

`taint` must be a mapping.

Only these keys are accepted:

- `sources` (required): non-empty YAML array
- `sinks` (required): non-empty YAML array
- `sanitizers` (optional): YAML array, defaults to empty

Each taint clause object uses the same rule-clause object schema:

- `shape` (required): YAML string
- `metavars` (optional): same schema and semantics as structural rules
- `guard`: recognized only to reject it in runtime AST mode

Additional taint-specific validation:

- `__SOURCE__` is reserved in taint clauses and must not be declared under
  `metavars`
- taint `sources` must not contain a supported `__SOURCE__` occurrence
- taint `sinks` and `sanitizers` must contain exactly one supported
  `__SOURCE__` occurrence
- in sinks and sanitizers, the accepted `__SOURCE__` placeholder must be a bare
  identifier expression used as the whole receiver or the whole argument value,
  not a nested subexpression. Unsupported textual occurrences are matched
  literally and do not satisfy this requirement.
- source, sink, and sanitizer shapes must be call expressions rooted at
  `Expr::Apply` or `Expr::DotApply`
- YAML taint shapes are written as direct calls or method calls only. Pipe and
  reverse-pipe surface syntax is not expressible by YAML taint rules today.

### `metavars`

If `metavars` is present, it must be a mapping. Only these keys are accepted:

- `subtree` (optional): array of strings
- `identifier` (optional): array of strings

If either bucket is omitted, it defaults to the empty array.

Each bucket:

- must be an array if present
- may contain only strings
- must not contain duplicate names

Across buckets:

- a metavar name must not appear in both `subtree` and `identifier`

## `shape`

`shape` must be a single MoonBit expression snippet accepted by the expression
parser used by `@handrolled_parser.parse_expr(...)`.

Normatively:

- `shape` is parsed with the expression parser, not the full-file parser
- `shape` must therefore be valid as one expression-sized snippet
- `shape` is not an arbitrary module fragment or entire source file

The compiler parses `shape` into a parser `Expr`. The rule author writes
surface MoonBit syntax; the matcher operates on `moonbitlang/parser/syntax`
nodes.

## Matching Model

The runtime matcher is applied to traversed expression subtrees, not to entire
files as single units.

Current structural traversal model:

- source files are parsed into parser `Impl` nodes before entering the `rules`
  package
- `apply_structural_rules(...)` collects expressions from supported top-level
  bodies, including top expressions, function bodies, method bodies, let
  definitions, tests, and views
- each collected expression subtree is visited in source-tree order
- each visited expression is passed to every structural rule

Pattern semantics:

- without `inside-expr`, entries in `patterns` are ordered alternatives
- for one expression and one rule, the first matching pattern wins, emits one
  hit, and stops checking later patterns for that expression
- traversal still continues into other expression subtrees
- with `inside-expr`, the current expression is first matched against
  `inside-expr`; if it matches and `__TARGET__` binds as an expression, the
  matcher recursively traverses that expression and applies `patterns` to every
  expression in that nested traversal
- the hit records the zero-based `pattern_index` of the inner `patterns` entry
  that matched
- all patterns in the same rule share the same `rule_id`, `package`, and
  `description`

The location stored in `MatchHit.loc` is:

- for structural rules, the `loc` of the matched expression subtree
- for taint argument sinks, the `loc` of the tainted argument
- for taint receiver sinks, the `loc` of the sink call

For structural `inside-expr` rules, `MatchHit.outer_loc` is `Some(...)` and
points at the outer expression that matched `inside-expr`. For other hits it is
`None`.

Current taint traversal model:

- `apply_taint_rules(...)` applies taint rules to top-level function
  definitions and impl methods with bodies, one rule at a time
- unsupported top-level nodes such as top-level lets, tests, views, and
  expressions are ignored as `UnsupportedFunctionLike`
- taint analysis is intraprocedural
- YAML taint rules use `UnknownCallPolicy::NoEffect`
- YAML sources, sinks, and sanitizers are lowered to a custom call transfer
- unmatched calls do not propagate taint through arbitrary wrapper/helper calls
- sanitizers contribute no return taint and kill stored taint only when
  `__SOURCE__` resolves to a storage path such as an identifier, field, or array
  access
- if one call matches both a source and a sanitizer, source return taint is
  still produced
- if one call matches both a sink and a sanitizer, the sink is reported from
  pre-call taint; sanitizer effects only affect later storage reads

## Metavariable Recognition

Identifiers inside `shape` are not metavariables by default. A declared
metavariable must appear at least once in a position counted by
`count_supported_name_in_expr`; otherwise compilation rejects it as unused.

The validation-counted positions include:

- bare identifier expressions represented as `Expr::Ident`
- simple parser `Var` positions, including simple assignment targets and
  operator variables
- `Binder`
- simple variable patterns represented as `Pattern::Var`
- `Label`, including method names, field labels, and labelled arguments

Pattern traversal is currently limited. Pattern metavars are counted only in a
direct `Pattern::Var` and under `Alias`, `Tuple`, `Or`, and `Range`. A
`Pattern::Var`, `Label`, or `Binder` occurrence under constructor, array,
record, map, constraint, or special-constructor patterns is not valid as the
only occurrence of a declared metavar today.

Runtime pattern matching can still recurse through nested pattern forms. When a
declared name or an all-underscore ignore placeholder appears under array,
constructor, record, map, constraint, or special-constructor patterns, it
participates in matching there. Those nested pattern occurrences are not
sufficient by themselves to satisfy used-metavar validation.

Names made only of two or more underscores, such as `__`, `___`, and `____`,
are special ignore placeholders:

- they must not be declared under `metavars`
- in validation-counted positions, they match anything in that one position
- they do not bind a value for equality checks
- repeated occurrences are independent wildcards
- in non-supported positions, they are treated literally as that identifier or
  other source-level text
- this rule is separate from MoonBit's own special handling of `_`

Parser hole expressions also act as expression wildcards when a shape parses to
`Expr::Hole`.

Current non-supported examples include:

- constructor names
- arbitrary string-valued fields
- qualified names that do not normalize to a simple identifier
- any position that is not one of the supported AST node kinds above

If a name is declared under `metavars` but only appears in unsupported
positions, compilation is rejected with an unused-metavar error because no
binding is generated for that name.

Undeclared names are matched literally according to the parser AST produced from
`shape`.

## `subtree` Semantics

A `subtree` metavar binds the matched parser AST node at its syntactic position.
The internal binding is one of:

- `Expr`
- `Var`
- `Binder`
- `Pattern`
- `Label`

Consequences:

- repeating the same `subtree` metavar requires every occurrence to bind the
  same internal binding kind
- repeated `Expr` captures are compared with matcher-defined structural
  equality that ignores source locations
- repeated `Var`, `Binder`, `Pattern`, and `Label` captures use matcher-defined
  per-form equality helpers
- if equality for a repeated captured node shape is not implemented, that
  repeated match fails

Current repeated-`Expr` equality is narrower than full structural matching. It
currently covers these expression forms:

- identifiers, holes, constants, units
- infix, apply, dot-apply, field, method, constructor, group, and sequence
  expressions
- array and tuple literals
- functional `for` expressions, with repeated-equality comparison currently
  ignoring labels and `where` clauses

It does not currently cover every expression form that can be matched once.
Avoid relying on repeated `subtree` equality for expression kinds not listed
above.

Current repeated-`Pattern` equality is also narrower than one-shot pattern
matching. It covers variable, wildcard, constant, tuple, and `or` patterns.
Other pattern forms may match once but fail as repeated `subtree` captures.

Example:

```yaml
patterns:
  - shape: _expr == _expr
    metavars:
      subtree: [_expr]
```

This can match repeated supported subtrees such as `x == x`,
`record.field == record.field`, and `make(value) == make(value)`.

`subtree` is usually the wrong choice when the same source-level name appears
once as a binder and later as an identifier expression or label, because those
are different parser node kinds and therefore do not compare as equal.

## `identifier` Semantics

An `identifier` metavar binds by normalized identifier or label name rather than
by raw parser-node equality.

Current normalization succeeds only for:

- simple variable targets represented as `Var` with `LongIdent::Ident`,
  including simple assignment targets and operator variables
- `Binder`
- simple identifier expressions represented as `Expr::Ident`
- `Pattern::Var`
- `Label`

If normalization succeeds:

- the internal binding stores the normalized `String`
- repeating the same `identifier` metavar requires all normalized strings to be
  equal

If normalization fails for any occurrence:

- the pattern does not emit a hit
- no exception is raised

This is the intended tool for cases where the same logical name appears across
different AST node kinds, such as loop-variable binders and later identifier
uses, or repeated field and method labels in expressions such as
`record.field = record.field + value` and `receiver.method()`.

## Guard Status

YAML `guard` expressions are not supported by the current runtime AST matcher.

The key is recognized so the loader can emit a clear error, but any `guard` key
inside `patterns`, `inside-expr`, or taint clauses is rejected before shape
compilation. There is no current guard syntax validation, guard parameter
binding, or guard evaluation.

## Reserved Names

The following names are reserved in all rule clauses and must not be declared as
metavars:

- any name consisting only of two or more underscores
- `__TARGET__`
- `file`
- `hits`
- `loc`
- any name beginning with `__moongrep_`

In taint clauses, `__SOURCE__` is also reserved and must not be declared as a
metavar. It is the built-in placeholder for the sink or sanitizer target.

These names are reserved because matcher code uses them for built-in
placeholder semantics, binding plumbing, or internal matcher/runtime names.

## Error Conditions

Loading or compilation is rejected in the following cases:

- the rules root contains no YAML rule files
- a rule file contains zero YAML documents or more than one YAML document
- the top-level YAML document is not a mapping
- a required key is missing
- `package`, `description`, or `shape` is not a YAML string
- a rule does not contain exactly one of `patterns` or `taint`
- `inside-expr` is present on a taint rule
- `inside-expr` is present but is not a mapping
- `patterns` is not an array or is empty
- a `patterns` entry is not a mapping
- `taint` is not a mapping
- `taint.sources` or `taint.sinks` is not an array or is empty
- `taint.sanitizers` is present but is not an array
- a taint clause entry is not a mapping
- an unsupported key appears at top level, inside `taint`, inside a rule
  clause, or inside `metavars`
- `guard` is present in any rule clause
- `metavars` is present but not a mapping
- a metavar bucket is present but not an array
- a metavar bucket contains a non-string entry
- a metavar name is duplicated within one bucket
- a metavar name appears in both `subtree` and `identifier`
- a metavar uses a reserved name for that rule context
- a declared metavar is never bound in a supported position
- `shape` is not syntactically valid MoonBit expression syntax
- `inside-expr.shape` does not contain exactly one supported `__TARGET__`
  occurrence according to the current name-position counter
- an inner structural pattern contains a supported `__TARGET__` occurrence
- an inner structural pattern redeclares a name from `inside-expr`
- a taint source contains a supported `__SOURCE__` occurrence
- a taint sink or sanitizer does not contain exactly one supported `__SOURCE__`
  occurrence
- a taint sink or sanitizer places the accepted `__SOURCE__` somewhere other
  than the whole receiver or whole argument value
- a taint source, sink, or sanitizer shape is not a call expression
- two rule ids have the same normalized matcher name after replacing
  `/` and `-` with `_`

## Runtime Interface

The `rules` package exposes runtime APIs rather than a generated bundle:

```moonbit nocheck
pub fn load_rules(String) -> Array[RawRuleSpec] raise
pub fn parse_rule_source(String, String, String) -> RawRuleSpec raise
pub fn compile_rules(Array[RawRuleSpec]) -> Array[CompiledRule] raise
pub fn apply_structural_rules(String, @list.List[@syntax.Impl], Array[CompiledRule]) -> Array[MatchHit]
pub fn apply_taint_rules(String, @list.List[@syntax.Impl], Array[CompiledRule]) -> Array[MatchHit] raise
```

The CLI uses this flow:

1. `load_rules(options.rules_root)`
2. `compile_rules(raw_rules)`
3. parse each source file with `@parser.parse_string(...)`
4. apply structural rules
5. apply taint rules

Each emitted `MatchHit` contains:

- `file`
- `rule_id`
- `package_name`, copied from YAML `package`
- `description`, copied from YAML `description`
- zero-based `pattern_index`
- `loc`
- `outer_loc`

For structural rules, `pattern_index` is the zero-based index of the first
matching entry in `patterns` for that expression. For taint rules,
`pattern_index` is the zero-based sink index inside `taint.sinks`.

## Normative Examples

### Repeated subtree equality

```yaml
package: moonbitlang/core
description: |
  Repeated subtree equality.
patterns:
  - shape: _expr == _expr
    metavars:
      subtree: [_expr]
```

Semantics:

- `_expr` binds as an internal `Expr`
- both occurrences must be equal according to repeated-`Expr` equality
- `x == x` may match
- `record.field == record.field` may match
- expression kinds outside the repeated-`Expr` equality list are not guaranteed
  to match when repeated

### Binder/use-name comparison

```yaml
package: moonbitlang/core
description: |
  Counter-style `for` loop.
patterns:
  - shape: |
      for counter = _start; counter < upper_limit; counter = counter + 1 {
        body
      }
    metavars:
      subtree: [_start, upper_limit, body]
      identifier: [counter]
```

Semantics:

- `_start`, `upper_limit`, and `body` bind as parser AST nodes
- each `counter` occurrence must normalize to a simple identifier name
- all normalized `counter` strings must be equal

### Multi-pattern rule

```yaml
package: moonbitlang/async/http
description: |
  These HTTP parser entrypoints accept messages where `Content-Length` and
  `Transfer-Encoding` may coexist.
patterns:
  - shape: |
      _conn.read_request()
    metavars:
      subtree: [_conn]
  - shape: |
      _client.end_request()
    metavars:
      subtree: [_client]
```

Semantics:

- the first and second patterns are ordered alternatives
- either form may emit a hit
- both alternatives use the same `rule_id`, `package`, and `description`
- the hit distinguishes them through `pattern_index`

### Taint sink target

```yaml
package: example/html
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

Semantics:

- `get_user_input()` marks the call result as tainted
- `render_html(__SOURCE__)` reports when its first argument is tainted
- `sanitize_html(__SOURCE__)` contributes no return taint and kills stored taint
  when its first argument resolves to a storage path
- `__SOURCE__` is the whole argument value in both sink and sanitizer clauses
