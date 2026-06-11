///|
/// Returns the normalized name when `expr` is a bare identifier expression.
///
/// This only handles `Expr::Ident` whose parser `Var.name` is
/// `LongIdent::Ident`. Package-qualified `LongIdent::Dot` vars intentionally
/// return `None`; field, method, and argument labels are normalized through
/// `normalize_identifier_name_from_label`.
pub fn normalize_identifier_name_from_expr(expr : @syntax.Expr) -> String? {
  match expr {
    Ident(id~, ..) => normalize_identifier_name_from_var(id)
    _ => None
  }
}

///|
/// Returns the simple identifier name stored in a parser `Var`.
///
/// Package-qualified `LongIdent::Dot` names return `None`; callers that need
/// package-qualified semantics should inspect the parser node directly.
pub fn normalize_identifier_name_from_var(v : @syntax.Var) -> String? {
  match v.name {
    Ident(name~) => Some(name)
    Dot(..) => None
  }
}

///|
/// Returns the binder name exactly as parsed.
pub fn normalize_identifier_name_from_binder(b : @syntax.Binder) -> String? {
  Some(b.name)
}

///|
/// Returns the label name exactly as parsed.
pub fn normalize_identifier_name_from_label(label : @syntax.Label) -> String? {
  Some(label.name)
}

///|
/// Returns the bound variable name when `pattern` is `Pattern::Var`.
///
/// All other patterns return `None` so matcher code can decide how deeply to
/// inspect them for metavars.
pub fn normalize_identifier_name_from_pattern(
  pattern : @syntax.Pattern,
) -> String? {
  match pattern {
    Var(binder) => normalize_identifier_name_from_binder(binder)
    _ => None
  }
}
