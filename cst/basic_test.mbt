///|
test "semantic view ignores formatting and exposes payloads" {
  let compact = @untyped_cst.parse_expression("f(1, label=x)").root()
  let spaced = @untyped_cst.parse_expression("f( 1 /* c */, label = x )").root()
  let left = expression_root(compact)
  let right = expression_root(spaced)
  assert_true(left.kind is @untyped_cst.Expr_Apply)
  assert_true(right.kind is @untyped_cst.Expr_Apply)
  debug_inspect(
    normalized_expr_identifier_name(child(left, "func").unwrap()),
    content="Some(\"f\")",
  )
  let args = child(left, "arg").unwrap()
  assert_eq(items(args).length(), 2)
  debug_inspect(argument_label_name(items(args)[1]), content="Some(\"label\")")
}

///|
test "interpolation semantics use the parsed expression" {
  let root = @untyped_cst.parse_expression("\"hello \\{value}\"").root()
  guard find_first_node(root, node => {
      node.kind is @untyped_cst.InterpSegment_Source
    })
    is Some(segment) else {
    fail("expected interpolation source")
  }
  guard semantic_children(segment) is [(Some("expr"), expr)] else {
    fail("expected only the parsed interpolation expression")
  }
  assert_true(expr.kind is @untyped_cst.Expr_Ident)
  debug_inspect(string_payload(segment), content="Some(\"value\")")
}

///|
test "groups and structure roots are normalized" {
  let pattern = @untyped_cst.parse_expression("match x { (Some(y)) => y }").root()
  let grouped = find_first_node(pattern, fn(node) {
    node.kind is @untyped_cst.Pattern_Tuple &&
    raw_child(node, "pattern_group") is Some(_)
  }).unwrap()
  assert_true(unwrap_groups(grouped).kind is @untyped_cst.Pattern_Constr)
  let impls = @untyped_cst.parse_structure("fn f {}\nlet x = 1").root()
  assert_eq(toplevel_nodes(impls).length(), 2)
}

///|
test "constructor identities retain every qualifier" {
  let cases = [
    ("Ctor", "Ctor"),
    ("@pkg.Ctor", "@pkg.Ctor"),
    ("Type::Ctor", "Type::Ctor"),
    ("@pkg.Type::Ctor", "@pkg.Type::Ctor"),
    ("@pkg.Type::@other.Ctor", "@pkg.Type::@other.Ctor"),
  ]
  for case in cases {
    let (source, expected) = case
    let parsed = @untyped_cst.parse_expression(source)
    guard parsed.diagnostics_view().is_empty() else {
      fail("expected constructor expression to parse: \{source}")
    }
    let constructor_expr = expression_root(parsed.root())
    assert_true(constructor_expr.kind is @untyped_cst.Expr_Constr)
    assert_eq(normalized_name(constructor_expr), Some(expected))
  }
  let pattern = @untyped_cst.parse_expression(
    "match input { @pkg.Type::@other.Ctor(value) => value }",
  ).root()
  guard find_first_node(pattern, node => {
      node.kind is @untyped_cst.Pattern_Constr
    })
    is Some(constructor_pattern) else {
    fail("expected constructor pattern")
  }
  assert_eq(
    normalized_name(constructor_pattern),
    Some("@pkg.Type::@other.Ctor"),
  )
}

///|
test "qualified attributes expose metadata" {
  let root = @untyped_cst.parse_structure("#moongrep.skip\nfn f {}").root()
  let item = toplevel_nodes(root)[0]
  guard attributes(item) is [attribute] else { fail("expected one attribute") }
  assert_eq(attribute.qualifier, Some("moongrep"))
  assert_eq(attribute.name, "skip")
  assert_eq(attribute.raw_payload, "")
}

///|
test "top-level and nested docstrings remain trivia" {
  let first = @untyped_cst.parse_structure(
    "///| AAA\nfn same {}",
    name="same-doc-location",
  )
  let second = @untyped_cst.parse_structure(
    "///| BBB\nfn same {}",
    name="same-doc-location",
  )
  guard toplevel_nodes(first.root()) is [first_node] &&
    toplevel_nodes(second.root()) is [second_node] else {
    fail("expected functions")
  }
  assert_true(
    find_first_node(first.root(), node => {
      node.kind is @untyped_cst.Syntax_Comment
    })
    is Some(_),
  )
  assert_false(semantic_tree_has_doc_trivia(first.root()))
  assert_false(semantic_tree_has_doc_trivia(second.root()))
  assert_eq(
    semantic_children(first_node).length(),
    semantic_children(second_node).length(),
  )
  let nested = @untyped_cst.parse_structure(
    "struct Sample {\n  /// field docs\n  value : Int\n}",
  )
  guard toplevel_nodes(nested.root()) is [struct_node] else {
    fail("expected struct")
  }
  assert_true(
    find_first_node(struct_node, node => {
      node.kind is @untyped_cst.Syntax_Comment
    })
    is Some(_),
  )
  assert_false(semantic_tree_has_doc_trivia(struct_node))
}

///|
fn semantic_tree_has_doc_trivia(node : @untyped_cst.CstNode) -> Bool {
  for entry in semantic_children(node) {
    let (label, child) = entry
    if label == Some("doc") || child.kind is @untyped_cst.Syntax_Comment {
      return true
    }
    if semantic_tree_has_doc_trivia(child) {
      return true
    }
  }
  false
}

///|
fn find_first_node(
  node : @untyped_cst.CstNode,
  expected : (@untyped_cst.CstNode) -> Bool,
) -> @untyped_cst.CstNode? {
  if expected(node) {
    return Some(node)
  }
  for entry in node.children {
    if find_first_node(entry.1, expected) is Some(found) {
      return Some(found)
    }
  }
  None
}
