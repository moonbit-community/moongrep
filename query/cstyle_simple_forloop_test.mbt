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
      counter_node.kind is Leaf(PString(counter_name)) &&
      capture.get("body") is Some(Single(body)) {
      // unused variable in for loop body
      if !body.contains_unshadowed(id=counter_name) {
        filtered_capture_maps.push(capture)
      }
    }
  }
  assert_eq(filtered_capture_maps.length(), 2)
  guard filtered_capture_maps[0].get("counter") is Some(Single(first)) &&
    first.kind is Leaf(PString(first_name)) else {
    fail("expected first counter")
  }
  inspect(first_name, content="i")
  guard filtered_capture_maps[1].get("counter") is Some(Single(second)) &&
    second.kind is Leaf(PString(second_name)) else {
    fail("expected second counter")
  }
  inspect(second_name, content="k")
}
