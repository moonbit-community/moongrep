///|
test "inside reports each nested closure finding once at depths zero through six" {
  let single = ScanPlan::from_rules(
    compile_scan_plan_rules([
      (
        #|id: single
        #|description: One structural pattern.
        #|inside-toplevel:
        #|  - shape: async fn sample { __TARGET__ }
        #|patterns:
        #|  - shape: target()
      ),
    ]),
  )
  let builtin = ScanPlan::from_rules(
    @compile.compile_rules(@builtin.load_rules()).filter(rule => {
      rule.rule_id == "moonbitlang/catch_all"
    }),
  )
  for depth in 0..<=6 {
    for
      (plan, leaf) in [
        (single, "target()"),
        (builtin, "try risky() catch { _ => () }"),
      ] {
      let mut body = leaf
      for _ in 0..<depth {
        body = "fn() { \{body} }"
      }
      for
        wrapped in [
          body,
          "if ready() { \{body} }",
          "let closure = \{body}; finish()",
        ] {
        let root = parse_scan_plan_root("async fn sample { \{wrapped} }")
        let findings = apply_structural_scan_plan_to_node(
          "nested.mbt", root, plan,
        )
        assert_eq(findings.length(), 1)
        assert_eq(findings[0].pattern_index, 0)
      }
    }
  }
}

///|
test "ordinary indexed and context scans share closure and explicit block candidates" {
  let header = "id: blocks\ndescription: Explicit blocks.\n"
  let patterns = "patterns:\n  - shape: '{ a; b }'\n"
  let plain = ScanPlan::from_rules(compile_scan_plan_rules([header + patterns]))
  let indexed = force_indexed_root_entries(plain)
  let inside = ScanPlan::from_rules(
    compile_scan_plan_rules([
      header +
      "inside-toplevel:\n  - shape: fn sample { __TARGET__ }\n" +
      patterns,
    ]),
  )
  for
    (body, expected) in [
      ("fn() { a; b }", 0),
      ("let closure = fn() { a; b }; finish()", 0),
      ("fn() { { a; b } }", 1),
      ("let closure = fn() { { a; b } }; { a; b }", 2),
    ] {
    let root = parse_scan_plan_root("fn sample { \{body} }")
    let direct_hits = apply_structural_scan_plan_to_node(
      "blocks.mbt", root, plain,
    )
    assert_eq(direct_hits.length(), expected)
    for plan in [indexed, inside] {
      assert_eq(
        apply_structural_scan_plan_to_node("blocks.mbt", root, plan).map(
          complete_finding_signature,
        ),
        direct_hits.map(complete_finding_signature),
      )
    }
  }
}

///|
test "then searches nested closures with the ordinary block boundary" {
  let rules = compile_scan_plan_rules([
    (
      #|id: then-block
      #|description: Explicit block below a selected closure.
      #|patterns:
      #|  - shape: wrapper(__TARGET__)
      #|    then:
      #|      patterns:
      #|        - shape: '{ a; b }'
    ),
  ])
  let plan = ScanPlan::from_rules(rules)
  for (body, expected) in [("fn() { a; b }", 0), ("fn() { { a; b } }", 1)] {
    let root = parse_scan_plan_root("fn sample { wrapper(\{body}) }")
    let hits = apply_structural_scan_plan_to_node("then.mbt", root, plan)
    assert_eq(hits.length(), expected)
    for hit in hits {
      assert_eq(hit.loc.start.column(), 13)
    }
  }
}
