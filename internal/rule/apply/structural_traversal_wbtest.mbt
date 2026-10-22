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
