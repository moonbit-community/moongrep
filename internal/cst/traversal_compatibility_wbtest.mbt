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
fn candidate_call_name(candidate : ExprMatchCandidate) -> String? {
  guard candidate is Direct(node) && node.kind is @untyped_cst.Expr_Apply else {
    return None
  }
  raw_child(node, "func").bind(normalized_expr_identifier_name)
}

///|
fn assert_direct_indexed_compatible(
  root : @untyped_cst.CstNode,
) -> Array[String] raise {
  let index = SourceIndex::new(root)
  let indexed : Array[String] = []
  let indexed_regions : Array[RegionId] = []
  index.walk(index.roots(), fn(region) {
    indexed_regions.push(region)
    indexed.push(candidate_signature(index.candidate(region)))
    NodeVisitContinue
  })
  let direct_candidates : Array[ExprMatchCandidate] = []
  let direct : Array[String] = []
  visit_expr_match_candidate_roots(root, fn(candidate) {
    direct_candidates.push(candidate)
    direct.push(candidate_signature(candidate))
    NodeVisitContinue
  })
  assert_eq(direct, indexed)
  assert_eq(direct_candidates.length(), indexed_regions.length())
  for candidate_index in 0..<direct_candidates.length() {
    let direct_children : Array[String] = []
    visit_expr_match_candidate_children(direct_candidates[candidate_index], fn(
      candidate,
    ) {
      direct_children.push(candidate_signature(candidate))
    })
    let indexed_children : Array[String] = []
    index.walk(index.children(indexed_regions[candidate_index]), fn(region) {
      indexed_children.push(candidate_signature(index.candidate(region)))
      NodeVisitPrune
    })
    assert_eq(direct_children, indexed_children)
  }
  indexed
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
    all.push(assert_direct_indexed_compatible(parsed.root()))
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

///|
test "shared traversal kernel covers roots, branches, cases, and empty bodies" {
  let structures = [
    "fn empty {}",
    "fn sample { if ready() {}; after() }",
    "fn sample { while ready() { tick(); next() } }",
    "fn sample { for item in items { use(item); next() } }",
    "fn sample { [for item in items if allow(item) => map(item)] }",
    "fn sample { try { risky(); done() } catch { error if check(error) => recover(error); _ => fallback() } noraise { value => accept(value) } }",
    "fn sample { lexmatch source() { (re\"a\" as piece) => hit(piece); _ => miss() }; lexscan source() { (re\"b\", before=head) => take(head) } }",
    "fn sample { match input { Some(_) as item => hit(item) }; ∀ item : Int, check(item); ∃ item : Int, check(item) }",
    "fn sample { let mut item = 0; item = next(); { let mut item = 1; item += next() }; object.item = item; object.item += item }",
    "fn first { one() }\nfn second { two() }",
    "let value = init()\nconst answer = make()",
    (
      #|///| Traversal ignores this documentation node.
      #|fn sample { "hello \{make()}" }
    ),
  ]
  for source in structures {
    let parsed = @untyped_cst.parse_structure(source, name="kernel structure")
    if !parsed.diagnostics_view().is_empty() {
      fail("parse failed: " + source)
    }
    ignore(assert_direct_indexed_compatible(parsed.root()))
  }
  let expressions = [
    "let value = source(); use(value)", "first(); defer cleanup(); after()", "(grouped()); next()",
  ]
  for source in expressions {
    let parsed = @untyped_cst.parse_expression(source, name="kernel expression")
    if !parsed.diagnostics_view().is_empty() {
      fail("parse failed: " + source)
    }
    ignore(assert_direct_indexed_compatible(parsed.root()))
  }
}

///|
test "direct traversal preserves indexed prune and return behavior" {
  let source = "fn sample { blocked(hidden()); after(); stop(); ignored() }"
  let parsed = @untyped_cst.parse_structure(source, name="traversal actions")
  guard parsed.diagnostics_view().is_empty() else {
    fail("expected action source to parse")
  }
  let decide = fn(candidate : ExprMatchCandidate) {
    match candidate_call_name(candidate) {
      Some("blocked") => NodeVisitPrune
      Some("stop") => NodeVisitReturn
      _ => NodeVisitContinue
    }
  }
  let direct : Array[String] = []
  visit_expr_match_candidate_roots(parsed.root(), fn(candidate) {
    if candidate_call_name(candidate) is Some(name) {
      direct.push(name)
    }
    decide(candidate)
  })
  let indexed : Array[String] = []
  let index = SourceIndex::new(parsed.root())
  index.walk(index.roots(), fn(region) {
    let candidate = index.candidate(region)
    if candidate_call_name(candidate) is Some(name) {
      indexed.push(name)
    }
    decide(candidate)
  })
  debug_inspect(direct, content="[\"blocked\", \"after\", \"stop\"]")
  assert_eq(direct, indexed)
}

///|
test "pruning a sequence root continues with siblings and return stops them" {
  let source =
    #|fn pruned { hidden(deep()) }
    #|fn kept { after(); stop(); ignored() }
    #|fn later { later() }
    #|
  let parsed = @untyped_cst.parse_structure(source, name="root actions")
  assert_true(parsed.diagnostics_view().is_empty())
  let decide = fn(candidate : ExprMatchCandidate) {
    match candidate {
      Sequence([first, ..]) if candidate_call_name(Direct(first)) ==
        Some("hidden") => NodeVisitPrune
      Direct(_) if candidate_call_name(candidate) == Some("stop") =>
        NodeVisitReturn
      _ => NodeVisitContinue
    }
  }
  let record = fn(result : Array[String], candidate : ExprMatchCandidate) {
    match candidate {
      Sequence([first, ..]) =>
        if candidate_call_name(Direct(first)) is Some(name) {
          result.push("S:" + name)
        }
      Direct(_) =>
        if candidate_call_name(candidate) is Some(name) {
          result.push("D:" + name)
        }
      Sequence([]) => ()
    }
  }
  let direct : Array[String] = []
  visit_expr_match_candidate_roots(parsed.root(), fn(candidate) {
    record(direct, candidate)
    decide(candidate)
  })
  let indexed : Array[String] = []
  let index = SourceIndex::new(parsed.root())
  index.walk(index.roots(), fn(region) {
    let candidate = index.candidate(region)
    record(indexed, candidate)
    decide(candidate)
  })
  debug_inspect(
    direct,
    content="[\"S:hidden\", \"S:after\", \"D:after\", \"D:stop\"]",
  )
  assert_eq(direct, indexed)
}

///|
test "direct sequence children do not require an indexed origin" {
  let parsed = @untyped_cst.parse_expression(
    "first(); let item = source(); middle(); defer cleanup(); last()",
    name="originless children",
  )
  assert_true(parsed.diagnostics_view().is_empty())
  let expressions = expression_nodes(parsed.root())
  let direct : Array[String] = []
  let mut saw_suffix = false
  visit_expr_match_candidate_children(Sequence(expressions[:]), fn(candidate) {
    if candidate is Sequence([first, ..]) && first.kind is @untyped_cst.Expr_Let {
      saw_suffix = true
    }
    direct.push(candidate_signature(candidate))
  })
  let index = SourceIndex::new(parsed.root())
  guard collect_immediate_regions(index, index.roots()) is [root] else {
    fail("expected one expression sequence root")
  }
  let indexed : Array[String] = []
  index.walk(index.children(root), fn(region) {
    indexed.push(candidate_signature(index.candidate(region)))
    NodeVisitPrune
  })
  assert_true(saw_suffix)
  assert_eq(direct, indexed)
}
