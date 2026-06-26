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
    RuleLoadError::InvalidRule(path=_, info~) => inspect(info, content=expected)
    _ => fail("expected RuleLoadError")
  } noraise {
    _ => fail("expected compile failure")
  }
}

///|
test "validate rejects reserved inline metavar names" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: $exp:__
    #|
  expect_compile_invalid(
    source, "patterns[0] cannot declare metavar __ because it is a built-in ignore placeholder",
  )
}

///|
test "validate rejects unsupported inline metavar kind" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: $pat:x
    #|
  expect_compile_invalid(
    source, "patterns[0].shape contains unsupported metavar kind pat",
  )
}

///|
test "validate rejects expr metavar outside bare expression position" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: match input { $exp:item => item }
    #|
  expect_compile_invalid(
    source, "patterns[0].shape uses $exp:item outside a bare expression position",
  )
}

///|
test "validate rejects inline metavar kind conflicts" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: $exp:value + $id:value
    #|
  expect_compile_invalid(
    source, "patterns[0].shape declares metavar value as multiple inline metavar kinds",
  )
}

///|
test "validate allows matcher-local-looking metavar names" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: $exp:file + $exp:hits + $exp:loc + $exp:__moongrep_value
    #|
  let rules = compile_one(source)
  match rules[0].definition {
    Structural(rule) =>
      debug_inspect(
        rule.patterns[0].compiled.expr_metavars,
        content="[\"file\", \"hits\", \"loc\", \"__moongrep_value\"]",
      )
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "validate records inline constant metavars" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: $const:value + $const:value
    #|
  let rules = compile_one(source)
  match rules[0].definition {
    Structural(rule) =>
      debug_inspect(
        rule.patterns[0].compiled.constant_metavars,
        content="[\"value\"]",
      )
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "validate rejects constant metavar kind conflicts" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: $const:value + $exp:value
    #|
  expect_compile_invalid(
    source, "patterns[0].shape declares metavar value as multiple inline metavar kinds",
  )
}

///|
test "validate rejects const metavar in labels" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: sink($const:value=actual)
    #|
  expect_compile_invalid(
    source, "patterns[0].shape uses $const:value outside a constant expression or pattern position",
  )
}

///|
test "validate rejects const metavar in qualified identifiers" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: "@pkg.$const:value"
    #|
  expect_compile_invalid(
    source, "patterns[0].shape uses $const:value in an unsupported qualified identifier position",
  )
}

///|
test "validate rejects const metavar in ordinary binders" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: let mut $const:value = 1
    #|
  expect_compile_invalid(
    source, "patterns[0].shape uses $const:value outside a constant expression or pattern position",
  )
}

///|
test "validate rejects redeclared inside expr metavars" {
  let source =
    #|id: example
    #|description: Example.
    #|inside-expr:
    #|  shape: wrapper($exp:prefix, __TARGET__)
    #|patterns:
    #|  - shape: target($exp:prefix)
    #|
  expect_compile_invalid(
    source, "patterns[0] cannot declare metavar prefix because it is already visible from inside-expr",
  )
}

///|
test "validate inside expr constant metavars are visible and cannot be redeclared" {
  let source =
    #|id: example
    #|description: Example.
    #|inside-expr:
    #|  shape: wrapper($const:lit, __TARGET__)
    #|patterns:
    #|  - shape: target($const:lit)
    #|
  expect_compile_invalid(
    source, "patterns[0] cannot declare metavar lit because it is already visible from inside-expr",
  )
  let visible_source =
    #|id: example
    #|description: Example.
    #|inside-expr:
    #|  shape: wrapper($const:lit, __TARGET__)
    #|patterns:
    #|  - shape: target(lit)
    #|
  let rules = compile_one(visible_source)
  match rules[0].definition {
    Structural(rule) =>
      debug_inspect(
        rule.patterns[0].compiled.constant_metavars,
        content="[\"lit\"]",
      )
    Taint(_) => fail("expected structural rule")
  }
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
test "validate rejects reference rule guard in runtime AST mode" {
  let source =
    #|id: example
    #|description: |
    #|  C-style loop guard fixture.
    #|patterns:
    #|  - shape: |
    #|      for $id:counter = __; $id:counter < $exp:upper_limit; $id:counter = $id:counter + 1 {
    #|        $exp:body
    #|      }
    #|    guard: |
    #|      @greptools.is_unused_var(upper_limit, counter)
    #|
  expect_compile_invalid(
    source, "patterns[0].guard is not supported in runtime AST mode",
  )
}
