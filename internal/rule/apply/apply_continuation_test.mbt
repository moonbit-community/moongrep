///|
test "apply structural rule matches let pattern header with omitted body" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Tuple let header.
    #|patterns:
    #|  - shape: let ($_, $_) = $_
    #|
  let source =
    #|fn sample {
    #|  let (fst, snd) = tuple; consume(fst); snd
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
test "apply structural rule matches guard header with omitted body" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Guard header.
    #|patterns:
    #|  - shape: guard ready() else { fallback() }
    #|
  let source =
    #|fn sample {
    #|  guard ready() else { fallback() }
    #|  { continue_work(); finish_work() }
    #|}
    #|
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
  inspect(location_signature(hits[0].loc), content="2:3-3:37")
}

///|
test "apply reports ordinary let continuation without function braces" {
  let rule_source =
    #|id: example
    #|description: Let header.
    #|patterns:
    #|  - shape: let $(name:id) = source()
    #|
  let source =
    #|fn sample {
    #|  let value = source()
    #|  consume(value)
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(location_signature(hits[0].loc), content="2:3-3:17")
}

///|
test "inside expr continuation target matches a complete multi-statement sequence" {
  let rule_source =
    #|id: example
    #|description: Matching continuation sequence.
    #|inside-expr:
    #|  - shape: let $(name:id) = source(); __TARGET__
    #|patterns:
    #|  - shape: consume($(name:id)); finish($(name:id))
    #|
  let source =
    #|fn sample {
    #|  let item = source()
    #|  consume(item)
    #|  finish(item)
    #|}
    #|fn ignored {
    #|  let other = source()
    #|  consume(other)
    #|  finish(item)
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].pattern_index, 0)
  inspect(location_signature(hits[0].loc), content="2:3-4:15")
}

///|
test "inside expr continuation target matches inside a nested block" {
  let rule_source =
    #|id: example
    #|description: Matching a nested continuation sequence.
    #|inside-expr:
    #|  - shape: wrapper({ let $(name:id) = source(); __TARGET__ })
    #|patterns:
    #|  - shape: consume($(name:id)); finish($(name:id))
    #|
  let source =
    #|fn sample {
    #|  wrapper({
    #|    let item = source()
    #|    consume(item)
    #|    finish(item)
    #|  })
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].pattern_index, 0)
  inspect(location_signature(hits[0].loc), content="2:3-6:5")
}

///|
test "inside expr multi-statement continuation targets traverse expressions" {
  let cases = [
    (
      "let mut $(name:id) = source(); __TARGET__", "target($(name:id))", "fn sample {\n  let mut item = source()\n  skip()\n  target(item)\n}\n",
      "2:3-4:15",
    ),
    (
      "guard ready() else { fallback() }; __TARGET__", "target()", "fn sample {\n  guard ready() else { fallback() }\n  skip()\n  target()\n}\n",
      "2:3-4:11",
    ),
  ]
  for case in cases {
    let (inside_shape, pattern_shape, source, expected_loc) = case
    let rule_source =
      $|id: example
      $|description: Traversing a continuation target.
      $|inside-expr:
      $|  - shape: \{inside_shape}
      $|patterns:
      $|  - shape: \{pattern_shape}
      $|
    let hits = apply_structural_rule_findings(source, rule_source)
    assert_eq(hits.length(), 1)
    assert_eq(location_signature(hits[0].loc), expected_loc)
  }
}

///|
test "inside expr empty continuation target supports patterns-not only" {
  let rule_source =
    #|id: example
    #|description: Empty clean continuation.
    #|inside-expr:
    #|  - shape: let $(name:id) = source(); __TARGET__
    #|patterns-not:
    #|  - shape: danger($(name:id))
    #|
  let source =
    #|fn sample {
    #|  prepare()
    #|  let item = source()
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].pattern_index, 0)
  assert_eq(hits[0].loc.start.lnum, 3)
  assert_eq(hits[0].loc.start.column(), 3)
}

///|
test "inside expr single-statement continuation target preserves location" {
  let rule_source =
    #|id: example
    #|description: Single continuation expression.
    #|inside-expr:
    #|  - shape: let $(name:id) = source(); __TARGET__
    #|patterns:
    #|  - shape: target($(name:id))
    #|
  let source =
    #|fn sample {
    #|  let item = source()
    #|  target(item)
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].pattern_index, 0)
  inspect(location_signature(hits[0].loc), content="2:3-3:15")
}

///|
test "apply rejects header-only non-shortcut continuations" {
  let cases = [
    (
      "let mut value = source()", "fn sample { let mut value = source(); consume(value) }",
    ),
    (
      "letrec recur = fn(value) { value }", "fn sample { letrec recur = fn(value) { value }; recur(source()) }",
    ),
    ("defer cleanup()", "fn sample { defer cleanup(); continue_work() }"),
  ]
  for case in cases {
    let (shape, source) = case
    let rule_source =
      $|id: example
      $|description: Header only.
      $|patterns:
      $|  - shape: \{shape}
      $|
    assert_eq(apply_structural_rule_findings(source, rule_source).length(), 0)
  }
}

