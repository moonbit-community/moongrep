///|
fn parse_expr(source : String) -> @syntax.Expr raise {
  let tokens = @lexer.tokens_from_string(
      source,
      comment=true,
      name="json matching test",
    ).tokens
  let (expr, reports) = @handrolled_parser.parse_expr(tokens)
  guard reports is [] else { fail("expected expression to parse: \{source}") }
  expr
}

///|
fn parse_expr_json(source : String) -> Json raise {
  parse_expr(source).to_json()
}

///|
fn compiled_ast(
  pattern : @syntax.Expr,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
  constant_metavars : Array[String],
) -> @matching.CompiledExprPattern {
  {
    ast: pattern,
    expr_metavars,
    identifier_metavars,
    constant_metavars,
    target_metavar: None,
    source_metavar: None,
  }
}

///|
fn assert_same_match(
  compiled : @matching.CompiledExprPattern,
  candidate : @syntax.Expr,
) -> Unit raise {
  let ast_result = @matching.match_expr_pattern(compiled, candidate) is Some(_)
  let json_result = match_expr_pattern(
      compiled_expr_pattern_to_json(compiled),
      candidate.to_json(),
    )
    is Some(_)
  assert_eq(json_result, ast_result)
}

///|
fn assert_same_expr_match(
  pattern : @syntax.Expr,
  candidate : @syntax.Expr,
) -> Unit raise {
  assert_eq(
    expr_matches(pattern.to_json(), candidate.to_json()),
    @matching.expr_matches(pattern, candidate),
  )
}

///|
fn expect_json_constant_guard_value(
  source : String,
  expected : String,
) -> Unit raise {
  let compiled = compiled_expr_pattern_to_json(
    compiled_ast(parse_expr("sink(value)"), [], [], ["value"]),
  )
  if match_expr_pattern_ast(compiled, parse_expr(source)) is Some(result) {
    match result.bindings.get("value") {
      Some(Constant(constant)) =>
        if json_constant_guard_value(constant) is Some(value) {
          inspect(value, content=expected)
        } else {
          fail("expected constant guard value")
        }
      _ => fail("expected constant binding")
    }
  } else {
    fail("expected match")
  }
}

///|
fn test_loc() -> @basic.Location {
  @syntax.no_location
}

///|
fn test_binder(name : String) -> @syntax.Binder {
  { name, loc: test_loc() }
}

///|
fn test_var(name : String) -> @syntax.Var {
  { name: @syntax.LongIdent::Ident(name~), loc: test_loc() }
}

///|
fn test_ident(name : String) -> @syntax.Expr {
  @syntax.Expr::Ident(id=test_var(name), loc=test_loc())
}

///|
fn test_pattern_var(name : String) -> @syntax.Pattern {
  @syntax.Pattern::Var(test_binder(name))
}

///|
fn test_pattern_tuple(items : Array[@syntax.Pattern]) -> @syntax.Pattern {
  @syntax.Pattern::Tuple(pats=@list.from_array(items), loc=test_loc())
}

