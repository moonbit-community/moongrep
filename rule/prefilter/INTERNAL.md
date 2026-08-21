# rule/prefilter Internal Notes

This document records implementation details that are easy to miss when
changing the `rule/prefilter` package. 

## Package Role

`rule/prefilter` builds and evaluates a conservative source-text filter for a
compiled rule.

The filter runs before parsing or CST matching. It asks only whether the source
text contains literals that every possible match of at least one rule branch
would require. A negative answer lets callers skip the rule. A positive answer
means only that the rule is still a candidate.

This package therefore may admit false positives, including literals found in
comments, strings, or unrelated expressions. It must not introduce false
negatives. It does not parse source, compare CST structure, evaluate guards, or
analyze taint flow.

`rule/compile` calls `compile_rule_prefilter` only after a
`CompiledRuleDefinition` has been built. This ordering is important because the
compiled patterns contain the normalized CST, metavar sets, reserved
target/source placeholders, and ignored matcher fields needed for safe literal
extraction.

## Representation and Evaluation

`RulePrefilter.alternatives` is a disjunction of conjunctions:

```text
[
  ["wrapper", "first_target"],
  ["wrapper", "second_target"],
  ["container", "first_target"],
  ["container", "second_target"],
]
```

The example remains relevant when every literal in any one inner array occurs
in the searched source. Literal order and source position do not matter.

`prefilter_matches_with_literal_matcher` implements this logic and
short-circuits on the first successful alternative or failed literal:

- the outer array is OR
- each inner array is AND
- an empty outer array returns `true`
- any empty inner array also returns `true`

Both empty cases are deliberate conservative fallbacks. They mean that no
useful necessary text was available, so the rule cannot be rejected safely.

`rule_is_relevant_to_source` supplies a matcher based on `String::contains`.
Matching is case-sensitive, unanchored, and literal. Regex metacharacters such
as `+`, `(`, or `.` have no special meaning.

The callback-based entry point keeps the Boolean evaluation separate from text
search. `rule/apply` uses it with `StringView::contains` and a per-filter-call
literal cache, so a literal shared by several rules is searched only once
during that call.

## Structural Rule Compilation

`compile_structural_prefilter` derives alternatives only from positive
requirements.

Without an inside context, each positive `patterns` item contributes one
alternative:

```text
alternative(pattern) = required_literals(pattern)
```

With `inside-expr` or `inside-toplevel`, each inside alternative is combined
with each positive pattern:

```text
alternative(inside, pattern) =
  required_literals(inside) + required_literals(pattern)
```

This is a Cartesian product. Flattening all inside and inner literals into one
conjunction would incorrectly require literals from mutually exclusive
branches.

When an inside-context rule has no positive patterns, each inside pattern still
contributes its own alternative. This supports rules that consist of an inside
context plus `patterns-not`. A rule with neither an inside context nor positive
patterns produces an empty outer array and remains relevant everywhere.

`patterns-not` never contributes required literals. A negative pattern
describes text whose presence may reject a structural match; its presence is
not required for a finding. Guards and `patterns-not-mode` likewise do not add
source anchors.

The rule compiler rejects definitions that contain both `inside-expr` and
`inside-toplevel`. The prefilter assumes that invariant. For a valid compiled
rule, it uses the non-empty inside-context collection and combines it with the
positive patterns as described above.

Within each alternative, duplicate literals are removed while preserving their
first-seen order. Duplicates between different alternatives are retained
because the alternatives remain independent branches.

## Taint Rule Compilation

`compile_taint_prefilter` creates the Cartesian product of taint sources and
sinks:

```text
alternative(source, sink) =
  required_literals(source.pattern) + required_literals(sink.pattern)
```

A taint finding needs some source and some sink, so the literals required by
that selected pair are safe coarse prerequisites. This check says nothing
about evaluation order, scope, data flow, or whether the sink receives the
source value.

Sanitizers are intentionally excluded. A sanitizer is not required for a taint
finding, and demanding its text would discard exactly the unsanitized cases the
rule is meant to report.

If a source or sink pattern yields no literals, the resulting empty or partial
alternative preserves conservative behavior. The compiled `__SOURCE__`
placeholder is excluded during literal collection.

## Required Literal Extraction

`required_literals_from_compiled_pattern` walks the compiled
`@untyped_cst.CstNode`, not the original YAML shape. This keeps literal extraction
aligned with the CST that `matching` will use.

The collector recognizes every node exposed by `@cst.normalized_name`,
including variables, binders, labels, accessors, constructors, and type names.
An unqualified name contributes its stored spelling. A qualified name
contributes its package/type prefix and final identifier as separate literals.

