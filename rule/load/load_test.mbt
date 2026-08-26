///|
fn native_rule_test_path(path : String) -> String {
  if @path.sep == '\\' {
    path.replace_all(old="/", new="\\")
  } else {
    path
  }
}

///|
async test "load single rule file derives rule id from yaml id" {
  let rule_file = if @path.sep == '\\' {
    ".\\testdata/recursive-rule-discovery-rules\\nested\\.\\b.yml"
  } else {
    "testdata/recursive-rule-discovery-rules/nested/b.yml"
  }
  let rule = load_rule(rule_file)
  inspect(rule.rule_id, content="example")
  inspect(
    rule.path,
    content=native_rule_test_path(
      "testdata/recursive-rule-discovery-rules/nested/b.yml",
    ),
  )
}

///|
async test "load rule directory normalizes traversal paths and keeps slash ids" {
  let rules_root = if @path.sep == '\\' {
    ".\\testdata/recursive-rule-discovery-rules\\."
  } else {
    "testdata/recursive-rule-discovery-rules"
  }
  let rules = load_rules(rules_root)
  let ids : Array[String] = []
  let paths : Array[String] = []
  for rule in rules {
    ids.push(rule.rule_id)
    paths.push(rule.path)
  }
  assert_eq(ids, ["example", "nested/example"])
  assert_eq(paths, [
    native_rule_test_path("testdata/recursive-rule-discovery-rules/a.yaml"),
    native_rule_test_path(
      "testdata/recursive-rule-discovery-rules/nested/b.yml",
    ),
  ])
}
