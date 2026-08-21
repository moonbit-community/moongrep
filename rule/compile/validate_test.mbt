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

///|
test "validate compiles bare and typed ellipsis metavars" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: inspect($$$args, $$$(values:arg))
    #|
  let rules = compile_one(source)
  match rules[0].definition {
    Structural(rule) => {
      let metavars = rule.patterns[0].compiled.ellipsis_metavars
      assert_eq(metavars.length(), 2)
      inspect(metavars[0].name, content="args")
      assert_true(metavars[0].kind == AnyItem)
      inspect(metavars[1].name, content="values")
      assert_true(metavars[1].kind == ArgItem)
    }
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "validate typed ellipsis occurrence determines bare occurrence kind" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: pair([$$$items], [$$$(items:exp)])
    #|
  let rules = compile_one(source)
  match rules[0].definition {
    Structural(rule) => {
      let metavars = rule.patterns[0].compiled.ellipsis_metavars
      assert_eq(metavars.length(), 1)
      inspect(metavars[0].name, content="items")
      assert_true(metavars[0].kind == ExpItem)
    }
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "validate rejects ellipsis outside a complete list item" {
  let root =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: $$$items
    #|
  expect_compile_invalid(
    root, "patterns[0].shape uses ellipsis metavar $$$items outside a complete ordered CST list item",
  )
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: wrap($$$items + 1)
    #|
  expect_compile_invalid(
    source, "patterns[0].shape uses ellipsis metavar $$$items outside a complete ordered CST list item",
  )
}

///|
test "validate rejects ellipsis guards" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: inspect($$$args)
    #|    guard:
    #|      $args: .+
    #|
  expect_compile_invalid(
    source, "patterns[0].guard.$args cannot reference ellipsis metavar args",
  )
}

///|
test "validate rejects conflicting and mixed ellipsis declarations" {
  let conflicting =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: pair([$$$(items:exp)], [$$$(items:id)])
    #|
  expect_compile_invalid(
    conflicting, "patterns[0].shape declares ellipsis metavar items as multiple metavar kinds",
  )
  let mixed =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: pair($items, [$$$items])
    #|
  expect_compile_invalid(
    mixed, "patterns[0].shape cannot use items as both an ellipsis metavar and a single-node metavar",
  )
}

///|
test "validate rejects ellipsis kinds incompatible with their list slots" {
  let parameter =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: fn($$$(params:exp)) { body }
    #|
  expect_compile_invalid(
    parameter, "patterns[0].shape uses ellipsis kind exp in an incompatible ordered-list item position",
  )
  let argument =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: sink($$$(values:pat))
    #|
  expect_compile_invalid(
    argument, "patterns[0].shape uses ellipsis kind pat in an incompatible ordered-list item position",
  )
}

///|
test "validate accepts all-underscore metavar names" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: $(__:exp) + $(__:exp) + $(___:exp)
    #|
  let rules = compile_one(source)
  match rules[0].definition {
    Structural(rule) =>
      debug_inspect(
        rule.patterns[0].compiled.expr_metavars,
        content="[\"__\", \"___\"]",
      )
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "validate does not collect $_ ignore placeholders" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: pair($_, $_)
    #|
  let rules = compile_one(source)
  match rules[0].definition {
    Structural(rule) => {
      debug_inspect(rule.patterns[0].compiled.expr_metavars, content="[]")
      debug_inspect(rule.patterns[0].compiled.identifier_metavars, content="[]")
      debug_inspect(rule.patterns[0].compiled.constant_metavars, content="[]")
      debug_inspect(rule.patterns[0].compiled.arg_metavars, content="[]")
      debug_inspect(rule.patterns[0].compiled.type_metavars, content="[]")
    }
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "validate rejects reserved target and source metavar names" {
  let target_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: $(__TARGET__:exp)
    #|
  expect_compile_invalid(
    target_source, "patterns[0] cannot declare metavar __TARGET__ because it is reserved for inside-expr target traversal",
  )
  let source_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: $(__SOURCE__:exp)
    #|
  expect_compile_invalid(
    source_source, "patterns[0] cannot declare metavar __SOURCE__ because it is reserved for taint source targets",
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
test "validate accepts keyword names for every single-node metavar form" {
  let source =
    #|id: example
    #|description: Keyword metavar names.
    #|patterns:
    #|  - shape: sink($(else:exp))
    #|  - shape: sink($(if:const))
    #|  - shape: $(for:id)()
    #|  - shape: sink($(match:arg))
    #|  - shape: match input { $(if:pat) => body }
    #|  - shape: |
    #|      let value : $(for:type) = input
    #|  - shape: $if + $if
    #|
  let rules = compile_one(source)
  match rules[0].definition {
    Structural(rule) => {
      assert_eq(rule.patterns.length(), 7)
      debug_inspect(
        rule.patterns[0].compiled.expr_metavars,
        content="[\"else\"]",
      )
      debug_inspect(
        rule.patterns[1].compiled.constant_metavars,
        content="[\"if\"]",
      )
      debug_inspect(
        rule.patterns[2].compiled.identifier_metavars,
        content="[\"for\"]",
      )
      debug_inspect(
        rule.patterns[3].compiled.arg_metavars,
        content="[\"match\"]",
      )
      debug_inspect(
        rule.patterns[5].compiled.type_metavars,
        content="[\"for\"]",
      )
      debug_inspect(rule.patterns[6].compiled.expr_metavars, content="[\"if\"]")
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
test "validate infers bare binders in foreach parameters and let mut" {
  let foreach =
    #|id: foreach
    #|description: Foreach binder.
    #|patterns:
    #|  - shape: for $item in $items { $body }
    #|
  let parameter =
    #|id: parameter
    #|description: Parameter binder.
    #|patterns:
    #|  - shape: fn($param) { $body }
    #|
  let let_mut =
    #|id: let-mut
    #|description: Mutable binder.
    #|patterns:
    #|  - shape: let mut $value = $initial
    #|
  for source in [foreach, parameter, let_mut] {
    let rules = compile_one(source)
    match rules[0].definition {
      Structural(rule) =>
        assert_eq(rule.patterns[0].compiled.identifier_metavars.length(), 1)
      Taint(_) => fail("expected structural rule")
    }
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
test "validate keeps nested match patterns ambiguous inside foreach" {
  let source =
    #|id: example
    #|description: Nested match pattern.
    #|patterns:
    #|  - shape: |
    #|      for $item in $items {
    #|        match value { $pattern => $body }
    #|      }
    #|
  expect_compile_invalid(
    source, "patterns[0].shape cannot infer kind for bare metavar $pattern in a pattern variable position; use explicit typed syntax like $(pattern:id), $(pattern:const), or $(pattern:pat)",
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
test "validate accepts explicit type metavars in annotations" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: |
    #|      let value : $(T:type) = input
    #|
  let rules = compile_one(source)
  match rules[0].definition {
    Structural(rule) =>
      debug_inspect(rule.patterns[0].compiled.type_metavars, content="[\"T\"]")
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "validate accepts spaced and bare type metavars in annotations" {
  let spaced_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: |
    #|      let value : $( T : type ) = input
    #|
  let spaced_rules = compile_one(spaced_source)
  match spaced_rules[0].definition {
    Structural(rule) =>
      debug_inspect(rule.patterns[0].compiled.type_metavars, content="[\"T\"]")
    Taint(_) => fail("expected structural rule")
  }
  let bare_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: |
    #|      let values : Array[$T] = input
    #|
  let bare_rules = compile_one(bare_source)
  match bare_rules[0].definition {
    Structural(rule) =>
      debug_inspect(rule.patterns[0].compiled.type_metavars, content="[\"T\"]")
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "validate rejects type metavar outside whole type positions" {
  let expr_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: $(T:type) + 1
    #|
  expect_compile_invalid(
    expr_source, "patterns[0].shape uses $(T:type) outside a whole type position",
  )
  let arg_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: sink($(T:type))
    #|
  expect_compile_invalid(
    arg_source, "patterns[0].shape uses $(T:type) outside a whole type position",
  )
  let pattern_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: match input { $(T:type) => body }
    #|
  expect_compile_invalid(
    pattern_source, "patterns[0].shape uses $(T:type) outside a whole type position",
  )
  let label_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: sink($(T:type)=value)
    #|
  expect_compile_invalid(
    label_source, "patterns[0].shape is not a valid MoonBit expression: Unexpected uppercase identifier $(T:type), expected lowercase identifier.",
  )
  let constructor_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: $(T:type)(value)
    #|
  expect_compile_invalid(
    constructor_source, "patterns[0].shape uses $(T:type) outside a whole type position",
  )
}

///|
test "validate rejects guard on type metavars" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: |
    #|      let value : $(T:type) = input
    #|    guard:
    #|      $T: "^Int$"
    #|
  expect_compile_invalid(
    source, "patterns[0].guard.$T cannot reference type metavar T",
  )
}

///|
test "validate rejects type metavar kind conflicts" {
  let exp_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: |
    #|      let value : $(T:type) = $(T:exp)
    #|
  expect_compile_invalid(
    exp_source, "patterns[0].shape uses $(T:exp) outside a bare expression position",
  )
  let id_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: |
    #|      let $(T:id) : $(T:type) = input
    #|
  expect_compile_invalid(
    id_source, "patterns[0].shape declares metavar T as multiple metavar kinds",
  )
  let const_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: |
    #|      let value : $(T:type) = $(T:const)
    #|
  expect_compile_invalid(
    const_source, "patterns[0].shape uses $(T:const) outside a constant expression or pattern position",
  )
  let arg_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: |
    #|      let value : $(T:type) = sink($(T:arg))
    #|
  expect_compile_invalid(
    arg_source, "patterns[0].shape uses $(T:arg) outside a bare argument position",
  )
  let pat_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: |
    #|      let value : $(T:type) = match input { $(T:pat) => body }
    #|
  expect_compile_invalid(
    pat_source, "patterns[0].shape uses $(T:pat) outside a bare pattern position",
  )
}

///|
test "validate rejects inherited type metavar kind mismatch" {
  let source =
    #|id: example
    #|description: Example.
    #|inside-expr:
    #|  - shape: |
    #|      let value : $(T:type) = __TARGET__
    #|patterns:
    #|  - shape: target($T)
    #|
  expect_compile_invalid(
    source, "patterns[0] cannot use inherited inside-expr[0] metavar T as id because it was declared as type",
  )
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
    #|inside-expr:
    #|  - shape: wrapper($(value:exp), $(name:id), $(lit:const), $(arg:arg), __TARGET__)
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
test "validate compiles inside expr id and const guards" {
  let source =
    #|id: example
    #|description: Example.
    #|inside-expr:
    #|  - shape: wrapper($(name:id), $(lit:const), __TARGET__)
    #|    guard:
    #|      $name: "^safe_"
    #|      $lit: "^ok$"
    #|patterns:
    #|  - shape: call()
    #|
  let rules = compile_one(source)
  match rules[0].definition {
    Structural(rule) => {
      assert_eq(rule.inside_expr.length(), 1)
      let inside_expr = rule.inside_expr[0]
      assert_eq(inside_expr.guards.length(), 2)
      debug_inspect(
        inside_expr.compiled.identifier_metavars,
        content="[\"name\"]",
      )
      debug_inspect(inside_expr.compiled.constant_metavars, content="[\"lit\"]")
    }
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "validate compiles inside toplevel function shape" {
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
  let rules = compile_one(source)
  match rules[0].definition {
    Structural(rule) => {
      assert_eq(rule.inside_toplevel.length(), 1)
      let inside_toplevel = rule.inside_toplevel[0]
      assert_eq(inside_toplevel.guards.length(), 1)
      debug_inspect(
        inside_toplevel.compiled.identifier_metavars,
        content="[\"param\", \"name\"]",
      )
      assert_true(rule.inside_expr.is_empty())
    }
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "validate resolves inside toplevel match modes per alternative" {
  let source =
    #|id: example
    #|description: Per-alternative top-level matching modes.
    #|inside-toplevel:
    #|  - shape: fn default_fn { __TARGET__ }
    #|  - shape: fn exact_fn { __TARGET__ }
    #|    match-mode: exact
    #|  - shape: async fn partial_fn() -> Int noraise { __TARGET__ }
    #|    match-mode: partial
    #|  - shape: let value = __TARGET__
    #|patterns:
    #|  - shape: call()
    #|
  let rules = compile_one(source)
  match rules[0].definition {
    Structural(rule) => {
      assert_eq(rule.inside_toplevel.length(), 4)
      let default_fn = rule.inside_toplevel[0].compiled
      assert_eq(default_fn.ignored_fields.length(), 8)
      assert_true(compiled_ignores_field(default_fn, "async"))
      assert_true(compiled_ignores_field(default_fn, "params"))
      assert_true(compiled_ignores_field(default_fn, "where"))
      let exact_fn = rule.inside_toplevel[1].compiled
      assert_true(exact_fn.ignored_fields.is_empty())
      let partial_fn = rule.inside_toplevel[2].compiled
      assert_false(compiled_ignores_field(partial_fn, "async"))
      assert_false(compiled_ignores_field(partial_fn, "params"))
      assert_false(compiled_ignores_field(partial_fn, "clause"))
      assert_true(compiled_ignores_field(partial_fn, "semantic_type_name"))
      assert_true(compiled_ignores_field(partial_fn, "quantifier"))
      assert_true(rule.inside_toplevel[3].compiled.ignored_fields.is_empty())
    }
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "validate rejects partial mode for non-function top-level shapes" {
  let source =
    #|id: example
    #|description: Invalid partial top-level shape.
    #|inside-toplevel:
    #|  - shape: let value = __TARGET__
    #|    match-mode: partial
    #|patterns:
    #|  - shape: call()
    #|
  expect_compile_invalid(
    source, "inside-toplevel[0].match-mode partial is only supported for function definition shapes",
  )
}

///|
test "validate compiles inside toplevel let guards" {
  let source =
    #|id: example
    #|description: Example.
    #|inside-toplevel:
    #|  - shape: let $(name:id) = wrapper($(lit:const), __TARGET__)
    #|    guard:
    #|      $name: "^safe_"
    #|      $lit: "^ok$"
    #|patterns:
    #|  - shape: call()
    #|
  let rules = compile_one(source)
  match rules[0].definition {
    Structural(rule) => {
      assert_eq(rule.inside_toplevel.length(), 1)
      let inside_toplevel = rule.inside_toplevel[0]
      assert_eq(inside_toplevel.guards.length(), 2)
      debug_inspect(
        inside_toplevel.compiled.identifier_metavars,
        content="[\"name\"]",
      )
      debug_inspect(
        inside_toplevel.compiled.constant_metavars,
        content="[\"lit\"]",
      )
    }
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "validate compiles inside toplevel test shape" {
  let source =
    #|id: example
    #|description: Example.
    #|inside-toplevel:
    #|  - shape: test "outer" { __TARGET__ }
    #|patterns:
    #|  - shape: call()
    #|
  let rules = compile_one(source)
  match rules[0].definition {
    Structural(rule) => assert_eq(rule.inside_toplevel.length(), 1)
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
    #|inside-expr:
    #|  - shape: wrapper($(name:id), __TARGET__)
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
test "validate patterns-not inherits inside toplevel metavars without positive patterns" {
  let source =
    #|id: example
    #|description: Example.
    #|inside-toplevel:
    #|  - shape: |
    #|      fn $(name:id) { __TARGET__ }
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
test "validate rejects inherited inside toplevel kind mismatch" {
  let source =
    #|id: example
    #|description: Example.
    #|inside-toplevel:
    #|  - shape: |
    #|      fn $(name:id) { __TARGET__ }
    #|patterns:
    #|  - shape: target($(name:exp))
    #|
  expect_compile_invalid(
    source, "patterns[0] cannot use inherited inside-toplevel[0] metavar name as exp because it was declared as id",
  )
}

///|
test "validate rejects inherited inside expr kind mismatch in patterns-not" {
  let source =
    #|id: example
    #|description: Example.
    #|inside-expr:
    #|  - shape: wrapper($(prefix:exp), __TARGET__)
    #|patterns-not:
    #|  - shape: target($(prefix:id))
    #|
  expect_compile_invalid(
    source, "patterns-not[0] cannot use inherited inside-expr[0] metavar prefix as id because it was declared as exp",
  )
}

///|
test "validate rejects inherited inside expr metavars with different inline forms" {
  let source =
    #|id: example
    #|description: Example.
    #|inside-expr:
    #|  - shape: wrapper($(prefix:exp), __TARGET__)
    #|patterns:
    #|  - shape: target($(prefix:id))
    #|
  expect_compile_invalid(
    source, "patterns[0] cannot use inherited inside-expr[0] metavar prefix as id because it was declared as exp",
  )
}

///|
test "validate rejects inherited inside expr argument kind mismatch" {
  let source =
    #|id: example
    #|description: Example.
    #|inside-expr:
    #|  - shape: wrapper($(arg:arg), __TARGET__)
    #|patterns:
    #|  - shape: target($(arg:exp))
    #|
  expect_compile_invalid(
    source, "patterns[0] cannot use inherited inside-expr[0] metavar arg as exp because it was declared as arg",
  )
}

///|
test "validate inside expr constant metavars use matching inline forms" {
  let source =
    #|id: example
    #|description: Example.
    #|inside-expr:
    #|  - shape: wrapper($(lit:const), __TARGET__)
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
    #|inside-expr:
    #|  - shape: wrapper(x)
    #|patterns:
    #|  - shape: x
    #|
  expect_compile_invalid(
    source, "inside-expr[0].shape must contain exactly one __TARGET__ placeholder in a supported expression position",
  )
}

///|
test "validate inside toplevel requires exactly one target" {
  let missing_target =
    #|id: example
    #|description: Example.
    #|inside-toplevel:
    #|  - shape: fn sample { wrapper(x) }
    #|patterns:
    #|  - shape: x
    #|
  expect_compile_invalid(
    missing_target, "inside-toplevel[0].shape must contain exactly one __TARGET__ placeholder in a supported expression position",
  )
  let duplicate_target =
    #|id: example
    #|description: Example.
    #|inside-toplevel:
    #|  - shape: fn sample { __TARGET__; __TARGET__ }
    #|patterns:
    #|  - shape: x
    #|
  expect_compile_invalid(
    duplicate_target, "inside-toplevel[0].shape must contain exactly one __TARGET__ placeholder in a supported expression position",
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
    #|inside-expr:
    #|  - shape: wrapper($(name:id), $(lit:const), __TARGET__)
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

///|
test "validate allows inner guard to reference inside toplevel id and const captures" {
  let source =
    #|id: example
    #|description: Example.
    #|inside-toplevel:
    #|  - shape: let $(name:id) = wrapper($(lit:const), __TARGET__)
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

///|
test "validate rejects unsupported inside expr guard captures" {
  let unknown_source =
    #|id: example
    #|description: Example.
    #|inside-expr:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|    guard:
    #|      $other: "^safe_"
    #|patterns:
    #|  - shape: call()
    #|
  expect_compile_invalid(
    unknown_source, "inside-expr[0].guard.$other references unknown metavar",
  )
  let exp_source =
    #|id: example
    #|description: Example.
    #|inside-expr:
    #|  - shape: wrapper($(value:exp), __TARGET__)
    #|    guard:
    #|      $value: "^safe_"
    #|patterns:
    #|  - shape: call()
    #|
  expect_compile_invalid(
    exp_source, "inside-expr[0].guard.$value cannot reference exp metavar value",
  )
  let arg_source =
    #|id: example
    #|description: Example.
    #|inside-expr:
    #|  - shape: wrapper($(value:arg), __TARGET__)
    #|    guard:
    #|      $value: "^safe_"
    #|patterns:
    #|  - shape: call()
    #|
  expect_compile_invalid(
    arg_source, "inside-expr[0].guard.$value cannot reference arg metavar value",
  )
  let pat_source =
    #|id: example
    #|description: Example.
    #|inside-expr:
    #|  - shape: match input { $(item:pat) => __TARGET__ }
    #|    guard:
    #|      $item: "^Some"
    #|patterns:
    #|  - shape: call()
    #|
  expect_compile_invalid(
    pat_source, "inside-expr[0].guard.$item cannot reference pat metavar item",
  )
  let invalid_regex_source =
    #|id: example
    #|description: Example.
    #|inside-expr:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|    guard:
    #|      $name: "("
    #|patterns:
    #|  - shape: call()
    #|
  expect_compile_invalid(
    invalid_regex_source, "inside-expr[0].guard.$name has invalid regex",
  )
}

///|
test "validate compiles ordered inside expr alternatives independently" {
  let source =
    #|id: example
    #|description: Multiple expression contexts.
    #|inside-expr:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|  - shape: container($(name:id), __TARGET__)
    #|    guard:
    #|      $name: "^safe_"
    #|patterns:
    #|  - shape: target($(name:id))
    #|
  let rules = compile_one(source)
  match rules[0].definition {
    Structural(rule) => {
      assert_eq(rule.inside_expr.length(), 2)
      assert_eq(rule.inside_expr[0].guards.length(), 0)
      assert_eq(rule.inside_expr[1].guards.length(), 1)
      debug_inspect(
        rule.inside_expr[0].compiled.identifier_metavars,
        content="[\"name\"]",
      )
      debug_inspect(
        rule.inside_expr[1].compiled.identifier_metavars,
        content="[\"name\"]",
      )
    }
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "validate compiles ordered inside toplevel alternatives independently" {
  let source =
    #|id: example
    #|description: Multiple top-level contexts.
    #|inside-toplevel:
    #|  - shape: fn $(name:id) { __TARGET__ }
    #|  - shape: let $(name:id) = wrapper(__TARGET__)
    #|patterns:
    #|  - shape: target($(name:id))
    #|
  let rules = compile_one(source)
  match rules[0].definition {
    Structural(rule) => {
      assert_eq(rule.inside_toplevel.length(), 2)
      debug_inspect(
        rule.inside_toplevel[0].compiled.identifier_metavars,
        content="[\"name\"]",
      )
      debug_inspect(
        rule.inside_toplevel[1].compiled.identifier_metavars,
        content="[\"name\"]",
      )
    }
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "validate requires reused inside captures in every outer alternative" {
  let missing =
    #|id: example
    #|description: Missing inherited capture.
    #|inside-expr:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|  - shape: container(__TARGET__)
    #|patterns:
    #|  - shape: target($(name:id))
    #|
  expect_compile_invalid(
    missing, "patterns[0] cannot use inherited inside-expr metavar name as id because inside-expr[1] does not declare it",
  )
  let wrong_kind =
    #|id: example
    #|description: Conflicting inherited capture.
    #|inside-expr:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|  - shape: container($(name:exp), __TARGET__)
    #|patterns:
    #|  - shape: target($(name:id))
    #|
  expect_compile_invalid(
    wrong_kind, "patterns[0] cannot use inherited inside-expr[1] metavar name as id because it was declared as exp",
  )
  let missing_from_patterns_not =
    #|id: example
    #|description: Missing inherited negative capture.
    #|inside-expr:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|  - shape: container(__TARGET__)
    #|patterns-not:
    #|  - shape: blocked($(name:id))
    #|
  expect_compile_invalid(
    missing_from_patterns_not, "patterns-not[0] cannot use inherited inside-expr metavar name as id because inside-expr[1] does not declare it",
  )
}

///|
test "validate requires reused ellipsis captures in every outer alternative" {
  let missing =
    #|id: example
    #|description: Missing inherited ellipsis.
    #|inside-expr:
    #|  - shape: wrapper($$$(items:exp), __TARGET__)
    #|  - shape: container(__TARGET__)
    #|patterns:
    #|  - shape: target($$$(items:exp))
    #|
  expect_compile_invalid(
    missing, "patterns[0] cannot use inherited inside-expr ellipsis metavar items because inside-expr[1] does not declare it with kind exp",
  )
  let wrong_kind =
    #|id: example
    #|description: Conflicting inherited ellipsis.
    #|inside-expr:
    #|  - shape: wrapper($$$(items:exp), __TARGET__)
    #|  - shape: container($$$(items:id), __TARGET__)
    #|patterns:
    #|  - shape: target($$$(items:exp))
    #|
  expect_compile_invalid(
    wrong_kind, "patterns[0] cannot use inherited inside-expr[1] ellipsis metavar items with a different kind",
  )
}

///|
test "validate allows unreferenced outer captures to differ by alternative" {
  let source =
    #|id: example
    #|description: Branch-local captures.
    #|inside-expr:
    #|  - shape: wrapper($(left:id), __TARGET__)
    #|  - shape: container($(right:exp), __TARGET__)
    #|patterns:
    #|  - shape: target()
    #|
  let rules = compile_one(source)
  match rules[0].definition {
    Structural(rule) => assert_eq(rule.inside_expr.length(), 2)
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "validate indexes target errors in later outer alternatives" {
  let source =
    #|id: example
    #|description: Missing target in second context.
    #|inside-expr:
    #|  - shape: wrapper(__TARGET__)
    #|  - shape: container(no_target)
    #|patterns:
    #|  - shape: target()
    #|
  expect_compile_invalid(
    source, "inside-expr[1].shape must contain exactly one __TARGET__ placeholder in a supported expression position",
  )
  let toplevel_source =
    #|id: example
    #|description: Duplicate target in second top-level context.
    #|inside-toplevel:
    #|  - shape: fn sample { __TARGET__ }
    #|  - shape: let value = pair(__TARGET__, __TARGET__)
    #|patterns:
    #|  - shape: target()
    #|
  expect_compile_invalid(
    toplevel_source, "inside-toplevel[1].shape must contain exactly one __TARGET__ placeholder in a supported expression position",
  )
}
