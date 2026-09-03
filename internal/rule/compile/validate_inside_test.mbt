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
  expect_compile_invalid_rule(
    source, "patterns[0] cannot use inherited inside-expr[0] metavar T as id because it was declared as type",
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
        rule.patterns[0].compiled.metavars.names(Expr),
        content="[\"value\"]",
      )
      debug_inspect(
        rule.patterns[0].compiled.metavars.names(Identifier),
        content="[\"name\"]",
      )
      debug_inspect(
        rule.patterns[0].compiled.metavars.names(Constant),
        content="[\"lit\"]",
      )
      debug_inspect(
        rule.patterns[0].compiled.metavars.names(Argument),
        content="[\"arg\"]",
      )
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
        inside_expr.compiled.metavars.names(Identifier),
        content="[\"name\"]",
      )
      debug_inspect(
        inside_expr.compiled.metavars.names(Constant),
        content="[\"lit\"]",
      )
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
        inside_toplevel.compiled.metavars.names(Identifier),
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
    source, "the pattern uses match-mode partial, which is only supported for function definition shapes",
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
        inside_toplevel.compiled.metavars.names(Identifier),
        content="[\"name\"]",
      )
      debug_inspect(
        inside_toplevel.compiled.metavars.names(Constant),
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
        rule.patterns_not[0].compiled.metavars.names(Identifier),
        content="[\"name\"]",
      )
      debug_inspect(
        rule.patterns_not[0].compiled.metavars.names(Constant),
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
        rule.patterns_not[0].compiled.metavars.names(Identifier),
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
        rule.patterns_not[0].compiled.metavars.names(Identifier),
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
  expect_compile_invalid(source, "the pattern must not contain __TARGET__")
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
        rule.patterns[0].compiled.metavars.names(Constant),
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
    source, "the pattern must contain exactly one __TARGET__ placeholder in a supported expression position",
  )
}

///|
test "validate inside expr counts only bindable target expressions" {
  let pattern_only =
    #|id: example
    #|description: Pattern-only target spelling.
    #|inside-expr:
    #|  - shape: match input { __TARGET__ => body }
    #|patterns:
    #|  - shape: marker()
    #|
  expect_compile_invalid(
    pattern_only, "the pattern must contain exactly one __TARGET__ placeholder in a supported expression position",
  )
  let binder_only =
    #|id: example
    #|description: Binder-only target spelling.
    #|inside-expr:
    #|  - shape: let __TARGET__ = value; body
    #|patterns:
    #|  - shape: marker()
    #|
  expect_compile_invalid(
    binder_only, "the pattern must contain exactly one __TARGET__ placeholder in a supported expression position",
  )
  let pattern_and_expression =
    #|id: example
    #|description: One bindable target plus a pattern spelling.
    #|inside-expr:
    #|  - shape: match input { __TARGET__ => __TARGET__ }
    #|patterns:
    #|  - shape: marker()
    #|
  let rules = compile_one(pattern_and_expression)
  match rules[0].definition {
    Structural(rule) => assert_eq(rule.inside_expr.length(), 1)
    Taint(_) => fail("expected structural rule")
  }
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
    missing_target, "the pattern must contain exactly one __TARGET__ placeholder in a supported expression position",
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
    duplicate_target, "the pattern must contain exactly one __TARGET__ placeholder in a supported expression position",
  )
}

