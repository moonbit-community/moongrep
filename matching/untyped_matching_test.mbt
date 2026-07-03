///|
fn parse_untyped_test_expr(source : String) -> @syntax.Expr raise {
  let tokens = @lexer.tokens_from_string(
      source,
      comment=true,
      name="untyped matching test",
    ).tokens
  let (expr, reports) = @handrolled_parser.parse_expr(tokens)
  guard reports is [] else { fail("expected expression to parse: \{source}") }
  expr
}

///|
fn parse_untyped_test_node(source : String) -> @untyped_ast.Node raise {
  @untyped_ast.from_expr(parse_untyped_test_expr(source))
}

///|
fn untyped_compiled(
  ast : @untyped_ast.Node,
  expr_metavars? : Array[String] = [],
  identifier_metavars? : Array[String] = [],
  constant_metavars? : Array[String] = [],
  target_metavar? : String? = None,
  source_metavar? : String? = None,
) -> CompiledExprPattern {
  {
    ast,
    expr_metavars,
    identifier_metavars,
    constant_metavars,
    target_metavar,
    source_metavar,
  }
}

///|
fn untyped_test_loc() -> @basic.Location {
  @syntax.no_location
}

///|
fn untyped_test_binder(name : String) -> @syntax.Binder {
  { name, loc: untyped_test_loc() }
}

///|
fn untyped_test_pattern_var(name : String) -> @syntax.Pattern {
  Var(untyped_test_binder(name))
}

///|
fn untyped_test_pattern_tuple(
  items : Array[@syntax.Pattern],
) -> @syntax.Pattern {
  Tuple(pats=@list.from_array(items), loc=untyped_test_loc())
}

///|
fn untyped_test_ident(name : String) -> @syntax.Expr {
  @syntax.Expr::Ident(
    id={ name: @syntax.LongIdent::Ident(name~), loc: untyped_test_loc() },
    loc=untyped_test_loc(),
  )
}

///|
fn untyped_test_match_pattern(pattern : @syntax.Pattern) -> @syntax.Expr {
  Match(
    expr=untyped_test_ident("input"),
    cases=@list.from_array([
      { pattern, guard_: None, body: untyped_test_ident("body") },
    ]),
    match_loc=untyped_test_loc(),
    loc=untyped_test_loc(),
  )
}

///|
fn untyped_test_match_pattern_node(
  pattern : @syntax.Pattern,
) -> @untyped_ast.Node {
  @untyped_ast.from_expr(untyped_test_match_pattern(pattern))
}

///|
fn untyped_match(
  compiled : CompiledExprPattern,
  candidate : String,
) -> ExprMatch? raise {
  match_expr_pattern(compiled, parse_untyped_test_node(candidate))
}

///|
test "default matcher compares untyped structural equality" {
  assert_true(
    expr_matches(
      parse_untyped_test_node("f(1, x)"),
      parse_untyped_test_node("f(1, x)"),
    ),
  )
  assert_false(
    expr_matches(
      parse_untyped_test_node("f(1, x)"),
      parse_untyped_test_node("f(2, x)"),
    ),
  )
}

///|
test "default matcher binds repeated expression metavars" {
  let compiled = untyped_compiled(parse_untyped_test_node("value + value"), expr_metavars=[
    "value",
  ])
  assert_true(untyped_match(compiled, "make() + make()") is Some(_))
  assert_false(untyped_match(compiled, "make() + other()") is Some(_))
}

///|
test "default matcher normalizes identifier metavars" {
  let compiled = untyped_compiled(
    parse_untyped_test_node("@int.callee(callee)"),
    identifier_metavars=["callee"],
  )
  if untyped_match(compiled, "@int.abs(@int.abs)") is Some(result) {
    match result.bindings.get("callee") {
      Some(node) =>
        match node.kind {
          Leaf(PString(value)) => inspect(value, content="@int.abs")
          _ => fail("expected identifier binding to be a leaf string node")
        }
      _ => fail("expected identifier binding")
    }
  } else {
    fail("expected identifier metavariable match")
  }
  assert_false(untyped_match(compiled, "@float.abs(@float.abs)") is Some(_))
  assert_false(untyped_match(compiled, "@int.abs(abs)") is Some(_))
}

///|
test "default matcher binds constants and preserves guard values" {
  let compiled = untyped_compiled(
    parse_untyped_test_node("match input { lit => lit }"),
    expr_metavars=["input"],
    constant_metavars=["lit"],
  )
  if untyped_match(compiled, "match value { 1 => 1 }") is Some(result) {
    match result.bindings.get("lit") {
      Some(node) => assert_true(node.kind == Constant_Int)
      _ => fail("expected constant binding")
    }
  } else {
    fail("expected match")
  }
  assert_false(untyped_match(compiled, "match value { 1 => 2 }") is Some(_))
  assert_false(
    untyped_match(compiled, "match value { item => item }") is Some(_),
  )
}

///|
test "default matcher captures repeated pattern metavars" {
  let compiled = untyped_compiled(
    untyped_test_match_pattern_node(
      untyped_test_pattern_tuple([
        untyped_test_pattern_var("$(item:pat)"),
        untyped_test_pattern_var("$(item:pat)"),
      ]),
    ),
    expr_metavars=["input", "body"],
  )
  assert_true(
    untyped_match(
      compiled, "match value { (Some(actual), Some(actual)) => ok }",
    )
    is Some(_),
  )
  assert_false(
    untyped_match(compiled, "match value { (Some(actual), Some(other)) => ok }")
    is Some(_),
  )
}

///|
test "default matcher supports target and source placeholders" {
  let target_compiled = untyped_compiled(
    parse_untyped_test_node("__TARGET__"),
    target_metavar=Some("__TARGET__"),
  )
  if untyped_match(target_compiled, "sink(value)") is Some(result) {
    match result.bindings.get("__TARGET__") {
      Some(expr) =>
        assert_true(expr_matches(expr, parse_untyped_test_node("sink(value)")))
      _ => fail("expected target expression binding")
    }
  } else {
    fail("expected target placeholder match")
  }
  let source_compiled = untyped_compiled(
    parse_untyped_test_node("__SOURCE__"),
    source_metavar=Some("__SOURCE__"),
  )
  assert_true(untyped_match(source_compiled, "source()") is Some(_))
}

///|
test "node matcher accepts nodes and captures constant nodes" {
  let compiled : CompiledExprPattern = {
    ast: parse_untyped_test_node("match input { lit => lit }"),
    expr_metavars: ["input"],
    identifier_metavars: [],
    constant_metavars: ["lit"],
    target_metavar: None,
    source_metavar: None,
  }
  if match_expr_pattern(
      compiled,
      parse_untyped_test_node("match value { 1 => 1 }"),
    )
    is Some(result) {
    match result.bindings.get("lit") {
      Some(node) => assert_true(node.kind == Constant_Int)
      _ => fail("expected constant node binding")
    }
  } else {
    fail("expected match")
  }
}
