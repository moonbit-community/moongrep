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
fn test_pattern_var(name : String) -> @syntax.Pattern {
  Var(test_binder(name))
}

///|
fn test_positional_parameter(name : String) -> @syntax.Parameter {
  Positional(binder=test_binder(name), ty=None)
}

///|
fn test_func(
  parameters : Array[@syntax.Parameter],
  body : @syntax.Expr,
) -> @syntax.Func {
  {
    parameters: @list.from_array(parameters),
    params_loc: test_loc(),
    return_type: None,
    error_type: NoErrorType,
    body,
    kind: Lambda,
    is_async: None,
    loc: test_loc(),
  }
}

///|
fn test_field_def(label : String, expr : @syntax.Expr) -> @syntax.FieldDef {
  { label: test_label(label), expr, is_pun: false, loc: test_loc() }
}

///|
fn shadowed_signature(names : Array[String]) -> String {
  "[\{names.join(", ")}]"
}

///|
fn collect_shadowed_for_ident(
  expr : @syntax.Expr,
  name : String,
) -> Array[String] {
  let scoped : Array[ScopedExpr] = []
  collect_scoped_exprs(expr, scoped)
  for item in scoped {
    match item.expr {
      Ident(id=v, ..) =>
        match v.name {
          Ident(name=found) => if found == name { return item.shadowed_names }
          _ => ()
        }
      _ => ()
    }
  }
  []
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

///|
test "scoped traversal shadows let pattern only in body" {
  let expr = @syntax.Expr::Let(
    pattern=test_pattern_var("x"),
    expr=test_ident("init"),
    body=test_ident("body"),
    loc=test_loc(),
  )
  inspect(
    shadowed_signature(collect_shadowed_for_ident(expr, "init")),
    content="[]",
  )
  inspect(
    shadowed_signature(collect_shadowed_for_ident(expr, "body")),
    content="[x]",
  )
}

///|
test "scoped traversal shadows function parameters in body" {
  let expr = @syntax.Expr::Function(
    func=test_func([test_positional_parameter("x")], test_ident("body")),
    loc=test_loc(),
  )
  inspect(
    shadowed_signature(collect_shadowed_for_ident(expr, "body")),
    content="[x]",
  )
}

///|
test "scoped traversal shadows match case pattern in guard and body" {
  let expr = @syntax.Expr::Match(
    expr=test_ident("scrutinee"),
    cases=@list.from_array([
      {
        pattern: test_pattern_var("x"),
        guard_: Some(test_ident("guard")),
        body: test_ident("body"),
      },
    ]),
    match_loc=test_loc(),
    loc=test_loc(),
  )
  inspect(
    shadowed_signature(collect_shadowed_for_ident(expr, "scrutinee")),
    content="[]",
  )
  inspect(
    shadowed_signature(collect_shadowed_for_ident(expr, "guard")),
    content="[x]",
  )
  inspect(
    shadowed_signature(collect_shadowed_for_ident(expr, "body")),
    content="[x]",
  )
}
