///|
fn query_leaf_string(node : @untyped_ast.Node) -> String? {
  match node.kind {
    Leaf(PString(value)) => Some(value)
    _ => None
  }
}

///|
fn query_child(node : @untyped_ast.Node, name : String) -> @untyped_ast.Node? {
  for entry in node.children {
    let (child_name, value) = entry
    if child_name == Some(name) {
      return Some(value)
    }
  }
  None
}

///|
fn query_leaf_string_child(node : @untyped_ast.Node, name : String) -> String? {
  if query_child(node, name) is Some(value) {
    query_leaf_string(value)
  } else {
    None
  }
}

///|
fn query_constant_value(node : @untyped_ast.Node) -> String? {
  guard node.kind == Constant_Int || node.kind == Constant_String else {
    return None
  }
  query_leaf_string_child(node, "value")
}

///|
fn query_argument_kind_signature(node : @untyped_ast.Node) -> String? {
  guard node.kind == Argument else { return None }
  guard query_child(node, "kind") is Some(kind) else { return None }
  Some(kind.kind.to_string())
}

///|
fn string_array_signature(values : Array[String]) -> String {
  "[\{values.join(", ")}]"
}

///|
fn parse_query_expr(source : String) -> @syntax.Expr raise {
  let lex_result = @lexer.tokens_from_string(
    source,
    comment=true,
    name="query expr test",
  )
  guard lex_result.errors.length() == 0 else {
    fail("expected expression to lex: \{source}")
  }
  let (expr, reports) = @handrolled_parser.parse_expr(lex_result.tokens)
  guard reports is [] else { fail("expected expression to parse: \{source}") }
  expr
}

///|
fn parse_query_impls(source : String) -> @list.List[@syntax.Impl] raise {
  let (impls, reports) = @parser.parse_string(source, name="query impl test")
  guard reports is [] else { fail("expected impls to parse: \{source}") }
  impls
}

///|
fn parse_query_impl(source : String) -> @syntax.Impl raise {
  let impls = parse_query_impls(source).to_array()
  guard impls.length() == 1 else { fail("expected one impl: \{source}") }
  impls[0]
}

///|
test "query matches simple expression and returns empty capture map" {
  let query = ExprQuery::ExprQuery("target()")
  let source =
    #|fn sample {
    #|  target()
    #|}
    #|
  let matches = query.captures(source_name="sample.mbt", source)
  assert_eq(matches.length(), 1)
  assert_eq(matches[0].length(), 0)
}

///|
test "query captures one repeated expression and rejects non-repeated candidates" {
  let query = ExprQuery::ExprQuery("$(value:exp) + $(value:exp)")
  let source =
    #|fn sample {
    #|  make() + make();
    #|  make() + other()
    #|}
    #|
  let matches = query.captures(source_name="sample.mbt", source)
  assert_eq(matches.length(), 1)
  guard matches[0].get("value") is Some(Single(value)) else {
    fail("expected value capture")
  }
  assert_true(value.kind == Expr_Apply)
}

///|
test "query captures identifiers and constants by metavar name" {
  let id_query = ExprQuery::ExprQuery("sink($(callee:id))")
  let id_source =
    #|fn sample {
    #|  sink(@math.abs)
    #|}
    #|
  let id_matches = id_query.captures(source_name="sample.mbt", id_source)
  assert_eq(id_matches.length(), 1)
  guard id_matches[0].get("callee") is Some(Single(callee)) else {
    fail("expected callee capture")
  }
  guard query_leaf_string(callee) is Some(callee_name) else {
    fail("expected callee name")
  }
  inspect(callee_name, content="@math.abs")

  let const_query = ExprQuery::ExprQuery("sink($(literal:const))")
  let const_source =
    #|fn sample {
    #|  sink("danger");
    #|  sink(42)
    #|}
    #|
  let const_matches = const_query.captures(
    source_name="sample.mbt",
    const_source,
  )
  assert_eq(const_matches.length(), 2)
  guard const_matches[0].get("literal") is Some(Single(first)) else {
    fail("expected first literal capture")
  }
  guard const_matches[1].get("literal") is Some(Single(second)) else {
    fail("expected second literal capture")
  }
  guard query_constant_value(first) is Some(first_value) else {
    fail("expected first literal value")
  }
  guard query_constant_value(second) is Some(second_value) else {
    fail("expected second literal value")
  }
  inspect(first_value, content="danger")
  inspect(second_value, content="42")
}

