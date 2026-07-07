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
test "validate rejects reserved metavar names" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: $(__:exp)
    #|
  expect_compile_invalid(
    source, "patterns[0] cannot declare metavar __ because it is a built-in ignore placeholder",
  )
}

///|
test "validate rejects legacy metavar syntax" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: $exp:value
    #|
  expect_compile_invalid(
    source, "patterns[0].shape uses legacy metavar syntax $exp:value; use $(value:exp)",
  )
}

///|
test "validate accepts bare inline expression metavars" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: $value + $value
    #|
  let rules = compile_one(source)
  match rules[0].definition {
    Structural(rule) => {
      debug_inspect(
        rule.patterns[0].compiled.expr_metavars,
        content="[\"value\"]",
      )
      debug_inspect(rule.patterns[0].compiled.identifier_metavars, content="[]")
      debug_inspect(rule.patterns[0].compiled.constant_metavars, content="[]")
    }
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "validate rejects bare dollar metavar syntax" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: $
    #|
  expect_compile_invalid(source, "patterns[0].shape has lexical errors")
}

///|
test "validate accepts inline pattern metavars" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: match input { $(item:pat) => $(body:exp) }
    #|
  let rules = compile_one(source)
  match rules[0].definition {
    Structural(rule) => {
      assert_eq(rule.patterns.length(), 1)
      debug_inspect(
        rule.patterns[0].compiled.expr_metavars,
        content="[\"body\"]",
      )
      debug_inspect(rule.patterns[0].compiled.identifier_metavars, content="[]")
      debug_inspect(rule.patterns[0].compiled.constant_metavars, content="[]")
    }
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "validate infers bare binder and expression metavars" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: |
    #|      for $counter = 0; $counter < $limit; $counter = $counter + 1 {
    #|        println($counter)
    #|      }
    #|
  let rules = compile_one(source)
  match rules[0].definition {
    Structural(rule) => {
      debug_inspect(
        rule.patterns[0].compiled.expr_metavars,
        content="[\"limit\"]",
      )
      debug_inspect(
        rule.patterns[0].compiled.identifier_metavars,
        content="[\"counter\"]",
      )
      debug_inspect(rule.patterns[0].compiled.constant_metavars, content="[]")
    }
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "validate rejects ambiguous bare pattern metavars" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: match input { $item => body }
    #|
  expect_compile_invalid(
    source, "patterns[0].shape cannot infer kind for bare metavar $item in a pattern variable position; use explicit typed syntax like $(item:id), $(item:const), or $(item:pat)",
  )
}

///|
test "validate rejects ambiguous bare pattern metavars with expression reuse" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: match input { $item => $item }
    #|
  expect_compile_invalid(
    source, "patterns[0].shape cannot infer kind for bare metavar $item in a pattern variable position; use explicit typed syntax like $(item:id), $(item:const), or $(item:pat)",
  )
}

///|
test "validate allows explicit pattern kind to disambiguate bare pattern metavars" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: match input { $(item:pat) => ok; $item => ok }
    #|
  ignore(compile_one(source))
}

///|
test "validate allows explicit identifier kind to disambiguate bare pattern metavars" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: match input { $(item:id) => ok; $item => ok }
    #|
  let rules = compile_one(source)
  match rules[0].definition {
    Structural(rule) =>
      debug_inspect(
        rule.patterns[0].compiled.identifier_metavars,
        content="[\"item\"]",
      )
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "validate rejects explicit kind incompatible with bare occurrences" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: match input { $item => $(item:exp) }
    #|
  expect_compile_invalid(
    source, "patterns[0].shape uses $(item:exp) outside a bare expression position",
  )
}

///|
test "validate rejects pattern metavar kind conflicts" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: match input { $(item:pat) => $(item:id) }
    #|
  expect_compile_invalid(
    source, "patterns[0].shape declares metavar item as multiple metavar kinds",
  )
}

