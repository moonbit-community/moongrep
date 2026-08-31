# matching Internal Notes

This document records implementation details that are easy to miss when
changing the `matching` package. It is for maintainers of the matcher and its
callers, not for rule authors.

## Match State

`match_expr_pattern` converts its raw node to an expression candidate and
delegates to `match_expr_pattern_candidate`. The candidate entry point starts
with a fresh `HashMap[String, BoundValue]`.
`match_expr_pattern_candidate_with_bindings` copies the caller-supplied map
before matching. Failed matches may leave partial captures in that local copy.
The caller's map remains unchanged.

`match_expr_pattern_candidate` and
`match_expr_pattern_candidate_with_bindings` apply the same state rules to
`Direct(CstNode)` and `Sequence(Array[CstNode])` candidates. Every successful
`ExprMatch` carries the exact candidate `loc`; sequence locations merge the
first and last statement and therefore exclude container braces.

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
2. special expression placeholders registered in `CompiledExprPattern.metavars`,
   such as `__TARGET__` and `__SOURCE__`, bind a whole expression
3. declared expression metavars bind a whole expression value
4. declared identifier metavars bind a normalized identifier string
5. declared constant metavars bind only `Expr_Constant`
6. undeclared names are literal CST names

All source spellings are resolved through the compiled `MetavarRegistry`.
The matcher does not infer a metavar kind from the raw spelling.

For type nodes, a simple `Type_Name` containing a declared type-metavar payload
binds the whole candidate type node. Repeated type captures use the same
location-insensitive structural equality as other CST-node captures.

For vars, binders, and labels, only ignore placeholders and declared identifier
metavars are special; everything else is literal. For pattern variables,
`$(name:pat)` binds the whole candidate pattern CST, declared constant
metavars match only `Pattern_Constant`, and declared identifier metavars
capture normalized pattern names. `__TARGET__` and `__SOURCE__` are special only
in whole expression positions. For example, undeclared `__x` is literal: only
exact `$_` is an ignore placeholder by spelling alone.

The parser forwards metavar mode when it re-lexes string and bytes
interpolation sources. `InterpSegment_Source` therefore contains the correct
parsed `expr` subtree, and the matcher handles it through normal recursive CST
matching. The same binding map flows through every segment, so repeated
captures across interpolation segments retain their normal equality semantics.

## Binding Kinds

`BoundValue` is either `Single(CstNode)` or `Multiple(Array[CstNode])`.

Expression, constant, argument, pattern, type, and identifier metavars normally
use `Single`. Identifier captures retain the candidate's actual semantic name
CST node; normalization is applied when comparing or guarding the capture.
Ellipsis metavars use `Multiple` and retain complete ordered sibling nodes. A
terminal named expression metavar or special target after a
continuation-owning header also retains the flattened CST suffix: a
one-statement suffix stays `Single`, while an empty or multi-statement suffix
uses `Multiple`. A terminal exact `$_` after a continuation-owning header also
matches the complete suffix, but it remains non-binding and creates no
`BoundValue`. In every other position, `$_` matches exactly one expression.

Expression metavars capture the candidate expression node at that position.
Repeated uses compare node structure and leaf values and ignore source
locations.

Identifier metavars normalize source-level names across expression, binder,
label, constructor, accessor, type-name, and qualified-name nodes. Repeated
bindings compare the normalized spelling even when the two occurrences use
different CST name kinds.

In constructor position, one identifier metavar binds the complete constructor
identity. Expression constructors retain their real `Expr_Constr` node;
constructor patterns retain their real full-span semantic name node. Both
normalize forms such as `@pkg.Ctor`, `Type::Ctor`, `@pkg.Type::Ctor`, and
`@pkg.Type::@other.Ctor`. A shape that explicitly separates
`$(Type:id)::$(Ctor:id)` still binds the two parts independently.

Constant placeholders accept only constant expression or pattern nodes. Pattern
metavars bind whole pattern nodes. Type metavars bind whole type nodes.
Repeated constant, pattern, and type captures use the same semantic-CST equality
as all other bindings.

## Equality Is Location-Insensitive

The matcher ignores source locations when comparing repeated expression,
argument, pattern, and type captures. Repeated binding comparison is handled by
`bound_value_equal`, which compares `Single` with `Single` and `Multiple` with
`Multiple`; mixed variants are unequal.

`node_equal_ignoring_loc` compares normalized identity nodes first. Whole
constructor patterns captured by `pat` are not identity nodes: they still
require the same kind and recursively compare the semantic child view,
including constructor arguments. Leaf payloads remain significant. Locations
never enter this view.

## Semantic CST View

The matcher does not compare raw `CstNode.children`. `@cst.semantic_children`
removes `_loc` fields, `Aggregate_Span`, EOF, `doc` fields, `Syntax_Comment`,
delimiters, separators, and other pure punctuation. This makes docstrings
non-semantic at every nesting level and in every matching mode. The view expands
semantic names, constants, operators, attributes, interpolation segments, and
flags from parser wrappers. An interpolation source's raw payload is omitted in
favor of its parsed expression. Redundant constructor qualification metadata is
ignored because the normalized name already preserves that identity.

`Pattern_Group` and `Type_Group` wrappers that the previous representation
eliminated are unwrapped. Expression blocks remain structural, except a block
used as a labelled `body` container can bind a single whole-body expression
placeholder to the candidate block. This preserves multi-statement body
captures used by loop and function-context rules.

Expression matching is preceded by the candidate traversal in `cst/scoped.mbt`.
Function, method, test, lambda, local-function, and letrec body blocks produce a
brace-free `Sequence` candidate instead of a direct block candidate. Explicit
nested blocks remain `Direct(Expr_Block)` candidates and keep their braces in
the match location.

A sequence accepts only a complete multi-statement `Expression` shape or the
omitted-continuation shortcut for ordinary `let` and `guard`. A terminal named
expression metavar, special target, or exact `$_` after `let`, `let mut`,
`guard`, or another continuation-owning header absorbs the complete remaining
suffix. Only `$_` discards that suffix instead of binding it.
`let mut`, local functions, `letrec`, and `defer` do not get the
omitted-continuation shortcut. When one of these headers has following
statements, traversal emits the sequence suffix instead of a header-only direct
candidate. `proof_let` is not a continuation owner and remains independently
matchable.

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

1. check whether the generic `structural_match` fallback in `match_node`
   already handles the node; add or adjust specialized dispatch only when the
   node needs special matching semantics
2. add helper matchers for child structures when needed
3. update repeated-capture equality if the node can be bound by a metavar
4. update prefilter literal collection so rules remain searchable
5. add focused tests in `matching/matching_test.mbt`
6. add `rule/apply` or taint integration tests if compiled rule behavior
   changes

For matcher-only changes, `moon test matching/matching_test.mbt` is the tight
loop. For behavior visible through YAML rules, also test the relevant caller
package.
