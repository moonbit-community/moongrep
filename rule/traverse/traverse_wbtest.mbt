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
test "traverse counts foreach init continue and where clause expressions" {
  let target = test_ident("__TARGET__")
  let expr = @syntax.Expr::ForEach(
    binders=@list.from_array([Some(test_binder("item"))]),
    expr=test_ident("items"),
    init=@list.from_array([(test_binder("init"), target)]),
    continue_block=@list.from_array([(test_binder("next"), target)]),
    body=test_ident("body"),
    else_block=None,
    where_clause=Some({
      fields: @list.from_array([test_field_def("field", target)]),
      loc: test_loc(),
    }),
    label=None,
    loc=test_loc(),
  )
  assert_eq(count_supported_name_in_expr(expr, "__TARGET__"), 3)
  let collected : Array[@syntax.Expr] = []
  collect_exprs(expr, collected)
  assert_eq(collected.length(), 6)
}
