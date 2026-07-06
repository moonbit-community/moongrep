# matching Internal Notes

This document records implementation details that are easy to miss when
changing the `matching` package. It is for maintainers of the matcher and its
callers, not for rule authors.

## Match State

`match_expr_pattern` starts with a fresh `HashMap[String, BoundValue]`.
`match_expr_pattern_with_bindings` copies the caller-supplied map before
matching. Failed matches may leave partial captures in that local copy, but
they never mutate the caller's map.

There is no backtracking engine. Helper functions bind as they walk left to
right; if a later child fails, the whole candidate fails. This is fine because
the current matcher has no alternatives that need rollback.

## Placeholder Dispatch

Expression matching first calls `match_expr_placeholder`. If it returns
`Some(true)` or `Some(false)`, structural AST comparison is skipped. Only
`None` falls through to normal node-kind matching.

Placeholder priority in expression positions is:

1. names made only of underscores, with length at least two, are ignore
   placeholders
2. `target_metavar` and `source_metavar` bind a whole expression when present
   in `CompiledExprPattern`
3. declared expression metavars bind a whole expression value
4. declared identifier metavars bind a normalized identifier string
5. declared constant metavars bind only `Expr::Constant`
6. undeclared names are literal AST names

For vars, binders, and labels, only ignore placeholders and declared identifier
metavars are special; everything else is literal. For pattern variables,
`$(name:pat)` binds the whole candidate `Pattern` AST, declared constant
metavars match only `Pattern::Constant`, and declared identifier metavars
capture normalized pattern names. `__TARGET__` and `__SOURCE__` are special only
in whole expression positions. For example, undeclared `__x` is literal: only
`__` or `___` are ignore placeholders by spelling alone.

## Binding Kinds

`BoundValue` is `@untyped_ast.Node`.

Every binding is stored directly as an untyped AST node. Expression, constant,
and pattern metavars bind their matched nodes. Identifier metavars bind the
normalized name encoded as a `Leaf(PString(_))` node.

Expression metavars capture the candidate expression node at that position.
Repeated uses compare node structure and leaf values while ignoring source
locations.

Identifier metavars normalize source-level names before binding. Expr, var, and
pattern values go through `untyped_ast` normalization helpers where possible.
Binder and label matching uses the candidate name directly because those nodes
already carry the short name being compared.

Constant placeholders accept only constant expression or pattern nodes. Pattern
metavars bind whole pattern nodes. Repeated constant and pattern captures use
the same untyped-node equality as all other bindings.

## Equality Is Location-Insensitive

The matcher ignores source locations when comparing repeated expression and
pattern captures. Repeated binding comparison is handled by
`bound_value_equal`, which delegates to `node_equal_ignoring_loc`.

`node_equal_ignoring_loc` requires the same node kind and recursively compares
child labels and child values in order. Leaf values compare through their node
kind. The `loc` field is ignored throughout the walk.

## Let Head Matching

MoonBit parses an expression such as `let (__, __) = __` as an `Expr::Let`
whose body is a parser-synthesized `Unit(faked=true)`.

The matcher treats that faked unit as "body omitted in the pattern". For
`Expr::Let` only, it still matches the binding pattern and right-hand side, but
does not require the candidate body to match.

Explicit let bodies still use normal structural matching. These forms keep
their old meaning:

- `let (__, __) = __; finish(__)`
- `let x = __; __`
- `let x = __; ()`

`LetMut`, `LetFn`, and `LetAnd` do not use the faked-unit shortcut.

This behavior belongs in the matcher, not the parser, so `inside-expr` can
still use nested let expressions such as `let println = ___; __TARGET__` and
traverse the target body normally.

## Exactness and Small Exceptions

Most AST nodes require the same node kind and exact child list lengths. The
untyped matcher compares children in stored order after checking equal lengths.

Notable exactness details:

- argument kind and labels must match, unless a label is a declared placeholder
- record/map trailing markers and open/closed flags are significant
- `Unit(faked=...)` compares the `faked` flag
- parser holes are literal AST nodes and compare by hole kind
- interpolation `Source(_)` nodes match by node kind only; parser token
  internals are not compared

There is no semantic normalization beyond the explicit identifier normalization
used for identifier metavars. For example, equivalent code with a different AST
shape does not match unless a placeholder absorbs the difference.

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
