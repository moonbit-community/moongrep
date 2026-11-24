# Rule Prefilter Internals

`internal/rule/prefilter` builds and evaluates conservative source-text filters
for compiled rules and standalone expression patterns, letting callers skip
parsing or matching when required literals are absent from the source.

## Package role and soundness invariant

The prefilter runs before parsing or CST matching:

- **False positives are allowed** (for example, a literal appearing only in a
  comment, string, or unrelated expression); downstream CST matching discards
  them.
- **False negatives are forbidden**:

> If the represented rule branch can produce a finding in the searched source
> slice, every collected literal in at least one alternative must occur verbatim
> in that same slice.

Because the prefilter needs classified metavars, reserved placeholders, and
ignored fields, `internal/rule/compile` calls `compile_rule_prefilter` only
after building `CompiledRuleDefinition`. Callers with a standalone
`CompiledExprPattern` call `compile_expr_pattern_prefilter` directly without
creating a synthetic rule.

## Representation and evaluation

`RulePrefilter.alternatives` is a disjunction of conjunctions (DNF):

```text
[
  ["wrapper", "first_target"],
  ["wrapper", "second_target"],
  ["container", "first_target"],
  ["container", "second_target"],
]
```

`prefilter_matches_with_literal_matcher` evaluates this structure with
short-circuiting:

- **Outer array = OR**; **inner array = AND** (order and position in source do
  not matter).
- **Empty outer array -> `true`** and **any empty inner array -> `true`**
  (deliberate conservative fallbacks when no necessary literal can be derived).
- `prefilter_matches_source` uses literal, case-sensitive, unanchored
  `String::contains` (regex metacharacters like `+`, `(`, `.` are ordinary
  characters).
- Keeping the literal matcher as a callback lets `internal/rule/apply` plug in
  `StringView::contains` with a per-call `Map[String, Bool]` cache so literals
  shared across rules are searched only once.

## How alternatives are compiled

| Rule / pattern type | Alternative construction | Excluded from literals |
| --- | --- | --- |
| Standalone `CompiledExprPattern` | Single alternative: `required_literals(pattern)` (empty if all metavars). | All placeholders |
| Structural rule | One alternative per positive root-to-leaf path (AND along path, OR across paths), deduplicated in order. If `inside-toplevel` is present, take the Cartesian product of outer alternatives and positive paths. A negative-only `then` adds no child requirements. | `patterns-not`, `guard`, placeholders, ignored fields |
| Taint rule | Cartesian product of `sources` and `sinks`: `required_literals(source) + required_literals(sink)`. | `sanitizers`, `__SOURCE__`, placeholders |

Note on structural execution: `ScanPlan` separately builds recursive positive
and negative CST buckets per group (preserving original YAML indices); only
complete `shape`/`guard`/`then` success prunes a positive subtree, existence
scans without negatives stop at the first hit, and groups with negatives scan
all uncovered regions before succeeding. Findings use the root entry's index
and location.

## Required literal extraction

`required_literals_from_compiled_pattern` walks the compiled
`@untyped_cst.CstNode` (not raw YAML) so extraction stays aligned with
`matching`:

- **Names** (`@cst.normalized_name` — variables, binders, labels, accessors,
  constructors, type names):
  - Unqualified names contribute their stored spelling.
  - Qualified names contribute their package/type prefix and final identifier
    as **separate** literals (never synthesized `@pkg.name`, because MoonBit
    allows whitespace before the dot as in `@pkg .name`). Each component is
    checked independently against placeholders, so `@pkg.$(callee:id)` still
    requires `pkg`.
- **Constants and text**:
  - `bigint`, `byte`, `bytes`, `char`, `double`, `float`, `int64`, `regex`,
    `string`, `uint`, and `uint64` payloads (empty strings omitted).
  - Integer payloads whose stored spelling has length `>= 2` (1-character
    integers are weak anchors and intentionally skipped).
  - Boolean constants (`true` or `false`).
  - Literal interpolation segments and multiline string text segments.
- **Recursion**: unrecognized non-leaf nodes recurse through children (including
  parsed interpolation `expr` subtrees, keeping fixed literals around metavars
  usable). Bare leaf tokens and CST kind names never become literals.

### Placeholders, ignored fields, and docstrings

- `is_filter_placeholder` excludes every single, ellipsis, wildcard, or special
  expression placeholder in `MetavarRegistry`. Only exact `$_` is a
  spelling-based wildcard; ordinary underscore identifiers like `__` stay
  required.
- `CompiledExprPattern.ignored_fields` skips a child only when both parent
  `NodeKind` and child name match, mirroring `partial` `inside-toplevel`
  function matching so omitted default header fields never become prefilter
  requirements.
- `@cst.semantic_children` removes docstrings before literal extraction, so
  docstrings are never required in any mode.

## Runtime consumers

| Consumer | Granularity | Caching / notes |
| --- | --- | --- |
| `internal/rule/apply` | `ScanPlan::filter_source` on a `StringView` | Shares one `Map[String, Bool]` across structural and taint entries per call; safe to re-filter a narrowed slice without mutating the original plan. |
| `internal/cli` | Whole file, then each `///|` source block | Skips irrelevant files/blocks before parsing (so irrelevant malformed blocks emit no parse diagnostics). |
| `query` | Whole source, then each top-level item slice | Caches standalone pattern prefilter; `captures_from_cst` has no source text and bypasses prefiltering. |

## Maintenance checklist

Remember: removing an anchor or leaving an alternative empty is always safe
(conservative), whereas adding or strengthening an anchor must satisfy the
verbatim-text invariant across all syntax spellings.

- **New placeholder or metavar kind**: update `is_filter_placeholder`; add a
  compile-to-prefilter test verifying substituted source stays relevant; sync
  with `internal/matching/INTERNAL.md` and `internal/rule/compile/INTERNAL.md`.
- **New or changed CST form**: add a dedicated collector branch only when the
  verbatim-text invariant holds; otherwise rely on child recursion; test both
  literal and metavar forms.
- **Rule composition changes**: preserve Cartesian products; keep negative
  patterns, guards, and sanitizers excluded; cover empty-literal branches and
  alternative counts; test both `prefilter_matches_source` and
  `ScanPlan::filter_source`.

Run `moon test internal/rule/prefilter` after changes, plus `compile`, `apply`,
`query`, and e2e tests when compilation or scanning is affected.
