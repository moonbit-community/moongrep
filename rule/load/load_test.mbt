///|
using @model {type RuleLoadError}

///|
fn valid_structural_rule_source() -> String {
  let source =
    #|id: example
    #|description: |
    #|  Repeated equality.
    #|patterns:
    #|  - shape: _expr == _expr
    #|    metavars:
    #|      subtree: [_expr]
    #|
  source
}

///|
fn valid_taint_rule_source() -> String {
  let source =
    #|id: example
    #|description: |
    #|  User input reaches sink.
    #|taint:
    #|  sources:
    #|    - shape: get_user_input()
    #|  sinks:
    #|    - shape: sink(__SOURCE__)
    #|
  source
}

///|
fn fresh_tmp_dir(prefix : String) -> String raise {
  let base = "_build/moongrep-test-tmp"
  @miniio.mkdir(base) catch {
    Exist => ()
    e => raise e
  }
  let path = "\{base}/\{prefix}"
  @miniio.rmdir(path, recursive=true) catch {
    Noent => ()
    Notdir => @miniio.remove_file(path)
    e => raise e
  }
  @miniio.mkdir(path)
  path
}

///|
fn host_symlink_tests_enabled() -> Bool raise {
  @miniio.get_env_var("RUNNER_OS") != Some("Windows")
}

///|
test "load recursively loads yaml files in stable order" {
  let rules_root = fresh_tmp_dir("moongrep-load-rules")
  let nested = "\{rules_root}/nested"
  @miniio.mkdir(nested)
  @miniio.write_text_file("\{rules_root}/ignored.txt", "nope")
  @miniio.write_text_file("\{nested}/b.yml", valid_taint_rule_source())
  @miniio.write_text_file(
    "\{rules_root}/a.yaml",
    valid_structural_rule_source(),
  )
  let rules = load_rules(rules_root)
  debug_inspect(
    [
      for rule in rules => rule.rule_id
    ],
    content="[\"example\", \"nested/example\"]",
  )
}

///|
test "load follows symlinked rule directories" {
  if host_symlink_tests_enabled() {
    let rules = load_rules("testdata/symlink-fixtures/rules-dir-link")
    inspect(rules.length(), content="1")
    inspect(rules[0].rule_id, content="example")
    inspect(
      rules[0].description,
      content="Target call through symlinked rules.\n",
    )
  }
}

///|
test "load rejects empty rule directory" {
  let rules_root = fresh_tmp_dir("moongrep-empty-rules")
  try load_rules(rules_root) catch {
    RuleLoadError::InvalidRule(path=_, info~) =>
      inspect(info, content="no YAML rule files found")
    _ => fail("expected RuleLoadError")
  } noraise {
    _ => fail("expected empty rule directory to fail")
  }
}
