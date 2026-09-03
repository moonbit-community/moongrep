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
        rule.patterns[0].compiled.metavars.names(Expr),
        content="[\"value\"]",
      )
      debug_inspect(
        rule.patterns[0].compiled.metavars.names(Identifier),
        content="[]",
      )
      debug_inspect(
        rule.patterns[0].compiled.metavars.names(Constant),
        content="[]",
      )
    }
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "validate accepts keyword names for non-type single-node metavars" {
  let source =
    #|id: example
    #|description: Keyword metavar names.
    #|patterns:
    #|  - shape: sink($(else:exp))
    #|  - shape: sink($(if:const))
    #|  - shape: $(for:id)()
    #|  - shape: sink($(match:arg))
    #|  - shape: match input { $(if:pat) => body }
    #|  - shape: $if + $if
    #|
  let rules = compile_one(source)
  match rules[0].definition {
    Structural(rule) => {
      assert_eq(rule.patterns.length(), 6)
      debug_inspect(
        rule.patterns[0].compiled.metavars.names(Expr),
        content="[\"else\"]",
      )
      debug_inspect(
        rule.patterns[1].compiled.metavars.names(Constant),
        content="[\"if\"]",
      )
      debug_inspect(
        rule.patterns[2].compiled.metavars.names(Identifier),
        content="[\"for\"]",
      )
      debug_inspect(
        rule.patterns[3].compiled.metavars.names(Argument),
        content="[\"match\"]",
      )
      debug_inspect(
        rule.patterns[5].compiled.metavars.names(Expr),
        content="[\"if\"]",
      )
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
  expect_compile_invalid(source, "the pattern has lexical errors")
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
        rule.patterns[0].compiled.metavars.names(Expr),
        content="[\"body\"]",
      )
      debug_inspect(
        rule.patterns[0].compiled.metavars.names(Identifier),
        content="[]",
      )
      debug_inspect(
        rule.patterns[0].compiled.metavars.names(Constant),
        content="[]",
      )
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
        rule.patterns[0].compiled.metavars.names(Expr),
        content="[\"limit\"]",
      )
      debug_inspect(
        rule.patterns[0].compiled.metavars.names(Identifier),
        content="[\"counter\"]",
      )
      debug_inspect(
        rule.patterns[0].compiled.metavars.names(Constant),
        content="[]",
      )
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
        assert_eq(
          rule.patterns[0].compiled.metavars.names(Identifier).length(),
          1,
        )
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
    source, "the pattern cannot infer kind for bare metavar $item in a pattern variable position; use explicit typed syntax like $(item:id), $(item:const), or $(item:pat)",
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
    source, "the pattern cannot infer kind for bare metavar $pattern in a pattern variable position; use explicit typed syntax like $(pattern:id), $(pattern:const), or $(pattern:pat)",
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
    source, "the pattern cannot infer kind for bare metavar $item in a pattern variable position; use explicit typed syntax like $(item:id), $(item:const), or $(item:pat)",
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
        rule.patterns[0].compiled.metavars.names(Identifier),
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
    source, "the pattern uses $(item:exp) outside a bare expression position",
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
    source, "the pattern declares metavar item as multiple metavar kinds",
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
    source, "the pattern uses $(value:pat) outside a bare pattern position",
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
    source, "the pattern uses $(item:exp) outside a bare expression position",
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
    source, "the pattern declares metavar value as multiple metavar kinds",
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
        rule.patterns[0].compiled.metavars.names(Expr),
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
        rule.patterns[0].compiled.metavars.names(Constant),
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
      debug_inspect(
        rule.patterns[0].compiled.metavars.names(Argument),
        content="[\"arg\"]",
      )
      debug_inspect(
        rule.patterns[0].compiled.metavars.names(Expr),
        content="[]",
      )
      debug_inspect(
        rule.patterns[0].compiled.metavars.names(Identifier),
        content="[]",
      )
      debug_inspect(
        rule.patterns[0].compiled.metavars.names(Constant),
        content="[]",
      )
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
      debug_inspect(
        rule.patterns[0].compiled.metavars.names(Type),
        content="[\"T\"]",
      )
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "validate keeps the uppercase requirement for type metavar names" {
  let lowercase =
    #|id: lowercase
    #|description: Lowercase type metavar.
    #|patterns:
    #|  - shape: |
    #|      let value : $(foo:type) = input
    #|
  expect_compile_invalid(
    lowercase, "the pattern is not a valid MoonBit expression: Unexpected token id (lowercase start), you may expect type.",
  )
  let keyword =
    #|id: keyword
    #|description: Keyword type metavar.
    #|patterns:
    #|  - shape: |
    #|      let value : $(for:type) = input
    #|
  expect_compile_invalid(
    keyword, "the pattern is not a valid MoonBit expression: Unexpected token id (lowercase start), you may expect type.",
  )
  let ellipsis =
    #|id: ellipsis
    #|description: Lowercase type ellipsis metavar.
    #|patterns:
    #|  - shape: |
    #|      let value : ($$$(types:type), Bool) = input
    #|
  expect_compile_invalid(
    ellipsis, "the pattern is not a valid MoonBit expression: Unexpected token id (lowercase start), you may expect type.",
  )
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
      debug_inspect(
        rule.patterns[0].compiled.metavars.names(Type),
        content="[\"T\"]",
      )
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
      debug_inspect(
        rule.patterns[0].compiled.metavars.names(Type),
        content="[\"T\"]",
      )
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
    expr_source, "the pattern uses $(T:type) outside a whole type position",
  )
  let arg_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: sink($(T:type))
    #|
  expect_compile_invalid(
    arg_source, "the pattern uses $(T:type) outside a whole type position",
  )
  let pattern_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: match input { $(T:type) => body }
    #|
  expect_compile_invalid(
    pattern_source, "the pattern uses $(T:type) outside a whole type position",
  )
  let label_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: sink($(T:type)=value)
    #|
  expect_compile_invalid(
    label_source, "the pattern is not a valid MoonBit expression: Unexpected uppercase identifier $(T:type), expected lowercase identifier.",
  )
  let constructor_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: $(T:type)(value)
    #|
  expect_compile_invalid(
    constructor_source, "the pattern uses $(T:type) outside a whole type position",
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
    exp_source, "the pattern uses $(T:exp) outside a bare expression position",
  )
  let id_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: |
    #|      let $(T:id) : $(T:type) = input
    #|
  expect_compile_invalid(
    id_source, "the pattern declares metavar T as multiple metavar kinds",
  )
  let const_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: |
    #|      let value : $(T:type) = $(T:const)
    #|
  expect_compile_invalid(
    const_source, "the pattern uses $(T:const) outside a constant expression or pattern position",
  )
  let arg_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: |
    #|      let value : $(T:type) = sink($(T:arg))
    #|
  expect_compile_invalid(
    arg_source, "the pattern uses $(T:arg) outside a bare argument position",
  )
  let pat_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: |
    #|      let value : $(T:type) = match input { $(T:pat) => body }
    #|
  expect_compile_invalid(
    pat_source, "the pattern uses $(T:pat) outside a bare pattern position",
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
        rule.patterns[0].compiled.metavars.names(Identifier),
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
        rule.patterns[0].compiled.metavars.names(Identifier),
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
        rule.patterns[0].compiled.metavars.names(Identifier),
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
    source, "the pattern declares metavar value as multiple metavar kinds",
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
    exp_source, "the pattern declares metavar value as multiple metavar kinds",
  )
  let id_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: sink($(value:arg), $(value:id))
    #|
  expect_compile_invalid(
    id_source, "the pattern declares metavar value as multiple metavar kinds",
  )
  let const_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: sink($(value:arg), $(value:const))
    #|
  expect_compile_invalid(
    const_source, "the pattern declares metavar value as multiple metavar kinds",
  )
  let pat_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: sink($(value:arg), match input { $(value:pat) => ok })
    #|
  expect_compile_invalid(
    pat_source, "the pattern declares metavar value as multiple metavar kinds",
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
    root_source, "the pattern uses $(value:arg) outside a bare argument position",
  )
  let labelled_value_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: sink(label=$(value:arg))
    #|
  expect_compile_invalid(
    labelled_value_source, "the pattern uses $(value:arg) outside a bare argument position",
  )
  let nested_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: sink($(value:arg) + 1)
    #|
  expect_compile_invalid(
    nested_source, "the pattern uses $(value:arg) outside a bare argument position",
  )
  let pattern_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: match input { $(value:arg) => body }
    #|
  expect_compile_invalid(
    pattern_source, "the pattern uses $(value:arg) outside a bare argument position",
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
    source, "the pattern uses $(value:const) outside a constant expression or pattern position",
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
    source, "the pattern uses $(value:const) in an unsupported qualified identifier position",
  )
}

///|
test "validate rejects wildcard in qualified identifiers" {
  let package_source =
    #|id: package
    #|description: Qualified package wildcard.
    #|patterns:
    #|  - shape: "@html.$_"
    #|
  expect_compile_invalid(
    package_source, "the pattern uses $_ in an unsupported qualified identifier position",
  )
  let constructor_source =
    #|id: constructor
    #|description: Qualified constructor wildcard.
    #|patterns:
    #|  - shape: "Type::$_"
    #|
  expect_compile_invalid(
    constructor_source, "the pattern uses $_ in an unsupported qualified identifier position",
  )
  let field_source =
    #|id: field
    #|description: Qualified field wildcard.
    #|patterns:
    #|  - shape: "value.$_"
    #|
  expect_compile_invalid(
    field_source, "the pattern uses $_ in an unsupported qualified identifier position",
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
    source, "the pattern uses $(value:const) outside a constant expression or pattern position",
  )
}
