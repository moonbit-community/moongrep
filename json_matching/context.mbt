///|
/// A compiled expression pattern over parser AST JSON.
///
/// `ast` is expected to have the same shape as `@syntax.Expr::to_json()`.
/// Metavar arrays mirror `@matching.CompiledExprPattern`.
pub(all) struct CompiledJsonExprPattern {
  ast : Json
  expr_metavars : Array[String]
  identifier_metavars : Array[String]
  constant_metavars : Array[String]
  target_metavar : String?
  source_metavar : String?
}

///|
/// Values captured while matching a `CompiledJsonExprPattern`.
pub(all) enum JsonBoundValue {
  Expr(Json)
  Identifier(String)
  Constant(Json)
  Pattern(Json)
}

///|
/// Result of a successful JSON expression-pattern match.
pub(all) struct JsonExprMatch {
  root : Json
  bindings : @hashmap.HashMap[String, JsonBoundValue]
}
