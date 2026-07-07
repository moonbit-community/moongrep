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
  guard matches[0].get("value") is Some(value) else {
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
  guard id_matches[0].get("callee") is Some(callee) else {
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
  guard const_matches[0].get("literal") is Some(first) else {
    fail("expected first literal capture")
  }
  guard const_matches[1].get("literal") is Some(second) else {
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
    guard capture.get("arg") is Some(arg) else {
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
    guard capture.get("arg") is Some(arg) else {
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
    err => inspect("\{to_repr(err)}".contains("parse"), content="true")
  } noraise {
    _ => fail("expected parse error")
  }
}

///|
test "query raises when pattern is invalid" {
  try ExprQuery::ExprQuery("target(") catch {
    err => inspect("\{to_repr(err)}".contains("InvalidRule"), content="true")
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
  guard matches[0].get("literal") is Some(literal) else {
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
  guard ast_matches[0].get("callee") is Some(callee) else {
    fail("expected callee capture")
  }
  guard query_leaf_string(callee) is Some(callee_name) else {
    fail("expected callee name")
  }
  inspect(callee_name, content="source")
  guard ast_matches[0].get("value") is Some(value) else {
    fail("expected expression capture")
  }
  assert_true(value.kind == Expr_Apply)
  guard ast_matches[0].get("literal") is Some(literal) else {
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
  guard matches[0].get("value") is Some(value) else {
    fail("expected value capture")
  }
  assert_true(value.kind == Expr_Apply)
}
