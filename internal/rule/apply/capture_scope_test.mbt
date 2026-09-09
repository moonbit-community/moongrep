///|
test "report condition binder cannot be rebound at the else target" {
  let rule =
    #|id: condition-origin
    #|description: Keep the conditional declaration's identity.
    #|patterns:
    #|  - shape: if $_ is Some($(name:id)) { $_ } else { __TARGET__ }
    #|    then:
    #|      patterns:
    #|        - shape: sink($(name:id))
  let source =
    #|fn sample {
    #|  let item = outer()
    #|  if input is Some(item) {
    #|    consume(item)
    #|  } else {
    #|    sink(item)
    #|  }
    #|}
  inspect(apply_structural_rule_findings(source, rule).length(), content="0")
  let then_rule =
    #|id: condition-origin
    #|description: The conditional declaration is visible in its body.
    #|patterns:
    #|  - shape: if $_ is Some($(name:id)) { __TARGET__ } else { $_ }
    #|    then:
    #|      patterns:
    #|        - shape: consume($(name:id))
  inspect(
    apply_structural_rule_findings(source, then_rule).length(),
    content="1",
  )
}

///|
test "report inherited occurrences check shadowing inside atomic sequences" {
  let rule =
    #|id: sequence-origin
    #|description: Check the sink occurrence after the local declaration.
    #|patterns:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: let $_ = $_; sink($(name:id))
  let source = "fn sample { wrapper(item, { let item = source(); sink(item) }) }"
  inspect(apply_structural_rule_findings(source, rule).length(), content="0")
  let control = "fn sample { wrapper(item, { let other = source(); sink(item) }) }"
  inspect(apply_structural_rule_findings(control, rule).length(), content="1")
}

///|
test "report field captures ignore same-named local variables" {
  let rule =
    #|id: field-origin
    #|description: Accessor names do not resolve in the variable namespace.
    #|patterns:
    #|  - shape: wrapper($_.$(field:id), __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: sink($_.$(field:id))
  let source = "fn sample { wrapper(object.field, { let field = source(); sink(object.field) }) }"
  inspect(apply_structural_rule_findings(source, rule).length(), content="1")
  let control = "fn sample { wrapper(object.field, sink(object.field)) }"
  inspect(apply_structural_rule_findings(control, rule).length(), content="1")
  let different = "fn sample { wrapper(object.field, sink(object.other)) }"
  inspect(apply_structural_rule_findings(different, rule).length(), content="0")
}

///|
test "report typed identifier lists retain each source binding" {
  let rule =
    #|id: list-origin
    #|description: Every inherited list element retains its binding.
    #|patterns:
    #|  - shape: wrapper($$$(names:id), __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: sink($$$(names:id))
  let source = "fn sample { wrapper(a, b, { let a = source(); sink(a, b) }) }"
  inspect(apply_structural_rule_findings(source, rule).length(), content="0")
  let control = "fn sample { wrapper(a, b, { let other = source(); sink(a, b) }) }"
  inspect(apply_structural_rule_findings(control, rule).length(), content="1")
  for
    (body, expected) in [
      ("wrapper(a, b, { let b = source(); sink(a, b) })", 0),
      ("wrapper(a, b, sink(b, a))", 0),
      ("wrapper(a, { let a = source(); sink(a) })", 0),
      ("wrapper(a, sink(a))", 1),
      ("wrapper({ let a = source(); sink() })", 1),
      ("wrapper(a, b, { sink(a, b); let a = source() })", 1),
      ("let a = source(); let b = source(); wrapper(a, b, sink(a, b))", 1),
      ("let a = source(); wrapper(a, b, { let a = source(); sink(a, b) })", 0),
    ] {
    assert_eq(
      apply_structural_rule_findings("fn sample { \{body} }", rule).length(),
      expected,
    )
  }
}

///|
test "every inherited occurrence uses its own scope including earlier references" {
  let prefix = "id: occurrences\ndescription: Check actual occurrences.\npatterns:\n  - shape: wrapper($(name:id), __TARGET__)\n    then:\n      patterns:\n        - shape: "
  let repeated = prefix + "sink($(name:id)); let $_ = $_; sink($(name:id))"
  let earlier = prefix + "sink($(name:id)); let $_ = $_; done()"
  for (binding, expected) in [("item", 0), ("other", 1)] {
    let source = "fn sample { wrapper(item, { sink(item); let \{binding} = source(); sink(item) }) }"
    assert_eq(
      apply_structural_rule_findings(source, repeated).length(),
      expected,
    )
  }
  inspect(
    apply_structural_rule_findings(
      "fn sample { wrapper(item, { sink(item); let item = source(); done() }) }",
      earlier,
    ).length(),
    content="1",
  )
}

