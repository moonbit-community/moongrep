///|
fn parse_expr(source : String) -> @syntax.Expr raise {
  let tokens = @lexer.tokens_from_string(source, comment=true, name="ident test").tokens
  let (expr, reports) = @handrolled_parser.parse_expr(tokens)
  guard reports is [] else {
    fail("expected expression to parse")
  }
  expr
}

///|
fn sample_loc() -> @basic.Location {
  try! parse_expr("target").loc()
}

///|
fn sample_var(name : String) -> @syntax.Var {
  { loc: sample_loc(), name: Ident(name~) }
}

///|
fn sample_binder(name : String) -> @syntax.Binder {
  { loc: sample_loc(), name }
}

///|
test "normalizes supported identifier positions" {
  let ident_var = sample_var("target")
  let binder = sample_binder("target")
  let label : @syntax.Label = { loc: sample_loc(), name: "target" }
  let expr = @syntax.Expr::Ident(id=ident_var, loc=sample_loc())
  let pattern = @syntax.Pattern::Var(binder)
  debug_inspect(
    normalize_identifier_name_from_var(ident_var),
    content="Some(\"target\")",
  )
  debug_inspect(
    normalize_identifier_name_from_binder(binder),
    content="Some(\"target\")",
  )
  debug_inspect(
    normalize_identifier_name_from_label(label),
    content="Some(\"target\")",
  )
  debug_inspect(
    normalize_identifier_name_from_expr(expr),
    content="Some(\"target\")",
  )
  debug_inspect(
    normalize_identifier_name_from_pattern(pattern),
    content="Some(\"target\")",
  )
}

///|
test "qualified long identifiers are not normalized" {
  let qualified : @syntax.Var = {
    loc: sample_loc(),
    name: Dot(pkg="pkg", id="target"),
  }
  let expr = @syntax.Expr::Ident(id=qualified, loc=sample_loc())
  debug_inspect(normalize_identifier_name_from_var(qualified), content="None")
  debug_inspect(normalize_identifier_name_from_expr(expr), content="None")
}