///|
fn test_match_pattern(pattern : @syntax.Pattern) -> @syntax.Expr {
  @syntax.Expr::Match(
    expr=test_ident("input"),
    cases=@list.from_array([{ pattern, guard_: None, body: test_ident("body") }]),
    match_loc=test_loc(),
    loc=test_loc(),
  )
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
fn json_kind_for_test(value : Json) -> String? {
  match value {
    Object(fields) =>
      match fields.get("kind") {
        Some(String(kind)) => Some(kind)
        _ => None
      }
    _ => None
  }
}

///|
fn with_top_loc(node : Json, loc : Json) -> Json {
  match node {
    Object(fields) => {
      let copy = fields.copy()
      copy["loc"] = loc
      Json::object(copy)
    }
    _ => node
  }
}

///|
fn with_apply_attr(node : Json, attr : Json) -> Json {
  match node {
    Object(fields) => {
      let copy = fields.copy()
      match fields.get("children") {
        Some(Object(children)) => {
          let child_copy = children.copy()
          child_copy["attr"] = attr
          copy["children"] = Json::object(child_copy)
        }
        _ => ()
      }
      Json::object(copy)
    }
    _ => node
  }
}

///|
test "json matcher mirrors expression and ignore placeholder semantics" {
  assert_same_expr_match(parse_expr("__ + __"), parse_expr("a + b"))
  assert_same_expr_match(parse_expr("__x + __x"), parse_expr("a + a"))
  assert_same_expr_match(parse_expr("_"), parse_expr("value"))
  assert_same_expr_match(
    parse_expr("sink <| input"),
    parse_expr("sink <| input"),
  )
  assert_same_expr_match(
    parse_expr("sink <| input"),
    parse_expr("other <| input"),
  )
}

///|
test "json matcher mirrors expression identifier and constant metavars" {
  let expr_compiled = compiled_ast(parse_expr("value + value"), ["value"], [], [])
  assert_same_match(expr_compiled, parse_expr("make() + make()"))
  assert_same_match(expr_compiled, parse_expr("make() + other()"))
  assert_same_match(expr_compiled, parse_expr("make(x) + make(x)"))
  assert_same_match(expr_compiled, parse_expr("make(x) + make(y)"))
  let id_compiled = compiled_ast(
    parse_expr(
      "for counter = 0; counter < limit; counter = counter + 1 { body }",
    ),
    ["limit", "body"],
    ["counter"],
    [],
  )
  assert_same_match(
    id_compiled,
    parse_expr("for i = 0; i < n; i = i + 1 { println(i) }"),
  )
  assert_same_match(
    id_compiled,
    parse_expr("for i = 0; j < n; i = i + 1 { println(i) }"),
  )
  let constant_compiled = compiled_ast(parse_expr("value + value"), [], [], [
    "value",
  ])
  assert_same_match(constant_compiled, parse_expr("1 + 1"))
  assert_same_match(constant_compiled, parse_expr("1 + 2"))
  assert_same_match(constant_compiled, parse_expr("x + x"))
}

///|
test "json matcher supports syntax expression wrappers and guard constants" {
  let compiled = compiled_expr_pattern_to_json(
    compiled_ast(parse_expr("callee(value)"), [], ["callee"], ["value"]),
  )
  let initial : @hashmap.HashMap[String, JsonBoundValue] = @hashmap.HashMap([])
  initial["callee"] = Identifier("sink")
  assert_true(
    match_expr_pattern_ast_with_bindings(
      compiled,
      parse_expr("sink(42)"),
      initial,
    )
    is Some(_),
  )
  assert_true(
    match_expr_pattern_ast_with_bindings(
      compiled,
      parse_expr("other(42)"),
      initial,
    )
    is None,
  )
  expect_json_constant_guard_value("sink(42)", "42")
  expect_json_constant_guard_value("sink(true)", "true")
  expect_json_constant_guard_value("sink(\"raw\")", "raw")
}

///|
test "json matcher mirrors pattern metavars and constant patterns" {
  let pattern_compiled = compiled_ast(
    test_match_pattern(test_pattern_var("$(item:pat)")),
    ["input", "body"],
    [],
    [],
  )
  let json_compiled = compiled_expr_pattern_to_json(pattern_compiled)
  if match_expr_pattern(
      json_compiled,
      parse_expr_json("match value { Some(actual) => ok }"),
    )
    is Some(result) {
    match result.bindings.get("item") {
      Some(JsonBoundValue::Pattern(pattern)) =>
        assert_true(json_kind_for_test(pattern) == Some("Pattern::Constr"))
      _ => fail("expected pattern binding")
    }
  } else {
    fail("expected match")
  }
  let repeated_pattern_compiled = compiled_ast(
    test_match_pattern(
      test_pattern_tuple([
        test_pattern_var("$(item:pat)"),
        test_pattern_var("$(item:pat)"),
      ]),
    ),
    ["input", "body"],
    [],
    [],
  )
  assert_same_match(
    repeated_pattern_compiled,
    parse_expr("match value { (Some(actual), Some(actual)) => ok }"),
  )
  assert_same_match(
    repeated_pattern_compiled,
    parse_expr("match value { (Some(actual), Some(other)) => ok }"),
  )
  let constant_pattern_compiled = compiled_ast(
    parse_expr("match input { lit => lit }"),
    ["input"],
    [],
    ["lit"],
  )
  assert_same_match(
    constant_pattern_compiled,
    parse_expr("match value { 1 => 1 }"),
  )
  assert_same_match(
    constant_pattern_compiled,
    parse_expr("match value { 1 => 2 }"),
  )
  assert_same_match(
    constant_pattern_compiled,
    parse_expr("match value { item => item }"),
  )
}

///|
test "json matcher mirrors qualified identifiers constructors and labels" {
  let qualified = compiled_ast(parse_expr("callee(callee)"), [], ["callee"], [])
  assert_same_match(qualified, parse_expr("@int.abs(@int.abs)"))
  assert_same_match(qualified, parse_expr("@int.abs(abs)"))
  let package_literal = compiled_ast(
    parse_expr("@int.callee(callee)"),
    [],
    ["callee"],
    [],
  )
  assert_same_match(package_literal, parse_expr("@int.abs(@int.abs)"))
  assert_same_match(package_literal, parse_expr("@float.abs(@float.abs)"))
  let constr_compiled = compiled_ast(parse_expr("Ctor(Ctor)"), [], ["Ctor"], [])
  assert_same_match(constr_compiled, parse_expr("@pkg.Actual(@pkg.Actual)"))
  assert_same_match(constr_compiled, parse_expr("@pkg.Actual(Actual)"))
  let typed_constructor = compiled_ast(
    parse_expr("TypeName::Ctor(Ctor)"),
    [],
    ["TypeName", "Ctor"],
    [],
  )
  assert_same_match(
    typed_constructor,
    parse_expr("@pkg.Option::Some(@pkg.Option::Some)"),
  )
  assert_same_match(
    typed_constructor,
    parse_expr("@pkg.Option::Some(Option::Some)"),
  )
  let label = compiled_ast(
    parse_expr("record.field + record.field"),
    ["record"],
    ["field"],
    [],
  )
  assert_same_match(label, parse_expr("item.name + item.name"))
  assert_same_match(label, parse_expr("item.name + item.other"))
}

///|
test "json matcher mirrors structural scalar roots and newer expression forms" {
  assert_same_expr_match(parse_expr("a + b"), parse_expr("a - b"))
  assert_same_expr_match(parse_expr("f(label=a)"), parse_expr("f(other=a)"))
  assert_same_expr_match(parse_expr("obj.field"), parse_expr("obj.other"))
  assert_same_expr_match(parse_expr("1"), parse_expr("2"))
  assert_same_expr_match(
    parse_expr("@http.Client::new(__)"),
    parse_expr("@http.Server::new(1)"),
  )
  assert_same_expr_match(parse_expr("Text(__)"), parse_expr("Blank"))
  let list_pattern = parse_expr(
    "[for item in items if allow(item) => target(item)]",
  )
  assert_same_expr_match(
    list_pattern,
    parse_expr("[for item in items if allow(item) => target(item)]"),
  )
  assert_same_expr_match(
    list_pattern,
    parse_expr("[for item in items if allow(item) => other(item)]"),
  )
  let foreach_pattern = test_foreach("seed", "step", "where_value")
  assert_same_expr_match(
    foreach_pattern,
    test_foreach("seed", "step", "where_value"),
  )
  assert_same_expr_match(
    foreach_pattern,
    test_foreach("other", "step", "where_value"),
  )
  assert_same_expr_match(
    foreach_pattern,
    test_foreach("seed", "other", "where_value"),
  )
  assert_same_expr_match(foreach_pattern, test_foreach("seed", "step", "other"))
}

///|
test "json matcher mirrors let omitted body semantics" {
  let pattern = parse_expr("let (__, __) = __")
  assert_same_expr_match(
    pattern,
    parse_expr("let (fst, snd) = tuple; use(fst, snd)"),
  )
  assert_same_expr_match(
    pattern,
    parse_expr("let (fst, snd) = tuple; { consume(fst); snd }"),
  )
  assert_same_expr_match(
    parse_expr("let (__, __) = __; finish(__)"),
    parse_expr("let (fst, snd) = tuple; other(fst)"),
  )
}

///|
test "json matcher ignores loc and parser-only apply attr" {
  let loc_a = @json.parse("{\"line\":1,\"col\":2}")
  let loc_b = @json.parse("{\"line\":9,\"col\":8}")
  assert_true(
    expr_matches(
      with_top_loc(parse_expr_json("x + 1"), loc_a),
      with_top_loc(parse_expr_json("x + 1"), loc_b),
    ),
  )
  let attr = @json.parse(
    "{\"kind\":\"ApplyAttr::Synthetic\",\"loc\":{\"line\":1},\"children\":{}}",
  )
  assert_true(
    expr_matches(
      parse_expr_json("f(x)"),
      with_apply_attr(parse_expr_json("f(x)"), attr),
    ),
  )
}

///|
test "json matcher exact equality keeps locations significant" {
  let loc = @json.parse("{\"line\":1,\"col\":2}")
  let original = parse_expr_json("x + 1")
  let changed = with_top_loc(original, loc)
  assert_true(json_exact_equal(original, original))
  assert_false(json_exact_equal(original, changed))
  assert_true(expr_matches(original, changed))
}

///|
test "json matcher rejects malformed json without mutating caller bindings" {
  let malformed = Json::object({ "kind": Json::string("Expr::Ident") })
  assert_false(expr_matches(malformed, parse_expr_json("x")))
  let compiled = compiled_expr_pattern_to_json(
    compiled_ast(parse_expr("value + expected"), ["value"], [], []),
  )
  let initial : @hashmap.HashMap[String, JsonBoundValue] = @hashmap.HashMap([])
  assert_true(
    match_expr_pattern_with_bindings(
      compiled,
      parse_expr_json("actual + other"),
      initial,
    )
    is None,
  )
  inspect(initial.length(), content="0")
}