///|
test "cross-role identifier reuse compares names when either side is nonlexical" {
  for
    (outer, inner) in [
      ("$(name:id)", "$_.$(name:id)"),
      ("$_.$(name:id)", "$(name:id)"),
      ("$_.$(name:id)", "$_.$(name:id)"),
      ("labelled($(name:id)=$_)", "$(name:id)"),
      ("$(name:id)", "labelled($(name:id)=$_ )"),
    ] {
    let rule = "id: roles\ndescription: Only compare lexical pairs.\npatterns:\n  - shape: wrapper(\{outer}, __TARGET__)\n    then:\n      patterns:\n        - shape: sink(\{inner})"
    let outer_value = if outer == "$(name:id)" {
      "item"
    } else if outer.has_prefix("labelled") {
      "labelled(item=0)"
    } else {
      "object.item"
    }
    let inner_value = if inner == "$(name:id)" {
      "item"
    } else if inner.has_prefix("labelled") {
      "labelled(item=0)"
    } else {
      "object.item"
    }
    let source = "fn sample { wrapper(\{outer_value}, { let item = source(); sink(\{inner_value}) }) }"
    assert_eq(apply_structural_rule_findings(source, rule).length(), 1)
  }
}

///|
test "intermediate cross-role uses preserve the original capture source" {
  let variable =
    #|id: variable-origin
    #|description: A field occurrence does not replace the variable's source.
    #|patterns:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: middle($_.$(name:id), __TARGET__)
    #|          then:
    #|            patterns:
    #|              - shape: sink($(name:id))
  let source = "fn sample { wrapper(item, { let item = source(); middle(object.item, sink(item)) }) }"
  inspect(
    apply_structural_rule_findings(source, variable).length(),
    content="0",
  )
  let field =
    #|id: field-origin
    #|description: Variable occurrences do not make a field capture lexical.
    #|patterns:
    #|  - shape: wrapper($_.$(name:id), __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: middle($(name:id), __TARGET__)
    #|          then:
    #|            patterns:
    #|              - shape: sink($(name:id))
  let source = "fn sample { wrapper(object.item, middle(item, { let item = source(); sink(item) })) }"
  inspect(apply_structural_rule_findings(source, field).length(), content="1")
}

///|
test "parameter binders are inherited by then and inside-toplevel" {
  let nested =
    #|id: parameter
    #|description: A parameter capture resolves to its declaration.
    #|patterns:
    #|  - shape: fn($(name:id)) { __TARGET__ }
    #|    then:
    #|      patterns:
    #|        - shape: sink($(name:id))
  let toplevel =
    #|id: parameter
    #|description: A top-level parameter keeps its declaration identity.
    #|inside-toplevel:
    #|  - shape: 'fn $_($(name:id) : Int) { __TARGET__ }'
    #|patterns:
    #|  - shape: let $_ = $_; sink($(name:id))
  for (binding, expected) in [("item", 0), ("other", 1)] {
    let body = "let \{binding} = source(); sink(item)"
    assert_eq(
      apply_structural_rule_findings(
        "fn sample { fn(item) { \{body} } }",
        nested,
      ).length(),
      expected,
    )
    assert_eq(
      apply_structural_rule_findings(
        "fn sample(item : Int) { \{body} }",
        toplevel,
      ).length(),
      expected,
    )
  }
}

///|
test "enumview parameter captures match their body references" {
  let rule =
    #|id: enumview-parameter
    #|description: A view parameter keeps its declaration identity.
    #|inside-toplevel:
    #|  - shape: enumview ValueView { Value(Int) } for Int with view($(name:id)) { __TARGET__ }
    #|patterns:
    #|  - shape: sink($(name:id))
  let visible = "enumview ValueView { Value(Int) } for Int with view(item) { sink(item) }"
  inspect(apply_structural_rule_findings(visible, rule).length(), content="1")
  let shadowed = "enumview ValueView { Value(Int) } for Int with view(item) { { let item = source(); sink(item) } }"
  inspect(apply_structural_rule_findings(shadowed, rule).length(), content="0")
}

