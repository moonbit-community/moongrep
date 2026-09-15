///|
fn compile_inside_toplevel_pattern_through_rule(
  shape : String,
) -> @matching.CompiledExprPattern raise {
  let source =
    $|id: example
    $|description: Direct inside-toplevel compilation.
    $|inside-toplevel:
    $|  - shape: \{shape}
    $|patterns:
    $|  - shape: marker()
    $|
  let rules = compile_one(source)
  guard rules is [rule] else { fail("expected one compiled rule") }
  match rule.definition {
    Structural(structural) => {
      guard structural.inside_toplevel is [pattern] else {
        fail("expected one compiled inside-toplevel pattern")
      }
      pattern.compiled
    }
    Taint(_) => fail("expected a structural rule")
  }
}

///|
fn direct_inside_toplevel_pattern_error(
  shape : String,
) -> (String, String, String) raise {
  try ignore(compile_inside_toplevel_pattern(shape)) catch {
    @model.RuleLoadError::InvalidPattern(path~, shape=error_shape, info~) =>
      (path, error_shape, info)
    _ => fail("expected InvalidPattern from direct compilation")
  } noraise {
    _ => fail("expected direct inside-toplevel compilation to fail")
  }
}

///|
fn rule_inside_toplevel_pattern_error_info(shape : String) -> String raise {
  try ignore(compile_inside_toplevel_pattern_through_rule(shape)) catch {
    @model.RuleLoadError::InvalidPattern(path=_, shape=_, info~) => info
    _ => fail("expected InvalidPattern from rule compilation")
  } noraise {
    _ => fail("expected rule inside-toplevel compilation to fail")
  }
}

///|
test "compile_inside_toplevel_pattern matches one default rule entry" {
  let shape = "fn $(name:id) { __TARGET__ }"
  let direct = compile_inside_toplevel_pattern(shape)
  let through_rule = compile_inside_toplevel_pattern_through_rule(shape)
  assert_eq(direct.cst.kind, through_rule.cst.kind)
  assert_eq(
    direct.ignored_fields.length(),
    through_rule.ignored_fields.length(),
  )
  assert_eq(direct.ignored_fields.length(), 8)
  for child_name in ["semantic_type_name", "async", "params", "where"] {
    assert_true(compiled_ignores_field(direct, child_name))
    assert_true(compiled_ignores_field(through_rule, child_name))
  }
  assert_eq(
    direct.metavars.special_expr_placeholders,
    through_rule.metavars.special_expr_placeholders,
  )
  assert_eq(direct.metavars.special_expr_placeholders, ["__TARGET__"])
  debug_inspect(direct.metavars.names(Identifier), content="[\"name\"]")
}

///|
test "compile_inside_toplevel_pattern preserves target validation" {
  let expected = "the pattern must contain exactly one __TARGET__ placeholder in a supported expression position"
  for
    shape in [
      "fn sample { value }", "fn sample { __TARGET__; __TARGET__ }", "let __TARGET__ = value",
    ] {
    let (path, error_shape, info) = direct_inside_toplevel_pattern_error(shape)
    assert_eq(path, shape)
    assert_eq(error_shape, shape)
    assert_eq(info, expected)
    assert_eq(info, rule_inside_toplevel_pattern_error_info(shape))
  }
}
