///|
fn candidate_signature(candidate : ExprMatchCandidate) -> String {
  match candidate {
    Direct(node) => "D:\{node.source_span.0}-\{node.source_span.1}"
    Sequence(items) =>
      "S:" +
      items.map(node => "\{node.source_span.0}-\{node.source_span.1}").join(",")
  }
}

///|
test "indexed traversal preserves candidate order and boundaries" {
  let sources = [
    "fn sample { before(); let mut x = source(); use(x); defer clean(); after(); errdefer fail(); recovered() }",
    "fn sample(x : Int) { if (input is Some(x)) && check(x) { hit(x) } else { miss(x) } }",
    "fn sample { for i = start(); i < end(); i = next(i) { body(i) } nobreak { after(i) } where { invariant: proof(i) } }",
    "fn sample { match input { Some(x) if x is Some(y) => hit(y)\n _ => miss() } }",
    "fn sample { let f = fn(x) { call(x) }; { target(); next() }; f(1) }", "fn sample { letrec f = fn(x) { g(x); next() }; after() }",
  ]
  let all : Array[Array[String]] = []
  for source in sources {
    let parsed = @untyped_cst.parse_structure(source, name="traversal")
    if !parsed.diagnostics_view().is_empty() {
      fail("parse failed: " + source)
    }
    let index = SourceIndex::new(parsed.root())
    let actual : Array[String] = []
    index.walk(index.roots(), fn(region) {
      actual.push(candidate_signature(index.candidate(region)))
      NodeVisitContinue
    })
    all.push(actual)
  }
  debug_inspect(
    all,
    content=(
      #|[
      #|  [
      #|    "S:12-20,22-42,44-50,52-65,67-74,76-91,93-104",
      #|    "D:12-20",
      #|    "D:12-18",
      #|    "S:22-42,44-50,52-65,67-74,76-91,93-104",
      #|    "D:34-42",
      #|    "D:34-40",
      #|    "D:44-50",
      #|    "D:44-47",
      #|    "D:48-49",
      #|    "S:52-65,67-74,76-91,93-104",
      #|    "D:58-65",
      #|    "D:58-63",
      #|    "D:67-74",
      #|    "D:67-72",
      #|    "S:76-91,93-104",
      #|    "D:85-91",
      #|    "D:85-89",
      #|    "D:93-104",
      #|    "D:93-102",
      #|  ],
      #|  [
      #|    "S:21-82",
      #|    "D:21-82",
      #|    "D:24-54",
      #|    "D:24-42",
      #|    "D:25-41",
      #|    "D:25-30",
      #|    "D:46-54",
      #|    "D:46-51",
      #|    "D:52-53",
      #|    "D:55-65",
      #|    "S:57-63",
      #|    "D:57-63",
      #|    "D:57-60",
      #|    "D:61-62",
      #|    "D:71-82",
      #|    "S:73-80",
      #|    "D:73-80",
      #|    "D:73-77",
      #|    "D:78-79",
      #|  ],
      #|  [
      #|    "S:12-114",
      #|    "D:12-114",
      #|    "D:20-27",
      #|    "D:20-25",
      #|    "D:29-38",
      #|    "D:29-30",
      #|    "D:33-38",
      #|    "D:33-36",
      #|    "D:44-51",
      #|    "D:44-48",
      #|    "D:49-50",
      #|    "D:52-63",
      #|    "S:54-61",
      #|    "D:54-61",
      #|    "D:54-58",
      #|    "D:59-60",
      #|    "D:72-84",
      #|    "S:74-82",
      #|    "D:74-82",
      #|    "D:74-79",
      #|    "D:80-81",
      #|    "D:104-112",
      #|    "D:104-109",
      #|    "D:110-111",
      #|  ],
      #|  [
      #|    "S:12-74",
      #|    "D:12-74",
      #|    "D:18-23",
      #|    "D:37-49",
      #|    "D:37-38",
      #|    "D:53-59",
      #|    "D:53-56",
      #|    "D:57-58",
      #|    "D:66-72",
      #|    "D:66-70",
      #|  ],
      #|  [
      #|    "S:12-37,39-59,61-65",
      #|    "D:20-37",
      #|    "S:28-35",
      #|    "D:28-35",
      #|    "D:28-32",
      #|    "D:33-34",
      #|    "D:39-59",
      #|    "S:41-49,51-57",
      #|    "D:41-49",
      #|    "D:41-47",
      #|    "D:51-57",
      #|    "D:51-55",
      #|    "D:61-65",
      #|    "D:61-62",
      #|    "D:63-64",
      #|  ],
      #|  [
      #|    "S:12-45,47-54",
      #|    "S:31-35,37-43",
      #|    "D:31-35",
      #|    "D:31-32",
      #|    "D:33-34",
      #|    "D:37-43",
      #|    "D:37-41",
      #|    "D:47-54",
      #|    "D:47-52",
      #|  ],
      #|]
    ),
  )
}
