///|
fn explicit_regex_capture_cases(label : String) -> Array[(String, String)] {
  [
    (
      "lexscan $_ { (re\"a\", \{label}=$(name:id)) => __TARGET__ }",
      "lexscan input { (re\"a\", \{label}=item) => { BODY } }",
    ),
    (
      "if $_ =~ (re\"a\", \{label}=$(name:id)) { __TARGET__ }",
      "if input =~ (re\"a\", \{label}=item) { BODY }",
    ),
  ]
}

///|
test "explicit regex captures survive inside-toplevel and recursive then" {
  for label in ["before", "after"] {
    for (shape, expression) in explicit_regex_capture_cases(label) {
      let nested = "id: regex-origin\ndescription: Preserve the explicit regex binder.\npatterns:\n  - shape: '\{shape}'\n    then:\n      patterns:\n        - shape: middle(__TARGET__)\n          then:\n            patterns:\n              - shape: sink($(name:id))"
      let toplevel = "id: regex-origin\ndescription: Preserve the explicit regex binder.\ninside-toplevel:\n  - shape: 'fn $_ { \{shape} }'\npatterns:\n  - shape: middle(__TARGET__)\n    then:\n      patterns:\n        - shape: sink($(name:id))"
      for (binding, expected) in [("item", 0), ("other", 1)] {
        let body = "middle({ let \{binding} = source(); sink(item) })"
        let source = "fn sample(item : Int) { " +
          expression.replace(old="BODY", new=body) +
          " }"
        for rule in [nested, toplevel] {
          assert_eq(
            apply_structural_rule_findings(source, rule).length(),
            expected,
          )
        }
      }
    }
  }
}

///|
test "negative patterns and ancestor guards retain explicit regex capture origins" {
  for label in ["before", "after"] {
    for (shape, expression) in explicit_regex_capture_cases(label) {
      let negative = "id: regex-negative\ndescription: Reject only sinks using the regex binding.\npatterns:\n  - shape: '\{shape}'\n    then:\n      patterns-not:\n        - shape: let $_ = $_; sink($(name:id))"
      let guarded = "id: regex-guard\ndescription: Keep an ancestor regex binding visible across levels.\npatterns:\n  - shape: '\{shape}'\n    then:\n      patterns:\n        - shape: middle(__TARGET__)\n          then:\n            patterns:\n              - shape: sink($_)\n                guard:\n                  $name: '^item$'"
      for (binding, expected) in [("item", 0), ("other", 1)] {
        let body = "let \{binding} = source(); sink(item)"
        let negative_source = "fn sample { " +
          expression.replace(old="BODY", new=body) +
          " }"
        assert_eq(
          apply_structural_rule_findings(negative_source, negative).length(),
          1 - expected,
        )
        let guard_source = "fn sample { " +
          expression.replace(old="BODY", new="middle({ \{body} })") +
          " }"
        assert_eq(
          apply_structural_rule_findings(guard_source, guarded).length(),
          expected,
        )
      }
    }
  }
}

///|
test "repeated regex captures keep the first occurrence as their inherited source" {
  for label in ["before", "after"] {
    for (shape, expression) in explicit_regex_capture_cases(label) {
      let rule = "id: regex-first\ndescription: Repeated captures preserve the first binding.\npatterns:\n  - shape: 'wrapper($(name:id), \{shape})'\n    then:\n      patterns:\n        - shape: sink($(name:id))"
      let source = "fn sample(item : Int) { wrapper(item, " +
        expression.replace(old="BODY", new="sink(item)") +
        ") }"
      assert_eq(apply_structural_rule_findings(source, rule).length(), 0)
      let binder_first = "id: regex-first\ndescription: A repeated reference does not replace the regex binding.\npatterns:\n  - shape: '" +
        shape.replace(old="__TARGET__", new="middle($(name:id), __TARGET__)") +
        "'\n    then:\n      patterns:\n        - shape: sink($(name:id))"
      let source = "fn sample { " +
        expression.replace(
          old="BODY",
          new="middle(item, { let item = source(); sink(item) })",
        ) +
        " }"
      assert_eq(
        apply_structural_rule_findings(source, binder_first).length(),
        0,
      )
    }
  }
}
