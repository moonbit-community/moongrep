///|
/// A compiled expression pattern.
///
/// `ast` is the parsed pattern expression. `subtree_metavars` bind whole AST
/// nodes, `identifier_metavars` bind normalized identifier strings, and
/// `auto_metavars` choose either mode from the first matched candidate.
/// `target_metavar` and `source_metavar` are reserved bare-expression
/// placeholders injected by the rules package for `__TARGET__` and
/// `__SOURCE__`.
pub(all) struct CompiledExprPattern {
  ast : @syntax.Expr
  subtree_metavars : Array[String]
  identifier_metavars : Array[String]
  auto_metavars : Array[String]
  target_metavar : String?
  source_metavar : String?
}

///|
/// Values captured while matching a `CompiledExprPattern`.
///
/// Subtree metavars capture the AST node kind appropriate to the syntactic
/// position in which the metavar appears. Identifier metavars capture the
/// normalized name as `Identifier`.
pub(all) enum BoundValue {
  Expr(@syntax.Expr)
  Var(@syntax.Var)
  Binder(@syntax.Binder)
  Pattern(@syntax.Pattern)
  Label(@syntax.Label)
  Identifier(String)
}

///|
/// Result of a successful expression-pattern match.
///
/// `root` is the candidate expression originally passed to the matcher.
/// `bindings` is the effective binding context after the match. For
/// `match_expr_pattern` it contains fresh captures; for
/// `match_expr_pattern_with_bindings` it contains a copy of the initial
/// bindings plus any new captures.
pub(all) struct ExprMatch {
  root : @syntax.Expr
  bindings : @hashmap.HashMap[String, BoundValue]
}