///|
test "enumview negative patterns reject only the captured parameter" {
  let rule =
    #|id: enumview-negative
    #|description: Reject only sinks using the captured view parameter.
    #|inside-toplevel:
    #|  - shape: enumview ValueView { Value(Int) } for Int with view($(name:id)) { __TARGET__ }
    #|patterns-not:
    #|  - shape: sink($(name:id))
  let visible = "enumview ValueView { Value(Int) } for Int with view(item) { sink(item) }"
  inspect(apply_structural_rule_findings(visible, rule).length(), content="0")
  let shadowed = "enumview ValueView { Value(Int) } for Int with view(item) { { let item = source(); sink(item) } }"
  inspect(apply_structural_rule_findings(shadowed, rule).length(), content="1")
}

///|
test "enumview guards require the inherited parameter to remain visible" {
  let rule =
    #|id: enumview-guard
    #|description: Guards preserve the view parameter's binding.
    #|inside-toplevel:
    #|  - shape: enumview ValueView { Value(Int) } for Int with view($(name:id)) { __TARGET__ }
    #|patterns:
    #|  - shape: sink($_)
    #|    guard:
    #|      $name: '^item$'
  let visible = "enumview ValueView { Value(Int) } for Int with view(item) { sink(item) }"
  inspect(apply_structural_rule_findings(visible, rule).length(), content="1")
  let shadowed = "enumview ValueView { Value(Int) } for Int with view(item) { { let item = source(); sink(item) } }"
  inspect(apply_structural_rule_findings(shadowed, rule).length(), content="0")
}

///|
test "enumview parameter captures survive recursive then" {
  let rule =
    #|id: enumview-recursive
    #|description: Keep the view parameter through unused capture levels.
    #|inside-toplevel:
    #|  - shape: enumview ValueView { Value(Int) } for Int with view($(name:id)) { __TARGET__ }
    #|patterns:
    #|  - shape: middle(__TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: wrapper(__TARGET__)
    #|          then:
    #|            patterns:
    #|              - shape: sink($(name:id))
  let visible = "enumview ValueView { Value(Int) } for Int with view(item) { middle(wrapper(sink(item))) }"
  inspect(apply_structural_rule_findings(visible, rule).length(), content="1")
  let shadowed = "enumview ValueView { Value(Int) } for Int with view(item) { middle(wrapper({ let item = source(); sink(item) })) }"
  inspect(apply_structural_rule_findings(shadowed, rule).length(), content="0")
}

///|
test "parameter defaults inherit preceding parameters through inside-toplevel" {
  let rule =
    #|id: default-origin
    #|description: A default value sees the preceding parameter.
    #|inside-toplevel:
    #|  - shape: 'fn $_($(name:id) : Int, next~ : Int = __TARGET__) { $_ }'
    #|patterns:
    #|  - shape: sink($(name:id))
  let source = "fn sample(item : Int, next~ : Int = sink(item)) { () }"
  inspect(apply_structural_rule_findings(source, rule).length(), content="1")
}

///|
test "for update captures reject a shadowing local and retain the loop variable" {
  let rule =
    #|id: for-update-origin
    #|description: An update target refers to the loop variable.
    #|patterns:
    #|  - shape: for $_ = $_; $_; $(name:id) = $_ { __TARGET__ }
    #|    then:
    #|      patterns:
    #|        - shape: sink($(name:id))
  let shadowed = "fn sample { for i = 0; i < 10; i = i + 1 { let i = source(); sink(i) } }"
  inspect(apply_structural_rule_findings(shadowed, rule).length(), content="0")
  let visible = "fn sample { for i = 0; i < 10; i = i + 1 { let other = source(); sink(i) } }"
  inspect(apply_structural_rule_findings(visible, rule).length(), content="1")
}

