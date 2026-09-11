///|
test "apply then and inner guards filter inherited bindings" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Guarded wrapper.
    #|patterns:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: call($(name:id))
    #|          guard:
    #|            $name: "^safe_.*ok$"
  let source =
    #|fn sample {
    #|  wrapper(safe_ok, call(safe_ok));
    #|  wrapper(unsafe_ok, call(unsafe_ok));
    #|  wrapper(safe_bad, call(safe_bad))
    #|}
    #|
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
}

///|
test "apply then guard filters outer context matches" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Guarded outer wrapper.
    #|patterns:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|    guard:
    #|      $name: "^safe_"
    #|    then:
    #|      patterns:
    #|        - shape: call()
  let source =
    #|fn sample {
    #|  wrapper(safe_ok, call());
    #|  wrapper(unsafe_ok, call());
    #|  wrapper(safe_bad, other())
    #|}
    #|
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
}

///|
test "apply structural rule matches guards then" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Guarded wrapper.
    #|patterns:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: call($(name:id), $(value:const))
    #|          guard:
    #|            $name: "^safe_.*ok$"
    #|            $value: "^(42|true)$"
  let source =
    #|fn sample {
    #|  wrapper(safe_ok, call(safe_ok, 42));
    #|  wrapper(unsafe_ok, call(unsafe_ok, 42));
    #|  wrapper(safe_bad, call(safe_bad, 42));
    #|  wrapper(safe_ok, call(safe_ok, false))
    #|}
    #|
  let rules = compile_rule_source(rule_source)
  let impls = parse_root_node(source)
  let hits = apply_structural_test_rules("sample.mbt", impls, rules)
  assert_eq(hits.length(), 1)
}

///|
test "then reports the outer context location" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Nested target call.
    #|patterns:
    #|  - shape: wrapper(__TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: target(secret)
  let source =
    #|fn sample {
    #|  wrapper(holder(target(secret)))
    #|}
    #|
  let rules = compile_rule_source(rule_source)
  let impls = parse_root_node(source)
  let hits = apply_structural_test_rules("sample.mbt", impls, rules)
  assert_eq(hits.length(), 1)
  inspect(location_signature(hits[0].loc), content="2:3-2:34")
}

///|
test "then merges inner hits and keeps the root pattern index" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped calls.
    #|patterns:
    #|  - shape: wrapper(__TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: second()
    #|        - shape: first()
  let source =
    #|fn sample {
    #|  wrapper({
    #|    first();
    #|    second()
    #|  })
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].pattern_index, 0)
  inspect(finding_signature(hits[0]), content="sample.mbt|example|0|2:3-5:5")
}

///|
test "then positive root ignores descendant patterns-not" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped holder positive wins before descendant negative.
    #|patterns:
    #|  - shape: wrapper(__TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: holder($(value:exp))
    #|      patterns-not:
    #|        - shape: danger()
  let source =
    #|fn sample {
    #|  wrapper(holder(danger()))
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(finding_signature(hits[0]), content="sample.mbt|example|0|2:3-2:28")
}

///|
test "then positive root wins over same-root patterns-not" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target roots match before negative patterns run.
    #|patterns:
    #|  - shape: wrapper(__TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: target($(value:exp))
    #|      patterns-not:
    #|        - shape: target(blocked)
  let source =
    #|fn sample {
    #|  wrapper(target(allowed));
    #|  wrapper(target(blocked))
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 2)
  inspect(finding_signature(hits[0]), content="sample.mbt|example|0|2:3-2:27")
  inspect(finding_signature(hits[1]), content="sample.mbt|example|0|3:3-3:27")
}

///|
test "then patterns-not rejects outer on uncovered negative" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped targets outside blocked branches.
    #|patterns:
    #|  - shape: wrapper(__TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: target()
    #|      patterns-not:
    #|        - shape: blocker($(value:exp))
  let source =
    #|fn sample {
    #|  wrapper({
    #|    blocker(target());
    #|    target()
    #|  });
    #|  wrapper({
    #|    target();
    #|    blocker(target())
    #|  });
    #|  wrapper(blocker(target()));
    #|  wrapper(target())
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(finding_signature(hits[0]), content="sample.mbt|example|0|11:3-11:20")
}

///|
test "then positive array access wins over patterns-not identifier" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped array access.
    #|patterns:
    #|  - shape: wrapper(__TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: $(array:exp)[$(index:exp)]
    #|      patterns-not:
    #|        - shape: $(counter:id)
  let source =
    #|fn sample {
    #|  wrapper(arr[i])
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(finding_signature(hits[0]), content="sample.mbt|example|0|2:3-2:18")
}