///|
test "query captures argument metavars as full argument nodes" {
  let query = ExprQuery::ExprQuery("sink($(arg:arg))")
  let source =
    #|fn sample {
    #|  sink(value);
    #|  sink(label=value);
    #|  sink(label~);
    #|  sink(label?=value);
    #|  sink(label?)
    #|}
    #|
  let matches = query.captures(source_name="sample.mbt", source)
  assert_eq(matches.length(), 5)
  let kinds : Array[String] = []
  for capture in matches {
    guard capture.get("arg") is Some(Single(arg)) else {
      fail("expected argument capture")
    }
    guard query_argument_kind_signature(arg) is Some(kind) else {
      fail("expected argument node capture")
    }
    kinds.push(kind)
  }
  inspect(
    string_array_signature(kinds),
    content="[ArgumentKind::Positional, ArgumentKind::Labelled, ArgumentKind::LabelledPun, ArgumentKind::LabelledOption, ArgumentKind::LabelledOptionPun]",
  )
}

///|
test "query repeated argument metavars require full argument equality" {
  let query = ExprQuery::ExprQuery("sink($(arg:arg), $(arg:arg))")
  let source =
    #|fn sample {
    #|  sink(value, value);
    #|  sink(value, other);
    #|  sink(label=value, label=value);
    #|  sink(label=value, other=value);
    #|  sink();
    #|  sink(value, value, value)
    #|}
    #|
  let matches = query.captures(source_name="sample.mbt", source)
  assert_eq(matches.length(), 2)
  for capture in matches {
    guard capture.get("arg") is Some(Single(arg)) else {
      fail("expected argument capture")
    }
    assert_true(arg.kind == Argument)
  }
}

///|
test "query prefilter skips irrelevant invalid source" {
  let query = ExprQuery::ExprQuery("target()")
  let source =
    #|fn broken {
    #|  this is not valid MoonBit
    #|}
    #|
  let matches = query.captures(source_name="bad.mbt", source)
  assert_eq(matches.length(), 0)
}

///|
test "query raises parse error when relevant source is invalid" {
  let query = ExprQuery::ExprQuery("target()")
  let source =
    #|fn broken {
    #|  target(
    #|}
    #|
  try query.captures(source_name="bad.mbt", source) catch {
    err => inspect("\{Repr(err)}".contains("parse"), content="true")
  } noraise {
    _ => fail("expected parse error")
  }
}

///|
test "query raises when pattern is invalid" {
  try ExprQuery::ExprQuery("target(") catch {
    err => inspect("\{Repr(err)}".contains("InvalidRule"), content="true")
  } noraise {
    _ => fail("expected invalid pattern")
  }
}

///|
test "query captures_from_ast finds matches under an impl list root" {
  let query = ExprQuery::ExprQuery("target()")
  let source =
    #|fn sample {
    #|  target();
    #|  other()
    #|}
    #|
  let ast = @untyped_ast.from_impls(parse_query_impls(source))
  let matches = query.captures_from_ast(ast~)
  assert_eq(matches.length(), 1)
  assert_eq(matches[0].length(), 0)
}

///|
test "query captures_from_ast matches a direct expression root" {
  let query = ExprQuery::ExprQuery("target($(literal:const))")
  let ast = @untyped_ast.from_expr(parse_query_expr("target(42)"))
  let matches = query.captures_from_ast(ast~)
  assert_eq(matches.length(), 1)
  guard matches[0].get("literal") is Some(Single(literal)) else {
    fail("expected literal capture")
  }
  guard query_constant_value(literal) is Some(value) else {
    fail("expected literal value")
  }
  inspect(value, content="42")
}

