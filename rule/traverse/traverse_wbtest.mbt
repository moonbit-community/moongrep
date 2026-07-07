///|
fn test_loc() -> @basic.Location {
  @syntax.no_location
}

///|
fn test_binder(name : String) -> @syntax.Binder {
  { name, loc: test_loc() }
}

///|
fn test_label(name : String) -> @syntax.Label {
  { name, loc: test_loc() }
}

///|
fn test_var(name : String) -> @syntax.Var {
  { name: Ident(name~), loc: test_loc() }
}

///|
fn test_ident(name : String) -> @syntax.Expr {
  Ident(id=test_var(name), loc=test_loc())
}

///|
fn test_field_def(label : String, expr : @syntax.Expr) -> @syntax.FieldDef {
  { label: test_label(label), expr, is_pun: false, loc: test_loc() }
}

///|
test "traverse counts supported names in node expressions" {
  let target = test_ident("__TARGET__")
  let expr = @syntax.Expr::ForEach(
    binders=List([Some(test_binder("item"))]),
    expr=test_ident("items"),
    init=List([(test_binder("init"), target)]),
    continue_block=List([(test_binder("next"), target)]),
    body=test_ident("body"),
    else_block=None,
    where_clause=Some({
      fields: List([test_field_def("field", target)]),
      loc: test_loc(),
    }),
    label=None,
    loc=test_loc(),
  )
  assert_eq(
    count_supported_name_in_node(@untyped_ast.from_expr(expr), "__TARGET__"),
    3,
  )
}

///|
test "traverse counts expression identifiers once" {
  assert_eq(
    count_supported_name_in_node(
      @untyped_ast.from_expr(test_ident("target")),
      "target",
    ),
    1,
  )
}
