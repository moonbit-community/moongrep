///|
fn collect_immediate_regions(
  index : SourceIndex,
  cursor : CursorId,
) -> Array[RegionId] {
  let regions : Array[RegionId] = []
  index.walk(cursor, fn(region) {
    regions.push(region)
    NodeVisitPrune
  })
  regions
}

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
test "ordinary traversal maps absolute sequence suffix positions" {
  let parsed = @untyped_cst.parse_expression(
    "first(); let item = source(); middle(); defer cleanup(); last()",
    name="sequence positions",
  )
  assert_true(parsed.diagnostics_view().is_empty())
  let index = SourceIndex::new(parsed.root())
  guard collect_immediate_regions(index, index.roots()) is [root] else {
    fail("expected one expression sequence root")
  }
  guard index.regions[root] is Slice(list, 0, 5) else {
    fail("expected the complete expression sequence")
  }
  assert_eq(index.sequences[list].values.length(), 5)
  let root_children = collect_immediate_regions(index, index.children(root))
  let mut first_suffix = -1
  for region in root_children {
    if index.regions[region] is Slice(found, 1, 5) && found == list {
      first_suffix = region
    }
  }
  assert_true(first_suffix >= 0)
  assert_true(index.candidate(first_suffix) is Sequence([_, _, _, _]))
  let suffix_children = collect_immediate_regions(
    index,
    index.children(first_suffix),
  )
  let mut nested_suffix = -1
  for region in suffix_children {
    if index.regions[region] is Slice(found, 3, 5) && found == list {
      nested_suffix = region
    }
  }
  assert_true(nested_suffix >= 0)
  assert_true(index.candidate(nested_suffix) is Sequence([_, _]))
  assert_eq(index.scope(first_suffix), index.sequences[list].scopes[1])
  assert_eq(index.scope(nested_suffix), index.sequences[list].scopes[3])
  assert_true(index.resolve(index.scope(first_suffix), "item") is None)
  assert_true(index.resolve(index.scope(nested_suffix), "item") is Some(_))
}

///|
test "ordinary traversal maps an empty nested sequence without losing scope" {
  let parsed = @untyped_cst.parse_structure(
    "fn sample { if ready() {}; after() }",
    name="empty nested sequence",
  )
  assert_true(parsed.diagnostics_view().is_empty())
  let index = SourceIndex::new(parsed.root())
  let regions : Array[RegionId] = []
  index.walk(index.roots(), fn(region) {
    regions.push(region)
    NodeVisitContinue
  })
  let mut empty = -1
  let mut empty_list = -1
  for region in regions {
    if index.regions[region] is Slice(list, start, end) && start == end {
      empty = region
      empty_list = list
    }
  }
  assert_true(empty >= 0)
  assert_true(index.candidate(empty) is Sequence([]))
  assert_eq(index.sequences[empty_list].values.length(), 0)
  assert_eq(index.scope(empty), index.sequences[empty_list].scopes[0])
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
