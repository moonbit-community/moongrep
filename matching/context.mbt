///|
pub(all) struct CompiledExprPattern {
  ast : @syntax.Expr
  subtree_metavars : Array[String]
  identifier_metavars : Array[String]
  target_metavar : String?
  source_metavar : String?
}

///|
pub(all) enum BoundValue {
  Expr(@syntax.Expr)
  Var(@syntax.Var)
  Binder(@syntax.Binder)
  Pattern(@syntax.Pattern)
  Label(@syntax.Label)
  Identifier(String)
}

///|
pub(all) struct ExprMatch {
  root : @syntax.Expr
  bindings : @hashmap.HashMap[String, BoundValue]
}