///|
test "defaults and for updates preserve captures through recursive then" {
  for
    (shape, expression) in [
      (
        "fn($(name:id) : Int, next~ : Int = __TARGET__) { $_ }", "fn(item : Int, next~ : Int = BODY) { () }",
      ),
      (
        "for $_ = $_; $_; $(name:id) = $_ { __TARGET__ }", "for item = 0; item < 10; item = item + 1 { BODY }",
      ),
    ] {
    let nested = "id: recursive-origin\ndescription: Keep the original binding through an unused level.\npatterns:\n  - shape: '\{shape}'\n    then:\n      patterns:\n        - shape: middle(__TARGET__)\n          then:\n            patterns:\n              - shape: sink($(name:id))"
    let toplevel = "id: recursive-origin\ndescription: Keep the original binding through an unused level.\ninside-toplevel:\n  - shape: 'fn $_ { \{shape} }'\npatterns:\n  - shape: middle(__TARGET__)\n    then:\n      patterns:\n        - shape: sink($(name:id))"
    for (binding, expected) in [("other", 1), ("item", 0)] {
      let body = "middle({ let \{binding} = source(); sink(item) })"
      let source = "fn sample { " +
        expression.replace(old="BODY", new=body) +
        " }"
      for rule in [nested, toplevel] {
        assert_eq(
          apply_structural_rule_findings(source, rule).length(),
          expected,
        )
      }
    }
  }
}

///|
test "negative patterns and guards use default and for update capture origins" {
  for
    (shape, expression) in [
      (
        "fn($(name:id) : Int, next~ : Int = __TARGET__) { $_ }", "fn(item : Int, next~ : Int = { BODY }) { () }",
      ),
      (
        "for $_ = $_; $_; $(name:id) = $_ { __TARGET__ }", "for item = 0; item < 10; item = item + 1 { BODY }",
      ),
    ] {
    let negative = "id: negative-origin\ndescription: Reject only sinks using the captured binding.\npatterns:\n  - shape: '\{shape}'\n    then:\n      patterns-not:\n        - shape: sink($(name:id))"
    let guarded = "id: guard-origin\ndescription: Guards require the original binding to remain visible.\npatterns:\n  - shape: '\{shape}'\n    then:\n      patterns:\n        - shape: sink($_)\n          guard:\n            $name: '^item$'"
    for (binding, expected) in [("other", 1), ("item", 0)] {
      let body = "let \{binding} = source(); sink(item)"
      let source = "fn sample { " +
        expression.replace(old="BODY", new=body) +
        " }"
      assert_eq(
        apply_structural_rule_findings(source, negative).length(),
        1 - expected,
      )
      assert_eq(
        apply_structural_rule_findings(source, guarded).length(),
        expected,
      )
    }
  }
}

///|
test "for update targets retain loop bindings when conditions bind the same name" {
  let rule =
    #|id: for-condition-origin
    #|description: The condition binder does not replace the update target.
    #|patterns:
    #|  - shape: for $_ = $_; $_; $(name:id) = __TARGET__ { $_ }
    #|    then:
    #|      patterns:
    #|        - shape: sink($(name:id))
  let shadowed = "fn sample { for i = 0; input is Some(i); i = sink(i) { () } }"
  inspect(apply_structural_rule_findings(shadowed, rule).length(), content="0")
  let visible = "fn sample { for i = 0; input is Some(other); i = sink(i) { () } }"
  inspect(apply_structural_rule_findings(visible, rule).length(), content="1")
}

///|
test "guard-only reads check inherited lexical visibility at candidate entry" {
  let variable =
    #|id: guard-origin
    #|description: Guards preserve the original lexical source.
    #|patterns:
    #|  - shape: if $_ is Some($(name:id)) { $_ } else { __TARGET__ }
    #|    then:
    #|      patterns:
    #|        - shape: sink($_)
    #|          guard:
    #|            $name: '^item$'
  inspect(
    apply_structural_rule_findings(
      "fn sample { let item = outer(); if input is Some(item) { () } else { sink(item) } }",
      variable,
    ).length(),
    content="0",
  )
  let field =
    #|id: guard-field
    #|description: A field capture has no lexical visibility constraint.
    #|patterns:
    #|  - shape: wrapper($_.$(name:id), __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: sink($_)
    #|          guard:
    #|            $name: '^item$'
  inspect(
    apply_structural_rule_findings(
      "fn sample { wrapper(object.item, { let item = source(); sink(item) }) }",
      field,
    ).length(),
    content="1",
  )
}

