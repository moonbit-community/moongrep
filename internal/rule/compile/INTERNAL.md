# Rule Compiler Internals

`internal/rule/compile` is the validation and normalization boundary between
pattern source text and executable matcher or rule values.

## Package role and entry points

| Entry point | Input | Output | Notes |
| --- | --- | --- | --- |
| `compile_rules(raw_rules)` | `Array[RawRuleSpec]` | `Array[CompiledRule]` | Checks unique IDs, compiles bodies, builds rule prefilters. |
| `compile_expr_pattern(pattern)` | `String` | `matching.CompiledExprPattern` | Compiles one ordinary structural expression shape without rule metadata, guards, or prefilter. |
| `compile_inside_toplevel_pattern(pattern)` | `String` | `matching.CompiledExprPattern` | Compiles one top-level shape using default `inside-toplevel` match mode (`partial` for functions) and `__TARGET__` validation; no guards or explicit match mode. |

What the compiler owns:

- Duplicate rule-ID checking.
- Parsing ordinary `shape` values as MoonBit expressions and `inside-toplevel`
  shapes as single top-level items.
- Recording metavars, validating CST positions, and rejecting reserved names or
  malformed guards.
- Recording taint sink and sanitizer target metadata.
- Building source-text prefilters from compiled rule definitions.

What lives elsewhere: runtime matching (`internal/matching`), guard evaluation
and scanning (`internal/rule/apply`), taint lowering
(`internal/rule/taint_lowering`), and prefilter evaluation
(`internal/rule/prefilter`).

## Main compilation flow

1. `compile_rules` runs `ensure_unique_rule_ids`, then calls `compile_rule` on
   each raw rule:
   - Structural rules run `compile_structural_rule`.
   - Taint rules run `compile_taint_rule`.
   - `compile_rule_prefilter(definition)` extracts required literals from the
     compiled CST (never raw YAML, because metavars must already be classified
     and excluded).
2. `compile_expr_pattern` builds an anonymous `patterns[0]` context and calls
   `compile_structural_expr_pattern` (parse, classify metavars, forbid
   `__TARGET__`, build matcher pattern). Callers may construct a standalone
   prefilter separately through `internal/rule/prefilter`.
3. `compile_inside_toplevel_pattern` builds an `inside-toplevel[0]` context,
   requires one bindable expression-position `__TARGET__`, registers it, and
   resolves default function match mode to `partial`.
4. `compile_structural_rule` compiles `inside-toplevel` alternatives via
   `compile_inside_toplevel_patterns` (resolving ignored fields per match mode
   under `inside-toplevel[index]` paths), then passes the outer shapes to
   `compile_structural_group`, which recursively compiles `patterns`,
   `patterns-not`, and nested `then` groups using `compile_metavar_shape` and
   `structural_visible_shapes`.

## Shape parsing

- `collect_shape_metavars` lexes with `comment = true` and
  `enable_metavar = true`, recording each metavar token's original span and
  logical syntax.
- `parse_shape` calls `@untyped_cst.parse_expression(..., enable_metavar=true)`;
  `parse_toplevel_shape` calls
  `@untyped_cst.parse_structure(..., enable_metavar=true)` and requires
  `@cst.toplevel_nodes` to return exactly one node. Metavar syntax stays directly
  in the parser's `CstNode` (no identifier rewriting or secondary tree).
- **Interpolations**: because the outer lexer emits a string/bytes
  interpolation as one aggregate token, the collector walks the CST and
  sub-lexes each `InterpSegment_Source` with its global start offset,
  `is_interpolation = true`, and `enable_metavar = true`. The parser forwards
  the same mode into each segment's `expr` subtree (including nested
  interpolations).
- **Type names**: `Type_Name` starts with an uppercase identifier token, so
  explicit `type` metavars and typed `type` ellipses must begin with an
  uppercase letter; lowercase and keyword names are rejected by the parser.
- **Diagnostics**: lexing errors report before parse errors.
  `InvalidMetavarSyntax` produces a dedicated diagnostic guiding legacy syntax
  such as `$exp:value` to `$(value:exp)`. Parse failures report `"not a valid
  MoonBit expression"` or `"not a valid MoonBit top-level item"`. Recovery
  nodes (`Missing`, `Error`) are always rejected even without parser
  diagnostics.

## Metavar context, inference, and registry

Metavar compilation locates every recorded span in the read-only CST and
derives its path context (expression, identifier, pattern, type,
whole-argument, binder-only, qualified-name, ordered-list).

### Conservative bare-name inference

1. Explicit `pat`, `exp`, `id`, `const`, `arg`, or `type` keeps that kind.
2. Bare identifier positions infer `id`.
3. Bare type positions infer `type`.
4. Bare pattern-variable positions cannot infer on their own (rejected as
   ambiguous between `id`, `const`, and `pat`).