///|
test "then rejects only uncovered negative and accepts covered array access" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Covered array index use.
    #|patterns:
    #|  - shape: wrapper($(counter:id), __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: arr[$(counter:id)]
    #|      patterns-not:
    #|        - shape: $(counter:id)
  let source =
    #|fn sample {
    #|  wrapper(i, arr[i])
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(finding_signature(hits[0]), content="sample.mbt|example|0|2:3-2:21")
}

///|
test "then rejects uncovered inherited id outside positive coverage" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Uncovered index use rejects the wrapper.
    #|patterns:
    #|  - shape: wrapper($(counter:id), __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: arr[$(counter:id)]
    #|      patterns-not:
    #|        - shape: $(counter:id)
  let source =
    #|fn sample {
    #|  wrapper(i, {
    #|    arr[i];
    #|    println(i)
    #|  })
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 0)
}

///|
test "then merges multiple covered positive hits" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Multiple covered index uses.
    #|patterns:
    #|  - shape: wrapper($(counter:id), __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: arr[$(counter:id)]
    #|      patterns-not:
    #|        - shape: $(counter:id)
  let source =
    #|fn sample {
    #|  wrapper(i, {
    #|    arr[i];
    #|    arr[i]
    #|  })
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(finding_signature(hits[0]), content="sample.mbt|example|0|2:3-5:5")
}

///|
test "then reject-uncovered-negative respects shadowed inherited identifiers" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Shadowed index use belongs to inner binding.
    #|patterns:
    #|  - shape: wrapper($(counter:id), __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: arr[$(counter:id)]
    #|      patterns-not:
    #|        - shape: $(counter:id)
  let source =
    #|fn sample {
    #|  wrapper(i, {
    #|    arr[i];
    #|    let i = other;
    #|    println(i)
    #|  })
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(finding_signature(hits[0]), content="sample.mbt|example|0|2:3-6:5")
}

///|
test "then accepts only loop counter uses covered by array access" {
  let rule_source =
    #|id: example
    #|description: |
    #|  C-style forward array iteration.
    #|patterns:
    #|  - shape: |
    #|      for $(counter:id) = 0; $(counter:id) < $(arr:id).length(); $(counter:id) = $(counter:id) + 1 {
    #|        __TARGET__
    #|      }
    #|    then:
    #|      patterns:
    #|        - shape: |
    #|            $(arr:id)[$(counter:id)]
    #|      patterns-not:
    #|        - shape: $(counter:id)
  let source =
    #|fn sample(arr) {
    #|  for i = 0; i < arr.length(); i = i + 1 {
    #|    wrapper(arr[i])
    #|  }
    #|  for i = 0; i < arr.length(); i = i + 1 {
    #|    arr[i];
    #|    println(i)
    #|  }
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].loc.start.lnum, 2)
}

///|
test "then with only patterns-not reports outer when target subtree is clean" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target without danger.
    #|patterns:
    #|  - shape: wrapper(__TARGET__)
    #|    then:
    #|      patterns-not:
    #|        - shape: danger()
  let source =
    #|fn sample {
    #|  wrapper(safe());
    #|  wrapper(danger());
    #|  wrapper(holder(danger()))
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(finding_signature(hits[0]), content="sample.mbt|example|0|2:3-2:18")
}

///|
test "then only patterns-not respects shadowed inherited identifiers" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target without same-name target call.
    #|patterns:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|    then:
    #|      patterns-not:
    #|        - shape: target($(name:id))
  let source =
    #|fn sample {
    #|  wrapper(x, {
    #|    let x = other;
    #|    target(x)
    #|  });
    #|  wrapper(x, target(x))
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].loc.start.lnum, 2)
}

///|
test "then condition binders shadow inherited identifiers" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target call.
    #|patterns:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: target($(name:id))
  let source =
    #|fn sample {
    #|  wrapper(x, if maybe is Some(x) { target(x) } else { fallback });
    #|  wrapper(x, if maybe is Some(x) && ready { target(x) } else { fallback });
    #|  wrapper(x, if maybe is Some(x) && target(x) { fallback } else { fallback });
    #|  wrapper(x, {
    #|    guard maybe is Some(x) else { fallback }
    #|    target(x)
    #|  });
    #|  wrapper(x, match value { _ if maybe is Some(x) => target(x) });
    #|  wrapper(x, while maybe is Some(x) { target(x) });
    #|  wrapper(x, for i = 0; maybe is Some(x); i = target(x) { target(x) });
    #|  wrapper(x, [for i = 0; maybe is Some(x); i = i + 1 => target(x)]);
    #|  wrapper(x, [for i = 0; i < 1; i = i + 1 if maybe is Some(x) => target(x)]);
    #|  wrapper(x, if ready { target(x) } else { fallback });
    #|  wrapper(x, if maybe is Some(y) { target(x) } else { fallback })
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 2)
  assert_eq(hits[0].loc.start.lnum, 14)
  assert_eq(hits[1].loc.start.lnum, 15)
}

