///|
fn parse_syntax_expr(source : String) -> @syntax.Expr raise {
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
fn parse_expr(source : String) -> @untyped_ast.Node raise {
  @untyped_ast.from_expr(parse_syntax_expr(source))
}

///|
fn test_loc() -> @basic.Location {
  @syntax.no_location
}

///|
fn test_var(name : String) -> @syntax.Var {
  { name: Ident(name~), loc: test_loc() }
}

///|
fn test_binder(name : String) -> @syntax.Binder {
  { name, loc: test_loc() }
}

///|
fn test_pattern_var(name : String) -> @syntax.Pattern {
  Var(test_binder(name))
}

///|
fn test_pattern_tuple(items : Array[@syntax.Pattern]) -> @syntax.Pattern {
  Tuple(pats=List(items), loc=test_loc())
}

///|
fn test_match_pattern(pattern : @syntax.Pattern) -> @untyped_ast.Node {
  @untyped_ast.from_expr(
    Match(
      expr=test_ident("input"),
      cases=List([{ pattern, guard_: None, body: test_ident("body") }]),
      match_loc=test_loc(),
      loc=test_loc(),
    ),
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
fn test_ident(name : String) -> @syntax.Expr {
  Ident(id=test_var(name), loc=test_loc())
}

///|
fn test_implies(lhs : String, rhs : String) -> @untyped_ast.Node {
  @untyped_ast.from_expr(
    Implies(lhs=test_ident(lhs), rhs=test_ident(rhs), loc=test_loc()),
  )
}

///|
fn test_foreach_syntax(
  init : String,
  continue_value : String,
  where_value : String,
) -> @syntax.Expr {
  ForEach(
    binders=List([Some(test_binder("item"))]),
    expr=test_ident("items"),
    init=List([(test_binder("start"), test_ident(init))]),
    continue_block=List([(test_binder("next"), test_ident(continue_value))]),
    body=test_ident("body"),
    else_block=None,
    where_clause=Some({
      fields: List([test_field_def("field", test_ident(where_value))]),
      loc: test_loc(),
    }),
    label=None,
    loc=test_loc(),
  )
}

///|
fn test_foreach(
  init : String,
  continue_value : String,
  where_value : String,
) -> @untyped_ast.Node {
  @untyped_ast.from_expr(test_foreach_syntax(init, continue_value, where_value))
}

///|
fn test_node_child(
  node : @untyped_ast.Node,
  name : String,
) -> @untyped_ast.Node? {
  for entry in node.children {
    let (child_name, value) = entry
    if child_name == Some(name) {
      return Some(value)
    }
  }
  None
}

///|
fn test_node_leaf_string(node : @untyped_ast.Node) -> String? {
  match node.kind {
    Leaf(PString(value)) => Some(value)
    _ => None
  }
}

///|
fn test_pattern_constructor_name(node : @untyped_ast.Node) -> String? {
  guard node.kind == Pattern_Constr else { return None }
  guard test_node_child(node, "constr") is Some(constr) else { return None }
  guard test_node_child(constr, "name") is Some(name_node) else { return None }
  guard test_node_child(name_node, "name") is Some(name_leaf) else {
    return None
  }
  test_node_leaf_string(name_leaf)
}

///|
test "undeclared double-underscore-prefixed identifier is literal" {
  let pattern = parse_expr("__x + __x")
  assert_false(expr_matches(pattern, parse_expr("a + a")))
  assert_true(expr_matches(pattern, parse_expr("__x + __x")))
}

///|
test "expression hole is literal instead of wildcard" {
  let pattern = parse_expr("_")
  assert_false(expr_matches(pattern, parse_expr("value")))
  assert_true(expr_matches(pattern, parse_expr("_")))
}

///|
test "declared expression metavar requires structural equality" {
  let pattern = parse_expr("__x + __x")
  let compiled : CompiledExprPattern = {
    ast: pattern,
    expr_metavars: ["__x"],
    identifier_metavars: [],
    constant_metavars: [],
    arg_metavars: [],
    type_metavars: [],
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
    expr_metavars: ["limit", "body"],
    identifier_metavars: ["counter"],
    constant_metavars: [],
    arg_metavars: [],
    type_metavars: [],
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
test "identifier metavar matches loop counter" {
  let pattern = parse_expr(
    "for counter = 0; counter < limit; counter = counter + 1 { body }",
  )
  let compiled : CompiledExprPattern = {
    ast: pattern,
    expr_metavars: ["limit", "body"],
    identifier_metavars: ["counter"],
    constant_metavars: [],
    arg_metavars: [],
    type_metavars: [],
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
test "expression metavar matches repeated call expression" {
  let pattern = parse_expr("value + value")
  let compiled : CompiledExprPattern = {
    ast: pattern,
    expr_metavars: ["value"],
    identifier_metavars: [],
    constant_metavars: [],
    arg_metavars: [],
    type_metavars: [],
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
test "expression metavar keeps structural equality" {
  let pattern = parse_expr("value + value")
  let compiled : CompiledExprPattern = {
    ast: pattern,
    expr_metavars: ["value"],
    identifier_metavars: [],
    constant_metavars: [],
    arg_metavars: [],
    type_metavars: [],
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
test "constant metavar requires repeated constant equality" {
  let pattern = parse_expr("value + value")
  let compiled : CompiledExprPattern = {
    ast: pattern,
    expr_metavars: [],
    identifier_metavars: [],
    constant_metavars: ["value"],
    arg_metavars: [],
    type_metavars: [],
    target_metavar: None,
    source_metavar: None,
  }
  assert_true(match_expr_pattern(compiled, parse_expr("1 + 1")) is Some(_))
  assert_false(match_expr_pattern(compiled, parse_expr("1 + 2")) is Some(_))
  assert_false(match_expr_pattern(compiled, parse_expr("x + x")) is Some(_))
}

///|
test "constant metavar matches only constant patterns" {
  let pattern = parse_expr("match input { lit => lit }")
  let compiled : CompiledExprPattern = {
    ast: pattern,
    expr_metavars: ["input"],
    identifier_metavars: [],
    constant_metavars: ["lit"],
    arg_metavars: [],
    type_metavars: [],
    target_metavar: None,
    source_metavar: None,
  }
  assert_true(
    match_expr_pattern(compiled, parse_expr("match value { 1 => 1 }"))
    is Some(_),
  )
  assert_false(
    match_expr_pattern(compiled, parse_expr("match value { 1 => 2 }"))
    is Some(_),
  )
  assert_false(
    match_expr_pattern(compiled, parse_expr("match value { item => item }"))
    is Some(_),
  )
}

///|
test "argument metavar captures complete argument nodes" {
  let compiled : CompiledExprPattern = {
    ast: parse_expr("sink(arg)"),
    expr_metavars: [],
    identifier_metavars: [],
    constant_metavars: [],
    arg_metavars: ["arg"],
    type_metavars: [],
    target_metavar: None,
    source_metavar: None,
  }
  for
    source in [
      "sink(value)", "sink(label=value)", "sink(label~)", "sink(label?=value)", "sink(label?)",
    ] {
    match match_expr_pattern(compiled, parse_expr(source)) {
      Some(result) =>
        match result.bindings.get("arg") {
          Some(node) => assert_true(node.kind == Argument)
          _ => fail("expected argument binding")
        }
      None => fail("expected argument metavar to match \{source}")
    }
  }
  assert_false(match_expr_pattern(compiled, parse_expr("sink()")) is Some(_))
  assert_false(
    match_expr_pattern(compiled, parse_expr("sink(value, other)")) is Some(_),
  )
}

///|
test "argument metavar requires repeated argument equality" {
  let compiled : CompiledExprPattern = {
    ast: parse_expr("sink(arg, arg)"),
    expr_metavars: [],
    identifier_metavars: [],
    constant_metavars: [],
    arg_metavars: ["arg"],
    type_metavars: [],
    target_metavar: None,
    source_metavar: None,
  }
  assert_true(
    match_expr_pattern(compiled, parse_expr("sink(value, value)")) is Some(_),
  )
  assert_true(
    match_expr_pattern(compiled, parse_expr("sink(label=value, label=value)"))
    is Some(_),
  )
  assert_false(
    match_expr_pattern(compiled, parse_expr("sink(value, other)")) is Some(_),
  )
  assert_false(
    match_expr_pattern(compiled, parse_expr("sink(label=value, other=value)"))
    is Some(_),
  )
}

///|
test "pattern metavar captures whole pattern AST" {
  let compiled : CompiledExprPattern = {
    ast: test_match_pattern(test_pattern_var("$(item:pat)")),
    expr_metavars: ["input", "body"],
    identifier_metavars: [],
    constant_metavars: [],
    arg_metavars: [],
    type_metavars: [],
    target_metavar: None,
    source_metavar: None,
  }
  if match_expr_pattern(
      compiled,
      parse_expr("match value { Some(actual) => ok }"),
    )
    is Some(result) {
    match result.bindings.get("item") {
      Some(node) => {
        guard test_pattern_constructor_name(node) is Some(name) else {
          fail("expected constructor pattern binding")
        }
        inspect(name, content="Some")
      }
      _ => fail("expected pattern binding")
    }
  } else {
    fail("expected match")
  }
}

///|
test "pattern metavar requires repeated pattern equality" {
  let compiled : CompiledExprPattern = {
    ast: test_match_pattern(
      test_pattern_tuple([
        test_pattern_var("$(item:pat)"),
        test_pattern_var("$(item:pat)"),
      ]),
    ),
    expr_metavars: ["input", "body"],
    identifier_metavars: [],
    constant_metavars: [],
    arg_metavars: [],
    type_metavars: [],
    target_metavar: None,
    source_metavar: None,
  }
  assert_true(
    match_expr_pattern(
      compiled,
      parse_expr("match value { (Some(actual), Some(actual)) => ok }"),
    )
    is Some(_),
  )
  assert_false(
    match_expr_pattern(
      compiled,
      parse_expr("match value { (Some(actual), Some(other)) => ok }"),
    )
    is Some(_),
  )
}

///|
test "identifier metavar matches pattern vars" {
  let pattern = parse_expr("match input { item => item }")
  let compiled : CompiledExprPattern = {
    ast: pattern,
    expr_metavars: ["input"],
    identifier_metavars: ["item"],
    constant_metavars: [],
    arg_metavars: [],
    type_metavars: [],
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
test "identifier metavar matches labels" {
  let pattern = parse_expr("record.field + record.field")
  let compiled : CompiledExprPattern = {
    ast: pattern,
    expr_metavars: ["record"],
    identifier_metavars: ["field"],
    constant_metavars: [],
    arg_metavars: [],
    type_metavars: [],
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
test "identifier metavar matches qualified function names" {
  let pattern = parse_expr("callee(callee)")
  let compiled : CompiledExprPattern = {
    ast: pattern,
    expr_metavars: [],
    identifier_metavars: ["callee"],
    constant_metavars: [],
    arg_metavars: [],
    type_metavars: [],
    target_metavar: None,
    source_metavar: None,
  }
  assert_true(
    match_expr_pattern(compiled, parse_expr("@int.abs(@int.abs)")) is Some(_),
  )
  assert_false(
    match_expr_pattern(compiled, parse_expr("@int.abs(abs)")) is Some(_),
  )
}

///|
test "qualified identifier metavar keeps literal package" {
  let pattern = parse_expr("@int.callee(callee)")
  let compiled : CompiledExprPattern = {
    ast: pattern,
    expr_metavars: [],
    identifier_metavars: ["callee"],
    constant_metavars: [],
    arg_metavars: [],
    type_metavars: [],
    target_metavar: None,
    source_metavar: None,
  }
  assert_true(
    match_expr_pattern(compiled, parse_expr("@int.abs(@int.abs)")) is Some(_),
  )
  assert_false(
    match_expr_pattern(compiled, parse_expr("@float.abs(@float.abs)"))
    is Some(_),
  )
}

///|
test "identifier metavar matches constructor identity with extra info" {
  let pattern = parse_expr("Ctor(Ctor)")
  let compiled : CompiledExprPattern = {
    ast: pattern,
    expr_metavars: [],
    identifier_metavars: ["Ctor"],
    constant_metavars: [],
    arg_metavars: [],
    type_metavars: [],
    target_metavar: None,
    source_metavar: None,
  }
  assert_true(
    match_expr_pattern(compiled, parse_expr("@pkg.Actual(@pkg.Actual)"))
    is Some(_),
  )
  assert_false(
    match_expr_pattern(compiled, parse_expr("@pkg.Actual(Actual)")) is Some(_),
  )
  assert_false(
    match_expr_pattern(compiled, parse_expr("@pkg.Actual(@other.Actual)"))
    is Some(_),
  )
}

///|
test "identifier metavar matches constructor type extra info" {
  let pattern = parse_expr("TypeName::Ctor(Ctor)")
  let compiled : CompiledExprPattern = {
    ast: pattern,
    expr_metavars: [],
    identifier_metavars: ["TypeName", "Ctor"],
    constant_metavars: [],
    arg_metavars: [],
    type_metavars: [],
    target_metavar: None,
    source_metavar: None,
  }
  assert_true(
    match_expr_pattern(
      compiled,
      parse_expr("@pkg.Option::Some(@pkg.Option::Some)"),
    )
    is Some(_),
  )
  assert_false(
    match_expr_pattern(compiled, parse_expr("@pkg.Option::Some(Option::Some)"))
    is Some(_),
  )
}

///|
test "identifier metavar matches constructor patterns" {
  let pattern = parse_expr("match input { Ctor => Ctor }")
  let compiled : CompiledExprPattern = {
    ast: pattern,
    expr_metavars: ["input"],
    identifier_metavars: ["Ctor"],
    constant_metavars: [],
    arg_metavars: [],
    type_metavars: [],
    target_metavar: None,
    source_metavar: None,
  }
  assert_true(
    match_expr_pattern(
      compiled,
      parse_expr("match value { @pkg.Actual => @pkg.Actual }"),
    )
    is Some(_),
  )
  assert_false(
    match_expr_pattern(
      compiled,
      parse_expr("match value { @pkg.Actual => Actual }"),
    )
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

///|
test "let pattern with omitted body matches let header only" {
  let pattern = parse_expr("let (__, __) = __")
  assert_true(
    expr_matches(pattern, parse_expr("let (fst, snd) = tuple; use(fst, snd)")),
  )
  assert_true(
    expr_matches(
      pattern,
      parse_expr("let (fst, snd) = tuple; { consume(fst); snd }"),
    ),
  )
  assert_false(
    expr_matches(
      parse_expr("let (__, __) = __; finish(__)"),
      parse_expr("let (fst, snd) = tuple; other(fst)"),
    ),
  )
}
