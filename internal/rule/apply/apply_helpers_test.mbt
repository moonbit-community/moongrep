///|
using @compile {compile_rules}

///|
using @model {type CompiledRule, type RuleFinding}

///|
fn parse_root_node(source : String) -> @untyped_cst.CstNode raise {
  let parsed = @untyped_cst.parse_structure(source, name="apply test")
  guard parsed.diagnostics_view().is_empty() else {
    fail("expected source to parse")
  }
  parsed.root()
}

///|
fn compile_rule_source(source : String) -> Array[CompiledRule] raise {
  compile_rules([
    @model.RawRuleSpec::from_str(
      "/tmp/rules/example.yaml", "/tmp/rules", source,
    ),
  ])
}

///|
fn apply_structural_test_rules(
  file : String,
  root_node : @untyped_cst.CstNode,
  rules : Array[CompiledRule],
) -> Array[RuleFinding] {
  apply_structural_scan_plan_to_node(
    file,
    root_node,
    ScanPlan::from_rules(rules),
  )
}

///|
fn apply_taint_test_rules(
  file : String,
  root_node : @untyped_cst.CstNode,
  rules : Array[CompiledRule],
) -> Array[RuleFinding] raise {
  let hits : Array[RuleFinding] = []
  let plan = ScanPlan::from_rules(rules)
  if root_node.kind is @untyped_cst.Impls {
    for node in @cst.toplevel_nodes(root_node) {
      let node_hits = apply_taint_scan_plan_to_node(file, node, plan)
      for hit in node_hits {
        hits.push(hit)
      }
    }
  } else {
    let node_hits = apply_taint_scan_plan_to_node(file, root_node, plan)
    for hit in node_hits {
      hits.push(hit)
    }
  }
  hits
}

///|
fn location_signature(loc : @basic.Location) -> String {
  "\{loc.start.lnum}:\{loc.start.column()}-\{loc.end.lnum}:\{loc.end.column()}"
}

///|
fn finding_signature(finding : RuleFinding) -> String {
  "\{finding.file}|\{finding.rule_id}|\{finding.pattern_index}|\{location_signature(finding.loc)}"
}

///|
fn int_array_signature(values : Array[Int]) -> String {
  let parts : Array[String] = []
  for value in values {
    parts.push(value.to_string())
  }
  "[\{parts.join(", ")}]"
}

///|
fn apply_structural_rule_findings(
  source : String,
  rule_source : String,
) -> Array[RuleFinding] raise {
  let rules = compile_rule_source(rule_source)
  apply_structural_test_rules("sample.mbt", parse_root_node(source), rules)
}
