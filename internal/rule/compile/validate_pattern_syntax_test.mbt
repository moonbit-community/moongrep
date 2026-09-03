///|
test "validate reports invalid pattern shape and info for every clause kind" {
  let pattern_source =
    #|id: pattern
    #|description: Invalid pattern.
    #|patterns:
    #|  - shape: wrap($$$items + 1)
    #|
  expect_compile_invalid_pattern(
    pattern_source, "wrap($$$items + 1)", "the pattern uses ellipsis metavar $$$items outside a complete ordered CST list item",
  )
  let negative_source =
    #|id: negative
    #|description: Invalid negative pattern.
    #|patterns:
    #|  - shape: target()
    #|patterns-not:
    #|  - shape: __TARGET__
    #|
  expect_compile_invalid_pattern(
    negative_source, "__TARGET__", "the pattern must not contain __TARGET__",
  )
  let inside_expr_source =
    #|id: inside-expr
    #|description: Invalid expression context.
    #|inside-expr:
    #|  - shape: wrapper()
    #|patterns:
    #|  - shape: target()
    #|
  expect_compile_invalid_pattern(
    inside_expr_source, "wrapper()", "the pattern must contain exactly one __TARGET__ placeholder in a supported expression position",
  )
  let inside_toplevel_source =
    #|id: inside-toplevel
    #|description: Invalid top-level context.
    #|inside-toplevel:
    #|  - shape: marker()
    #|patterns:
    #|  - shape: target()
    #|
  expect_compile_invalid_pattern(
    inside_toplevel_source, "marker()", "the pattern is not a valid MoonBit top-level item",
  )
  let taint_source =
    #|id: taint-source
    #|description: Invalid taint source.
    #|taint:
    #|  sources:
    #|    - shape: source(__SOURCE__)
    #|  sinks:
    #|    - shape: sink(__SOURCE__)
    #|
  expect_compile_invalid_pattern(
    taint_source, "source(__SOURCE__)", "the pattern must not contain __SOURCE__",
  )
  let taint_sink =
    #|id: taint-sink
    #|description: Invalid taint sink.
    #|taint:
    #|  sources:
    #|    - shape: source()
    #|  sinks:
    #|    - shape: sink(wrap(__SOURCE__))
    #|
  expect_compile_invalid_pattern(
    taint_sink, "sink(wrap(__SOURCE__))", "the pattern must place __SOURCE__ as the whole receiver or argument value",
  )
  let taint_sanitizer =
    #|id: taint-sanitizer
    #|description: Invalid taint sanitizer.
    #|taint:
    #|  sources:
    #|    - shape: source()
    #|  sinks:
    #|    - shape: sink(__SOURCE__)
    #|  sanitizers:
    #|    - shape: __SOURCE__
    #|
  expect_compile_invalid_pattern(
    taint_sanitizer, "__SOURCE__", "the pattern must be a call expression",
  )
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
      let metavars = rule.patterns[0].compiled.metavars
      assert_eq(metavars.entries.length(), 2)
      debug_inspect(metavars.names(Ellipsis(AnyItem)), content="[\"args\"]")
      debug_inspect(metavars.names(Ellipsis(ArgItem)), content="[\"values\"]")
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
      let metavars = rule.patterns[0].compiled.metavars
      assert_eq(metavars.entries.length(), 1)
      debug_inspect(metavars.names(Ellipsis(ExpItem)), content="[\"items\"]")
    }
    Taint(_) => fail("expected structural rule")
  }
}