///|
test "apply accepts complete non-shortcut continuation shapes" {
  let cases = [
    "let mut value = source(); consume(value)", "letrec recur = fn(value) { value }; recur(source())",
    "defer cleanup(); continue_work()",
  ]
  for shape in cases {
    let rule_source =
      $|id: example
      $|description: Complete continuation.
      $|patterns:
      $|  - shape: \{shape}
      $|
    let source = "fn sample { \{shape} }"
    assert_eq(apply_structural_rule_findings(source, rule_source).length(), 1)
  }
}

///|
test "proof let matches only its header and leaves its continuation visible" {
  let proof_rule =
    #|id: example
    #|description: Proof header.
    #|patterns:
    #|  - shape: proof_let witness = fact()
    #|
  let continuation_rule =
    #|id: example
    #|description: Continuation.
    #|patterns:
    #|  - shape: finish(witness)
    #|
  let source =
    #|fn sample {
    #|  proof_let witness = fact()
    #|  finish(witness)
    #|}
    #|
  let proof_hits = apply_structural_rule_findings(source, proof_rule)
  assert_eq(proof_hits.length(), 1)
  inspect(location_signature(proof_hits[0].loc), content="2:3-2:29")
  let continuation_hits = apply_structural_rule_findings(
    source, continuation_rule,
  )
  assert_eq(continuation_hits.length(), 1)
  inspect(location_signature(continuation_hits[0].loc), content="3:3-3:18")
}

///|
test "apply broad expressions skip function body wrapper braces" {
  let ignore_rule =
    #|id: example
    #|description: Any expression.
    #|patterns:
    #|  - shape: $_
    #|
  let capture_rule =
    #|id: example
    #|description: Any captured expression.
    #|patterns:
    #|  - shape: $(root:exp)
    #|
  let source =
    #|fn sample {
    #|  f <| value
    #|}
    #|
  let ignore_hits = apply_structural_rule_findings(source, ignore_rule)
  let capture_hits = apply_structural_rule_findings(source, capture_rule)
  assert_eq(ignore_hits.length(), 1)
  assert_eq(capture_hits.length(), 1)
  inspect(location_signature(ignore_hits[0].loc), content="2:3-2:13")
  inspect(location_signature(capture_hits[0].loc), content="2:3-2:13")
}

///|
test "apply explicit block shapes do not match function body wrappers" {
  let rule_source =
    #|id: example
    #|description: Explicit block.
    #|patterns:
    #|  - shape: "{ a; b }"
    #|
  let source =
    #|fn wrapper { a; b }
    #|fn nested { { a; b } }
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(location_signature(hits[0].loc), content="2:13-2:21")
}

///|
test "negative block patterns distinguish wrappers from explicit blocks" {
  let rule_source =
    #|id: example
    #|description: Target outside an explicit blocked block.
    #|patterns:
    #|  - shape: target()
    #|patterns-not:
    #|  - shape: "{ target(); other() }"
    #|
  let source =
    #|fn wrapper { target(); other() }
    #|fn nested { { target(); other() } }
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(location_signature(hits[0].loc), content="1:14-1:22")
}

///|
test "inside toplevel target traversal skips function body wrapper blocks" {
  let rule_source =
    #|id: example
    #|description: Inner expression.
    #|inside-toplevel:
    #|  - shape: fn sample { __TARGET__ }
    #|patterns:
    #|  - shape: $(root:exp)
    #|
  let source =
    #|fn sample {
    #|  target()
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(location_signature(hits[0].loc), content="2:3-2:11")
}

///|
test "inside expr target traversal distinguishes lambda bodies from blocks" {
  let rule_source =
    #|id: example
    #|description: Explicit block in a lambda.
    #|inside-expr:
    #|  - shape: wrapper(fn() { __TARGET__ })
    #|patterns:
    #|  - shape: "{ target(); other() }"
    #|
  let source =
    #|fn sample {
    #|  wrapper(fn() { target(); other() });
    #|  wrapper(fn() { { target(); other() } })
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].loc.start.lnum, 3)
}

///|
test "inside expr negative patterns use lambda body candidates" {
  let rule_source =
    #|id: example
    #|description: Lambda without an explicit blocked block.
    #|inside-expr:
    #|  - shape: wrapper(fn() { __TARGET__ })
    #|patterns-not:
    #|  - shape: "{ target(); other() }"
    #|
  let source =
    #|fn sample {
    #|  wrapper(fn() { target(); other() });
    #|  wrapper(fn() { { target(); other() } })
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].loc.start.lnum, 2)
}
