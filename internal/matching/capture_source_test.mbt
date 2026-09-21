///|
test "indexed typed identifier lists keep complete items and parameter origins" {
  let node = test_expr("fn(a, b) { sink(a, b) }")
  let index = @cst.SourceIndex::new(node)
  let pattern = test_compiled(
    test_expr("fn($$$(names:id)) { __TARGET__ }"),
    entries=[test_metavar_entry("names", Ellipsis(IdItem))],
    special_expr_placeholders=["__TARGET__"],
  )
  let matched = match_indexed_expr_pattern(
    pattern,
    index,
    index.direct(index.node_id(node)),
    HashMap([]),
    HashMap([]),
  ).unwrap()
  guard matched.result.bindings.get("names") is Some(Multiple(items)) else {
    fail("expected complete parameter items")
  }
  assert_eq(items.length(), 2)
  assert_true(items.all(item => item.kind is Parameter_Positional))
  let call = test_compiled(test_expr("sink($$$(names:id))"), entries=[
    test_metavar_entry("names", Ellipsis(IdItem)),
  ])
  let mut reference_sources : IdentifierCaptureSource? = None
  index.walk(index.scan(matched.target.unwrap().region), fn(region) {
    if match_indexed_expr_pattern(call, index, region, HashMap([]), HashMap([]))
      is Some(found) {
      reference_sources = found.sources.get("names")
      return NodeVisitReturn
    }
    NodeVisitContinue
  })
  assert_true(reference_sources == matched.sources.get("names"))
}

///|
test "indexed matching keeps structural equality for new identifier lists" {
  let node = test_expr("choose(fn(a) { () }, fn(a) { () })")
  let pattern = test_compiled(
    test_expr("choose(fn($$$(names:id)) { $_ }, fn($$$(names:id)) { $_ })"),
    entries=[test_metavar_entry("names", Ellipsis(IdItem))],
  )
  let index = @cst.SourceIndex::new(node)
  assert_true(
    match_indexed_expr_pattern(
      pattern,
      index,
      index.direct(index.node_id(node)),
      HashMap([]),
      HashMap([]),
    )
    is Some(_),
  )
  assert_true(match_expr_pattern(pattern, node) is Some(_))
}

///|
test "indexed split constructor captures agree with ordinary matching" {
  for
    (shape, source) in [
      ("$(Type:id)::$(Ctor:id)(value)", "Option::Some(value)"),
      (
        "match input { $(Type:id)::$(Ctor:id)(value) => body }", "match input { Option::Some(value) => body }",
      ),
    ] {
    let node = test_expr(source)
    let pattern = test_compiled(test_expr(shape), entries=[
      test_metavar_entry("Type", Identifier),
      test_metavar_entry("Ctor", Identifier),
    ])
    let ordinary = match_expr_pattern(pattern, node).unwrap()
    let index = @cst.SourceIndex::new(node)
    let indexed = match_indexed_expr_pattern(
      pattern,
      index,
      index.direct(index.node_id(node)),
      HashMap([]),
      HashMap([]),
    ).unwrap()
    assert_eq(indexed.result.bindings.length(), 2)
    for (capture, name) in [("Type", "Option"), ("Ctor", "Some")] {
      let value = test_single_binding(Some(indexed.result), capture)
      assert_true(
        physical_equal(value, test_single_binding(Some(ordinary), capture)),
      )
      assert_eq(@cst.normalized_name(value), Some(name))
      assert_eq(
        indexed.sources.get(capture),
        Some(SingleIdentifier({ name, binding: NonLexical, })),
      )
    }
  }
}
