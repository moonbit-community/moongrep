///|
test "query can emulate cstyle forward simple forloop patterns-not by iterating captured body" {
  let source =
    #|fn sample {
    #|  for i = 0; i < n; i = i + 1 {
    #|    println("tick")
    #|  };
    #|  for j = 0; j < n; j = j + 1 {
    #|    println(j)
    #|  };
    #|  for k = 0; k < n; k = k + 1 {
    #|    let k = local()
    #|    println(k)
    #|  }
    #|}
    #|
  let pattern =
    #|for $(counter:id) = $(start:exp); $(counter:id) < $(limit:exp); $(counter:id) = $(counter:id) + 1 {
    #|  $(body:exp)
    #|}
  let captures = ExprQuery::ExprQuery(pattern).captures(
    source_name="sample.mbt",
    source,
  )
  assert_eq(captures.length(), 3)
  let filtered_capture_maps : Array[Map[String, @matching.BoundValue]] = []
  for capture in captures {
    if capture.get("counter") is Some(Single(counter_node)) &&
      @cst.normalized_name(counter_node) is Some(counter_name) &&
      capture.get("body") is Some(Single(body)) {
      // unused variable in for loop body
      if !query_contains_unshadowed(body, counter_name) {
        filtered_capture_maps.push(capture)
      }
    }
  }
  assert_eq(filtered_capture_maps.length(), 2)
  guard filtered_capture_maps[0].get("counter") is Some(Single(first)) &&
    @cst.normalized_name(first) is Some(first_name) else {
    fail("expected first counter")
  }
  inspect(first_name, content="i")
  guard filtered_capture_maps[1].get("counter") is Some(Single(second)) &&
    @cst.normalized_name(second) is Some(second_name) else {
    fail("expected second counter")
  }
  inspect(second_name, content="k")
}

///|
fn query_contains_unshadowed(cst : @untyped_cst.CstNode, name : String) -> Bool {
  let mut found = false
  @cst.visit_scoped_expr_match_candidate_roots(cst, fn(item) {
    match item.candidate {
      @cst.Direct(expr) if !found &&
        !item.shadowed_names.contains(name) &&
        @cst.normalized_expr_identifier_name(expr) == Some(name) => {
        found = true
        @cst.NodeVisitReturn
      }
      _ => @cst.NodeVisitContinue
    }
  })
  found
}