///|
test "negative atomic sequences check inherited occurrences after declarations" {
  let rule =
    #|id: negative-origin
    #|description: A shadowed occurrence does not match a negative entry.
    #|patterns:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|    then:
    #|      patterns-not:
    #|        - shape: let $_ = $_; sink($(name:id))
  for (binding, expected) in [("item", 1), ("other", 0)] {
    let source = "fn sample { wrapper(item, { let \{binding} = source(); sink(item) }) }"
    assert_eq(apply_structural_rule_findings(source, rule).length(), expected)
  }
}

///|
test "binding mismatch retries an atomic ellipsis partition" {
  let rule =
    #|id: retry-binding
    #|description: The first item is shadowed but the second retains the source.
    #|patterns:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: choose($$$_, { let $_ = $_; sink($(name:id)) }, $$$_)
  let source = "fn sample { wrapper(item, choose({ let item = source(); sink(item) }, { let other = source(); sink(item) })) }"
  inspect(apply_structural_rule_findings(source, rule).length(), content="1")
}

///|
test "new capture provenance rolls back with failed ellipsis branches" {
  let rule =
    #|id: retry-source
    #|description: Commit the source of the successful partition.
    #|patterns:
    #|  - shape: choose($$$_, fn($(name:id)) { __TARGET__ }, marker())
    #|    then:
    #|      patterns:
    #|        - shape: sink($(name:id))
  let source = "fn sample { choose(fn(item) { sink(item) }, fn(item) { sink(item) }, marker()) }"
  inspect(apply_structural_rule_findings(source, rule).length(), content="1")
}

///|
test "same-shape identifier repetitions keep name equality and the first source" {
  let rule =
    #|id: first-source
    #|description: Repeated new captures keep existing name comparison.
    #|patterns:
    #|  - shape: wrapper($(name:id), { let $(name:id) = $_; __TARGET__ })
    #|    then:
    #|      patterns:
    #|        - shape: sink($(name:id))
  let source = "fn sample { wrapper(item, { let item = source(); sink(item) }) }"
  inspect(apply_structural_rule_findings(source, rule).length(), content="0")
  let plain =
    #|id: same-shape
    #|description: New identifier repetitions compare names.
    #|patterns:
    #|  - shape: wrapper($(name:id), { let $(name:id) = $_; sink($(name:id)) })
  inspect(apply_structural_rule_findings(source, plain).length(), content="1")
}

///|
test "failed sibling sources cannot affect a same-named field capture" {
  let rule =
    #|id: siblings
    #|description: Siblings keep independent identifier sources.
    #|patterns:
    #|  - shape: pick($(name:id), $_, __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: sink($(name:id))
    #|  - shape: pick($_, $_.$(name:id), __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: sink($(name:id))
  let hits = apply_structural_rule_findings(
    "fn sample { pick(item, object.item, { let item = source(); sink(item) }) }",
    rule,
  )
  inspect(hits.length(), content="1")
  inspect(hits[0].pattern_index, content="1")
}

///|
test "inherited identifier lists keep origins across levels and atomic backtracking" {
  let rule =
    #|id: list-levels
    #|description: Preserve each original list element through an unused level.
    #|patterns:
    #|  - shape: wrapper($$$(names:id), __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: middle(__TARGET__)
    #|          then:
    #|            patterns:
    #|              - shape: choose($$$_, { let $_ = $_; sink($$$(names:id)) }, $$$_)
  let prefix = "fn sample { wrapper(a, b, middle(choose({ let a = source(); sink(a, b) }, "
  for (second, expected) in [("other", 1), ("b", 0)] {
    let source = prefix + "{ let \{second} = source(); sink(a, b) }))) }"
    assert_eq(apply_structural_rule_findings(source, rule).length(), expected)
  }
}