///|
test "then patterns-not ignores condition-shadowed inherited identifiers" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target without same-name target call.
    #|patterns:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|    then:
    #|      patterns-not:
    #|        - shape: target($(name:id))
  let source =
    #|fn sample {
    #|  wrapper(x, if maybe is Some(x) { target(x) } else { fallback });
    #|  wrapper(x, if maybe is Some(x) && target(x) { fallback } else { fallback });
    #|  wrapper(x, {
    #|    guard maybe is Some(x) else { fallback }
    #|    target(x)
    #|  });
    #|  wrapper(x, match value { _ if maybe is Some(x) => target(x) });
    #|  wrapper(x, while maybe is Some(x) { target(x) });
    #|  wrapper(x, for i = 0; maybe is Some(x); i = i + 1 { target(x) });
    #|  wrapper(x, [for i = 0; maybe is Some(x); i = i + 1 => target(x)]);
    #|  wrapper(x, [for i = 0; i < 1; i = i + 1 if maybe is Some(x) => target(x)]);
    #|  wrapper(x, if ready { target(x) } else { fallback });
    #|  wrapper(x, if maybe is Some(y) { target(x) } else { fallback })
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 8)
}

///|
test "then preserves source order of outer locations" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target call.
    #|patterns:
    #|  - shape: wrapper(__TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: target()
  let source =
    #|fn sample {
    #|  wrapper(holder(target()));
    #|  wrapper(holder(other()));
    #|  wrapper(holder(target()))
    #|}
    #|
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 2)
  assert_eq(hits[0].pattern_index, 0)
  assert_eq(hits[1].pattern_index, 0)
  assert_true(hits[0].loc.start.lnum < hits[1].loc.start.lnum)
  assert_eq(hits[0].loc.start.column(), 3)
  assert_eq(hits[1].loc.start.column(), 3)
}

///|
test "apply structural rule supports then inherited bindings" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target call.
    #|patterns:
    #|  - shape: wrapper($(prefix:exp), __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: target.call($(prefix:exp))
  let source =
    #|fn sample {
    #|  wrapper(make(), target.call(make()));
    #|  wrapper(make(), target.call(other))
    #|}
    #|
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
}

///|
test "apply then inherits ellipsis sequence bindings" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Reuse an outer argument prefix inside the target.
    #|patterns:
    #|  - shape: wrapper($$$args, __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: target($$$args)
  let source =
    #|fn sample {
    #|  wrapper(a, b, target(a, b));
    #|  wrapper(a, b, target(a, other))
    #|}
    #|
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
}

///|
test "then plain names do not reference inherited bindings" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Plain names remain literal.
    #|patterns:
    #|  - shape: wrapper($(prefix:exp), __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: target.call(prefix)
  let source =
    #|fn sample {
    #|  wrapper(token, target.call(token))
    #|}
    #|
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 0)
}

///|
test "apply structural rule inherits then identifier bindings" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target call.
    #|patterns:
    #|  - shape: wrapper($(prefix:id), __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: target.call($(prefix:id))
  let source =
    #|fn sample {
    #|  wrapper(token, target.call(token));
    #|  wrapper(token, target.call(other))
    #|}
    #|
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
}

///|
test "then inherited id is blocked after lexical let shadow" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target call.
    #|patterns:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: target($(name:id))
  let source =
    #|fn sample {
    #|  wrapper(x, {
    #|    let x = y;
    #|    target(x)
    #|  })
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 0)
}

///|
test "then inherited id still matches without shadow" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target call.
    #|patterns:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: target($(name:id))
  let source =
    #|fn sample {
    #|  wrapper(x, target(x))
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
}

///|
test "then later shadow does not block earlier candidate" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target call.
    #|patterns:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: target($(name:id))
  let source =
    #|fn sample {
    #|  wrapper(x, {
    #|    target(x);
    #|    let x = y;
    #|    done
    #|  })
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
}

///|
test "then only blocks patterns referencing shadowed outer id" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target call.
    #|patterns:
    #|  - shape: wrapper($(left:id), $(right:id), __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: target($(right:id))
    #|        - shape: target($(left:id))
  let source =
    #|fn sample {
    #|  wrapper(x, y, {
    #|    let x = other;
    #|    target(y);
    #|    target(x)
    #|  })
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].pattern_index, 0)
}

