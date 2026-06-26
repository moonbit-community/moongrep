///|
/// A compiled expression pattern.
///
/// `ast` is the parsed pattern expression. `expr_metavars` bind whole
/// expression AST nodes, `identifier_metavars` bind normalized identifier
/// strings, and `constant_metavars` bind literal constants.
/// `target_metavar` and `source_metavar` are reserved bare-expression
/// placeholders injected by the rules package for `__TARGET__` and
/// `__SOURCE__`.
pub(all) struct CompiledExprPattern {
  ast : @syntax.Expr
  expr_metavars : Array[String]
  identifier_metavars : Array[String]
  constant_metavars : Array[String]
  target_metavar : String?
  source_metavar : String?
}

///|
/// Values captured while matching a `CompiledExprPattern`.
///
/// Expression metavars capture whole expressions. Identifier metavars capture
/// the normalized name as `Identifier`. Constant metavars capture parser
/// constants.
pub(all) enum BoundValue {
  Expr(@syntax.Expr)
  Identifier(String)
  Constant(@syntax.Constant)
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