///|
test "validate inside toplevel counts only bindable target expressions" {
  let binder_only =
    #|id: example
    #|description: Top-level binder-only target spelling.
    #|inside-toplevel:
    #|  - shape: let __TARGET__ = value
    #|patterns:
    #|  - shape: marker()
    #|
  expect_compile_invalid(
    binder_only, "the pattern must contain exactly one __TARGET__ placeholder in a supported expression position",
  )
  let binder_and_expression =
    #|id: example
    #|description: One bindable target plus a top-level binder spelling.
    #|inside-toplevel:
    #|  - shape: let __TARGET__ = __TARGET__
    #|patterns:
    #|  - shape: marker()
    #|
  let rules = compile_one(binder_and_expression)
  match rules[0].definition {
    Structural(rule) => assert_eq(rule.inside_toplevel.length(), 1)
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "validate ordinary patterns reject only bindable target expressions" {
  let non_expression_names =
    #|id: example
    #|description: Non-expression target spellings are literal names.
    #|patterns:
    #|  - shape: match input { __TARGET__ => body }
    #|patterns-not:
    #|  - shape: call(__TARGET__=value)
    #|
  let rules = compile_one(non_expression_names)
  match rules[0].definition {
    Structural(rule) => {
      assert_eq(rule.patterns.length(), 1)
      assert_eq(rule.patterns_not.length(), 1)
    }
    Taint(_) => fail("expected structural rule")
  }
  let expression_target =
    #|id: example
    #|description: Bindable target spelling is reserved.
    #|patterns:
    #|  - shape: match input { value => __TARGET__ }
    #|
  expect_compile_invalid(
    expression_target, "the pattern must not contain __TARGET__",
  )
}

///|
test "validate rejects standalone expression as inside toplevel shape" {
  let source =
    #|id: example
    #|description: Expressions are not top-level items.
    #|inside-toplevel:
    #|  - shape: wrapper(__TARGET__)
    #|patterns:
    #|  - shape: marker()
    #|
  expect_compile_invalid(
    source, "the pattern is not a valid MoonBit top-level item",
  )
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
        rule.patterns[0].compiled.metavars.names(Identifier),
        content="[\"name\"]",
      )
      debug_inspect(
        rule.patterns[0].compiled.metavars.names(Constant),
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
        rule.patterns[0].compiled.metavars.names(Identifier),
        content="[\"name\"]",
      )
      debug_inspect(
        rule.patterns[0].compiled.metavars.names(Constant),
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
        rule.inside_expr[0].compiled.metavars.names(Identifier),
        content="[\"name\"]",
      )
      debug_inspect(
        rule.inside_expr[1].compiled.metavars.names(Identifier),
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
        rule.inside_toplevel[0].compiled.metavars.names(Identifier),
        content="[\"name\"]",
      )
      debug_inspect(
        rule.inside_toplevel[1].compiled.metavars.names(Identifier),
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
test "validate merges bare ellipsis kinds across compatible inside reuse" {
  let source =
    #|id: compatible-ellipsis
    #|description: Compatible inherited ellipsis.
    #|inside-expr:
    #|  - shape: wrapper([$$$items], [$$$(items:exp)], __TARGET__)
    #|  - shape: container([$$$(items:exp)], __TARGET__)
    #|patterns:
    #|  - shape: target([$$$items], [$$$(items:exp)])
    #|
  let rules = compile_one(source)
  match rules[0].definition {
    Structural(rule) => {
      assert_true(
        rule.inside_expr[0].compiled.metavars.kind_of("items") ==
        Some(Ellipsis(ExpItem)),
      )
      assert_true(
        rule.inside_expr[1].compiled.metavars.kind_of("items") ==
        Some(Ellipsis(ExpItem)),
      )
      assert_true(
        rule.patterns[0].compiled.metavars.kind_of("items") ==
        Some(Ellipsis(ExpItem)),
      )
    }
    Taint(_) => fail("expected structural rule")
  }
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
test "validate reports target error shape from later outer alternatives" {
  let source =
    #|id: example
    #|description: Missing target in second context.
    #|inside-expr:
    #|  - shape: wrapper(__TARGET__)
    #|  - shape: container(no_target)
    #|patterns:
    #|  - shape: target()
    #|
  expect_compile_invalid_pattern(
    source, "container(no_target)", "the pattern must contain exactly one __TARGET__ placeholder in a supported expression position",
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
  expect_compile_invalid_pattern(
    toplevel_source, "let value = pair(__TARGET__, __TARGET__)", "the pattern must contain exactly one __TARGET__ placeholder in a supported expression position",
  )
}
