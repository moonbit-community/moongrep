///|
fn compile_one(source : String) -> Array[CompiledRule] raise {
  compile_rules([parse_rule_source("/tmp/rules/example.yaml", "/tmp/rules", source)])
}

///|
fn expect_compile_invalid(source : String, expected : String) -> Unit raise {
  try ignore(compile_one(source)) catch {
    RuleLoadError::InvalidRule(path=_, info~) => inspect(info, content=expected)
    _ => fail("expected RuleLoadError")
  } noraise {
    _ => fail("expected compile failure")
  }
}

///|
test "validate rejects reserved metavar names" {
  let source =
    #|package: example/pkg
    #|description: Example.
    #|patterns:
    #|  - shape: x
    #|    metavars:
    #|      subtree: [__]
    #|
  expect_compile_invalid(
    source,
    "patterns[0] cannot declare metavar __ because it is a built-in ignore placeholder",
  )
}

///|
test "validate rejects unused metavars" {
  let source =
    #|package: example/pkg
    #|description: Example.
    #|patterns:
    #|  - shape: x
    #|    metavars:
    #|      subtree: [missing]
    #|
  expect_compile_invalid(
    source,
    "patterns[0] declares unused metavar missing",
  )
}

///|
test "validate inside expr requires exactly one target" {
  let source =
    #|package: example/pkg
    #|description: Example.
    #|inside-expr:
    #|  shape: wrapper(x)
    #|patterns:
    #|  - shape: x
    #|
  expect_compile_invalid(
    source,
    "inside-expr.shape must contain exactly one __TARGET__ placeholder in a supported expression position",
  )
}

///|
test "validate taint source placeholder placement" {
  let source =
    #|package: example/pkg
    #|description: Example.
    #|taint:
    #|  sources:
    #|    - shape: source(__SOURCE__)
    #|  sinks:
    #|    - shape: sink(__SOURCE__)
    #|
  expect_compile_invalid(
    source,
    "taint.sources[0] must not contain __SOURCE__",
  )
}

///|
test "validate taint sink requires whole source target" {
  let source =
    #|package: example/pkg
    #|description: Example.
    #|taint:
    #|  sources:
    #|    - shape: source()
    #|  sinks:
    #|    - shape: sink(wrap(__SOURCE__))
    #|
  expect_compile_invalid(
    source,
    "taint.sinks[0].shape must place __SOURCE__ as the whole receiver or argument value",
  )
}

///|
test "validate compiles taint source target metadata" {
  let source =
    #|package: example/pkg
    #|description: Example.
    #|taint:
    #|  sources:
    #|    - shape: source()
    #|  sinks:
    #|    - shape: receiver.sink(__SOURCE__)
    #|    - shape: __SOURCE__.dangerous()
    #|
  let rules = compile_one(source)
  match rules[0].definition {
    Taint(rule) => {
      inspect(rule.sinks.length(), content="2")
      inspect(rule.sinks[0].target is PositionalArg(0), content="true")
      inspect(rule.sinks[1].target is Receiver, content="true")
    }
    Structural(_) => fail("expected taint rule")
  }
}

///|
test "validate rejects normalized rule id collisions" {
  let left = parse_rule_source(
    "/tmp/rules/a-b.yaml",
    "/tmp/rules",
    valid_structural_rule_source(),
  )
  let right = parse_rule_source(
    "/tmp/rules/a_b.yaml",
    "/tmp/rules",
    valid_structural_rule_source(),
  )
  try ignore(compile_rules([left, right])) catch {
    RuleLoadError::InvalidRule(path=_, info~) =>
      inspect(
        info,
        content="rule id a_b conflicts with another rule after matcher name normalization",
      )
    _ => fail("expected RuleLoadError")
  } noraise {
    _ => fail("expected collision failure")
  }
}
