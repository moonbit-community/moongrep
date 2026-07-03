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
  let matches = ExprQuery::ExprQuery(pattern).matches_all(
    source_name="sample.mbt",
    source,
  )
  assert_eq(matches.length(), 3)
  let filtered : Array[Map[String, @untyped_ast.Node]] = []
  for captures in matches {
    if captures.get("counter") is Some(counter_node) &&
      counter_node.kind is Leaf(PString(counter_name)) &&
      captures.get("body") is Some(body) {
      // unused variable in for loop body
      if !body.contains_unshadowed(id=counter_name) {
        filtered.push(captures)
      }
    }
  }
  assert_eq(filtered.length(), 2)
  debug_inspect(
    filtered[0].get("counter").unwrap(),
    content=(
      #|{
      #|  kind: Leaf(PString("i")),
      #|  loc: {
      #|    start: { fname: "sample.mbt", lnum: 2, bol: 12, cnum: 18 },
      #|    end: { fname: "sample.mbt", lnum: 2, bol: 12, cnum: 19 },
      #|  },
      #|  children: <FixedArray: []>,
      #|}
    ),
  )
  debug_inspect(
    filtered[1].get("counter").unwrap(),
    content=(
      #|{
      #|  kind: Leaf(PString("k")),
      #|  loc: {
      #|    start: { fname: "sample.mbt", lnum: 8, bol: 121, cnum: 127 },
      #|    end: { fname: "sample.mbt", lnum: 8, bol: 121, cnum: 128 },
      #|  },
      #|  children: <FixedArray: []>,
      #|}
    ),
  )
}
