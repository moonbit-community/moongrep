///|
test "inherited identifiers stay shadowed across multi-statement targets" {
  let rule =
    #|id: continuation-scope
    #|description: Keep the ancestor binding across selected continuations.
    #|patterns:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: let $_ = $_; __TARGET__
    #|          then:
    #|            patterns:
    #|              - shape: sink($(name:id))
  for (binding, expected) in [("item", 0), ("other", 1)] {
    let source = "fn sample { wrapper(item, { let \{binding} = source(); skip(); sink(item) }) }"
    assert_eq(apply_structural_rule_findings(source, rule).length(), expected)
  }
}

///|
test "continuation scope applies to positive negative and guard-only reads" {
  let prefix = "id: scope\ndescription: Continuation scope.\npatterns:\n  - shape: wrapper($(name:id), __TARGET__)\n    then:\n      patterns:\n        - shape: let $_ = $_; __TARGET__\n          then:\n"
  let positive = prefix +
    "            patterns:\n              - shape: sink($(name:id))\n"
  let guard_only = prefix +
    "            patterns:\n              - shape: sink($_)\n                guard:\n                  $name: '^item$'\n"
  let negative = prefix +
    "            patterns-not:\n              - shape: sink($(name:id))\n"
  for binding in ["item", "other"] {
    for tail in ["", "; sink(item)", "; skip(); sink(item)"] {
      let source = "fn sample { wrapper(item, { let \{binding} = source()\{tail} }) }"
      let visible = binding == "other" && tail != ""
      assert_eq(
        apply_structural_rule_findings(source, positive).length(),
        if visible {
          1
        } else {
          0
        },
      )
      assert_eq(
        apply_structural_rule_findings(source, guard_only).length(),
        if visible {
          1
        } else {
          0
        },
      )
      assert_eq(
        apply_structural_rule_findings(source, negative).length(),
        if visible {
          0
        } else {
          1
        },
      )
    }
  }
}

///|
test "target entry scopes include parameters condition patterns and loop bindings" {
  let cases = [
    (
      "fn($_) { __TARGET__ }", "fn(item) { skip(); sink(item) }", "fn(other) { skip(); sink(item) }",
    ),
    (
      "if $_ { __TARGET__ }", "if input is Some(item) { skip(); sink(item) }", "if input is Some(other) { skip(); sink(item) }",
    ),
    (
      "while $_ { __TARGET__ }", "while input is Some(item) { skip(); sink(item) }",
      "while input is Some(other) { skip(); sink(item) }",
    ),
    (
      "for $_ in $_ { __TARGET__ }", "for item in input { skip(); sink(item) }",
      "for other in input { skip(); sink(item) }",
    ),
    (
      "for $_ = $_; $_; $_ = $_ { __TARGET__ }", "for item = 0; item < 3; item = item + 1 { skip(); sink(item) }",
      "for other = 0; other < 3; other = other + 1 { skip(); sink(item) }",
    ),
    (
      "match $_ { Some($_) => __TARGET__ }", "match input { Some(item) => { skip(); sink(item) } }",
      "match input { Some(other) => { skip(); sink(item) } }",
    ),
  ]
  for (shape, shadowed, visible) in cases {
    let rule = "id: scope\ndescription: Selected body scope.\npatterns:\n  - shape: wrapper($(name:id), __TARGET__)\n    then:\n      patterns:\n        - shape: \"\{shape}\"\n          then:\n            patterns:\n              - shape: sink($(name:id))\n"
    for (body, expected) in [(shadowed, 0), (visible, 1)] {
      assert_eq(
        apply_structural_rule_findings(
          "fn sample { wrapper(item, \{body}) }",
          rule,
        ).length(),
        expected,
      )
    }
  }
}

///|
test "local recursive bindings and guard continuations keep ancestor anchors" {
  let cases = [
    (
      "let mut $_ = $_; __TARGET__", "let mut item = source()", "let mut other = source()",
    ),
    ("fn $_() { $_ }; __TARGET__", "fn item() { () }", "fn other() { () }"),
    (
      "letrec $_ = fn($_) { $_ }; __TARGET__", "letrec item = fn(x) { x }", "letrec other = fn(x) { x }",
    ),
    (
      "guard $_ else { $_ }; __TARGET__", "guard input is Some(item) else { return }",
      "guard input is Some(other) else { return }",
    ),
  ]
  for (shape, shadowed, visible) in cases {
    let rule = "id: scope\ndescription: Selected continuation scope.\npatterns:\n  - shape: wrapper($(name:id), __TARGET__)\n    then:\n      patterns:\n        - shape: \"\{shape}\"\n          then:\n            patterns:\n              - shape: sink($(name:id))\n"
    for (header, expected) in [(shadowed, 0), (visible, 1)] {
      assert_eq(
        apply_structural_rule_findings(
          "fn sample { wrapper(item, { \{header}; skip(); sink(item) }) }",
          rule,
        ).length(),
        expected,
      )
    }
  }
}

///|
test "new captures start at the target and sibling scopes remain independent" {
  let rule =
    #|id: sibling
    #|description: Retain original anchors through sibling scopes.
    #|patterns:
    #|  - shape: let $(name:id) = source(); __TARGET__
    #|    then:
    #|      patterns:
    #|        - shape: __TARGET__
    #|          then:
    #|            patterns:
    #|              - shape: sink($(name:id))
  let source = "fn sample { let item = source(); { let item = other(); sink(item) }; sink(item) }"
  inspect(apply_structural_rule_findings(source, rule).length(), content="1")
  let shadowed = "fn sample { let item = source(); { let item = other(); sink(item) }; skip() }"
  inspect(apply_structural_rule_findings(shadowed, rule).length(), content="0")
}

///|
test "target provenance rolls back with ellipsis branches and then does not repartition" {
  let backtracking =
    #|id: rollback
    #|description: Commit the target with its successful atomic branch.
    #|patterns:
    #|  - shape: choose($$$_, __TARGET__, marker())
    #|    then:
    #|      patterns:
    #|        - shape: sink()
  inspect(
    apply_structural_rule_findings(
      "fn sample { choose(miss(), sink(), marker()) }", backtracking,
    ).length(),
    content="1",
  )
  let no_retry =
    #|id: no-retry
    #|description: Then failure does not retry the atomic split.
    #|patterns:
    #|  - shape: choose($$$_, __TARGET__, $$$rest)
    #|    then:
    #|      patterns:
    #|        - shape: sink()
  inspect(
    apply_structural_rule_findings(
      "fn sample { choose(miss(), sink()) }", no_retry,
    ).length(),
    content="0",
  )
}

///|
test "alternative captures do not share a failing environment" {
  let rule =
    #|id: environments
    #|description: The second capture environment succeeds at the same target.
    #|patterns:
    #|  - shape: pick($(name:id), $_, __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: sink($(name:id))
    #|  - shape: pick($_, $(name:id), __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: sink($(name:id))
  let hits = apply_structural_rule_findings(
    "fn sample { pick(a, b, sink(b)) }", rule,
  )
  inspect(hits.length(), content="1")
  inspect(hits[0].pattern_index, content="1")
}
