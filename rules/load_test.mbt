///|
fn valid_structural_rule_source() -> String {
  let source =
    #|package: example/pkg
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
    #|package: example/pkg
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
  for index in 0..<1000 {
    let path = "/tmp/\{prefix}-\{index}"
    if !@fs.path_exists(path) {
      @fs.create_dir(path)
      return path
    }
  }
  fail("could not create temporary directory")
}

///|
fn expect_invalid_rule_info(source : String, expected : String) -> Unit raise {
  try parse_rule_source("/tmp/rules/example.yaml", "/tmp/rules", source) catch {
    RuleLoadError::InvalidRule(path=_, info~) => inspect(info, content=expected)
    _ => fail("expected RuleLoadError")
  } noraise {
    _ => fail("expected invalid rule")
  }
}

///|
test "load parses structural rule and derives yaml rule id" {
  let rule = parse_rule_source(
    "/tmp/rules/language/example.yaml",
    "/tmp/rules",
    valid_structural_rule_source(),
  )
  inspect(rule.rule_id, content="language/example")
  inspect(rule.package_name, content="example/pkg")
  inspect(rule.description, content="Repeated equality.\n")
  match rule.definition {
    Structural(spec) => {
      inspect(spec.patterns.length(), content="1")
      inspect(spec.patterns[0].shape, content="_expr == _expr")
      debug_inspect(spec.patterns[0].subtree_metavars, content="[\"_expr\"]")
      debug_inspect(spec.patterns[0].identifier_metavars, content="[]")
      inspect(spec.inside_expr is None, content="true")
    }
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "load derives yml rule id" {
  let rule = parse_rule_source(
    "/tmp/rules/language/example.yml",
    "/tmp/rules",
    valid_structural_rule_source(),
  )
  inspect(rule.rule_id, content="language/example")
}

///|
test "load parses taint rule and defaults sanitizers to empty" {
  let rule = parse_rule_source(
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
test "load recursively loads yaml files in stable order" {
  let rules_root = fresh_tmp_dir("moongrep-load-rules")
  let nested = "\{rules_root}/nested"
  @fs.create_dir(nested)
  @fs.write_string_to_file("\{rules_root}/ignored.txt", "nope")
  @fs.write_string_to_file("\{nested}/b.yml", valid_taint_rule_source())
  @fs.write_string_to_file("\{rules_root}/a.yaml", valid_structural_rule_source())
  let rules = load_rules(rules_root)
  debug_inspect([ for rule in rules => rule.rule_id ], content="[\"a\", \"nested/b\"]")
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

///|
test "load rejects unsupported top-level key" {
  let source =
    #|package: example/pkg
    #|description: Example.
    #|patterns:
    #|  - shape: x
    #|extra: nope
    #|
  expect_invalid_rule_info(
    source,
    "top-level rule contains unsupported key extra",
  )
}

///|
test "load rejects guard in runtime AST mode" {
  let source =
    #|package: example/pkg
    #|description: Example.
    #|patterns:
    #|  - shape: x
    #|    guard: x
    #|
  expect_invalid_rule_info(
    source,
    "patterns[0].guard is not supported in runtime AST mode",
  )
}

///|
test "load rejects invalid metavar buckets" {
  let source =
    #|package: example/pkg
    #|description: Example.
    #|patterns:
    #|  - shape: x
    #|    metavars:
    #|      subtree: [x]
    #|      identifier: [x]
    #|
  expect_invalid_rule_info(
    source,
    "patterns[0].metavars contains duplicate metavar x",
  )
}

///|
test "load rejects multi document and missing required keys" {
  let multi_doc =
    #|---
    #|package: example/pkg
    #|description: Example.
    #|patterns:
    #|  - shape: x
    #|---
    #|package: example/pkg
    #|description: Example.
    #|patterns:
    #|  - shape: y
    #|
  expect_invalid_rule_info(
    multi_doc,
    "rule file must contain exactly one YAML document",
  )
  let missing_package =
    #|description: Example.
    #|patterns:
    #|  - shape: x
    #|
  expect_invalid_rule_info(missing_package, "missing required key package")
}

///|
test "load rejects malformed taint schema" {
  let missing_sources =
    #|package: example/pkg
    #|description: Example.
    #|taint:
    #|  sinks:
    #|    - shape: sink(__SOURCE__)
    #|
  expect_invalid_rule_info(missing_sources, "missing required key sources")
  let empty_sinks =
    #|package: example/pkg
    #|description: Example.
    #|taint:
    #|  sources:
    #|    - shape: source()
    #|  sinks: []
    #|
  expect_invalid_rule_info(empty_sinks, "taint.sinks must not be empty")
  let bad_sanitizers =
    #|package: example/pkg
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
    #|package: example/pkg
    #|description: Example.
    #|taint:
    #|  sources:
    #|    - source()
    #|  sinks:
    #|    - shape: sink(__SOURCE__)
    #|
  expect_invalid_rule_info(
    non_mapping_clause,
    "taint.sources[0] must be a mapping",
  )
}

///|
test "load rejects malformed metavars schema" {
  let bucket_not_array =
    #|package: example/pkg
    #|description: Example.
    #|patterns:
    #|  - shape: x
    #|    metavars:
    #|      subtree: x
    #|
  expect_invalid_rule_info(
    bucket_not_array,
    "patterns[0].metavars.subtree must be an array",
  )
  let bucket_non_string =
    #|package: example/pkg
    #|description: Example.
    #|patterns:
    #|  - shape: x
    #|    metavars:
    #|      subtree: [1]
    #|
  expect_invalid_rule_info(
    bucket_non_string,
    "patterns[0].metavars.subtree[0] must be a string",
  )
}
