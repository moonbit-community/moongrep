///|
fn compile_scan_plan_rules(
  sources : Array[String],
) -> Array[CompiledRule] raise {
  let raw_rules : Array[@model.RawRuleSpec] = []
  for index in 0..<sources.length() {
    raw_rules.push(
      @model.RawRuleSpec::from_str(
        "/tmp/rules/r\{index}.yaml",
        "/tmp/rules",
        sources[index],
      ),
    )
  }
  @compile.compile_rules(raw_rules)
}

///|
fn parse_scan_plan_root(source : String) -> @untyped_ast.Node raise {
  let (impls, reports) = @parser.parse_string(source, name="scan plan test")
  guard reports is [] else { fail("expected source to parse") }
  @untyped_ast.from_impls(impls)
}

///|
fn parse_scan_plan_single_node(source : String) -> @untyped_ast.Node raise {
  let (impls, reports) = @parser.parse_string(source, name="scan plan test")
  guard reports is [] else { fail("expected source to parse") }
  let nodes = impls.to_array()
  guard nodes is [node] else { fail("expected exactly one impl") }
  @untyped_ast.from_impl(node)
}

///|
fn scan_plan_location_signature(loc : @basic.Location) -> String {
  "\{loc.start.lnum}:\{loc.start.column()}-\{loc.end.lnum}:\{loc.end.column()}"
}

///|
fn scan_plan_finding_signature(finding : RuleFinding) -> String {
  "\{finding.file}|\{finding.rule_id}|\{finding.pattern_index}|\{scan_plan_location_signature(finding.loc)}"
}

///|
fn scan_plan_finding_signatures(findings : Array[RuleFinding]) -> Array[String] {
  let signatures : Array[String] = []
  for finding in findings {
    signatures.push(scan_plan_finding_signature(finding))
  }
  signatures
}

///|
fn scan_plan_rule_ids(plan : ScanPlan) -> Array[String] {
  let ids : Array[String] = []
  for entry in plan.structural_entries {
    ids.push("S:\{entry.rule.rule_id}")
  }
  for entry in plan.taint_entries {
    ids.push("T:\{entry.rule.rule_id}")
  }
  ids
}

///|
fn prefilter_rule_ids(
  rules : Array[CompiledRule],
  source : String,
) -> Array[String] {
  let ids : Array[String] = []
  for rule in rules {
    if @rule_prefilter.rule_is_relevant_to_source(rule, source) {
      match rule.definition {
        Structural(_) => ids.push("S:\{rule.rule_id}")
        Taint(_) => ids.push("T:\{rule.rule_id}")
      }
    }
  }
  ids
}

///|
test "scan plan separates structural and taint entries" {
  let structural_rule =
    #|id: structural-example
    #|description: Structural target.
    #|patterns:
    #|  - shape: target()
    #|
  let taint_rule =
    #|id: taint-example
    #|description: User input reaches sink.
    #|taint:
    #|  sources:
    #|    - shape: read_input()
    #|  sinks:
    #|    - shape: sink(__SOURCE__)
    #|
  let rules = compile_scan_plan_rules([structural_rule, taint_rule])
  let plan = ScanPlan::from_rules(rules)
  assert_eq(plan.structural_entries.length(), 1)
  assert_eq(plan.taint_entries.length(), 1)
  debug_inspect(
    scan_plan_rule_ids(plan),
    content="[\"S:structural-example\", \"T:taint-example\"]",
  )
  inspect(plan.taint_entries[0].spec.rule_id, content="taint-example")
}

///|
test "scan plan filter source matches compiled rule prefilter" {
  let target_rule =
    #|id: structural-target
    #|description: Target call.
    #|patterns:
    #|  - shape: target()
    #|
  let other_rule =
    #|id: structural-other
    #|description: Other call.
    #|patterns:
    #|  - shape: other()
    #|
  let taint_rule =
    #|id: taint-flow
    #|description: User input reaches sink.
    #|taint:
    #|  sources:
    #|    - shape: read_input()
    #|  sinks:
    #|    - shape: sink(__SOURCE__)
    #|
  let rules = compile_scan_plan_rules([target_rule, other_rule, taint_rule])
  let source = "fn sample { let x = read_input(); target(); sink(x) }\n"
  let plan = ScanPlan::from_rules(rules).filter_source(source)
  debug_inspect(
    scan_plan_rule_ids(plan),
    content="[\"S:structural-target\", \"T:taint-flow\"]",
  )
  assert_eq(
    scan_plan_rule_ids(plan).join("|"),
    prefilter_rule_ids(rules, source).join("|"),
  )
  assert_false(plan.is_empty())
  assert_true(
    ScanPlan::from_rules(rules)
    .filter_source("fn sample { noop() }\n")
    .is_empty(),
  )
}

///|
test "scan plan structural apply returns expected findings" {
  let target_rule =
    #|id: structural-target
    #|description: Target call.
    #|patterns:
    #|  - shape: target()
    #|
  let other_rule =
    #|id: structural-other
    #|description: Other call.
    #|patterns:
    #|  - shape: other()
    #|
  let taint_rule =
    #|id: taint-flow
    #|description: User input reaches sink.
    #|taint:
    #|  sources:
    #|    - shape: read_input()
    #|  sinks:
    #|    - shape: sink(__SOURCE__)
    #|
  let source =
    #|fn sample {
    #|  target();
    #|  other()
    #|}
    #|
  let rules = compile_scan_plan_rules([target_rule, taint_rule, other_rule])
  let node = parse_scan_plan_root(source)
  let plan_hits = apply_structural_scan_plan_to_node(
    "sample.mbt",
    node,
    ScanPlan::from_rules(rules),
  )
  debug_inspect(
    [
      for hit in plan_hits => hit.rule_id
    ],
    content="[\"structural-target\", \"structural-other\"]",
  )
  assert_true(scan_plan_finding_signatures(plan_hits)[0].contains("sample.mbt"))
}

///|
test "scan plan taint apply returns expected findings" {
  let structural_rule =
    #|id: structural-target
    #|description: Target call.
    #|patterns:
    #|  - shape: target()
    #|
  let taint_rule =
    #|id: taint-flow
    #|description: User input reaches sink.
    #|taint:
    #|  sources:
    #|    - shape: read_input()
    #|  sinks:
    #|    - shape: sink(__SOURCE__)
    #|
  let source =
    #|fn sample {
    #|  let x = read_input();
    #|  sink(x)
    #|}
    #|
  let rules = compile_scan_plan_rules([structural_rule, taint_rule])
  let node = parse_scan_plan_single_node(source)
  let plan_hits = apply_taint_scan_plan_to_node(
    "sample.mbt",
    node,
    ScanPlan::from_rules(rules),
  )
  debug_inspect(
    [
      for hit in plan_hits => hit.rule_id
    ],
    content="[\"taint-flow\"]",
  )
  assert_eq(plan_hits[0].pattern_index, 0)
}
