///|
test "builtin boolean and early exit rules respect binding and control flow" {
  let plan = @apply.ScanPlan::from_rules(
    @compile.compile_rules(@builtin.load_rules()),
  )
  let cases = [
    ("boolean_if", "if ready && enabled { true } else { false }", 1),
    ("boolean_if", "if items.length() > 0 { false } else { true }", 1),
    ("boolean_if", "if x is Some(v) && v > 0 { true } else { false }", 0),
    ("boolean_if", "if s =~ (re\"a\" as v) { true } else { false }", 0),
    ("boolean_if", "if ready { work(); true } else { false }", 0),
    ("boolean_match", "match x { Some(_) => true; _ => false }", 1),
    ("boolean_match", "match x { @pkg.Event::Ready => false; _ => true }", 1),
    ("boolean_match", "match x { 0 => true; _ => false }", 1),
    ("boolean_match", "match x { Some(v) => true; _ => false }", 0),
    ("boolean_match", "match x { Some(_) if ready => true; _ => false }", 0),
    (
      "match_option_early_exit", "let x = match opt { Some(v) => v; None => return }; use(x)",
      1,
    ),
    (
      "match_option_early_exit", "let x = match opt { None => raise Missing; Some(v) => v }; use(x)",
      1,
    ),
    (
      "match_option_early_exit", "while ready { let x = match opt { Some(v) => v; _ => continue }; use(x) }",
      1,
    ),
    (
      "match_option_early_exit", "let x = match opt { Some(v) => v; None => 0 }; use(x)",
      0,
    ),
    (
      "match_option_early_exit", "let x = match opt { Some(v) => v; None => if ready { return 0 } else { 0 } }; use(x)",
      0,
    ),
    (
      "match_option_early_exit", "let x = match opt { Some(v) => v; None => fn() { return 0 } }; use(x)",
      0,
    ),
  ]
  for (rule, expression, expected) in cases {
    let source = "fn sample { \{expression} }"
    let parsed = @untyped_cst.parse_structure(source, name=rule)
    assert_true(parsed.diagnostics_view().is_empty(), msg=expression)
    let findings = @apply.apply_structural_scan_plan_to_node(
      "sample.mbt",
      parsed.root(),
      plan.filter_source(source[:]),
    )
    assert_eq(
      findings
      .filter(finding => finding.rule_id == "moonbitlang/\{rule}")
      .length(),
      expected,
      msg=expression,
    )
  }
}
