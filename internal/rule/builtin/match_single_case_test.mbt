///|
test "builtin match_single_case covers constructor and explicit unit fallback forms" {
  let rules = @builtin.load_rules().filter(rule => {
    rule.rule_id == "moonbitlang/match_single_case"
  })
  let plan = @apply.ScanPlan::from_rules(@compile.compile_rules(rules))
  let cases = [
    ("nullary unit", "match x { Ready => work(); _ => () }"),
    ("positional unit", "match x { Some(v) => work(v); _ => () }"),
    ("open unit", "match x { Payload(..) => work(); _ => () }"),
    ("nullary block unit", "match x { Ready => work(); _ => { () } }"),
    ("positional block unit", "match x { Some(v) => work(v); _ => { () } }"),
    ("open block unit", "match x { Payload(..) => work(); _ => { () } }"),
    ("qualified nullary", "match x { @events.Event::Ready => work(); _ => () }"),
    (
      "qualified payload", "match x { @events.Event::Payload(v, _) => work(v); _ => () }",
    ),
    ("nested pattern", "match x { Some((Ok(v), [1, ..])) => work(v); _ => () }"),
    (
      "labelled patterns", "match x { Payload(value=Some(v), tag~) => work(v, tag); _ => () }",
    ),
    (
      "open labelled pattern", "match x { Payload(value=Some(v), ..) => work(v); _ => () }",
    ),
    (
      "scrutinee and block body", "match next_event() { Some(v) => { prepare(v); work(v) }; _ => () }",
    ),
    ("expression position", "ignore(match x { Some(v) => work(v); _ => () })"),
    ("return", "match x { Some(v) => return work(v); _ => () }"),
    ("continue", "while ready() { match x { Some(_) => continue; _ => () } }"),
    ("break", "while ready() { match x { Some(_) => break; _ => () } }"),
  ]
  let matches : Array[String] = []
  for (name, expression) in cases {
    let source = "fn sample { \{expression} }"
    let parsed = @untyped_cst.parse_structure(source, name~)
    assert_true(parsed.diagnostics_view().is_empty(), msg=name)
    let findings = @apply.apply_structural_scan_plan_to_node(
      "sample.mbt",
      parsed.root(),
      plan.filter_source(source[:]),
    )
    assert_eq(findings.length(), 1, msg=name)
    matches.push("\{name}:\{findings[0].pattern_index}")
  }
  debug_inspect(
    matches,
    content=(
      #|[
      #|  "nullary unit:0",
      #|  "positional unit:1",
      #|  "open unit:2",
      #|  "nullary block unit:3",
      #|  "positional block unit:4",
      #|  "open block unit:5",
      #|  "qualified nullary:0",
      #|  "qualified payload:1",
      #|  "nested pattern:1",
      #|  "labelled patterns:1",
      #|  "open labelled pattern:2",
      #|  "scrutinee and block body:1",
      #|  "expression position:1",
      #|  "return:1",
      #|  "continue:1",
      #|  "break:1",
      #|]
    ),
  )
}

///|
test "builtin match_single_case excludes guarded nonunit and nonconstructor cases" {
  let rules = @builtin.load_rules().filter(rule => {
    rule.rule_id == "moonbitlang/match_single_case"
  })
  let plan = @apply.ScanPlan::from_rules(@compile.compile_rules(rules))
  let cases = [
    ("nullary empty map", "match x { Ready => work(); _ => {} }"),
    ("positional empty map", "match x { Some(v) => work(v); _ => {} }"),
    ("open empty map", "match x { Payload(..) => work(); _ => {} }"),
    ("map result", "match x { Some(v) => { 0: v }; _ => {} }"),
    (
      "guarded constructor", "match x { Some(v) if valid(v) => work(v); _ => () }",
    ),
    ("guarded wildcard", "match x { Some(v) => work(v); _ if ready() => () }"),
    (
      "fallback side effect", "match x { Some(v) => work(v); _ => { log(); () } }",
    ),
    (
      "fallback call returning unit", "match x { Some(v) => work(v); _ => fallback() }",
    ),
    ("fallback return", "match x { Some(v) => work(v); _ => return }"),
    (
      "fallback defer", "match x { Some(v) => work(v); _ => { defer cleanup(); () } }",
    ),
    (
      "three branches", "match x { Some(0) => first(); Some(v) => work(v); _ => () }",
    ),
    ("reversed arms", "match x { _ => (); Some(v) => work(v) }"),
    ("explicit None", "match x { Some(v) => work(v); None => () }"),
    ("or pattern", "match x { First(v) | Second(v) => work(v); _ => () }"),
    ("alias pattern", "match x { Some(v) as whole => work(whole); _ => () }"),
    ("literal pattern", "match x { 0 => work(); _ => () }"),
    ("variable pattern", "match x { v => work(v); _ => () }"),
    ("wildcard pattern", "match x { _ => work(); _ => () }"),
    ("array pattern", "match x { [v, ..] => work(v); _ => () }"),
    ("existing if is", "if x is Some(v) { work(v) }"),
  ]
  for (name, expression) in cases {
    let source = "fn sample { \{expression} }"
    let parsed = @untyped_cst.parse_structure(source, name~)
    assert_true(parsed.diagnostics_view().is_empty(), msg=name)
    let findings = @apply.apply_structural_scan_plan_to_node(
      "sample.mbt",
      parsed.root(),
      plan.filter_source(source[:]),
    )
    assert_eq(findings.length(), 0, msg=name)
  }
}
