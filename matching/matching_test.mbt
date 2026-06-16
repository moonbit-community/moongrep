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
