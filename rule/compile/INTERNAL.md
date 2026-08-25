# rule/compile Internal Notes

This document records implementation details that are easy to miss when
changing the `rule/compile` package. It is for maintainers of the rule compiler
and its callers, not for rule authors.

## Package Role

`rule/compile` is the validation and normalization boundary between loaded YAML
rules and executable rules.

The package takes `RawRuleSpec` values from `rule/model` and produces
`CompiledRule` values through the package's only public entry point:

- `compile_rules(raw_rules)`

Compilation is deliberately narrow. This package:

- checks duplicate rule ids
- parses ordinary rule `shape` values as MoonBit expressions and each
  `inside-toplevel` entry's shape as one top-level item
- records metavars and validates their positions in the parsed CST
- rejects unsupported placeholder positions and malformed guards
- records taint sink and sanitizer target metadata
- builds the source-text prefilter for the compiled definition

It does not match source code, evaluate guards, lower taint rules, or scan
files. Those responsibilities live in `matching`, `rule/apply`,
`rule/taint_lowering`, and `rule/prefilter`.

## Main Flow

`compile_rules` first calls `ensure_unique_rule_ids`, then compiles each raw rule
with `compile_rule`.

`compile_rule` compiles the rule body before building the prefilter:

1. structural rules go through `compile_structural_rule`
2. taint rules go through `compile_taint_rule`
3. `compile_rule_prefilter(definition)` derives required source literals from
   the compiled CST

The prefilter must be built from the compiled definition, not from raw YAML,
because metavars have already been classified and can be excluded from literal
collection.

## Shape Parsing

`collect_shape_metavars` first lexes with:

```text
comment = true
enable_metavar = true
```

The lexer identifies metavariable tokens and records each occurrence's original
span and logical syntax. `parse_shape` then calls
`@untyped_cst.parse_expression(..., enable_metavar=true)` on the shape itself;
`parse_toplevel_shape` calls
`@untyped_cst.parse_structure(..., enable_metavar=true)` and requires exactly
one node returned by `@cst.toplevel_nodes`. Metavariable syntax therefore
remains visible in the CST instead of being replaced with reserved identifiers.

The outer lexer keeps each string or bytes interpolation as one aggregate
token. To record metavars inside it, the collector walks the parser CST and
sublexes each `InterpSegment_Source` with its global start position,
`is_interpolation=true`, and `enable_metavar=true`. The parser forwards the same
metavar mode while building each segment's `expr` subtree, including nested
interpolations, so validation and context discovery use the original CST
directly.

As before the CST migration, a `Type_Name` starts with an uppercase identifier
token. Explicit `type` metavars and typed type ellipsis metavars therefore need
an uppercase name. Lowercase and keyword names remain rejected by the parser.

Ordinary `patterns`, `patterns-not`, every `inside-expr` entry, and taint clause
shape are exactly one MoonBit expression. Each `inside-toplevel` shape is
exactly one top-level item. The compiler keeps the parser's `CstNode` directly;
there is no typed-syntax lowering or local tree conversion.

Lexing errors are reported before parse errors. `InvalidMetavarSyntax` gets a
special diagnostic so legacy syntax such as `$exp:value` can point to the modern
`$(value:exp)` form. Other lexing failures report lexical errors, and parse
reports become "not a valid MoonBit expression" or "not a valid MoonBit
top-level item" depending on the clause.

Recovery nodes (`Missing` and `Error`) are rejected even when the parser does
not emit a diagnostic.

## Metavar Context

Metavar compilation locates every recorded source span in the parsed CST and
derives its context from the path to that node. The context records expression,
identifier, pattern, type, whole-argument, binder-only, qualified-name, and
ordered-list information. Kind validation uses this context; it never mutates
or reconstructs the read-only CST. Interpolation expression nodes and their
metavar spans already use global source offsets, so the same root is used for
every occurrence.

Bare kind inference is intentionally conservative:

- a name explicitly declared as `pat`, `exp`, `id`, `const`, `arg`, or `type`
  keeps that kind
- bare identifier positions infer `id`
- bare type positions infer `type`
- bare pattern-variable positions cannot infer by themselves
- bare expression positions infer `exp` only if no earlier rule resolved the
  name
- `const`, `arg`, and `pat` are never inferred from a bare `$name`

This ordering lets a repeated bare name such as `$counter` infer `id` from a
binder and reuse that kind in later expression occurrences. It also rejects a
plain match pattern such as `$item => body`, because that position is ambiguous
between `id`, `const`, and `pat`.

## Metavar Kinds

Only these inline kinds are supported:

- `exp`: a whole bare identifier expression, capturing the candidate expression
- `id`: source-level names such as identifiers, binders, labels, constructors,
  type names, and qualified-name suffixes
- `const`: a whole bare identifier expression or simple pattern-variable
  position that must match a parsed constant
- `arg`: a whole bare call argument slot
- `pat`: a simple pattern-variable position that captures the whole candidate
  pattern CST
- `type`: a whole CST type node

The matcher recognizes `$name`, `$(name:kind)`, `$$$name`, and `$_` spellings
directly and consults the compiled kind arrays or ellipsis metadata for their
semantics.

Metavar arrays preserve first-seen order. Several tests assert that order, so do
not sort these arrays as a cleanup.

