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
