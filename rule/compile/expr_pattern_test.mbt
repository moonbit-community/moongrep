///|
fn compile_expr_pattern_through_rule(
  shape : String,
) -> @matching.CompiledExprPattern raise {
  let source =
    $|id: anonymous
    $|description: Anonymous expression pattern.
    $|patterns:
    $|  - shape: \{shape}
    $|
  let rules = compile_rules([
    @model.RawRuleSpec::from_str(
      "/tmp/rules/anonymous.yaml", "/tmp/rules", source,
    ),
  ])
  guard rules is [rule] else { fail("expected one compiled rule") }
  match rule.definition {
    Structural(structural) => {
      guard structural.patterns is [pattern] else {
        fail("expected one compiled structural pattern")
      }
      pattern.compiled
    }
    Taint(_) => fail("expected a structural rule")
  }
}

///|
fn expr_pattern_test_candidate(source : String) -> @untyped_cst.CstNode raise {
  let parsed = @untyped_cst.parse_expression(
    source,
    name="compiled expression pattern test",
  )
  guard parsed.diagnostics_view().is_empty() else {
    fail("expected candidate expression to parse")
  }
  @cst.expression_root(parsed.root())
}

///|
fn direct_expr_pattern_error(shape : String) -> (String, String, String) raise {
  try ignore(compile_expr_pattern(shape)) catch {
    @model.RuleLoadError::InvalidPattern(path~, shape=error_shape, info~) =>
      (path, error_shape, info)
    _ => fail("expected InvalidPattern from direct compilation")
  } noraise {
    _ => fail("expected direct expression pattern compilation to fail")
  }
}

///|
fn rule_expr_pattern_error_info(shape : String) -> String raise {
  try ignore(compile_expr_pattern_through_rule(shape)) catch {
    @model.RuleLoadError::InvalidPattern(path=_, shape=_, info~) => info
    _ => fail("expected InvalidPattern from rule compilation")
  } noraise {
    _ => fail("expected rule expression pattern compilation to fail")
  }
}

///|
test "compile_expr_pattern matches one raw rule pattern" {
  let shape = "sink($(value:exp), $(name:id), $(literal:const))"
  let direct = compile_expr_pattern(shape)
  let through_rule = compile_expr_pattern_through_rule(shape)
  assert_eq(direct.cst.kind, through_rule.cst.kind)
  assert_eq(
    direct.ignored_fields.length(),
    through_rule.ignored_fields.length(),
  )
  assert_eq(
    direct.metavars.special_expr_placeholders.length(),
    through_rule.metavars.special_expr_placeholders.length(),
  )
  assert_eq(
    direct.metavars.entries.length(),
    through_rule.metavars.entries.length(),
  )
  for index in 0..<direct.metavars.entries.length() {
    assert_eq(
      direct.metavars.entries[index].name,
      through_rule.metavars.entries[index].name,
    )
    assert_true(
      direct.metavars.entries[index].kind ==
      through_rule.metavars.entries[index].kind,
    )
  }
  let candidate = expr_pattern_test_candidate("sink(make(), field, 42)")
  guard @matching.match_expr_pattern(direct, candidate) is Some(direct_match) else {
    fail("expected directly compiled pattern to match")
  }
  guard @matching.match_expr_pattern(through_rule, candidate)
    is Some(rule_match) else {
    fail("expected rule-compiled pattern to match")
  }
  assert_eq(direct_match.root.kind, rule_match.root.kind)
  for name in ["value", "name", "literal"] {
    assert_true(direct_match.bindings.get(name) is Some(_))
    assert_true(rule_match.bindings.get(name) is Some(_))
  }
}

///|
test "compile_expr_pattern preserves ordinary pattern validation" {
  for
    case in [
      ("target(", "the pattern is not a valid MoonBit expression"),
      ("__TARGET__", "the pattern must not contain __TARGET__"),
    ] {
    let (path, shape, info) = direct_expr_pattern_error(case.0)
    assert_eq(path, case.0)
    assert_eq(shape, case.0)
    assert_true(info.contains(case.1))
    assert_eq(info, rule_expr_pattern_error_info(case.0))
  }
}
