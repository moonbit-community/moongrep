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
  target_metavar : String?
  source_metavar : String?
}

///|
/// Values captured while matching a `CompiledExprPattern`.
///
/// Every binding is stored directly as an untyped AST node. Expression,
/// constant, argument, type, and pattern metavars capture their matched nodes.
/// Identifier metavars capture their normalized name in a `Leaf(PString(_))`
/// node.
pub type BoundValue = @untyped_ast.Node

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