///|
test "validate rejects pattern metavar outside bare pattern position" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: $(value:pat) + 1
    #|
  expect_compile_invalid(
    source, "patterns[0].shape uses $(value:pat) outside a bare pattern position",
  )
}

///|
test "validate rejects expr metavar outside bare expression position" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: match input { $(item:exp) => item }
    #|
  expect_compile_invalid(
    source, "patterns[0].shape uses $(item:exp) outside a bare expression position",
  )
}

///|
test "validate rejects metavar kind conflicts" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: $(value:exp) + $(value:id)
    #|
  expect_compile_invalid(
    source, "patterns[0].shape declares metavar value as multiple metavar kinds",
  )
}

///|
test "validate allows matcher-local-looking metavar names" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: $(file:exp) + $(hits:exp) + $(loc:exp) + $(__moongrep_value:exp)
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
    #|  - shape: $(value:const) + $(value:const)
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
test "validate records inline argument metavars" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: sink($(arg:arg), $(arg:arg))
    #|
  let rules = compile_one(source)
  match rules[0].definition {
    Structural(rule) => {
      debug_inspect(rule.patterns[0].compiled.arg_metavars, content="[\"arg\"]")
      debug_inspect(rule.patterns[0].compiled.expr_metavars, content="[]")
      debug_inspect(rule.patterns[0].compiled.identifier_metavars, content="[]")
      debug_inspect(rule.patterns[0].compiled.constant_metavars, content="[]")
    }
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "validate records constructor identifier metavars" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: $(Ctor:id)($(value:exp))
    #|
  let rules = compile_one(source)
  match rules[0].definition {
    Structural(rule) =>
      debug_inspect(
        rule.patterns[0].compiled.identifier_metavars,
        content="[\"Ctor\"]",
      )
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "validate records constructor extra info identifier metavars" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: $(TypeName:id)::$(Ctor:id)
    #|
  let rules = compile_one(source)
  match rules[0].definition {
    Structural(rule) =>
      debug_inspect(
        rule.patterns[0].compiled.identifier_metavars,
        content="[\"TypeName\", \"Ctor\"]",
      )
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "validate records qualified function identifier metavars" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: "@pkg.$(callee:id)($(value:exp))"
    #|
  let rules = compile_one(source)
  match rules[0].definition {
    Structural(rule) =>
      debug_inspect(
        rule.patterns[0].compiled.identifier_metavars,
        content="[\"callee\"]",
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
    #|  - shape: $(value:const) + $(value:exp)
    #|
  expect_compile_invalid(
    source, "patterns[0].shape declares metavar value as multiple metavar kinds",
  )
}

///|
test "validate rejects argument metavar kind conflicts" {
  let exp_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: sink($(value:arg), $(value:exp))
    #|
  expect_compile_invalid(
    exp_source, "patterns[0].shape declares metavar value as multiple metavar kinds",
  )
  let id_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: sink($(value:arg), $(value:id))
    #|
  expect_compile_invalid(
    id_source, "patterns[0].shape declares metavar value as multiple metavar kinds",
  )
  let const_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: sink($(value:arg), $(value:const))
    #|
  expect_compile_invalid(
    const_source, "patterns[0].shape declares metavar value as multiple metavar kinds",
  )
  let pat_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: sink($(value:arg), match input { $(value:pat) => ok })
    #|
  expect_compile_invalid(
    pat_source, "patterns[0].shape declares metavar value as multiple metavar kinds",
  )
}

///|
test "validate rejects argument metavars outside bare argument position" {
  let root_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: $(value:arg)
    #|
  expect_compile_invalid(
    root_source, "patterns[0].shape uses $(value:arg) outside a bare argument position",
  )
  let labelled_value_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: sink(label=$(value:arg))
    #|
  expect_compile_invalid(
    labelled_value_source, "patterns[0].shape uses $(value:arg) outside a bare argument position",
  )
  let nested_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: sink($(value:arg) + 1)
    #|
  expect_compile_invalid(
    nested_source, "patterns[0].shape uses $(value:arg) outside a bare argument position",
  )
  let pattern_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: match input { $(value:arg) => body }
    #|
  expect_compile_invalid(
    pattern_source, "patterns[0].shape uses $(value:arg) outside a bare argument position",
  )
}

///|
test "validate rejects const metavar in labels" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: sink($(value:const)=actual)
    #|
  expect_compile_invalid(
    source, "patterns[0].shape uses $(value:const) outside a constant expression or pattern position",
  )
}

///|
test "validate rejects const metavar in qualified identifiers" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: "@pkg.$(value:const)"
    #|
  expect_compile_invalid(
    source, "patterns[0].shape uses $(value:const) in an unsupported qualified identifier position",
  )
}

///|
test "validate rejects const metavar in ordinary binders" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: let mut $(value:const) = 1
    #|
  expect_compile_invalid(
    source, "patterns[0].shape uses $(value:const) outside a constant expression or pattern position",
  )
}

///|
test "validate allows inherited inside expr metavars with matching inline forms" {
  let source =
    #|id: example
    #|description: Example.
    #|inside-expr: wrapper($(value:exp), $(name:id), $(lit:const), $(arg:arg), __TARGET__)
    #|patterns:
    #|  - shape: target($(value:exp), $(name:id), $(lit:const), $(arg:arg))
    #|
  let rules = compile_one(source)
  match rules[0].definition {
    Structural(rule) => {
      debug_inspect(
        rule.patterns[0].compiled.expr_metavars,
        content="[\"value\"]",
      )
      debug_inspect(
        rule.patterns[0].compiled.identifier_metavars,
        content="[\"name\"]",
      )
      debug_inspect(
        rule.patterns[0].compiled.constant_metavars,
        content="[\"lit\"]",
      )
      debug_inspect(rule.patterns[0].compiled.arg_metavars, content="[\"arg\"]")
    }
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "validate compiles patterns-not metavars and guards" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: sink($(value:exp))
    #|patterns-not:
    #|  - shape: allow($(name:id), $(lit:const))
    #|    guard:
    #|      $name: "^safe_"
    #|      $lit: "^ok$"
    #|
  let rules = compile_one(source)
  match rules[0].definition {
    Structural(rule) => {
      assert_eq(rule.patterns.length(), 1)
      assert_eq(rule.patterns_not.length(), 1)
      assert_eq(rule.patterns_not[0].guards.length(), 2)
      debug_inspect(
        rule.patterns_not[0].compiled.identifier_metavars,
        content="[\"name\"]",
      )
      debug_inspect(
        rule.patterns_not[0].compiled.constant_metavars,
        content="[\"lit\"]",
      )
    }
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "validate patterns-not inherits inside expr metavars without positive patterns" {
  let source =
    #|id: example
    #|description: Example.
    #|inside-expr: wrapper($(name:id), __TARGET__)
    #|patterns-not:
    #|  - shape: blocked($(name:id))
    #|
  let rules = compile_one(source)
  match rules[0].definition {
    Structural(rule) => {
      assert_eq(rule.patterns.length(), 0)
      assert_eq(rule.patterns_not.length(), 1)
      debug_inspect(
        rule.patterns_not[0].compiled.identifier_metavars,
        content="[\"name\"]",
      )
    }
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "validate rejects target placeholder in patterns-not" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: sink($(value:exp))
    #|patterns-not:
    #|  - shape: __TARGET__
    #|
  expect_compile_invalid(
    source, "patterns-not[0].shape must not contain __TARGET__",
  )
}

///|
test "validate rejects inherited inside expr kind mismatch in patterns-not" {
  let source =
    #|id: example
    #|description: Example.
    #|inside-expr: wrapper($(prefix:exp), __TARGET__)
    #|patterns-not:
    #|  - shape: target($(prefix:id))
    #|
  expect_compile_invalid(
    source, "patterns-not[0] cannot use inherited inside-expr metavar prefix as id because it was declared as exp",
  )
}

///|
test "validate rejects inherited inside expr metavars with different inline forms" {
  let source =
    #|id: example
    #|description: Example.
    #|inside-expr: wrapper($(prefix:exp), __TARGET__)
    #|patterns:
    #|  - shape: target($(prefix:id))
    #|
  expect_compile_invalid(
    source, "patterns[0] cannot use inherited inside-expr metavar prefix as id because it was declared as exp",
  )
}

///|
test "validate rejects inherited inside expr argument kind mismatch" {
  let source =
    #|id: example
    #|description: Example.
    #|inside-expr: wrapper($(arg:arg), __TARGET__)
    #|patterns:
    #|  - shape: target($(arg:exp))
    #|
  expect_compile_invalid(
    source, "patterns[0] cannot use inherited inside-expr metavar arg as exp because it was declared as arg",
  )
}

///|
test "validate inside expr constant metavars use matching inline forms" {
  let source =
    #|id: example
    #|description: Example.
    #|inside-expr: wrapper($(lit:const), __TARGET__)
    #|patterns:
    #|  - shape: target($(lit:const))
    #|
  let rules = compile_one(source)
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
    #|inside-expr: wrapper(x)
    #|patterns:
    #|  - shape: x
    #|
  expect_compile_invalid(
    source, "inside-expr must contain exactly one __TARGET__ placeholder in a supported expression position",
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
      assert_eq(rule.sinks.length(), 2)
      assert_true(rule.sinks[0].target is PositionalArg(0))
      assert_true(rule.sinks[1].target is Receiver)
    }
    Structural(_) => fail("expected taint rule")
  }
}

///|
test "validate rejects unknown guard key" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: $(name:id)
    #|    guard:
    #|      $other: "^safe_"
    #|
  expect_compile_invalid(
    source, "patterns[0].guard.$other references unknown metavar",
  )
}

///|
test "validate rejects guard on exp and pat metavars" {
  let exp_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: sink($(value:exp))
    #|    guard:
    #|      $value: "^safe_"
    #|
  expect_compile_invalid(
    exp_source, "patterns[0].guard.$value cannot reference exp metavar value",
  )
  let pat_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: match input { $(item:pat) => body }
    #|    guard:
    #|      $item: "^Some"
    #|
  expect_compile_invalid(
    pat_source, "patterns[0].guard.$item cannot reference pat metavar item",
  )
}

///|
test "validate rejects guard on arg metavars" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: sink($(value:arg))
    #|    guard:
    #|      $value: "^safe_"
    #|
  expect_compile_invalid(
    source, "patterns[0].guard.$value cannot reference arg metavar value",
  )
}

///|
test "validate rejects invalid guard regex" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: $(name:id)
    #|    guard:
    #|      $name: "("
    #|
  expect_compile_invalid(source, "patterns[0].guard.$name has invalid regex")
}

///|
test "validate allows inner guard to reference inside expr id and const captures" {
  let source =
    #|id: example
    #|description: Example.
    #|inside-expr: wrapper($(name:id), $(lit:const), __TARGET__)
    #|patterns:
    #|  - shape: call($(name:id), $(lit:const))
    #|    guard:
    #|      $name: "^safe_"
    #|      $lit: "^ok$"
    #|
  let rules = compile_one(source)
  match rules[0].definition {
    Structural(rule) => {
      assert_eq(rule.patterns[0].guards.length(), 2)
      debug_inspect(
        rule.patterns[0].compiled.identifier_metavars,
        content="[\"name\"]",
      )
      debug_inspect(
        rule.patterns[0].compiled.constant_metavars,
        content="[\"lit\"]",
      )
    }
    Taint(_) => fail("expected structural rule")
  }
}