///|
test "query captures_from_ast finds nested expressions from a non-expression impl root" {
  let query = ExprQuery::ExprQuery("target()")
  let ast = @untyped_ast.from_impl(parse_query_impl("fn sample { target() }"))
  assert_true(ast.kind == Impl_TopFuncDef)
  let matches = query.captures_from_ast(ast~)
  assert_eq(matches.length(), 1)
}

///|
test "query captures_from_ast preserves expression id and constant captures" {
  let query = ExprQuery::ExprQuery(
    "sink($(callee:id), $(value:exp), $(literal:const))",
  )
  let source =
    #|fn sample {
    #|  sink(source, make(), "danger")
    #|}
    #|
  let source_matches = query.captures(source_name="sample.mbt", source)
  let ast_matches = query.captures_from_ast(
    ast=@untyped_ast.from_impls(parse_query_impls(source)),
  )
  assert_eq(ast_matches.length(), source_matches.length())
  assert_eq(ast_matches.length(), 1)
  guard ast_matches[0].get("callee") is Some(Single(callee)) else {
    fail("expected callee capture")
  }
  guard query_leaf_string(callee) is Some(callee_name) else {
    fail("expected callee name")
  }
  inspect(callee_name, content="source")
  guard ast_matches[0].get("value") is Some(Single(value)) else {
    fail("expected expression capture")
  }
  assert_true(value.kind == Expr_Apply)
  guard ast_matches[0].get("literal") is Some(Single(literal)) else {
    fail("expected literal capture")
  }
  guard query_constant_value(literal) is Some(literal_value) else {
    fail("expected literal value")
  }
  inspect(literal_value, content="danger")
}

///|
test "query captures_from_ast prunes nested expressions after an outer match" {
  let query = ExprQuery::ExprQuery("wrap($(value:exp))")
  let ast = @untyped_ast.from_expr(parse_query_expr("wrap(wrap(1))"))
  let matches = query.captures_from_ast(ast~)
  assert_eq(matches.length(), 1)
  guard matches[0].get("value") is Some(Single(value)) else {
    fail("expected value capture")
  }
  assert_true(value.kind == Expr_Apply)
}

///|
test "query captures zero one and many sibling arguments with ellipsis" {
  let query = ExprQuery::ExprQuery("inspect($$$args)")
  let source =
    #|fn sample {
    #|  inspect();
    #|  inspect(1);
    #|  inspect(1, label=2)
    #|}
    #|
  let matches = query.captures(source_name="sample.mbt", source)
  assert_eq(matches.length(), 3)
  let lengths : Array[Int] = []
  for capture in matches {
    guard capture.get("args") is Some(Multiple(args)) else {
      fail("expected multiple argument capture")
    }
    for arg in args {
      assert_true(arg.kind == Argument)
    }
    lengths.push(args.length())
  }
  debug_inspect(lengths, content="[0, 1, 2]")
}

///|
test "query ellipsis uses global left-to-right lazy backtracking" {
  let query = ExprQuery::ExprQuery("f($$$left, marker, $$$right, marker)")
  let matches = query.captures(
    source_name="sample.mbt",
    "fn sample { f(a, marker, b, marker) }",
  )
  assert_eq(matches.length(), 1)
  guard matches[0].get("left") is Some(Multiple(left)) else {
    fail("expected left sequence")
  }
  guard matches[0].get("right") is Some(Multiple(right)) else {
    fail("expected right sequence")
  }
  debug_inspect((left.length(), right.length()), content="(1, 1)")
}

///|
test "query repeated ellipsis names require equal node sequences" {
  let query = ExprQuery::ExprQuery("pair([$$$items], [$$$items])")
  let source =
    #|fn sample {
    #|  pair([], []);
    #|  pair([a, b], [a, b]);
    #|  pair([a], [b])
    #|}
    #|
  let matches = query.captures(source_name="sample.mbt", source)
  assert_eq(matches.length(), 2)
  guard matches[0].get("items") is Some(Multiple(empty)) else {
    fail("expected empty sequence")
  }
  guard matches[1].get("items") is Some(Multiple(two)) else {
    fail("expected two-item sequence")
  }
  debug_inspect((empty.length(), two.length()), content="(0, 2)")
}