Qualified names deliberately do not contribute a synthesized `@pkg.name`
literal. MoonBit accepts whitespace before the dot, so a matching source may
spell the same CST identity as `@pkg .name`. Requiring the stored `pkg` and
`name` components separately remains conservative across both spellings. Each
component is checked independently for matcher placeholders, so a pattern such
as `@pkg.$(callee:id)` requires only the fixed `pkg` component.

The collector also recognizes:

- bigint, byte, bytes, char, double, float, int64, regex, string, uint, and
  uint64 constant payloads
- integer payloads whose stored spelling has at least two characters
- Boolean constants as `true` or `false`
- literal interpolation segments
- multiline string text segments

One-character integer spellings are intentionally omitted because they are
weak anchors. This is a length check on the stored spelling, not a numeric
magnitude check. Empty strings are also omitted.

Unrecognized non-leaf nodes are traversed recursively. Bare leaf nodes do not
become literals by themselves, so CST kind names and structural punctuation
are not source requirements. Interpolation expressions, including ones that
contain metavars, are reached through normal recursion over the parser-provided
`expr` subtree. Fixed literals around a metavar therefore remain usable without
any separate parse.

## Placeholders and Ignored Fields

A name must not be collected when the matcher can replace it with arbitrary
source. `is_filter_placeholder` excludes:

- raw metavar names containing `$`, including single and ellipsis forms
- the exact ignore placeholder `$_`
- the compiled pattern's `target_metavar` and `source_metavar`
- declared expression, identifier, constant, argument, and type metavars

Only exact `$_` has spelling-based underscore semantics. An ordinary
all-underscore identifier such as `__` remains a required literal.

`CompiledExprPattern.ignored_fields` is also part of the soundness contract.
During child traversal, a field is skipped only when both its parent
`NodeKind` and child name match an ignored-field entry. This mirrors structural
matching, especially partial `inside-toplevel` function shapes whose omitted
visibility, attributes, parameters, return type, or other default fields must
not become prefilter requirements. Explicit semantic fields remain eligible
literals.

Docstrings are different: `@cst.semantic_children` removes them before literal
collection, so their text is never required in default, exact, or partial mode.
Candidate source comments can still satisfy an unrelated required text search;
that is a conservative false positive and the final CST matcher rejects it.

When placeholder or ignored-field behavior changes in `matching` or
`rule/compile`, the prefilter must change in the same patch.

## Runtime Consumers

The main consumers use the same compiled Boolean expression at different
granularities:

- `rule/apply` filters `ScanPlan` entries against a `StringView`. One
  `Map[String, Bool]` cache is shared by structural and taint entries during
  each `ScanPlan::filter_source` call.
- the CLI filters a whole file, then filters each `///|` source block before
  parsing it. An irrelevant malformed file or block can therefore be skipped
  before parser diagnostics are produced.
- `query` filters the whole source and then each top-level item's source slice
  before CST traversal. `captures_from_cst` has no source text and bypasses the
  prefilter.

Filtering a previously filtered `ScanPlan` is safe: it can only remove more
entries for the narrower source slice and does not mutate the original plan.

## Soundness Invariant

Returning `false` can prevent parsing and all later rule evaluation. Every
collected literal must therefore satisfy this condition:

> If the represented rule branch can produce a finding in the searched source
> slice, that literal occurs verbatim in the same slice.

Before adding an anchor, check both sides of that implication. In particular:

- do not require literals from negative patterns, guards, or sanitizers
- do not require the spelling of any matcher placeholder
- do not use fields ignored by structural matching
- do not derive text that may differ from the original source spelling
- preserve branch structure when combining alternatives

Removing an anchor or making an alternative empty is conservative: it may cost
performance but cannot hide a finding. Adding an anchor or strengthening a
conjunction needs focused tests for every syntax form it covers.

## Maintenance Checklist

When adding a matcher placeholder or metavar kind:

1. update `is_filter_placeholder`
2. add a rule-compiler-to-prefilter test showing substituted source remains
   relevant
3. check `matching/INTERNAL.md` and `rule/compile/INTERNAL.md` for the same
   placeholder contract

When adding or changing an untyped CST form:

1. decide whether it carries a source spelling that is necessary for a match
2. add a dedicated collector branch only when the verbatim-text invariant
   holds
3. otherwise rely on recursive child traversal
4. test fixed literals and metavar forms separately

When changing structural or taint rule composition:

1. preserve the correct Cartesian-product alternatives
2. keep negative patterns and sanitizers out of required literals
3. cover empty-literal branches and alternative counts
4. test both direct `rule_is_relevant_to_source` behavior and
   `ScanPlan::filter_source` integration

For package-local work, `moon test rule/prefilter` is the tight loop. Changes
to compilation or scan behavior should also run the relevant `rule/compile`,
`rule/apply`, `query`, and end-to-end tests.
