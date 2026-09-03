///|
using @model {type CompiledRule, type RuleLoadError}

///|
fn compile_one(source : String) -> Array[CompiledRule] raise {
  compile_rules([
    @model.RawRuleSpec::from_str(
      "/tmp/rules/example.yaml", "/tmp/rules", source,
    ),
  ])
}

///|
fn expect_compile_invalid(source : String, expected : String) -> Unit raise {
  try ignore(compile_one(source)) catch {
    RuleLoadError::InvalidPattern(path=_, shape=_, info~) =>
      inspect(info, content=expected)
    RuleLoadError::InvalidRule(path=_, info~) => inspect(info, content=expected)
    _ => fail("expected RuleLoadError")
  } noraise {
    _ => fail("expected compile failure")
  }
}

///|
fn expect_compile_invalid_pattern(
  source : String,
  expected_shape : String,
  expected_info : String,
) -> Unit raise {
  try ignore(compile_one(source)) catch {
    RuleLoadError::InvalidPattern(path~, shape~, info~) => {
      inspect(path, content="/tmp/rules/example.yaml")
      inspect(shape, content=expected_shape)
      inspect(info, content=expected_info)
    }
    _ => fail("expected InvalidPattern")
  } noraise {
    _ => fail("expected invalid pattern")
  }
}

///|
fn expect_compile_invalid_rule(
  source : String,
  expected_info : String,
) -> Unit raise {
  try ignore(compile_one(source)) catch {
    RuleLoadError::InvalidRule(path~, info~) => {
      inspect(path, content="/tmp/rules/example.yaml")
      inspect(info, content=expected_info)
    }
    _ => fail("expected InvalidRule")
  } noraise {
    _ => fail("expected invalid rule")
  }
}

///|
fn compiled_ignores_field(
  compiled : @matching.CompiledExprPattern,
  child_name : String,
) -> Bool {
  for field in compiled.ignored_fields {
    if field.parent_kind == compiled.cst.kind && field.child_name == child_name {
      return true
    }
  }
  false
}
