///|
/// A compiled structural pattern.
///
/// `ast` is the untyped AST node for the parsed pattern expression or, for an
/// `inside-toplevel` context, the parsed top-level item.
/// `expr_metavars` bind whole expression AST nodes, `identifier_metavars`
/// bind normalized identifier strings encoded as leaf string nodes, and
/// `constant_metavars` bind literal constant nodes, and `arg_metavars` bind
/// whole call argument AST nodes. `type_metavars` bind whole type AST nodes.
/// Pattern metavars are represented directly in `ast` as `$(name:pat)` pattern
/// variables and bind whole pattern AST nodes.
/// `ellipsis_metavars` describe named `$$$name` / `$$$(name:kind)` list-item
/// sequence captures. Anonymous ellipses are represented only in `ast`.
/// `target_metavar` and `source_metavar` are reserved bare-expression
/// placeholders injected by the rules package for `__TARGET__` and
/// `__SOURCE__`.
pub(all) struct CompiledExprPattern {
  ast : @untyped_ast.Node
  expr_metavars : Array[String]
  identifier_metavars : Array[String]
  constant_metavars : Array[String]
  arg_metavars : Array[String]
  type_metavars : Array[String]
  ellipsis_metavars : Array[EllipsisMetavar]
  target_metavar : String?
  source_metavar : String?
}

///|
/// The per-item constraint applied by an ellipsis metavar.
pub(all) enum EllipsisMetavarKind {
  AnyItem
  ExpItem
  IdItem
  ConstItem
  ArgItem
  PatItem
  TypeItem
} derive(Eq)

///|
/// A named ellipsis metavar discovered while compiling a pattern.
pub(all) struct EllipsisMetavar {
  name : String
  kind : EllipsisMetavarKind
}

///|
/// Values captured while matching a `CompiledExprPattern`.
///
/// Ordinary metavars use `Single`. Expression,
/// constant, argument, type, and pattern metavars capture their matched nodes.
/// Identifier metavars capture their normalized name in a `Leaf(PString(_))`
/// node. Ellipsis metavars use `Multiple` and retain the complete sibling nodes
/// from the candidate list.
pub(all) enum BoundValue {
  Single(@untyped_ast.Node)
  Multiple(Array[@untyped_ast.Node])
}

///|
/// Result of a successful expression-pattern match.
///
/// `root` is the candidate expression node originally passed to the matcher.
/// `bindings` is the effective binding context after the match. For
/// `match_expr_pattern` it contains fresh captures; for
/// `match_expr_pattern_with_bindings` it contains a copy of the initial
/// bindings plus any new captures.
pub(all) struct ExprMatch {
  root : @untyped_ast.Node
  bindings : @hashmap.HashMap[String, BoundValue]
}