///|
test "validate keeps mixed metavar kinds in first occurrence order" {
  let source =
    #|id: mixed-order
    #|description: Mixed metavar order.
    #|patterns:
    #|  - shape: |
    #|      consume(
    #|        $(literal:const),
    #|        $(name:id),
    #|        $$$items,
    #|        $value,
    #|        $(argument:arg),
    #|        match input { $(pattern:pat) => body },
    #|        match input { (item : $(T:type)) => body },
    #|      )
    #|
  let rules = compile_one(source)
  match rules[0].definition {
    Structural(rule) => {
      let metavars = rule.patterns[0].compiled.metavars
      debug_inspect(
        [
          for entry in metavars.entries => entry.name
        ],
        content="[\"literal\", \"name\", \"items\", \"value\", \"argument\", \"pattern\", \"T\"]",
      )
      debug_inspect(metavars.names(Constant), content="[\"literal\"]")
      debug_inspect(metavars.names(Identifier), content="[\"name\"]")
      debug_inspect(metavars.names(Ellipsis(AnyItem)), content="[\"items\"]")
      debug_inspect(metavars.names(Expr), content="[\"value\"]")
      debug_inspect(metavars.names(Argument), content="[\"argument\"]")
      debug_inspect(metavars.names(Pattern), content="[\"pattern\"]")
      debug_inspect(metavars.names(Type), content="[\"T\"]")
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
    root, "the pattern uses ellipsis metavar $$$items outside a complete ordered CST list item",
  )
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: wrap($$$items + 1)
    #|
  expect_compile_invalid(
    source, "the pattern uses ellipsis metavar $$$items outside a complete ordered CST list item",
  )
}

///|
test "validate rejects ellipsis inside grouping parentheses" {
  let grouped_bare =
    #|id: grouped-bare
    #|description: Grouped bare ellipsis.
    #|patterns:
    #|  - shape: ($$$items)
    #|
  expect_compile_invalid(
    grouped_bare, "the pattern uses ellipsis metavar $$$items outside a complete ordered CST list item",
  )
  let grouped_typed =
    #|id: grouped-typed
    #|description: Grouped typed ellipsis.
    #|patterns:
    #|  - shape: ($$$(values:exp))
    #|
  expect_compile_invalid(
    grouped_typed, "the pattern uses ellipsis metavar $$$(values:exp) outside a complete ordered CST list item",
  )
  let nested =
    #|id: nested-group
    #|description: Nested grouped ellipsis.
    #|patterns:
    #|  - shape: (($$$items))
    #|
  expect_compile_invalid(
    nested, "the pattern uses ellipsis metavar $$$items outside a complete ordered CST list item",
  )
  let grouped_pattern_item =
    #|id: grouped-pattern-item
    #|description: Grouped pattern tuple item.
    #|patterns:
    #|  - shape: match input { (($$$(patterns:pat)), tail) => body }
    #|
  expect_compile_invalid(
    grouped_pattern_item, "the pattern uses ellipsis metavar $$$(patterns:pat) outside a complete ordered CST list item",
  )
  let grouped_type_item =
    #|id: grouped-type-item
    #|description: Grouped type tuple item.
    #|patterns:
    #|  - shape: |
    #|      let value : (($$$(Types:type)), Bool) = input
    #|
  expect_compile_invalid(
    grouped_type_item, "the pattern uses ellipsis metavar $$$(Types:type) outside a complete ordered CST list item",
  )
}

///|
test "validate keeps ellipsis in true tuple lists" {
  let source =
    #|id: tuple-lists
    #|description: True tuple list ellipses.
    #|patterns:
    #|  - shape: tuple_expr(($$$(items:exp), tail))
    #|  - shape: match input { ($$$(patterns:pat), tail) => body }
    #|  - shape: |
    #|      let value : ($$$(Types:type), Bool) = input
    #|
  let rules = compile_one(source)
  match rules[0].definition {
    Structural(rule) => {
      assert_true(
        rule.patterns[0].compiled.metavars.kind_of("items") ==
        Some(Ellipsis(ExpItem)),
      )
      assert_true(
        rule.patterns[1].compiled.metavars.kind_of("patterns") ==
        Some(Ellipsis(PatItem)),
      )
      assert_true(
        rule.patterns[2].compiled.metavars.kind_of("Types") ==
        Some(Ellipsis(TypeItem)),
      )
    }
    Taint(_) => fail("expected structural rule")
  }
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
  expect_compile_invalid_rule(
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
    conflicting, "the pattern declares ellipsis metavar items as multiple metavar kinds",
  )
  let mixed =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: pair($items, [$$$items])
    #|
  expect_compile_invalid(
    mixed, "the pattern cannot use items as both an ellipsis metavar and a single-node metavar",
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
    parameter, "the pattern uses ellipsis kind exp in an incompatible ordered-list item position",
  )
  let argument =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: sink($$$(values:pat))
    #|
  expect_compile_invalid(
    argument, "the pattern uses ellipsis kind pat in an incompatible ordered-list item position",
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
        rule.patterns[0].compiled.metavars.names(Expr),
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
      debug_inspect(
        rule.patterns[0].compiled.metavars.names(Argument),
        content="[]",
      )
      debug_inspect(
        rule.patterns[0].compiled.metavars.names(Type),
        content="[]",
      )
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
    target_source, "the pattern cannot declare metavar __TARGET__ because it is reserved for inside-expr target traversal",
  )
  let source_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: $(__SOURCE__:exp)
    #|
  expect_compile_invalid(
    source_source, "the pattern cannot declare metavar __SOURCE__ because it is reserved for taint source targets",
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
    source, "the pattern uses legacy metavar syntax $exp:value; use $(value:exp)",
  )
}
