///|
fn parse_expr(source : String) -> @syntax.Expr raise {
  let tokens = @lexer.tokens_from_string(source, comment=true, name="matching test").tokens
  let (expr, reports) = @handrolled_parser.parse_expr(tokens)
  guard reports is [] else {
    fail("expected expression to parse: \{source}")
  }
  expr
}

///|
test "undeclared double-underscore identifier is literal" {
  let pattern = parse_expr("__x + __x")
  inspect(expr_matches(pattern, parse_expr("a + a")), content="false")
  inspect(expr_matches(pattern, parse_expr("__x + __x")), content="true")
}

///|
test "declared subtree metavar requires structural equality" {
  let pattern = parse_expr("__x + __x")
  let compiled : CompiledExprPattern = {
    ast: pattern,
    subtree_metavars: ["__x"],
    identifier_metavars: [],
    target_metavar: None,
    source_metavar: None,
  }
  inspect(
    match_expr_pattern(compiled, parse_expr("a + a")) is Some(_),
    content="true",
  )
  inspect(
    match_expr_pattern(compiled, parse_expr("a + b")) is Some(_),
    content="false",
  )
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
    target_metavar: None,
    source_metavar: None,
  }
  inspect(
    match_expr_pattern(
      compiled,
      parse_expr("for i = 0; i < n; i = i + 1 { println(i) }"),
    ) is Some(_),
    content="true",
  )
  inspect(
    match_expr_pattern(
      compiled,
      parse_expr("for i = 0; j < n; i = i + 1 { println(i) }"),
    ) is Some(_),
    content="false",
  )
}

///|
test "structural matcher compares scalar AST fields" {
  inspect(expr_matches(parse_expr("a + b"), parse_expr("a - b")), content="false")
  inspect(
    expr_matches(parse_expr("f(label=a)"), parse_expr("f(other=a)")),
    content="false",
  )
  inspect(
    expr_matches(parse_expr("obj.field"), parse_expr("obj.other")),
    content="false",
  )
  inspect(expr_matches(parse_expr("1"), parse_expr("2")), content="false")
  inspect(
    expr_matches(
      parse_expr("@http.Client::new(__)"),
      parse_expr("@http.Server::new(1)"),
    ),
    content="false",
  )
  inspect(
    expr_matches(parse_expr("Text(__)"), parse_expr("Blank")),
    content="false",
  )
}