///|
test "then traverses guard target children" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Guard target call.
    #|patterns:
    #|  - shape: wrapper(__TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: target()
  let source =
    #|fn sample {
    #|  wrapper({
    #|    guard ready() else { fallback() }
    #|    target()
    #|  })
    #|}
    #|
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
}

///|
test "then traverses reverse pipe target children" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Reverse pipe target call.
    #|patterns:
    #|  - shape: wrapper(__TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: target()
  let source =
    #|fn sample {
    #|  wrapper(sink <| target())
    #|}
    #|
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
}

///|
test "then traverses list comprehension target children" {
  let rule_source =
    #|id: example
    #|description: |
    #|  List comprehension target call.
    #|patterns:
    #|  - shape: wrapper(__TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: target(item)
  let source =
    #|fn sample {
    #|  wrapper([for item in items if allow(item) => target(item)])
    #|}
    #|
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
}

///|
test "default structural matcher carries inside target bindings" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target using same expression.
    #|patterns:
    #|  - shape: wrapper($(prefix:exp), __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: target($(prefix:exp))
  let source =
    #|fn sample {
    #|  wrapper(if ready { a } else { b }, target(if ready { a } else { b }));
    #|  wrapper(if ready { a } else { b }, target(if ready { a } else { c }))
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
}

///|
test "default structural matcher respects shadowed inherited identifiers" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target call.
    #|patterns:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: target($(name:id))
  let source =
    #|fn sample {
    #|  wrapper(x, {
    #|    let x = y;
    #|    target(x)
    #|  });
    #|  wrapper(x, target(x))
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
}

///|
test "then tries multiple outer shapes in yaml order" {
  let rule_source =
    #|id: example
    #|description: Multiple expression contexts.
    #|patterns:
    #|  - shape: wrapper(__TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: target()
    #|  - shape: container(__TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: target()
  let source =
    #|fn sample {
    #|  wrapper(target());
    #|  container(target())
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 2)
  assert_eq(hits[0].loc.start.lnum, 2)
  assert_eq(hits[1].loc.start.lnum, 3)
}

///|
test "then selects the first overlapping outer alternative" {
  let rule_source =
    #|id: example
    #|description: Ordered overlapping contexts.
    #|patterns:
    #|  - shape: wrapper($(name:id), $_, __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: target($(name:id))
    #|  - shape: wrapper($_, $(name:id), __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: target($(name:id))
  let source =
    #|fn sample {
    #|  wrapper(first, second, target(first));
    #|  wrapper(first, second, target(second))
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 2)
  assert_eq(hits[0].loc.start.lnum, 2)
}

///|
test "then falls through when an earlier outer guard fails" {
  let rule_source =
    #|id: example
    #|description: Guarded ordered contexts.
    #|patterns:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|    guard:
    #|      $name: "^primary$"
    #|    then:
    #|      patterns:
    #|        - shape: target($(name:id))
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|    guard:
    #|      $name: "^fallback$"
    #|    then:
    #|      patterns:
    #|        - shape: target($(name:id))
  let source =
    #|fn sample {
    #|  wrapper(fallback, target(fallback))
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].loc.start.lnum, 2)
}

///|
test "then tries later alternatives after inner matching fails" {
  let rule_source =
    #|id: example
    #|description: Fallback after a failed child group.
    #|patterns:
    #|  - shape: wrapper($(name:id), $_, __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: target($(name:id))
    #|  - shape: wrapper($_, $(name:id), __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: target($(name:id))
  let source =
    #|fn sample {
    #|  wrapper(first, second, target(second))
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].pattern_index, 1)
}

///|
test "then alternatives support patterns-not only" {
  let rule_source =
    #|id: example
    #|description: Clean ordered contexts.
    #|patterns:
    #|  - shape: wrapper(__TARGET__)
    #|    then:
    #|      patterns-not:
    #|        - shape: danger()
    #|  - shape: container(__TARGET__)
    #|    then:
    #|      patterns-not:
    #|        - shape: danger()
  let source =
    #|fn sample {
    #|  wrapper(safe());
    #|  container(safe());
    #|  wrapper(danger());
    #|  container(holder(danger()))
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 2)
  assert_eq(hits[0].loc.start.lnum, 2)
  assert_eq(hits[1].loc.start.lnum, 3)
}

///|
test "then alternatives preserve outer locations and root pattern indexes" {
  let rule_source =
    #|id: example
    #|description: Ordered context metadata.
    #|patterns:
    #|  - shape: wrapper(__TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: first()
    #|        - shape: second()
    #|  - shape: container(__TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: first()
    #|        - shape: second()
  let source =
    #|fn sample {
    #|  container(holder(second()))
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].pattern_index, 1)
  assert_eq(hits[0].loc.start.lnum, 2)
  assert_eq(hits[0].loc.start.column(), 3)
}