///|
test "wrapped binder captures survive inside-toplevel and recursive then" {
  for
    (shape, expression) in [
      (
        "match $_ { Some(_) as $(name:id) => __TARGET__ }", "match input { Some(_) as item => BODY }",
      ),
      (
        "lexmatch $_ { (re\"a\" as $(name:id)) => __TARGET__ }", "lexmatch input { (re\"a\" as item) => BODY }",
      ),
      ("∀ $(name:id) : Int, __TARGET__", "∀ item : Int, BODY"),
      ("∃ $(name:id) : Int, __TARGET__", "∃ item : Int, BODY"),
    ] {
    let nested = "id: wrapped\ndescription: Preserve the wrapped declaration.\npatterns:\n  - shape: '\{shape}'\n    then:\n      patterns:\n        - shape: middle(__TARGET__)\n          then:\n            patterns:\n              - shape: sink($(name:id))"
    let toplevel = "id: wrapped\ndescription: Preserve the wrapped declaration.\ninside-toplevel:\n  - shape: 'fn $_ { \{shape} }'\npatterns:\n  - shape: middle(__TARGET__)\n    then:\n      patterns:\n        - shape: sink($(name:id))"
    for (binding, expected) in [("other", 1), ("item", 0)] {
      let body = "{ middle({ let \{binding} = source(); sink(item) }) }"
      let source = "fn sample(item : Int) { " +
        expression.replace(old="BODY", new=body) +
        " }"
      for rule in [nested, toplevel] {
        assert_eq(
          apply_structural_rule_findings(source, rule).length(),
          expected,
        )
      }
    }
  }
}

///|
test "inherited assignment targets check bound and free variable shadowing" {
  for operator in ["=", "+="] {
    let rule = "id: assign\ndescription: Resolve each assignment target.\npatterns:\n  - shape: wrapper($(name:id), __TARGET__)\n    then:\n      patterns:\n        - shape: let mut $_ = $_; $(name:id) \{operator} 1"
    for prefix in ["", "let mut item = 0; "] {
      for (binding, expected) in [("other", 1), ("item", 0)] {
        let source = "fn sample { \{prefix}wrapper(item, { let mut \{binding} = 0; item \{operator} 1 }) }"
        assert_eq(
          apply_structural_rule_findings(source, rule).length(),
          expected,
        )
      }
    }
  }
}

///|
test "negative assignments cannot reject a capture shadowed by a local" {
  for operator in ["=", "+="] {
    let rule = "id: negative-assign\ndescription: Only reject assignments to the captured binding.\npatterns:\n  - shape: wrapper($(name:id), __TARGET__)\n    then:\n      patterns-not:\n        - shape: let mut $_ = $_; $(name:id) \{operator} 1"
    for prefix in ["", "let mut item = 0; "] {
      for (binding, expected) in [("other", 0), ("item", 1)] {
        let source = "fn sample { \{prefix}wrapper(item, { let mut \{binding} = 0; item \{operator} 1 }) }"
        assert_eq(
          apply_structural_rule_findings(source, rule).length(),
          expected,
        )
      }
    }
  }
}

///|
test "first captures from assignment targets retain their source in descendants" {
  for operator in ["=", "+="] {
    let rule = "id: assign-origin\ndescription: Inherit the assignment target binding.\npatterns:\n  - shape: $(name:id) \{operator} __TARGET__\n    then:\n      patterns:\n        - shape: middle(__TARGET__)\n          then:\n            patterns:\n              - shape: sink($(name:id))"
    for prefix in ["", "let mut item = 0; "] {
      for (binding, expected) in [("other", 1), ("item", 0)] {
        let source = "fn sample { \{prefix}item \{operator} middle({ let \{binding} = source(); sink(item) }) }"
        assert_eq(
          apply_structural_rule_findings(source, rule).length(),
          expected,
        )
      }
    }
  }
}

///|
test "field assignment names remain nonlexical in inherited and first captures" {
  for operator in ["=", "+="] {
    let inherited = "id: field-assign\ndescription: Field targets ignore local bindings.\npatterns:\n  - shape: wrapper($(name:id), __TARGET__)\n    then:\n      patterns:\n        - shape: let mut $_ = $_; $_.$(name:id) \{operator} 1"
    let source = "fn sample { wrapper(item, { let mut item = 0; object.item \{operator} 1 }) }"
    assert_eq(apply_structural_rule_findings(source, inherited).length(), 1)
    let first = "id: field-origin\ndescription: Field captures stay nonlexical.\npatterns:\n  - shape: $_.$(name:id) \{operator} __TARGET__\n    then:\n      patterns:\n        - shape: sink($(name:id))"
    let source = "fn sample { object.item \{operator} { let item = source(); sink(item) } }"
    assert_eq(apply_structural_rule_findings(source, first).length(), 1)
  }
}
