# Matcher Internals

`internal/matching` compares compiled CST patterns against MoonBit source CSTs
and manages metavariable captures. This guide documents the invariants that
maintainers of the matcher and its callers rely on.

## Entry points and match state

- `match_expr_pattern` wraps a raw CST node as an expression candidate and
  delegates to `match_expr_pattern_candidate` (which starts with an empty
  `HashMap[String, BoundValue]`).
- `match_expr_pattern_candidate_with_bindings` copies the caller's binding map
  before matching. Failed attempts may mutate only that local copy; the
  caller's map is never modified.
- Both entry points handle `Direct(CstNode)` and `Sequence(ArrayView[CstNode])`
  candidates identically. Every successful `ExprMatch` returns `bindings` and
  the exact candidate `loc` (for sequences, merged from the first to the last
  statement, excluding container braces).

### Backtracking, indexing, and interning

- Ordinary nodes bind left to right. Ordered child lists containing ellipses
  backtrack locally: each candidate slice runs against a copied binding map,
  and only the first complete successful branch commits.
- Indexed matching shares the same atomic matcher via `MatchContext` (captures
  plus an optional `TargetRef`). `TargetRef` records only the selected region
  (or continuation statement list + start/end offsets, including empty tails);
  lexical scopes are queried from `SourceIndex` on demand.
- Ellipsis backtracking commits or rolls back captures, identifier provenance,
  and `TargetRef` together. A failed outer `then` never asks the atomic matcher
  for another ellipsis partition.
- Standalone matching leaves `SourceIndex` absent, so `query` and taint call
  matching avoid index setup overhead.
- `ValueInterner` mirrors `bound_value_equal` (including normalized identity
  nodes and `Single` vs. `Multiple`), verifying complete keys on hash
  collisions. Rule environments use interned IDs for sharing, while public
  queries continue returning original CST nodes.

## Placeholder dispatch

Before falling through to structural CST comparison, matching runs specialized
placeholder matchers (`match_expr_placeholder`, `match_type_placeholder`,
`match_pattern_placeholder`, `match_argument_placeholder`). Returning
`Some(true)` or `Some(false)` short-circuits comparison; only `None` falls
through to normal node-kind matching.

### Expression placeholder priority

1. Exact, unqualified `$_` — ignore placeholder.
2. Context-reserved expression placeholders in `CompiledExprPattern.metavars`
   (`__TARGET__`, `__SOURCE__`) — bind a whole expression.
3. Declared `exp` metavars — bind a whole expression node.
4. Declared `id` metavars — bind a semantic name node (compared by normalized
   identifier).
5. Declared `const` metavars — bind `Expr_Constant` only.
6. All other names — literal CST names.

All spellings resolve strictly through the compiled `MetavarRegistry`; the
matcher never infers kinds from raw text. Qualified forms such as `@pkg.$_`,
`Type::$_`, or qualified anonymous ellipses are not wildcards.

### Non-expression positions

| Position | Special placeholders | Everything else |
| --- | --- | --- |
| Type (`Type_Name`) | Declared `type` metavar binds whole candidate `Type` node | Literal |
| Var, binder, label | `$_` and declared `id` metavars | Literal |
| Pattern variable | `$(name:pat)` (whole `Pattern`), declared `const` (`Pattern_Constant`), declared `id` (normalized pattern name), `$_` | Literal |

`__TARGET__` and `__SOURCE__` are special only in whole-expression positions.
Undeclared names like `__x` are always literal.

### String and bytes interpolations

The parser forwards metavar mode when re-lexing interpolation segments, so
`InterpSegment_Source` already carries its parsed `expr` subtree. The matcher
recurses through it normally with the same binding map, preserving repeated
capture equality across segments.

## Binding representation and equality

Public `model.BoundValue` has two variants: `Single(CstNode)` and
`Multiple(Array[CstNode])`.

- **Normal metavars** (`exp`, `id`, `const`, `arg`, `pat`, `type`): bind
  `Single`. Identifier captures keep the candidate's real semantic name node;
  normalization runs during comparison and guard evaluation.
- **Ellipsis metavars**: bind `Multiple`, storing complete ordered sibling
  nodes.