///|
test "query typed argument ellipsis distinguishes full args from positional values" {
  let arg_query = ExprQuery::ExprQuery("sink($$$(args:arg))")
  let exp_query = ExprQuery::ExprQuery("sink($$$(args:exp))")
  let source =
    #|fn sample {
    #|  sink(value, label=other);
    #|  sink(value, other);
    #|  sink(label~);
    #|  sink(label?=other);
    #|  sink(label?)
    #|}
    #|
  let arg_matches = arg_query.captures(source_name="sample.mbt", source)
  let exp_matches = exp_query.captures(source_name="sample.mbt", source)
  assert_eq(arg_matches.length(), 5)
  assert_eq(exp_matches.length(), 1)
}

///|
test "query anonymous ellipsis does not create a binding" {
  let query = ExprQuery::ExprQuery("inspect($$$_)")
  let matches = query.captures(
    source_name="sample.mbt",
    "fn sample { inspect(1, 2, 3) }",
  )
  assert_eq(matches.length(), 1)
  assert_eq(matches[0].length(), 0)

  let typed = ExprQuery::ExprQuery("sink($$$(_:const))")
  let typed_matches = typed.captures(
    source_name="sample.mbt",
    "fn sample { sink(); sink(1, 2); sink(1, value) }",
  )
  assert_eq(typed_matches.length(), 2)
  for capture in typed_matches {
    assert_eq(capture.length(), 0)
  }
}

///|
test "query ellipsis covers parameter pattern and type lists" {
  let parameter_query = ExprQuery::ExprQuery("fn($$$(params:id)) { body }")
  let parameter_matches = parameter_query.captures(
    source_name="sample.mbt",
    "fn sample { let f = fn(a, b : Int, c? : String) { body } }",
  )
  assert_eq(parameter_matches.length(), 1)
  guard parameter_matches[0].get("params") is Some(Multiple(params)) else {
    fail("expected parameter sequence")
  }
  assert_eq(params.length(), 3)
  for parameter in params {
    assert_true(parameter.kind.to_string().has_prefix("Parameter::"))
  }

  let pattern_query = ExprQuery::ExprQuery(
    "match input { [$$$(pats:pat)] => body }",
  )
  let pattern_matches = pattern_query.captures(
    source_name="sample.mbt",
    "fn sample { match input { [Some(x), _, 1] => body } }",
  )
  assert_eq(pattern_matches.length(), 1)
  guard pattern_matches[0].get("pats") is Some(Multiple(patterns)) else {
    fail("expected pattern sequence")
  }
  assert_eq(patterns.length(), 3)
  for pattern in patterns {
    assert_true(pattern.kind.to_string().has_prefix("ArrayPattern::"))
  }

  let type_query = ExprQuery::ExprQuery(
    "let value : ($$$(Types:type), Bool) = input",
  )
  let type_matches = type_query.captures(
    source_name="sample.mbt",
    "fn sample { let value : (Int, String, Bool) = input }",
  )
  assert_eq(type_matches.length(), 1)
  guard type_matches[0].get("Types") is Some(Multiple(types)) else {
    fail("expected type sequence")
  }
  assert_eq(types.length(), 2)
  for ty in types {
    assert_true(ty.kind.to_string().has_prefix("Type::"))
  }
}

///|
test "query failed ellipsis branches do not leak single bindings" {
  let query = ExprQuery::ExprQuery("f($$$gap, $(value:exp), marker)")
  let matches = query.captures(
    source_name="sample.mbt",
    "fn sample { f(first, selected, marker) }",
  )
  assert_eq(matches.length(), 1)
  guard matches[0].get("gap") is Some(Multiple(gap)) else {
    fail("expected gap sequence")
  }
  guard matches[0].get("value") is Some(Single(value)) else {
    fail("expected value binding")
  }
  assert_eq(gap.length(), 1)
  guard value.normalized_expr_identifier_name() is Some(name) else {
    fail("expected identifier expression")
  }
  inspect(name, content="selected")
}