5. Bare expression positions infer `exp` only if no earlier rule resolved the
   name.
6. `const`, `arg`, and `pat` are never inferred from bare `$name`.

This lets a repeated bare name like `$counter` infer `id` from a loop binder
and reuse `id` in later expression uses, while rejecting ambiguous `$item =>
body`.

### Supported inline kinds and reserved names

- **Kinds**: `exp` (whole bare identifier expr), `id` (identifier, binder,
  label, constructor, type name, qualified-name suffix), `const` (whole bare
  identifier expr or simple pattern variable), `arg` (whole bare call-argument
  slot), `pat` (simple pattern variable), `type` (whole CST type node).
- **Registry ordering**: ordinary expression shapes preserve first-occurrence
  order. Top-level function shapes keep parameter `id` metavars ahead of other
  `id` entries. Do not sort registry entries as a cleanup.
- **Reserved names**: exact `$_`, `__TARGET__`, and `__SOURCE__` cannot be used
  as inline metavar names. Qualified wildcard positions are rejected. Names
  merely starting with underscores (such as `__moongrep_value`) are not
  reserved.

## Structural groups and guards

- `StructuralRuleSpec` holds optional ordered `inside_toplevel` plus a
  recursive `StructuralPatternGroupSpec`. Each positive `StructuralPatternSpec`
  holds an atomic `RulePatternSpec` and optional `then_body`; negatives stay
  atomic. Compiled types mirror this recursion.
- Compilation descends each group independently:
  - A shape with `then` requires one bindable `__TARGET__`; leaves and
    negatives forbid it.
  - Current-shape registrations stay separate from ancestor visible
    environments. Descendants reuse ancestor names with identical kinds
    (including ellipsis kinds), guards may read ancestor `id`/`const` captures
    without local declarations, and new names stay in their branch.
  - For `inside-toplevel`, visible environments track every alternative so
    referenced inherited names (even in deep guards) must exist with compatible
    kinds in every alternative.
  - Negative mode is derived per group: root negatives prune; nested `then` and
    `inside-toplevel` groups reject uncovered negatives.
  - Guard compilation checks the visible environment; matcher compilation uses
    only the current shape's registry.
- **Guards** (`compile_guards`): require `$`-prefixed keys and valid regex
  strings, and permit only `id` and `const` captures (rejecting unknown, `exp`,
  `arg`, `pat`, `type`, and ellipsis captures because `internal/rule/apply`
  evaluates guards against normalized strings).

## Taint rules

- Every `source`, `sink`, and `sanitizer` shape must compile to `Expr_Apply` or
  `Expr_DotApply`.
- `sources` forbid `__SOURCE__`.
- `sinks` and `sanitizers` require exactly one `__SOURCE__`, placed as the
  whole receiver or the whole value of one argument (nested forms like
  `sink(wrap(__SOURCE__))` are rejected because lowering selects one
  pre-evaluated value from `CallInfo`).
- `require_source_target` records the target as `Receiver`,
  `PositionalArg(index)`, or `LabelledArg(label, index)` (storing both label
  and index so lowering confirms the exact labelled slot).

## Integration boundaries and maintenance checklist

Packages sharing placeholder semantics:

- `internal/rule/compile` — parses and validates inline syntax, `__TARGET__`,
  and `__SOURCE__`.
- `internal/matching` — implements runtime placeholder matching and binding.
- `internal/rule/prefilter` — excludes matcher placeholders from required
  literals.
- `internal/rule/taint_lowering` — consumes compiled `TaintTarget` metadata.
- `internal/rule/apply` — evaluates compiled guards after structural matches.

Update `internal/docs/RuleSpec.md` and `internal/docs/RuleSpec_CN.md` whenever
user-visible rule semantics change.

### Quick checklists

- **New parser CST form**: update occurrence-context classification; keep the
  parser `CstNode` directly; add compile validation tests; verify `matching`
  handles the CST; update `prefilter` if it carries literal names or constants.
- **Metavar kind/position changes**: update collection, resolution, and
  validation together; sync matcher dispatch and guard validation; test
  explicit syntax, bare inference, repeated captures, and conflicts.
- **Inside-context changes**: keep `__TARGET__` checks synced with matcher
  support; preserve inherited kind checks for both `patterns` and
  `patterns-not`; preserve ordered first-match selection (guard fallthrough, no
  fallback after outer selection); test positive, negative, and negative-only
  groups; check `apply` buckets and `prefilter` outer-by-inner combinations.
- **Taint target changes**: update `ensure_taint_call_shape` /
  `require_source_target` and `taint_lowering.target_value`; keep
  `internal/taint/INTERNAL.md` and `internal/matching/INTERNAL.md` aligned; add
  compile and apply tests.

Run `moon test internal/rule/compile` after validation changes, plus
`internal/rule/apply`, `internal/rule/taint_lowering`, and e2e tests when
loaded YAML rule behavior changes.
