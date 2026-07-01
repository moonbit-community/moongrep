///|
test "load single rule file derives rule id from yaml id" {
  let rule = load_rule("testdata/recursive-rule-discovery-rules/nested/b.yml")
  inspect(rule.rule_id, content="example")
  inspect(
    rule.path,
    content="testdata/recursive-rule-discovery-rules/nested/b.yml",
  )
}
