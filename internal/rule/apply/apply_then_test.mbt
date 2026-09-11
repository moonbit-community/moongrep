///|
fn then_hits(rule : String, source : String) -> Array[@model.RuleFinding] raise {
  let rules = compile_rule_source(
    "id: recursive\ndescription: Recursive.\n" + rule,
  )
  let full_source = "fn sample {\n" + source + "\n}"
  let node = parse_root_node(full_source)
  let plan = ScanPlan::from_rules(rules)
  let hits = apply_structural_scan_plan_to_node("sample.mbt", node, plan)
  let filtered = apply_structural_scan_plan_to_node(
    "sample.mbt",
    node,
    plan.filter_source(full_source),
  )
  assert_eq(hits.length(), filtered.length())
  for index in 0..<hits.length() {
    assert_eq(hits[index].pattern_index, filtered[index].pattern_index)
    assert_eq(hits[index].loc, filtered[index].loc)
  }
  hits
}

///|
test "then recursive guards inherit across unused intermediate captures" {
  let rule =
    #|patterns:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: container(__TARGET__)
    #|          then:
    #|            patterns:
    #|              - shape: holder(__TARGET__)
    #|                then:
    #|                  patterns:
    #|                    - shape: target()
    #|                      guard:
    #|                        $name: '^safe_'
  inspect(
    then_hits(rule, "wrapper(safe_name, container(holder(target())))").length(),
    content="1",
  )
  inspect(
    then_hits(rule, "wrapper(other, container(holder(target())))").length(),
    content="0",
  )
  inspect(
    then_hits(
      rule, "wrapper(safe_name, container(holder({ let safe_name = 0; target() })))",
    ).length(),
    content="0",
  )
}

///|
test "then keeps inherited shadowing across a matched middle shape" {
  let rule =
    #|patterns:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: fn ($(parameter:id)) { __TARGET__ }
    #|          then:
    #|            patterns:
    #|              - shape: target()
    #|                guard:
    #|                  $name: '^x$'
  inspect(
    then_hits(rule, "wrapper(x, fn (x) { target() })").length(),
    content="0",
  )
  inspect(
    then_hits(rule, "wrapper(x, fn (y) { target() })").length(),
    content="1",
  )
}

///|
test "then failure falls back and success prunes with root index" {
  let rule =
    #|patterns:
    #|  - shape: wrapper(__TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: missing()
    #|  - shape: wrapper(__TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: target()
    #|  - shape: target()
  let hits = then_hits(
    rule, "wrapper({ target(); target() }); wrapper(other(target()))",
  )
  debug_inspect(hits.map(h => h.pattern_index), content="[1, 1]")
  inspect(hits[0].loc.start.lnum, content="2")
  let fallback = then_hits(rule, "wrapper(other())")
  inspect(fallback.length(), content="0")
}

///|
test "then negative rejection is local and covers whole successful subtree" {
  let rule =
    #|patterns:
    #|  - shape: wrapper(__TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: holder(__TARGET__)
    #|          then:
    #|            patterns:
    #|              - shape: target()
    #|      patterns-not:
    #|        - shape: danger()
    #|  - shape: wrapper(__TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: danger()
  debug_inspect(
    then_hits(rule, "wrapper(holder({ target(); danger() }))").map(h => {
      h.pattern_index
    }),
    content="[0]",
  )
  debug_inspect(
    then_hits(rule, "wrapper({ holder(target()); danger() })").map(h => {
      h.pattern_index
    }),
    content="[1]",
  )
}

///|
test "then supports pure negatives and scans below a failed parent" {
  let rule =
    #|patterns:
    #|  - shape: wrapper(__TARGET__)
    #|    then:
    #|      patterns-not:
    #|        - shape: danger()
  inspect(
    then_hits(rule, "wrapper({ danger(); wrapper(target()) })").length(),
    content="1",
  )
  inspect(then_hits(rule, "wrapper(target())").length(), content="1")
}

///|
test "then supports sixty four rules selecting the same candidate" {
  let mut body = "patterns:\n  - shape: target()\n"
  for _ in 0..<64 {
    body = "patterns:\n  - shape: __TARGET__\n    then:\n" +
      body
      .split("\n")
      .filter(s => s != "")
      .map(s => "      " + s.to_owned())
      .join("\n") +
      "\n"
  }
  inspect(then_hits(body, "target()").length(), content="1")
}

///|
test "then applies let bindings between middle shape and target to ancestor guards" {
  let rule =
    #|patterns:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: let $(local:id) = $_; __TARGET__
    #|          then:
    #|            patterns:
    #|              - shape: target()
    #|                guard:
    #|                  $name: '^x$'
  inspect(
    then_hits(rule, "wrapper(x, { let x = 0; target() })").length(),
    content="0",
  )
  inspect(
    then_hits(rule, "wrapper(x, { let y = 0; target() })").length(),
    content="1",
  )
}

///|
test "then inherits named ellipses and equal captures through an unused level" {
  let rule =
    #|patterns:
    #|  - shape: wrapper([$$$(items:exp)], $(name:id), __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: holder(__TARGET__)
    #|          then:
    #|            patterns:
    #|              - shape: target([$$$(items:exp)], $(name:id))
  inspect(
    then_hits(rule, "wrapper([a, b], value, holder(target([a, b], value)))").length(),
    content="1",
  )
  inspect(
    then_hits(rule, "wrapper([a, b], value, holder(target([b, a], value)))").length(),
    content="0",
  )
  inspect(
    then_hits(rule, "wrapper([a, b], value, holder(target([a, b], other)))").length(),
    content="0",
  )
}

///|
test "then inside toplevel keeps root findings pending until negative checks finish" {
  let rule =
    #|inside-toplevel:
    #|  - shape: fn sample { __TARGET__ }
    #|patterns:
    #|  - shape: wrapper(__TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: target()
    #|patterns-not:
    #|  - shape: danger()
  inspect(then_hits(rule, "wrapper(target()); danger()").length(), content="0")
  inspect(
    then_hits(rule, "wrapper({ target(); danger() }); wrapper(target())").length(),
    content="2",
  )
}
