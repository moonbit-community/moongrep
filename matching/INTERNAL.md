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
`Some(true)` or `Some(false)`, structural AST comparison is skipped. Only
`None` falls through to normal node-kind matching.

Placeholder priority in expression positions is:

1. exact `$_` is an ignore placeholder
2. `target_metavar` and `source_metavar` bind a whole expression when present
   in `CompiledExprPattern`
3. declared expression metavars bind a whole expression value
4. declared identifier metavars bind a normalized identifier string
5. declared constant metavars bind only `Expr::Constant`
6. undeclared names are literal AST names

For type nodes, a simple `Type::Name` marker whose name is in
`CompiledExprPattern.type_metavars` binds the whole candidate `Type_*` node.
Repeated type captures use the same location-insensitive structural equality as
other AST-node captures.

For vars, binders, and labels, only ignore placeholders and declared identifier
metavars are special; everything else is literal. For pattern variables,
`$(name:pat)` binds the whole candidate `Pattern` AST, declared constant
metavars match only `Pattern::Constant`, and declared identifier metavars
capture normalized pattern names. `__TARGET__` and `__SOURCE__` are special only
in whole expression positions. For example, undeclared `__x` is literal: only
exact `$_` is an ignore placeholder by spelling alone.

## Binding Kinds

`BoundValue` is either `Single(Node)` or `Multiple(Array[Node])`.

Expression, constant, argument, pattern, type, and identifier metavars use
`Single`; normalized identifier names are encoded as `Leaf(PString(_))` nodes.
Ellipsis metavars use `Multiple` and retain complete sibling nodes.

Expression metavars capture the candidate expression node at that position.
Repeated uses compare node structure and leaf values and ignore source
locations.

Identifier metavars normalize source-level names before binding. Expr, var, and
pattern values go through `untyped_ast` normalization helpers where possible.
Binder and label matching uses the candidate name directly because those nodes
already carry the short name being compared.

Constant placeholders accept only constant expression or pattern nodes. Pattern
metavars bind whole pattern nodes. Type metavars bind whole type nodes.
Repeated constant, pattern, and type captures use the same untyped-node equality
as all other bindings.

## Equality Is Location-Insensitive

The matcher ignores source locations when comparing repeated expression,
argument, pattern, and type captures. Repeated binding comparison is handled by
`bound_value_equal`, which compares `Single` with `Single` and `Multiple` with
`Multiple`; mixed variants are unequal.

`node_equal_ignoring_loc` requires the same node kind and recursively compares
child labels and child values in order. Leaf values compare through their node
kind. The `loc` field is ignored throughout the walk.

## Let and Guard Header Matching

MoonBit parses an expression such as `let ($_, $_) = $_` as an `Expr::Let`
whose body is a parser-synthesized `Unit(faked=true)`.

The matcher treats that faked unit as "body omitted in the pattern". For
`Expr::Let`, it matches the binding pattern and right-hand side and places no
matching requirement on the candidate body.

Explicit let bodies use normal structural matching. These forms keep
their old meaning:

- `let ($_, $_) = $_; finish($_)`
- `let x = $_; $_`
- `let x = $_; ()`

`LetMut`, `LetFn`, and `LetAnd` do not use the faked-unit shortcut.

Guard expressions use the same parser convention. A shape such as
`guard ready() else { fallback() }` has a parser-synthesized
`Unit(faked=true)` body. For `Expr::Guard`, the matcher still recursively
matches `cond` and `otherwise`, but places no requirement on the candidate body
when the pattern body is that faked unit.

Explicit guard bodies use normal structural matching, including
`guard ready() else { fallback() }; ()`. An explicit unit has `faked=false`
and is not a wildcard. A body metavar such as `$(body:exp)` continues to bind
the candidate body normally.

These behaviors belong in the matcher. They let `inside-expr` use nested let
expressions such as `let println = $_; __TARGET__` and traverse the target body
normally. They do not change scoped traversal, YAML `guard` filters, or taint
matching.

## Exactness and Small Exceptions

Most AST nodes require the same node kind and exact child list lengths. The
untyped matcher compares children in stored order after checking equal lengths.

Notable exactness details:

- argument kind must match; labels must also match, and a declared label
  placeholder can capture a varying label
- record/map trailing markers and open/closed flags are significant
- `Unit(faked=...)` compares the `faked` flag
- parser holes are literal AST nodes and compare by hole kind
- interpolation `Source(_)` nodes match by node kind only; parser token
  internals are not compared

There is no semantic normalization beyond the explicit identifier normalization
used for identifier metavars. For example, equivalent code with a different AST
shape does not match. A placeholder can absorb the structural difference.

## Integration Notes

When changing placeholder behavior, update all three places that know about
placeholder names:

- `matching/matching.mbt`
- `rule/prefilter/prefilter.mbt`
- `rule/compile/compile.mbt` validation for reserved names and supported
  `__TARGET__` / `__SOURCE__` positions

When adding support for a new AST node:

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
