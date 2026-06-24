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
fn expect_invalid_rule_info(source : String, expected : String) -> Unit raise {
  try
    RawRuleSpec::from_str("/tmp/rules/example.yaml", "/tmp/rules", source)
  catch {
    RuleLoadError::InvalidRule(path=_, info~) => inspect(info, content=expected)
    _ => fail("expected RuleLoadError")
  } noraise {
    _ => fail("expected invalid rule")
  }
}

///|
test "model parses structural rule and prefixes yaml id with rule directory" {
  let rule = RawRuleSpec::from_str(
    "/tmp/rules/language/example.yaml",
    "/tmp/rules",
    valid_structural_rule_source(),
  )
  inspect(rule.rule_id, content="language/example")
  inspect(rule.description, content="Repeated equality.\n")
  match rule.definition {
    Structural(spec) => {
      inspect(spec.patterns.length(), content="1")
      inspect(spec.patterns[0].shape, content="_expr == _expr")
      debug_inspect(spec.patterns[0].subtree_metavars, content="[\"_expr\"]")
      debug_inspect(spec.patterns[0].identifier_metavars, content="[]")
      debug_inspect(spec.patterns[0].auto_metavars, content="[]")
      assert_true(spec.inside_expr is None)
    }
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "model parses auto metavar shorthand" {
  let source =
    #|id: example
    #|description: |
    #|  Auto metavars.
    #|patterns:
    #|  - shape: counter + body
    #|    metavars: [counter, body]
    #|
  let rule = RawRuleSpec::from_str(
    "/tmp/rules/example.yaml", "/tmp/rules", source,
  )
  match rule.definition {
    Structural(spec) => {
      debug_inspect(spec.patterns[0].subtree_metavars, content="[]")
      debug_inspect(spec.patterns[0].identifier_metavars, content="[]")
      debug_inspect(
        spec.patterns[0].auto_metavars,
        content="[\"counter\", \"body\"]",
      )
    }
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "model derives root rule id from yaml id" {
  let rule = RawRuleSpec::from_str(
    "/tmp/rules/from-filename.yaml",
    "/tmp/rules",
    valid_structural_rule_source(),
  )
  inspect(rule.rule_id, content="example")
}

///|
test "model ignores yaml and yml file names when deriving rule id" {
  let yaml_rule = RawRuleSpec::from_str(
    "/tmp/rules/language/first.yaml",
    "/tmp/rules",
    valid_structural_rule_source(),
  )
  let yml_rule = RawRuleSpec::from_str(
    "/tmp/rules/language/second.yml",
    "/tmp/rules",
    valid_structural_rule_source(),
  )
  inspect(yaml_rule.rule_id, content="language/example")
  inspect(yml_rule.rule_id, content="language/example")
}

///|
test "model derives nested yml rule id from yaml id" {
  let rule = RawRuleSpec::from_str(
    "/tmp/rules/language/ignored-file-name.yml",
    "/tmp/rules",
    valid_structural_rule_source(),
  )
  inspect(rule.rule_id, content="language/example")
}

///|
test "model parses taint rule and defaults sanitizers to empty" {
  let rule = RawRuleSpec::from_str(
    "/tmp/rules/taint/user-input.yaml",
    "/tmp/rules",
    valid_taint_rule_source(),
  )
  match rule.definition {
    Taint(spec) => {
      inspect(spec.sources.length(), content="1")
      inspect(spec.sinks.length(), content="1")
      inspect(spec.sanitizers.length(), content="0")
    }
    Structural(_) => fail("expected taint rule")
  }
}

///|
test "model rejects unsupported top-level key" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: x
    #|extra: nope
    #|
  expect_invalid_rule_info(
    source, "top-level rule contains unsupported key extra",
  )
}

///|
test "model rejects old package key" {
  let source =
    #|package: example/pkg
    #|description: Example.
    #|patterns:
    #|  - shape: x
    #|
  expect_invalid_rule_info(
    source, "top-level rule contains unsupported key package",
  )
}

///|
test "model rejects invalid id schema" {
  let missing_id =
    #|description: Example.
    #|patterns:
    #|  - shape: x
    #|
  expect_invalid_rule_info(missing_id, "missing required key id")
  let non_string_id =
    #|id: 1
    #|description: Example.
    #|patterns:
    #|  - shape: x
    #|
  expect_invalid_rule_info(non_string_id, "id must be a string")
  let empty_id =
    #|id: ""
    #|description: Example.
    #|patterns:
    #|  - shape: x
    #|
  expect_invalid_rule_info(empty_id, "id must not be empty")
  let slash_id =
    #|id: nested/example
    #|description: Example.
    #|patterns:
    #|  - shape: x
    #|
  expect_invalid_rule_info(slash_id, "id must not contain /")
}

///|
test "model rejects guard in runtime AST mode" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: x
    #|    guard: x
    #|
  expect_invalid_rule_info(
    source, "patterns[0].guard is not supported in runtime AST mode",
  )
}

///|
test "model rejects invalid metavar buckets" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: x
    #|    metavars:
    #|      subtree: [x]
    #|      identifier: [x]
    #|
  expect_invalid_rule_info(
    source, "patterns[0].metavars contains duplicate metavar x",
  )
}

///|
test "model rejects multi document and missing required keys" {
  let multi_doc =
    #|---
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: x
    #|---
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: y
    #|
  expect_invalid_rule_info(
    multi_doc, "rule file must contain exactly one YAML document",
  )
  let missing_description =
    #|id: example
    #|patterns:
    #|  - shape: x
    #|
  expect_invalid_rule_info(
    missing_description, "missing required key description",
  )
  let missing_definition =
    #|id: example
    #|description: Example.
    #|
  expect_invalid_rule_info(
    missing_definition, "rule must contain exactly one of patterns or taint",
  )
}

///|
test "model rejects malformed taint schema" {
  let missing_sources =
    #|id: example
    #|description: Example.
    #|taint:
    #|  sinks:
    #|    - shape: sink(__SOURCE__)
    #|
  expect_invalid_rule_info(missing_sources, "missing required key sources")
  let empty_sinks =
    #|id: example
    #|description: Example.
    #|taint:
    #|  sources:
    #|    - shape: source()
    #|  sinks: []
    #|
  expect_invalid_rule_info(empty_sinks, "taint.sinks must not be empty")
  let bad_sanitizers =
    #|id: example
    #|description: Example.
    #|taint:
    #|  sources:
    #|    - shape: source()
    #|  sinks:
    #|    - shape: sink(__SOURCE__)
    #|  sanitizers: nope
    #|
  expect_invalid_rule_info(bad_sanitizers, "sanitizers must be an array")
  let non_mapping_clause =
    #|id: example
    #|description: Example.
    #|taint:
    #|  sources:
    #|    - source()
    #|  sinks:
    #|    - shape: sink(__SOURCE__)
    #|
  expect_invalid_rule_info(
    non_mapping_clause, "taint.sources[0] must be a mapping",
  )
}

///|
test "model rejects malformed metavars schema" {
  let bucket_not_array =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: x
    #|    metavars:
    #|      subtree: x
    #|
  expect_invalid_rule_info(
    bucket_not_array, "patterns[0].metavars.subtree must be an array",
  )
  let bucket_non_string =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: x
    #|    metavars:
    #|      subtree: [1]
    #|
  expect_invalid_rule_info(
    bucket_non_string, "patterns[0].metavars.subtree[0] must be a string",
  )
  let auto_duplicate =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: x
    #|    metavars: [x, x]
    #|
  expect_invalid_rule_info(
    auto_duplicate, "patterns[0].metavars contains duplicate metavar x",
  )
  let auto_non_string =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: x
    #|    metavars: [1]
    #|
  expect_invalid_rule_info(
    auto_non_string, "patterns[0].metavars[0] must be a string",
  )
  let unsupported_auto_bucket =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: x
    #|    metavars:
    #|      auto: [x]
    #|
  expect_invalid_rule_info(
    unsupported_auto_bucket, "patterns[0].metavars contains unsupported key auto",
  )
}