## Reserved Names

Inline declarations may not use:

- `$_`
- `__TARGET__`
- `__SOURCE__`

`$_` is the matcher ignore placeholder. `__TARGET__` is reserved for structural
inside-context traversal, and `__SOURCE__` is reserved for taint sink and
sanitizer target selection.

Names that merely start with underscores, such as `__moongrep_value`, are not
reserved. The exact built-ins listed above are reserved.

## Structural Rules

`compile_structural_rule` compiles every ordered `inside-expr` or
`inside-toplevel` alternative before inner positive and negative patterns when
an inside context exists.

Each inside-context shape is compiled as a normal pattern with:

- the guards declared on its pattern object
- `target_metavar = Some("__TARGET__")`
- `source_metavar = None`

Every alternative must contain exactly one `__TARGET__` in a complete
expression-identifier position as counted by
`count_bindable_expr_identifier_in_node`. This is the same position where the
runtime matcher dispatches a special expression metavar. Pattern variables,
binders, labels, and other literal name nodes do not count. The broader
`count_supported_name_in_node` remains in use for `__SOURCE__` validation.

Metavars declared by the selected inside alternative are visible during
target-expression matching. Inner `patterns` and `patterns-not` must repeat the
same inline form to reuse the binding. Reused captures must be declared by
every outer alternative with the same kind, including named ellipsis captures.
`ensure_inherited_inside_context_metavar_forms_for_all` checks both
cross-alternative availability and kind consistency. Captures not referenced
by inner patterns remain branch-local and need not agree.

Normal `patterns` and `patterns-not` are compiled independently after the
inside context. They must not contain `__TARGET__` in a complete expression
position; the same spelling in a non-expression literal name remains literal.

## Guards

`compile_guards` accepts only map entries whose key is a `$`-prefixed capture
name and whose value compiles as a regex.

Guards can reference only `id` and `const` captures. They cannot reference:

- unknown names
- `exp` captures
- `arg` captures
- `pat` captures
- `type` captures

This is a rule-compiler restriction. Guard evaluation in `rule/apply` expects a
string-like value from normalized identifiers or constants, not arbitrary
expression, pattern, argument, or type CST subtrees.

## Taint Rules

Every taint source, sink, and sanitizer shape must compile to a top-level call
CST:

- `Expr_Apply`
- `Expr_DotApply`

Sources must not contain `__SOURCE__`. A matching source call adds fresh return
taint later in `rule/taint_lowering`.

Sinks and sanitizers must contain exactly one `__SOURCE__`, and it must be the
whole receiver or the whole value of one argument. Nested forms such as
`sink(wrap(__SOURCE__))` are rejected because lowering needs to select one
already-evaluated call value from `CallInfo`.

`require_source_target` records that selected value as:

- `Receiver`
- `PositionalArg(index)`
- `LabelledArg(label, index)`

For labelled arguments, both label and index are stored. The lowering layer uses
the index to find the evaluated call argument and the label to confirm that the
same labelled slot was selected.

## Integration Boundaries

Several packages intentionally know about the same placeholder semantics:

- `rule/compile` parses and validates inline syntax, `__TARGET__`, and
  `__SOURCE__`
- `matching` implements the actual placeholder matching and binding behavior
- `rule/prefilter` excludes matcher placeholders from required literal
  collection
- `rule/taint_lowering` consumes compiled `TaintTarget` metadata
- `rule/apply` evaluates compiled guards after a structural match

When changing user-visible rule semantics, update all affected boundaries and
the rule-author docs in `docs/RuleSpec.md` and `docs/RuleSpec_CN.md`.

## Maintenance Checklist

When adding support for a new parser CST form:

1. update CST occurrence-context classification for the new path or wrapper
2. preserve the parser node directly; do not add a second tree representation
3. add `rule/compile` validation tests showing the new position works
4. check whether `matching` can actually match the resulting untyped CST
5. update `rule/prefilter` if the new CST carries literal names or constants

When changing metavar kinds or positions:

1. update collection, resolution, and rewrite validation together
2. update matcher placeholder dispatch if runtime matching changes
3. update guard validation if the new kind can be guarded
4. add tests for explicit syntax, bare inference, repeated captures, and
   conflict diagnostics
5. update the public rule spec only for rule-author-visible behavior

When changing inside-context behavior:

1. keep the `__TARGET__` compile-time check in sync with matcher support
2. preserve inherited metavar kind checks for both `patterns` and
   `patterns-not`
3. preserve ordered first-match selection, including guard fallthrough but no
   fallback after an outer alternative is selected
4. test rules with positive patterns, negative patterns, and negative-only
   `inside-expr` / `inside-toplevel`
5. check `rule/apply` root buckets and `rule/prefilter` outer-by-inner
   alternatives

When changing taint target behavior:

1. update `ensure_taint_call_shape` or `require_source_target`
2. update `rule/taint_lowering.target_value`
3. keep `taint/INTERNAL.md` and `matching/INTERNAL.md` notes in sync if
   `__SOURCE__` matching changes
4. add compile-time validation tests and rule-application tests

For package-local validation work, `moon test rule/compile` is the tight loop.
For behavior visible through loaded YAML rules, also test `rule/apply`,
`rule/taint_lowering`, and the relevant e2e snapshots.
