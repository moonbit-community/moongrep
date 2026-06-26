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
5. undeclared names are literal AST names

For vars, binders, labels, and pattern variables, only ignore placeholders and
declared identifier metavars are special; everything else is literal.
`__TARGET__` and `__SOURCE__` are special only in whole expression positions.
For example, undeclared `__x` is literal: only `__` or `___` are ignore
placeholders by spelling alone.

## Binding Kinds

`BoundValue` stores either `Expr` for whole-expression captures or
`Identifier` for normalized name captures.

Expression metavars capture the candidate expression at that position.
Repeated uses compare the parsed expression structure, ignoring locations.

Identifier metavars store `Identifier(String)`. Expr, var, and pattern values
go through `rule/syntax_id` normalization where possible. Binder and label
matching uses the candidate name directly because those nodes already carry the
short name being compared.

## Equality Is Location-Insensitive but Not Complete

The matcher ignores source locations. It compares the semantic fields that
matter for each supported AST node, using helper functions such as
`var_equal`, `type_equal`, `constant_equal`, and `argument_kind_equal`.

The equality used for repeated captures is intentionally smaller than the full
root matcher:

- `expr_equal_ignoring_loc` supports common expression shapes such as
  identifiers, holes, constants, infix, calls, dot calls, fields, methods,
  constructors, arrays, tuples, groups, sequences, `for`, and `unit`

If a new `match_expr` branch is added and that node can be captured by a
repeated expression metavar, update the relevant equality helper too. Otherwise a
single occurrence may match while repeated occurrences fail even when the ASTs
look identical.

`option_location_presence_equal` compares only whether async/location-like
fields are present, not their concrete locations.

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

Most AST nodes require the same node kind and exact list lengths. `list_match`
converts MoonBit lists to arrays, checks equal lengths first, and then compares
children in order.

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
