///|
using @load {parse_rule_source}

///|
using @model {type CompiledRule, type RuleLoadError}

///|
fn compile_one(source : String) -> Array[CompiledRule] raise {
  compile_rules([
    parse_rule_source("/tmp/rules/example.yaml", "/tmp/rules", source),
  ])
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
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: x
    #|    metavars:
    #|      subtree: [__]
    #|
  expect_compile_invalid(
    source, "patterns[0] cannot declare metavar __ because it is a built-in ignore placeholder",
  )
  let auto_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: x
    #|    metavars: [__]
    #|
  expect_compile_invalid(
    auto_source, "patterns[0] cannot declare metavar __ because it is a built-in ignore placeholder",
  )
}

///|
test "validate allows matcher-local-looking metavar names" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: file + hits + loc + __moongrep_value
    #|    metavars:
    #|      subtree: [file, hits, loc, __moongrep_value]
    #|
  let rules = compile_one(source)
  match rules[0].definition {
    Structural(rule) =>
      debug_inspect(
        rule.patterns[0].source.subtree_metavars,
        content="[\"file\", \"hits\", \"loc\", \"__moongrep_value\"]",
      )
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "validate rejects unused metavars" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: x
    #|    metavars:
    #|      subtree: [missing]
    #|
  expect_compile_invalid(source, "patterns[0] declares unused metavar missing")
}

///|
test "validate rejects redeclared inside expr auto metavars" {
  let source =
    #|id: example
    #|description: Example.
    #|inside-expr:
    #|  shape: wrapper(prefix, __TARGET__)
    #|  metavars: [prefix]
    #|patterns:
    #|  - shape: target(prefix)
    #|    metavars:
    #|      subtree: [prefix]
    #|
  expect_compile_invalid(
    source, "patterns[0] cannot declare metavar prefix because it is already visible from inside-expr",
  )
}

///|
test "validate inside expr requires exactly one target" {
  let source =
    #|id: example
    #|description: Example.
    #|inside-expr:
    #|  shape: wrapper(x)
    #|patterns:
    #|  - shape: x
    #|
  expect_compile_invalid(
    source, "inside-expr.shape must contain exactly one __TARGET__ placeholder in a supported expression position",
  )
}

///|
test "validate taint source placeholder placement" {
  let source =
    #|id: example
    #|description: Example.
    #|taint:
    #|  sources:
    #|    - shape: source(__SOURCE__)
    #|  sinks:
    #|    - shape: sink(__SOURCE__)
    #|
  expect_compile_invalid(source, "taint.sources[0] must not contain __SOURCE__")
}

///|
test "validate taint sink requires whole source target" {
  let source =
    #|id: example
    #|description: Example.
    #|taint:
    #|  sources:
    #|    - shape: source()
    #|  sinks:
    #|    - shape: sink(wrap(__SOURCE__))
    #|
  expect_compile_invalid(
    source, "taint.sinks[0].shape must place __SOURCE__ as the whole receiver or argument value",
  )
}

///|
test "validate compiles taint source target metadata" {
  let source =
    #|id: example
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
      assert_true(rule.sinks[0].target is PositionalArg(0))
      assert_true(rule.sinks[1].target is Receiver)
    }
    Structural(_) => fail("expected taint rule")
  }
}

///|
test "validate rejects normalized rule id collisions" {
  let hyphen_source =
    #|id: a-b
    #|description: |
    #|  Repeated equality.
    #|patterns:
    #|  - shape: _expr == _expr
    #|    metavars:
    #|      subtree: [_expr]
    #|
  let underscore_source =
    #|id: a_b
    #|description: |
    #|  Repeated equality.
    #|patterns:
    #|  - shape: _expr == _expr
    #|    metavars:
    #|      subtree: [_expr]
    #|
  let left = parse_rule_source(
    "/tmp/rules/left.yaml", "/tmp/rules", hyphen_source,
  )
  let right = parse_rule_source(
    "/tmp/rules/right.yaml", "/tmp/rules", underscore_source,
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

///|
test "validate rejects reference rule guard in runtime AST mode" {
  let source =
    #|id: example
    #|description: |
    #|  C-style loop guard fixture.
    #|patterns:
    #|  - shape: |
    #|      for counter = __; counter < upper_limit; counter = counter + 1 {
    #|        body
    #|      }
    #|    metavars:
    #|      subtree: [upper_limit, body]
    #|      identifier: [counter]
    #|    guard: |
    #|      @greptools.is_unused_var(upper_limit, counter)
    #|
  expect_compile_invalid(
    source, "patterns[0].guard is not supported in runtime AST mode",
  )
}
