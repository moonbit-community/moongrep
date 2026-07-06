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