- **Continuation tails**: after a continuation-owning header (`let`, `let mut`,
  local function, `letrec`, `guard`, `defer`, `errdefer`), a terminal named
  `exp` metavar or special target binds the flattened suffix as `Single` for
  one statement and `Multiple` for an empty or multi-statement suffix. A
  terminal exact `$_` absorbs the complete suffix without binding; everywhere
  else `$_` matches one expression.
- **Constructors**: a single `id` metavar binds the full constructor identity
  (`Expr_Constr` in expressions, full-span semantic name in patterns),
  normalizing `@pkg.Ctor`, `Type::Ctor`, `@pkg.Type::Ctor`, and
  `@pkg.Type::@other.Ctor`. Writing `$(Type:id)::$(Ctor:id)` binds the two parts
  independently.

Repeated-capture equality (`bound_value_equal`):

- `Single` compares only with `Single`, and `Multiple` only with `Multiple`.
- `node_equal_ignoring_loc` checks normalized identity nodes first. Whole
  constructor patterns captured by `pat` are not identity nodes; they require
  matching kinds and recursively compare semantic children (including
  arguments). Leaf payloads stay significant; source locations never enter the
  comparison.

## Semantic CST view and traversal

Matching operates on `@cst.semantic_children` rather than raw `CstNode.children`:

- Strips `doc` fields and pure punctuation tokens (`TK_EOF`, `TK_COMMENT`,
  delimiters, separators), making docstrings non-semantic everywhere.
- Expands semantic names, constants, operators, attributes, interpolation
  segments (using the parsed `expr` instead of raw source payload), and flags.
- Omits redundant constructor qualification metadata already captured by
  normalized names.
- Unwraps `Pattern_Group` and `Type_Group`.
- Keeps expression blocks structural, except a labelled `body` block containing
  a single whole-body expression placeholder can bind the candidate block
  directly (supporting loop and function-context rules).

Candidate traversal (`internal/cst`):

- Function, method, test, lambda, local-function, and `letrec` bodies emit
  brace-free `Sequence` candidates; explicit nested blocks stay
  `Direct(Expr_Block)` with braces in their match span.
- Plain rules and `query` walk the CST directly without node IDs, scopes, or
  caches. Recursive and `inside-toplevel` rules use `SourceIndex`, which stores
  lexical scopes and target roles once and avoids span-based target rescans.
- Indexed matches return identifier provenance alongside `BoundValue`. Inherited
  `id` captures (and typed `id` ellipses) enforce lexical binding equality only
  when both source and use are lexical variables; new captures within one shape
  keep standard name/structural equality.
- Sequences match either multi-statement `Expression` shapes or the
  omitted-continuation shortcut for ordinary `let` and `guard` (not `let mut`,
  local functions, `letrec`, `defer`, or `errdefer`). `proof_let` is not a
  continuation owner and remains independently matchable.

## Exactness rules

- Most nodes require identical `NodeKind`, identical semantic child count, and
  matching child labels and order.
- Argument kinds and labels must match (declared label placeholders capture
  varying labels).
- Constants compare parser kind and preserved source spelling.
- Operators, names, argument shapes, attributes, flags, open/closed patterns,
  and parser holes (by hole kind) are significant; comments, formatting,
  locations, delimiters, and trailing punctuation are ignored.
- Equivalent code with a different semantic CST shape does not match unless a
  placeholder absorbs the difference.

## Maintenance checklist

When changing placeholder names or behavior, keep all three sites synchronized:

- `internal/matching/matching.mbt`
- `internal/rule/prefilter/prefilter.mbt`
- `internal/rule/compile/compile.mbt` (reserved-name and `__TARGET__` /
  `__SOURCE__` validation)

When adding support for a new CST node:

1. Check whether `structural_match` in `match_node` already handles it; add
   specialized dispatch only if it needs custom semantics.
2. Add child-structure helpers if needed.
3. Update repeated-capture equality if a metavar can bind the node.
4. Update prefilter literal collection so rules remain searchable.
5. Add focused tests in `internal/matching/matching_test.mbt` (and
   `internal/rule/apply` or taint tests when compiled rule behavior changes).

Run `moon test internal/matching/matching_test.mbt` after matcher edits, plus
caller package tests if YAML rule behavior is affected.
