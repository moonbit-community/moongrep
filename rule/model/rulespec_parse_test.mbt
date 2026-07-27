///|
fn valid_structural_rule_source() -> String {
  let source =
    #|id: example
    #|description: |
    #|  Repeated equality.
    #|patterns:
    #|  - shape: $(_expr:exp) == $(_expr:exp)
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
test "model shows rule load error path and info" {
  let error = RuleLoadError::InvalidRule(
    path="/tmp/rules/example.yaml",
    info="missing required key id",
  )
  inspect(
    error.to_string(),
    content="/tmp/rules/example.yaml: missing required key id",
  )
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
      assert_eq(spec.patterns.length(), 1)
      inspect(spec.patterns[0].shape, content="$(_expr:exp) == $(_expr:exp)")
      assert_eq(spec.patterns[0].guards.length(), 0)
      assert_eq(spec.patterns_not.length(), 0)
      assert_true(spec.inside_expr.is_empty())
      assert_true(spec.inside_toplevel.is_empty())
    }
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "model preserves metavar shape text" {
  let source =
    #|id: example
    #|description: |
    #|  Metavars.
    #|patterns:
    #|  - shape: $(counter:id) + $(body:exp)
    #|
  let rule = RawRuleSpec::from_str(
    "/tmp/rules/example.yaml", "/tmp/rules", source,
  )
  match rule.definition {
    Structural(spec) =>
      inspect(spec.patterns[0].shape, content="$(counter:id) + $(body:exp)")
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
      assert_eq(spec.sources.length(), 1)
      assert_eq(spec.sinks.length(), 1)
      assert_eq(spec.sanitizers.length(), 0)
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
test "model parses structural pattern guard map" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: $(callee:id)($(value:const))
    #|    guard:
    #|      $callee: "^@html\\.render$"
    #|      $value: "danger|raw"
    #|
  let rule = RawRuleSpec::from_str(
    "/tmp/rules/example.yaml", "/tmp/rules", source,
  )
  match rule.definition {
    Structural(spec) => {
      inspect(spec.patterns[0].guards["$callee"], content="^@html\\.render$")
      inspect(spec.patterns[0].guards["$value"], content="danger|raw")
    }
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "model parses structural patterns-not shape and guard map" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: sink($(value:exp))
    #|patterns-not:
    #|  - shape: safe($(callee:id), $(literal:const))
    #|    guard:
    #|      $callee: "^allow_"
    #|      $literal: "^ok$"
    #|
  let rule = RawRuleSpec::from_str(
    "/tmp/rules/example.yaml", "/tmp/rules", source,
  )
  match rule.definition {
    Structural(spec) => {
      assert_eq(spec.patterns.length(), 1)
      assert_eq(spec.patterns_not.length(), 1)
      inspect(
        spec.patterns_not[0].shape,
        content="safe($(callee:id), $(literal:const))",
      )
      inspect(spec.patterns_not[0].guards["$callee"], content="^allow_")
      inspect(spec.patterns_not[0].guards["$literal"], content="^ok$")
    }
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "model defaults patterns-not mode to prune on negative" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: sink($(value:exp))
    #|patterns-not:
    #|  - shape: safe($(value:exp))
    #|
  let rule = RawRuleSpec::from_str(
    "/tmp/rules/example.yaml", "/tmp/rules", source,
  )
  match rule.definition {
    Structural(spec) => assert_true(spec.patterns_not_mode is PruneOnNegative)
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "model derives reject-uncovered-negative for inside expr positives and negatives" {
  let source =
    #|id: example
    #|description: Example.
    #|inside-expr:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|patterns:
    #|  - shape: arr[$(name:id)]
    #|patterns-not:
    #|  - shape: $(name:id)
    #|
  let rule = RawRuleSpec::from_str(
    "/tmp/rules/example.yaml", "/tmp/rules", source,
  )
  match rule.definition {
    Structural(spec) =>
      assert_true(spec.patterns_not_mode is RejectUncoveredNegative)
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "model parses inside toplevel shape and guard map" {
  let source =
    #|id: example
    #|description: Example.
    #|inside-toplevel:
    #|  - shape: |
    #|      fn $(name:id)($(param:id) : Int) -> Int { __TARGET__ }
    #|    guard:
    #|      $name: "^safe_"
    #|patterns:
    #|  - shape: call($(param:id))
    #|
  let rule = RawRuleSpec::from_str(
    "/tmp/rules/example.yaml", "/tmp/rules", source,
  )
  match rule.definition {
    Structural(spec) => {
      assert_eq(spec.inside_toplevel.length(), 1)
      let inside_toplevel = spec.inside_toplevel[0]
      assert_true(spec.inside_expr.is_empty())
      inspect(
        inside_toplevel.shape,
        content="fn $(name:id)($(param:id) : Int) -> Int { __TARGET__ }\n",
      )
      inspect(inside_toplevel.guards["$name"], content="^safe_")
      assert_true(inside_toplevel.match_mode is Default)
    }
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "model parses explicit inside toplevel match modes" {
  let source =
    #|id: example
    #|description: Explicit matching modes.
    #|inside-toplevel:
    #|  - shape: fn exact_fn { __TARGET__ }
    #|    match-mode: exact
    #|  - shape: fn partial_fn { __TARGET__ }
    #|    match-mode: partial
    #|patterns:
    #|  - shape: call()
    #|
  let rule = RawRuleSpec::from_str(
    "/tmp/rules/example.yaml", "/tmp/rules", source,
  )
  match rule.definition {
    Structural(spec) => {
      assert_eq(spec.inside_toplevel.length(), 2)
      assert_true(spec.inside_toplevel[0].match_mode is Exact)
      assert_true(spec.inside_toplevel[1].match_mode is Partial)
    }
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "model rejects invalid inside toplevel match modes" {
  let invalid_value =
    #|id: example
    #|description: Invalid matching mode.
    #|inside-toplevel:
    #|  - shape: fn sample { __TARGET__ }
    #|    match-mode: prefix
    #|patterns:
    #|  - shape: call()
    #|
  expect_invalid_rule_info(
    invalid_value, "inside-toplevel[0].match-mode must be exact or partial",
  )
  let invalid_type =
    #|id: example
    #|description: Invalid matching mode type.
    #|inside-toplevel:
    #|  - shape: fn sample { __TARGET__ }
    #|    match-mode: true
    #|patterns:
    #|  - shape: call()
    #|
  expect_invalid_rule_info(
    invalid_type, "inside-toplevel[0].match-mode must be a string",
  )
}

///|
test "model rejects match mode outside inside toplevel" {
  let patterns =
    #|id: example
    #|description: Invalid pattern matching mode.
    #|patterns:
    #|  - shape: call()
    #|    match-mode: exact
    #|
  expect_invalid_rule_info(
    patterns, "patterns[0] contains unsupported key match-mode",
  )
  let inside_expr =
    #|id: example
    #|description: Invalid expression matching mode.
    #|inside-expr:
    #|  - shape: wrapper(__TARGET__)
    #|    match-mode: partial
    #|patterns:
    #|  - shape: call()
    #|
  expect_invalid_rule_info(
    inside_expr, "inside-expr[0] contains unsupported key match-mode",
  )
  let taint =
    #|id: example
    #|description: Invalid taint matching mode.
    #|taint:
    #|  sources:
    #|    - shape: source()
    #|      match-mode: exact
    #|  sinks:
    #|    - shape: sink(__SOURCE__)
    #|
  expect_invalid_rule_info(
    taint, "taint.sources[0] contains unsupported key match-mode",
  )
}

///|
test "model derives reject-uncovered-negative for inside toplevel positives and negatives" {
  let source =
    #|id: example
    #|description: Example.
    #|inside-toplevel:
    #|  - shape: |
    #|      fn $(name:id) { __TARGET__ }
    #|patterns:
    #|  - shape: arr[$(name:id)]
    #|patterns-not:
    #|  - shape: $(name:id)
    #|
  let rule = RawRuleSpec::from_str(
    "/tmp/rules/example.yaml", "/tmp/rules", source,
  )
  match rule.definition {
    Structural(spec) =>
      assert_true(spec.patterns_not_mode is RejectUncoveredNegative)
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "model rejects patterns-not-mode as an unsupported top-level key" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns-not-mode: covered-by-patterns
    #|patterns:
    #|  - shape: x
    #|
  expect_invalid_rule_info(
    source, "top-level rule contains unsupported key patterns-not-mode",
  )
}

///|
test "model allows inside expr with only patterns-not" {
  let source =
    #|id: example
    #|description: Example.
    #|inside-expr:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|patterns-not:
    #|  - shape: block($(name:id))
    #|
  let rule = RawRuleSpec::from_str(
    "/tmp/rules/example.yaml", "/tmp/rules", source,
  )
  match rule.definition {
    Structural(spec) => {
      assert_eq(spec.inside_expr.length(), 1)
      let inside_expr = spec.inside_expr[0]
      inspect(inside_expr.shape, content="wrapper($(name:id), __TARGET__)")
      assert_eq(inside_expr.guards.length(), 0)
      assert_eq(spec.patterns.length(), 0)
      assert_eq(spec.patterns_not.length(), 1)
      inspect(spec.patterns_not[0].shape, content="block($(name:id))")
    }
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "model allows inside toplevel with only patterns-not" {
  let source =
    #|id: example
    #|description: Example.
    #|inside-toplevel:
    #|  - shape: |
    #|      fn $(name:id) { __TARGET__ }
    #|patterns-not:
    #|  - shape: block($(name:id))
    #|
  let rule = RawRuleSpec::from_str(
    "/tmp/rules/example.yaml", "/tmp/rules", source,
  )
  match rule.definition {
    Structural(spec) => {
      assert_eq(spec.inside_toplevel.length(), 1)
      let inside_toplevel = spec.inside_toplevel[0]
      inspect(inside_toplevel.shape, content="fn $(name:id) { __TARGET__ }\n")
      assert_eq(inside_toplevel.guards.length(), 0)
      assert_eq(spec.patterns.length(), 0)
      assert_eq(spec.patterns_not.length(), 1)
      inspect(spec.patterns_not[0].shape, content="block($(name:id))")
    }
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "model parses inside expr shape and guard map" {
  let source =
    #|id: example
    #|description: Example.
    #|inside-expr:
    #|  - shape: wrapper($(name:id), $(lit:const), __TARGET__)
    #|    guard:
    #|      $name: "^safe_"
    #|      $lit: "^ok$"
    #|patterns:
    #|  - shape: call($(name:id))
    #|
  let rule = RawRuleSpec::from_str(
    "/tmp/rules/example.yaml", "/tmp/rules", source,
  )
  match rule.definition {
    Structural(spec) => {
      assert_eq(spec.inside_expr.length(), 1)
      let inside_expr = spec.inside_expr[0]
      inspect(
        inside_expr.shape,
        content="wrapper($(name:id), $(lit:const), __TARGET__)",
      )
      inspect(inside_expr.guards["$name"], content="^safe_")
      inspect(inside_expr.guards["$lit"], content="^ok$")
    }
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "model rejects scalar inside toplevel" {
  let source =
    #|id: example
    #|description: Example.
    #|inside-toplevel: fn sample { __TARGET__ }
    #|patterns:
    #|  - shape: call()
    #|
  expect_invalid_rule_info(source, "inside-toplevel must be an array")
}

///|
test "model rejects malformed inside toplevel object schema" {
  let missing_shape =
    #|id: example
    #|description: Example.
    #|inside-toplevel:
    #|  - guard:
    #|      $name: "^safe_"
    #|patterns:
    #|  - shape: call()
    #|
  expect_invalid_rule_info(
    missing_shape, "missing required key inside-toplevel[0].shape",
  )
  let unsupported_key =
    #|id: example
    #|description: Example.
    #|inside-toplevel:
    #|  - shape: fn sample { __TARGET__ }
    #|    extra: nope
    #|patterns:
    #|  - shape: call()
    #|
  expect_invalid_rule_info(
    unsupported_key, "inside-toplevel[0] contains unsupported key extra",
  )
  let non_mapping_guard =
    #|id: example
    #|description: Example.
    #|inside-toplevel:
    #|  - shape: fn sample { __TARGET__ }
    #|    guard: nope
    #|patterns:
    #|  - shape: call()
    #|
  expect_invalid_rule_info(
    non_mapping_guard, "inside-toplevel[0].guard must be a mapping",
  )
  let non_string_guard_value =
    #|id: example
    #|description: Example.
    #|inside-toplevel:
    #|  - shape: fn sample { __TARGET__ }
    #|    guard:
    #|      $name: 1
    #|patterns:
    #|  - shape: call()
    #|
  expect_invalid_rule_info(
    non_string_guard_value, "inside-toplevel[0].guard.$name must be a string",
  )
}

///|
test "model rejects invalid inside toplevel combinations" {
  let with_taint =
    #|id: example
    #|description: Example.
    #|inside-toplevel:
    #|  - shape: fn sample { __TARGET__ }
    #|taint:
    #|  sources:
    #|    - shape: source()
    #|  sinks:
    #|    - shape: sink(__SOURCE__)
    #|
  expect_invalid_rule_info(
    with_taint, "inside-toplevel is only supported for structural rules",
  )
  let with_inside_expr =
    #|id: example
    #|description: Example.
    #|inside-expr:
    #|  - shape: wrapper(__TARGET__)
    #|inside-toplevel:
    #|  - shape: fn sample { __TARGET__ }
    #|patterns:
    #|  - shape: call()
    #|
  expect_invalid_rule_info(
    with_inside_expr, "inside-expr and inside-toplevel are mutually exclusive",
  )
  let inside_only =
    #|id: example
    #|description: Example.
    #|inside-toplevel:
    #|  - shape: fn sample { __TARGET__ }
    #|
  expect_invalid_rule_info(
    inside_only, "inside-toplevel requires patterns or patterns-not",
  )
}

///|
test "model rejects scalar inside expr" {
  let source =
    #|id: example
    #|description: Example.
    #|inside-expr: wrapper($(name:id), __TARGET__)
    #|patterns:
    #|  - shape: call($(name:id))
    #|
  expect_invalid_rule_info(source, "inside-expr must be an array")
}

///|
test "model rejects malformed inside expr object schema" {
  let missing_shape =
    #|id: example
    #|description: Example.
    #|inside-expr:
    #|  - guard:
    #|      $name: "^safe_"
    #|patterns:
    #|  - shape: call($(name:id))
    #|
  expect_invalid_rule_info(
    missing_shape, "missing required key inside-expr[0].shape",
  )
  let non_string_shape =
    #|id: example
    #|description: Example.
    #|inside-expr:
    #|  - shape: 1
    #|patterns:
    #|  - shape: call($(name:id))
    #|
  expect_invalid_rule_info(
    non_string_shape, "inside-expr[0].shape must be a string",
  )
  let unsupported_key =
    #|id: example
    #|description: Example.
    #|inside-expr:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|    extra: nope
    #|patterns:
    #|  - shape: call($(name:id))
    #|
  expect_invalid_rule_info(
    unsupported_key, "inside-expr[0] contains unsupported key extra",
  )
  let non_mapping_guard =
    #|id: example
    #|description: Example.
    #|inside-expr:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|    guard: nope
    #|patterns:
    #|  - shape: call($(name:id))
    #|
  expect_invalid_rule_info(
    non_mapping_guard, "inside-expr[0].guard must be a mapping",
  )
  let non_string_guard_value =
    #|id: example
    #|description: Example.
    #|inside-expr:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|    guard:
    #|      $name: 1
    #|patterns:
    #|  - shape: call($(name:id))
    #|
  expect_invalid_rule_info(
    non_string_guard_value, "inside-expr[0].guard.$name must be a string",
  )
  let bare_guard_key =
    #|id: example
    #|description: Example.
    #|inside-expr:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|    guard:
    #|      name: "^safe_"
    #|patterns:
    #|  - shape: call($(name:id))
    #|
  expect_invalid_rule_info(
    bare_guard_key, "inside-expr[0].guard.name must be a $-prefixed metavar name",
  )
}

///|
test "model rejects malformed patterns-not schema" {
  let non_array =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: x
    #|patterns-not: nope
    #|
  expect_invalid_rule_info(non_array, "patterns-not must be an array")
  let empty_array =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: x
    #|patterns-not: []
    #|
  expect_invalid_rule_info(empty_array, "patterns-not must not be empty")
  let non_mapping_clause =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: x
    #|patterns-not:
    #|  - x
    #|
  expect_invalid_rule_info(
    non_mapping_clause, "patterns-not[0] must be a mapping",
  )
}

///|
test "model rejects invalid patterns-not combinations" {
  let only_patterns_not =
    #|id: example
    #|description: Example.
    #|patterns-not:
    #|  - shape: x
    #|
  expect_invalid_rule_info(
    only_patterns_not, "patterns-not requires patterns, inside-expr, or inside-toplevel",
  )
  let taint_patterns_not =
    #|id: example
    #|description: Example.
    #|patterns-not:
    #|  - shape: x
    #|taint:
    #|  sources:
    #|    - shape: source()
    #|  sinks:
    #|    - shape: sink(__SOURCE__)
    #|
  expect_invalid_rule_info(
    taint_patterns_not, "patterns-not is only supported for structural rules",
  )
  let inside_only =
    #|id: example
    #|description: Example.
    #|inside-expr:
    #|  - shape: wrapper(__TARGET__)
    #|
  expect_invalid_rule_info(
    inside_only, "inside-expr requires patterns or patterns-not",
  )
}

///|
test "model rejects malformed structural guard schema" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: x
    #|    guard: x
    #|
  expect_invalid_rule_info(source, "patterns[0].guard must be a mapping")
  let non_string_value =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: $(name:id)
    #|    guard:
    #|      $name: 1
    #|
  expect_invalid_rule_info(
    non_string_value, "patterns[0].guard.$name must be a string",
  )
  let bare_guard_key =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: $(name:id)
    #|    guard:
    #|      name: "^safe_"
    #|
  expect_invalid_rule_info(
    bare_guard_key, "patterns[0].guard.name must be a $-prefixed metavar name",
  )
}

///|
test "model rejects yaml metavars key" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: $(x:exp) == $(x:exp)
    #|    metavars: [x]
    #|
  expect_invalid_rule_info(
    source, "patterns[0] contains unsupported key metavars",
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
    missing_definition, "rule must contain patterns, patterns-not with inside-expr or inside-toplevel, or taint",
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
  let taint_guard =
    #|id: example
    #|description: Example.
    #|taint:
    #|  sources:
    #|    - shape: source()
    #|      guard:
    #|        name: x
    #|  sinks:
    #|    - shape: sink(__SOURCE__)
    #|
  expect_invalid_rule_info(
    taint_guard, "taint.sources[0].guard is not supported for taint rules",
  )
}

///|
test "model parses ordered inside expr alternatives" {
  let source =
    #|id: example
    #|description: Multiple expression contexts.
    #|inside-expr:
    #|  - shape: wrapper(__TARGET__)
    #|  - shape: container($(name:id), __TARGET__)
    #|    guard:
    #|      $name: "^safe_"
    #|patterns:
    #|  - shape: target()
    #|
  let rule = RawRuleSpec::from_str(
    "/tmp/rules/example.yaml", "/tmp/rules", source,
  )
  match rule.definition {
    Structural(spec) => {
      assert_eq(spec.inside_expr.length(), 2)
      inspect(spec.inside_expr[0].shape, content="wrapper(__TARGET__)")
      inspect(
        spec.inside_expr[1].shape,
        content="container($(name:id), __TARGET__)",
      )
      inspect(spec.inside_expr[1].guards["$name"], content="^safe_")
      assert_true(spec.inside_toplevel.is_empty())
    }
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "model parses ordered inside toplevel alternatives" {
  let source =
    #|id: example
    #|description: Multiple top-level contexts.
    #|inside-toplevel:
    #|  - shape: fn $(name:id) { __TARGET__ }
    #|  - shape: let $(name:id) = wrapper(__TARGET__)
    #|patterns:
    #|  - shape: target($(name:id))
    #|
  let rule = RawRuleSpec::from_str(
    "/tmp/rules/example.yaml", "/tmp/rules", source,
  )
  match rule.definition {
    Structural(spec) => {
      assert_eq(spec.inside_toplevel.length(), 2)
      inspect(
        spec.inside_toplevel[0].shape,
        content="fn $(name:id) { __TARGET__ }",
      )
      inspect(
        spec.inside_toplevel[1].shape,
        content="let $(name:id) = wrapper(__TARGET__)",
      )
      assert_true(spec.inside_expr.is_empty())
    }
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "model rejects old and empty inside context forms" {
  let old_expr_mapping =
    #|id: example
    #|description: Example.
    #|inside-expr:
    #|  shape: wrapper(__TARGET__)
    #|patterns:
    #|  - shape: target()
    #|
  expect_invalid_rule_info(old_expr_mapping, "inside-expr must be an array")
  let old_toplevel_mapping =
    #|id: example
    #|description: Example.
    #|inside-toplevel:
    #|  shape: fn sample { __TARGET__ }
    #|patterns:
    #|  - shape: target()
    #|
  expect_invalid_rule_info(
    old_toplevel_mapping, "inside-toplevel must be an array",
  )
  let empty_expr =
    #|id: example
    #|description: Example.
    #|inside-expr: []
    #|patterns:
    #|  - shape: target()
    #|
  expect_invalid_rule_info(empty_expr, "inside-expr must not be empty")
  let empty_toplevel =
    #|id: example
    #|description: Example.
    #|inside-toplevel: []
    #|patterns:
    #|  - shape: target()
    #|
  expect_invalid_rule_info(empty_toplevel, "inside-toplevel must not be empty")
}

///|
test "model indexes malformed inside context alternatives" {
  let non_mapping =
    #|id: example
    #|description: Example.
    #|inside-expr:
    #|  - shape: wrapper(__TARGET__)
    #|  - container(__TARGET__)
    #|patterns:
    #|  - shape: target()
    #|
  expect_invalid_rule_info(non_mapping, "inside-expr[1] must be a mapping")
  let unsupported_key =
    #|id: example
    #|description: Example.
    #|inside-toplevel:
    #|  - shape: fn sample { __TARGET__ }
    #|  - shape: let value = __TARGET__
    #|    extra: nope
    #|patterns:
    #|  - shape: target()
    #|
  expect_invalid_rule_info(
    unsupported_key, "inside-toplevel[1] contains unsupported key extra",
  )
  let invalid_guard =
    #|id: example
    #|description: Example.
    #|inside-expr:
    #|  - shape: wrapper(__TARGET__)
    #|  - shape: container($(name:id), __TARGET__)
    #|    guard:
    #|      name: "^safe_"
    #|patterns:
    #|  - shape: target()
    #|
  expect_invalid_rule_info(
    invalid_guard, "inside-expr[1].guard.name must be a $-prefixed metavar name",
  )
}
