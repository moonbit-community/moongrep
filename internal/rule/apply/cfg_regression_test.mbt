///|
fn cfg_rule() -> String {
  let rule =
    #|id: cfg-regression
    #|description: CFG taint regressions.
    #|taint:
    #|  sources:
    #|    - shape: source()
    #|  sinks:
    #|    - shape: sink(__SOURCE__)
    #|  sanitizers:
    #|    - shape: sanitize(__SOURCE__)
  rule
}

///|
fn cfg_hits(body : String) -> Int32 raise {
  let rules = compile_rule_source(cfg_rule())
  let root = parse_root_node("fn sample(flag, index) {\n" + body + "\n}")
  let plan = @apply.ScanPlan::from_rules(rules)
  let result = @apply.apply_taint_scan_plan_to_node(
    "cfg.mbt",
    @cst.toplevel_nodes(root)[0],
    plan,
  )
  if !result.diagnostics.is_empty() {
    fail(
      "unexpected incomplete analysis: \{result.diagnostics.map(d => d.reason).join("; ")} for \{body}",
    )
  }
  result.findings.length()
}

///|
test "report nine missed examples and nine positive controls" {
  let examples = [
    (
      "let x = source(); let _ = flag && { sanitize(x); true }; sink(x)", "let x = source(); if flag { sanitize(x) }; sink(x)",
    ),
    (
      "let mut x = source(); x += \"suffix\"; sink(x)", "let mut x = source(); x = x + \"suffix\"; sink(x)",
    ),
    (
      "let xs = [\"clean\"]; xs[0] = source(); sink(xs[0])", "let xs = [source()]; sink(xs[0])",
    ),
    (
      "let r = { secret: source(), count: 0 }; let s = { ..r, count: 1 }; sink(s.secret)",
      "let r = { secret: source(), count: 0 }; sink(r.secret)",
    ),
    (
      "let r = source(); sink(r.secret)", "let r = source(); match r { { secret, .. } => sink(secret) }",
    ),
    (
      "let xs = source(); sink(xs[0])", "let xs = source(); match xs { [first, ..] => sink(first); _ => () }",
    ),
    (
      "for x = \"clean\", i = 0; i < 2; { sink(x); continue source(), i + 1 }", "for x = \"clean\", i = 0; i < 2; x = source(), i = i + 1 { sink(x) }",
    ),
    (
      "for x = source(), y = \"clean\", i = 0; i < 2; x = \"clean\", y = x, i = i + 1 { sink(y) }",
      "for x = source(), y = \"clean\", i = 0; i < 2; y = x, i = i + 1 { sink(y) }",
    ),
    (
      "let mut x = \"clean\"; defer sink(x)\nx = source()", "let x = source(); defer sink(x)\n()",
    ),
  ]
  let counts = examples.map(pair => (cfg_hits(pair.0), cfg_hits(pair.1)))
  debug_inspect(
    counts,
    content=(
      #|[
      #|  (1, 1),
      #|  (1, 1),
      #|  (1, 1),
      #|  (1, 1),
      #|  (1, 1),
      #|  (1, 1),
      #|  (1, 1),
      #|  (1, 1),
      #|  (1, 1),
      #|]
    ),
  )
}

///|
test "report clean negative examples" {
  let examples = [
    "let x = source(); sanitize(x); let _ = flag && true; sink(x)", "let mut x = source(); x = \"clean\"; x += \"suffix\"; sink(x)",
    "let xs = [source()]; xs[0] = \"clean\"; sink(xs[0])", "let r = { secret: source(), count: 0 }; let s = { ..r, secret: \"clean\" }; sink(s.secret)",
    "let r = source(); sanitize(r.secret); sink(r.secret)", "let xs = source(); sanitize(xs[0]); sink(xs[0])",
    "for x = \"clean\", i = 0; i < 2; { sink(x); continue \"clean\", i + 1 }", "for x = \"clean\", y = \"clean\", i = 0; i < 2; x = \"clean\", y = x, i = i + 1 { sink(y) }",
    "let mut x = source(); defer sink(x)\nx = \"clean\"",
  ]
  debug_inspect(examples.map(cfg_hits), content="[0, 0, 0, 0, 0, 0, 0, 0, 0]")
}

