///|
pub fn normalize_identifier_name_from_expr(expr : @syntax.Expr) -> String? {
  match expr {
    Ident(id~, ..) => normalize_identifier_name_from_var(id)
    _ => None
  }
}

///|
pub fn normalize_identifier_name_from_var(v : @syntax.Var) -> String? {
  match v.name {
    Ident(name~) => Some(name)
    Dot(..) => None
  }
}

///|
pub fn normalize_identifier_name_from_binder(b : @syntax.Binder) -> String? {
  Some(b.name)
}

///|
pub fn normalize_identifier_name_from_label(label : @syntax.Label) -> String? {
  Some(label.name)
}

///|
pub fn normalize_identifier_name_from_pattern(
  pattern : @syntax.Pattern,
) -> String? {
  match pattern {
    Var(binder) => normalize_identifier_name_from_binder(binder)
    _ => None
  }
}
