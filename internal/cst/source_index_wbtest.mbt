///|
test "continuation regions keep empty and partial sequence boundaries" {
  let parsed = @untyped_cst.parse_expression(
    "let item = source(); skip(); sink(item)",
    name="regions",
  )
  assert_true(parsed.diagnostics_view().is_empty())
  let index = SourceIndex::new(parsed.root())
  let header = expression_nodes(parsed.root())[0]
  let header_id = index.node_id(header)
  let empty = index.continuation(header_id, 1)
  let single = index.continuation(header_id, 2)
  let multiple = index.continuation(header_id, 3)
  inspect(index.candidate(empty) is Sequence([]), content="true")
  inspect(index.candidate(single) is Sequence([_]), content="true")
  inspect(index.candidate(multiple) is Sequence([_, _]), content="true")
  inspect(index.resolve(index.scope(empty), "item") is Some(_), content="true")
  assert_eq(index.scope(empty), index.scope(multiple))
  assert_eq(index.continuation(header_id, 3), multiple)
  assert_true(empty != single && single != multiple)
  let candidates : Array[RegionId] = []
  index.walk(index.roots(), fn(region) {
    candidates.push(region)
    NodeVisitContinue
  })
  // These targets are addressable even though ordinary traversal never emits them.
  assert_false(candidates.contains(empty))
  assert_false(candidates.contains(single))
  assert_false(candidates.contains(multiple))
}

///|
test "source identity does not merge equal spans" {
  let parsed = @untyped_cst.parse_expression("item", name="same-span")
  let expr = expression_root(parsed.root())
  let name = name_node(expr).unwrap()
  assert_eq(expr.source_span, name.source_span)
  let index = SourceIndex::new(parsed.root())
  assert_true(index.node_id(expr) != index.node_id(name))
  assert_eq(index.node_id(expr), index.node_id(expr))
}

///|
test "split constructor pattern names retain their original indexed references" {
  let root = parse_identifier_source(
    "fn sample { match input { Option::Some(value) => sink(value) } }",
  )
  let index = SourceIndex::new(root)
  let constructors = index.nodes.filter_map(entry => {
    if entry.node.kind is @untyped_cst.Pattern_Constr {
      Some(entry.node)
    } else {
      None
    }
  })
  guard constructors is [constr] else { fail("expected one constructor") }
  let names = raw_children(constr, "name")
  debug_inspect(
    names.map(normalized_name),
    content="[Some(\"Option\"), Some(\"Some\")]",
  )
  let semantic = raw_child(constr, "semantic_name").unwrap()
  for name in names {
    let id = index.node_id(name)
    assert_true(physical_equal(index.node(id), name))
    assert_true(id != index.node_id(semantic))
    assert_eq(index.identifier_source(name).unwrap().binding, NonLexical)
    let value = raw_child(name, "name_value").unwrap()
    assert_true(physical_equal(index.node(index.node_id(value)), value))
    assert_eq(index.identifier_source(value).unwrap().binding, NonLexical)
  }
  let mut visits_syntax = false
  index.walk(index.roots(), fn(region) {
    if index.candidate(region) is Direct(node) && is_syntax_kind(node.kind) {
      visits_syntax = true
    }
    NodeVisitContinue
  })
  inspect(visits_syntax, content="false")
}