///|
test "short circuit preserves skipped side effects and exits" {
  let examples = [
    "let x = source(); let _ = flag || { sanitize(x); false }; sink(x)", "let x = source(); if flag && { sanitize(x); true } { () }; sink(x)",
    "let x = source(); let _ = flag && { return () }; sink(x)", "let x = source(); let _ = flag || { return () }; sink(x)",
    "let mut x = \"clean\"; let _ = flag && { x = source(); true }; sink(x)", "let mut x = \"clean\"; let _ = flag || { x = source(); false }; sink(x)",
  ]
  debug_inspect(examples.map(cfg_hits), content="[1, 1, 1, 1, 1, 1]")
}

///|
test "known and dynamic projections retain exact cleanup semantics" {
  let examples = [
    "let r = source(); sanitize(r.secret); sink(r.sibling)", "let r = source(); sanitize(r.secret); match r { { secret, .. } => sink(secret) }",
    "sink(source().secret)", "sink(source()[0])", "let xs = source(); sanitize(xs[0]); xs[index] = source(); sink(xs[0])",
    "let xs = source(); sanitize(xs[index]); sink(xs[0])", "let xs = [\"clean\", \"clean\"]; xs[index] = source(); sink(xs[0])",
    "let xs = [source(), \"clean\"]; xs[0] = \"clean\"; sink(xs[index])", "let xs = [source()]; xs[0] += \"suffix\"; sink(xs[0])",
    "let r = { secret: source() }; r.secret += \"suffix\"; sink(r.secret)",
  ]
  debug_inspect(
    examples.map(cfg_hits),
    content="[1, 0, 1, 1, 1, 1, 1, 0, 1, 1]",
  )
}

///|
test "loop updates and lexical environments follow the compiler" {
  let examples = [
    "let x = source(); for x = \"clean\", y = x; flag; { sink(y); break }", "for x = \"clean\"; flag; x = source() { sink(x); continue }",
    "for x = source(); flag; x = \"clean\" { continue } nobreak { sink(x) }", "let mut x = source(); for ;; { break } nobreak { sanitize(x) }; sink(x)",
    "let mut x = \"clean\"; while flag { x = source() }; sink(x)",
  ]
  debug_inspect(examples.map(cfg_hits), content="[1, 0, 1, 1, 1]")
}

///|
test "defers run in reverse order on exit and preserve pending snapshots" {
  let examples = [
    "let mut x = source(); defer sink(x)\ndefer sanitize(x)\n()", "let mut x = source(); defer sanitize(x)\ndefer sink(x)\n()",
    "let x = source(); defer sink(x)\nlet x = \"clean\"; ()", "let mut x = source(); let y = { defer sanitize(x)\nx }; sink(y)",
    "let mut x = \"clean\"; defer sink(x)\nx = source(); return ()", "let mut x = \"clean\"; while flag { defer sink(x)\nx = source(); break }",
    "let mut x = \"clean\"; while flag { defer sink(x)\nx = source(); continue }",
    "let x = source(); errdefer sink(x)\n()", "let x = source(); errdefer sink(x)\nreturn ()",
    "let x = source(); errdefer sink(x)\nraise \"error\"",
  ]
  debug_inspect(
    examples.map(cfg_hits),
    content="[0, 1, 1, 1, 1, 1, 1, 0, 0, 1]",
  )
}

///|
test "cleanup exceptions replace pending errors and try bang aborts" {
  let examples = [
    "try { defer { raise source() }\nraise \"clean\" } catch { err => sink(err) }",
    "try { defer { raise \"clean\" }\nraise source() } catch { err => sink(err) }",
    "let mut x = \"clean\"; try { defer sink(x)\ndefer { x = source(); raise \"error\" }\n() } catch { _ => () }",
    "try { try! { raise source() } } catch { err => sink(err) }", "let mut x = \"clean\"; match flag { true if { x = source(); flag } => (); _ => sink(x) }",
  ]
  debug_inspect(examples.map(cfg_hits), content="[1, 0, 1, 0, 1]")
}

