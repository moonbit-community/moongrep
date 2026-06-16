///|
fn parse_expr(source : String) -> @syntax.Expr raise {
  let tokens = @lexer.tokens_from_string(
      source,
      comment=true,
      name="matching test",
    ).tokens
  let (expr, reports) = @handrolled_parser.parse_expr(tokens)
  guard reports is [] else { fail("expected expression to parse: \{source}") }
  expr
}

///|
fn test_loc() -> @basic.Location {
  @syntax.no_location
}

///|
fn test_var(name : String) -> @syntax.Var {
  { name: @syntax.LongIdent::Ident(name~), loc: test_loc() }
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
fn test_field_def(label : String, expr : @syntax.Expr) -> @syntax.FieldDef {
  { label: test_label(label), expr, is_pun: false, loc: test_loc() }
}

///|
fn test_ident(name : String) -> @syntax.Expr {
  @syntax.Expr::Ident(id=test_var(name), loc=test_loc())
}

///|
fn test_implies(lhs : String, rhs : String) -> @syntax.Expr {
  @syntax.Expr::Implies(
    lhs=test_ident(lhs),
    rhs=test_ident(rhs),
    loc=test_loc(),
  )
}

///|
fn test_foreach(
  init : String,
  continue_value : String,
  where_value : String,
) -> @syntax.Expr {
  @syntax.Expr::ForEach(
    binders=@list.from_array([Some(test_binder("item"))]),
    expr=test_ident("items"),
    init=@list.from_array([(test_binder("start"), test_ident(init))]),
    continue_block=@list.from_array([
      (test_binder("next"), test_ident(continue_value)),
    ]),
    body=test_ident("body"),
    else_block=None,
    where_clause=Some({
      fields: @list.from_array([
        test_field_def("field", test_ident(where_value)),
      ]),
      loc: test_loc(),
    }),
    label=None,
    loc=test_loc(),
  )
}

///|
test "undeclared double-underscore-prefixed identifier is literal" {
  let pattern = parse_expr("__x + __x")
  assert_false(expr_matches(pattern, parse_expr("a + a")))
  assert_true(expr_matches(pattern, parse_expr("__x + __x")))
}

///|
test "declared subtree metavar requires structural equality" {
  let pattern = parse_expr("__x + __x")
  let compiled : CompiledExprPattern = {
    ast: pattern,
    subtree_metavars: ["__x"],
    identifier_metavars: [],
    auto_metavars: [],
    target_metavar: None,
    source_metavar: None,
  }
  assert_true(match_expr_pattern(compiled, parse_expr("a + a")) is Some(_))
  assert_false(match_expr_pattern(compiled, parse_expr("a + b")) is Some(_))
}

///|
test "identifier metavar compares binder and uses by normalized name" {
  let pattern = parse_expr(
    "for counter = 0; counter < limit; counter = counter + 1 { body }",
  )
  let compiled : CompiledExprPattern = {
    ast: pattern,
    subtree_metavars: ["limit", "body"],
    identifier_metavars: ["counter"],
    auto_metavars: [],
    target_metavar: None,
    source_metavar: None,
  }
  assert_true(
    match_expr_pattern(
      compiled,
      parse_expr("for i = 0; i < n; i = i + 1 { println(i) }"),
    )
    is Some(_),
  )
  assert_false(
    match_expr_pattern(
      compiled,
      parse_expr("for i = 0; j < n; i = i + 1 { println(i) }"),
    )
    is Some(_),
  )
}

///|
test "auto metavar chooses identifier mode for loop counter" {
  let pattern = parse_expr(
    "for counter = 0; counter < limit; counter = counter + 1 { body }",
  )
  let compiled : CompiledExprPattern = {
    ast: pattern,
    subtree_metavars: ["limit", "body"],
    identifier_metavars: [],
    auto_metavars: ["counter"],
    target_metavar: None,
    source_metavar: None,
  }
  assert_true(
    match_expr_pattern(
      compiled,
      parse_expr("for i = 0; i < n; i = i + 1 { println(i) }"),
    )
    is Some(_),
  )
  assert_false(
    match_expr_pattern(
      compiled,
      parse_expr("for i = 0; j < n; i = i + 1 { println(i) }"),
    )
    is Some(_),
  )
}

///|
test "auto metavar chooses structural mode for repeated call expression" {
  let pattern = parse_expr("value + value")
  let compiled : CompiledExprPattern = {
    ast: pattern,
    subtree_metavars: [],
    identifier_metavars: [],
    auto_metavars: ["value"],
    target_metavar: None,
    source_metavar: None,
  }
  assert_true(
    match_expr_pattern(compiled, parse_expr("make() + make()")) is Some(_),
  )
  assert_false(
    match_expr_pattern(compiled, parse_expr("make() + other()")) is Some(_),
  )
}

///|
test "auto metavar keeps the first chosen binding kind" {
  let pattern = parse_expr("value + value")
  let compiled : CompiledExprPattern = {
    ast: pattern,
    subtree_metavars: [],
    identifier_metavars: [],
    auto_metavars: ["value"],
    target_metavar: None,
    source_metavar: None,
  }
  assert_false(
    match_expr_pattern(compiled, parse_expr("item + make()")) is Some(_),
  )
  assert_false(
    match_expr_pattern(compiled, parse_expr("make() + item")) is Some(_),
  )
}

///|
test "auto metavar matches pattern vars by identifier mode" {
  let pattern = parse_expr("match input { item => item }")
  let compiled : CompiledExprPattern = {
    ast: pattern,
    subtree_metavars: ["input"],
    identifier_metavars: [],
    auto_metavars: ["item"],
    target_metavar: None,
    source_metavar: None,
  }
  assert_true(
    match_expr_pattern(compiled, parse_expr("match value { actual => actual }"))
    is Some(_),
  )
  assert_false(
    match_expr_pattern(compiled, parse_expr("match value { actual => other }"))
    is Some(_),
  )
}

///|
test "auto metavar matches labels by identifier mode" {
  let pattern = parse_expr("record.field + record.field")
  let compiled : CompiledExprPattern = {
    ast: pattern,
    subtree_metavars: ["record"],
    identifier_metavars: [],
    auto_metavars: ["field"],
    target_metavar: None,
    source_metavar: None,
  }
  assert_true(
    match_expr_pattern(compiled, parse_expr("item.name + item.name")) is Some(_),
  )
  assert_false(
    match_expr_pattern(compiled, parse_expr("item.name + item.other"))
    is Some(_),
  )
}

///|
test "structural matcher compares scalar AST fields" {
  assert_false(expr_matches(parse_expr("a + b"), parse_expr("a - b")))
  assert_false(expr_matches(parse_expr("f(label=a)"), parse_expr("f(other=a)")))
  assert_false(expr_matches(parse_expr("obj.field"), parse_expr("obj.other")))
  assert_false(expr_matches(parse_expr("1"), parse_expr("2")))
  assert_false(
    expr_matches(
      parse_expr("@http.Client::new(__)"),
      parse_expr("@http.Server::new(1)"),
    ),
  )
  assert_false(expr_matches(parse_expr("Text(__)"), parse_expr("Blank")))
}

///|
test "structural matcher supports reverse pipe and implication roots" {
  assert_true(
    expr_matches(parse_expr("sink <| input"), parse_expr("sink <| input")),
  )
  assert_false(
    expr_matches(parse_expr("sink <| input"), parse_expr("other <| input")),
  )
  assert_true(expr_matches(test_implies("a", "b"), test_implies("a", "b")))
  assert_false(expr_matches(test_implies("a", "b"), test_implies("a", "c")))
}

///|
test "structural matcher supports list comprehension roots" {
  let pattern = parse_expr("[for item in items if allow(item) => target(item)]")
  assert_true(
    expr_matches(
      pattern,
      parse_expr("[for item in items if allow(item) => target(item)]"),
    ),
  )
  assert_false(
    expr_matches(
      pattern,
      parse_expr("[for item in items if allow(item) => other(item)]"),
    ),
  )
}

///|
test "structural matcher compares foreach init continue and where clause" {
  let pattern = test_foreach("seed", "step", "where_value")
  assert_true(
    expr_matches(pattern, test_foreach("seed", "step", "where_value")),
  )
  assert_false(
    expr_matches(pattern, test_foreach("other", "step", "where_value")),
  )
  assert_false(
    expr_matches(pattern, test_foreach("seed", "other", "where_value")),
  )
  assert_false(expr_matches(pattern, test_foreach("seed", "step", "other")))
}
