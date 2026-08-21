# matching Internal Notes

This document records implementation details that are easy to miss when
changing the `matching` package. It is for maintainers of the matcher and its
callers, not for rule authors.

## Match State

`match_expr_pattern` starts with a fresh `HashMap[String, BoundValue]`.
`match_expr_pattern_with_bindings` copies the caller-supplied map before
matching. Failed matches may leave partial captures in that local copy. The
caller's map remains unchanged.

Ordinary nodes bind as they walk left to right. Ordered child lists use a small
backtracking matcher when they contain ellipses: each candidate length runs
against a copied binding map, and only the first complete successful branch is
committed.

## Placeholder Dispatch

Expression matching first calls placeholder matchers such as
`match_expr_placeholder` and `match_type_placeholder`. If one returns
`Some(true)` or `Some(false)`, structural CST comparison is skipped. Only
`None` falls through to normal node-kind matching.

Placeholder priority in expression positions is:

1. exact `$_` is an ignore placeholder
2. `target_metavar` and `source_metavar` bind a whole expression when present
   in `CompiledExprPattern`
3. declared expression metavars bind a whole expression value
4. declared identifier metavars bind a normalized identifier string
5. declared constant metavars bind only `Expr_Constant`
6. undeclared names are literal CST names

For type nodes, a simple `Type_Name` marker whose name is in
`CompiledExprPattern.type_metavars` binds the whole candidate type node.
Repeated type captures use the same location-insensitive structural equality as
other CST-node captures.

For vars, binders, and labels, only ignore placeholders and declared identifier
metavars are special; everything else is literal. For pattern variables,
`$(name:pat)` binds the whole candidate pattern CST, declared constant
metavars match only `Pattern_Constant`, and declared identifier metavars
capture normalized pattern names. `__TARGET__` and `__SOURCE__` are special only
in whole expression positions. For example, undeclared `__x` is literal: only
exact `$_` is an ignore placeholder by spelling alone.

## Binding Kinds

`BoundValue` is either `Single(CstNode)` or `Multiple(Array[CstNode])`.

Expression, constant, argument, pattern, type, and identifier metavars use
`Single`. Identifier captures retain the candidate's actual semantic name CST
node; normalization is applied when comparing or guarding the capture.
Ellipsis metavars use `Multiple` and retain complete ordered sibling nodes.

Expression metavars capture the candidate expression node at that position.
Repeated uses compare node structure and leaf values and ignore source
locations.

Identifier metavars normalize source-level names across expression, binder,
label, constructor, accessor, type-name, and qualified-name nodes. Repeated
bindings compare the normalized spelling even when the two occurrences use
different CST name kinds.

Constant placeholders accept only constant expression or pattern nodes. Pattern
metavars bind whole pattern nodes. Type metavars bind whole type nodes.
Repeated constant, pattern, and type captures use the same semantic-CST equality
as all other bindings.

## Equality Is Location-Insensitive

The matcher ignores source locations when comparing repeated expression,
argument, pattern, and type captures. Repeated binding comparison is handled by
`bound_value_equal`, which compares `Single` with `Single` and `Multiple` with
`Multiple`; mixed variants are unequal.

`node_equal_ignoring_loc` compares normalized name nodes first. Other nodes
require the same kind and recursively compare the semantic child view in order.
Leaf payloads remain significant. Locations never enter this view.

## Semantic CST View

The matcher does not compare raw `CstNode.children`. `@cst.semantic_children`
removes `_loc` fields, `Aggregate_Span`, EOF, `doc` fields, `Syntax_Comment`,
delimiters, separators, and other pure punctuation. This makes docstrings
non-semantic at every nesting level and in every matching mode. The view expands
semantic names, constants, operators, attributes, interpolation segments, and
flags from parser wrappers. Redundant constructor qualification metadata is
ignored because the normalized name already preserves that identity.

`Pattern_Group` and `Type_Group` wrappers that the previous representation
eliminated are unwrapped. Expression blocks remain structural, except a block
used as a labelled `body` container can bind a single whole-body expression
placeholder to the candidate block. This preserves multi-statement body
captures used by loop and function-context rules.

The expression-container matcher also retains the earlier spelling-level
compatibility for an omitted let or guard body versus a trailing unit. Explicit
bodies continue to match structurally.

## Exactness

Most semantic CST nodes require the same node kind and exact semantic child
list length. Child labels and ordering are significant.

Notable exactness details:

- argument kind must match; labels must also match, and a declared label
  placeholder can capture a varying label
- constants preserve parser kind and source spelling
- operators, name spelling, argument structure, attributes, flags, and
  open/closed pattern structure are significant
- comments, including docstrings, formatting, locations, delimiters, and
  trailing punctuation are not significant
- parser holes remain literal CST nodes and compare by hole kind

Equivalent code with a different semantic CST shape does not match. A
placeholder can absorb the structural difference.

## Integration Notes

When changing placeholder behavior, update all three places that know about
placeholder names:

- `matching/matching.mbt`
- `rule/prefilter/prefilter.mbt`
- `rule/compile/compile.mbt` validation for reserved names and supported
  `__TARGET__` / `__SOURCE__` positions

When adding support for a new CST node:

1. add or adjust the root `match_expr` branch
2. add helper matchers for child structures when needed
3. update repeated-capture equality if the node can be bound by a metavar
4. update prefilter literal collection so rules remain searchable
5. add focused tests in `matching/matching_test.mbt`
6. add `rule/apply` or taint integration tests if compiled rule behavior
   changes

For matcher-only changes, `moon test matching/matching_test.mbt` is the tight
loop. For behavior visible through YAML rules, also test the relevant caller
package.