///|
test "equivalent literal indexes share precise storage" {
  let examples = [
    "let xs = [source()]; xs[0x0] = \"clean\"; sink(xs[0])", "let xs = [\"clean\"]; xs[0b0] = source(); sink(xs[0])",
    "let xs = source(); sanitize(xs[0o0]); sink(xs[0])", "sink(source() && flag)",
    "sink(flag || source())",
  ]
  debug_inspect(examples.map(cfg_hits), content="[0, 1, 0, 1, 1]")
}

///|
test "exhaustive catches do not activate outer error-only cleanups" {
  let examples = [
    "errdefer sink(source())\ntry { raise \"clean\" } catch { _ => () }", "errdefer sink(source())\ntry { raise \"clean\" } catch { error => ignore(error) }",
    "errdefer sink(source())\ntry { raise \"clean\" } catch { _ if flag => () }",
  ]
  debug_inspect(examples.map(cfg_hits), content="[0, 0, 1]")
}

///|
test "predicate results carry explicit data dependencies without control taint" {
  let examples = [
    "sink(source() is Some(_))", "let value = source() is Some(_); sink(value)",
    "let value = if source() is Some(_) { \"clean\" } else { \"clean\" }; sink(value)",
    "sink(\"clean\" is Some(_))",
  ]
  debug_inspect(examples.map(cfg_hits), content="[1, 1, 0, 0]")
}

///|
test "diagnostics merge affected rules and preserve complete rule results" {
  let rule = cfg_rule()
  let first = compile_rule_source(rule)
  let second = compile_rule_source(
    rule.replace_all(old="cfg-regression", new="second"),
  )
  let third = compile_rule_source(
    rule
    .replace_all(old="cfg-regression", new="third")
    .replace_all(old="source()", new="safe()"),
  )
  let rules = first.copy()
  for rule in second {
    rules.push(rule)
  }
  for rule in third {
    rules.push(rule)
  }
  let plan = @apply.ScanPlan::from_rules(rules)
  let source = "fn sample(flag) { sink(source()); sink(safe()); let mut value = { secret: source() }; while flag { value = { next: value } }; sink(value) }"
  let node = @cst.toplevel_nodes(parse_root_node(source))[0]
  let result = @apply.apply_taint_scan_plan_to_node("sample.mbt", node, plan)
  assert_eq(result.diagnostics.length(), 1)
  debug_inspect(
    result.diagnostics[0].rule_ids,
    content="[\"cfg-regression\", \"second\"]",
  )
  debug_inspect(
    result.findings.map(finding => finding.rule_id),
    content="[\"third\"]",
  )
  let unsupported = @cst.toplevel_nodes(
      parse_root_node("fn sample { sink(source()); [for x in xs => x] }"),
    )[0]
  let skipped = @apply.apply_taint_scan_plan_to_node(
    "sample.mbt", unsupported, plan,
  )
  assert_eq(skipped.diagnostics.length(), 1)
  debug_inspect(
    skipped.diagnostics[0].rule_ids,
    content="[\"cfg-regression\", \"second\", \"third\"]",
  )
  assert_eq(skipped.findings.length(), 0)
}

///|
test "exit arguments are saved before cleanup and error-only cleanup skips loop control" {
  let examples = [
    "let mut z = \"clean\"; for x = \"clean\", i = 0; i < 2; { sink(x); defer sanitize(z)\nz = source(); continue z, i + 1 }",
    "let mut z = source(); let y = for ;; { defer sanitize(z)\nbreak z }; sink(y); sink(z)",
    "let mut z = source(); try { defer sanitize(z)\nraise z } catch { error => sink(error) }; sink(z)",
    "while flag { errdefer sink(source())\nbreak }", "while flag { errdefer sink(source())\ncontinue }",
    "defer sink(source())\ntry! { raise \"clean\" }",
  ]
  debug_inspect(examples.map(cfg_hits), content="[1, 1, 1, 0, 0, 0]")
}
