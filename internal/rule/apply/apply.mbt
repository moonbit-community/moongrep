///|
using @model {
  type CompiledRule,
  type CompiledRuleGuard,
  type CompiledRulePattern,
  type CompiledStructuralRule,
  type RuleFinding,
}

///|
using @taint_lowering {lower_compiled_taint_rule}

///|
priv suberror RuleApplyError {
  InvalidTaintSinkId(sink_id~ : @taint.SinkId, sink_count~ : Int)
} derive(Debug)

///|
priv enum RuleTraversalAction {
  RuleContinue
  RulePrune
}

///|
pub fn apply_structural_scan_plan_to_node(
  file : String,
  node : @untyped_cst.CstNode,
  plan : ScanPlan,
) -> Array[RuleFinding] {
  let hits : Array[RuleFinding] = []
  apply_toplevel_structural_rule_entries_to_node(
    file,
    plan.structural_entries,
    node,
    hits,
  )
  @cst.visit_scoped_expr_match_candidate_roots(node, fn(scoped_candidate) {
    apply_cst_structural_rule_entries_to_scoped_candidate(
      file,
      plan.structural_entries,
      scoped_candidate,
      hits,
    )
    @cst.NodeVisitPrune
  })
  hits
}

///|
fn apply_toplevel_structural_rule_entries_to_node(
  file : String,
  entries : Array[CstStructuralRuleEntry],
  node : @untyped_cst.CstNode,
  hits : Array[RuleFinding],
) -> Unit {
  if node.kind is @untyped_cst.Impls {
    for child in @cst.toplevel_nodes(node) {
      apply_toplevel_structural_rule_entries_to_node(file, entries, child, hits)
    }
    return
  }
  if node.kind.is_impl() {
    for entry in entries {
      if !entry.structural.inside_toplevel.is_empty() {
        apply_toplevel_group(file, entry, node, hits)
      }
    }
  }
}

///|
fn apply_cst_structural_rule_entries_to_scoped_candidate(
  file : String,
  entries : Array[CstStructuralRuleEntry],
  scoped_candidate : @cst.ScopedExprMatchCandidate,
  hits : Array[RuleFinding],
) -> Unit {
  let child_entries : Array[CstStructuralRuleEntry] = []
  for entry in entries {
    match
      apply_cst_structural_rule_entry_to_scoped_candidate(
        file, entry, scoped_candidate, hits,
      ) {
      RuleContinue => child_entries.push(entry)
      RulePrune => ()
    }
  }
  if child_entries.length() == 0 {
    return
  }
  @cst.visit_scoped_expr_match_candidate_children(
    scoped_candidate.candidate,
    scoped_candidate.shadowed_names,
    fn(child) {
      apply_cst_structural_rule_entries_to_scoped_candidate(
        file, child_entries, child, hits,
      )
    },
  )
}

///|
fn apply_cst_structural_rule_entry_to_scoped_candidate(
  file : String,
  entry : CstStructuralRuleEntry,
  scoped_candidate : @cst.ScopedExprMatchCandidate,
  hits : Array[RuleFinding],
) -> RuleTraversalAction {
  if !entry.structural.inside_toplevel.is_empty() {
    return RulePrune
  }
  let env = empty_capture_environment()
  match evaluate_group_candidate(entry.group, scoped_candidate.candidate, env) {
    GroupHit(index, loc) => {
      push_structural_hit(file, entry.rule, index, loc, hits)
      RulePrune
    }
    GroupNegative => RulePrune
    GroupMiss => RuleContinue
  }
}

///|
pub fn apply_taint_scan_plan_to_node(
  file : String,
  node : @untyped_cst.CstNode,
  plan : ScanPlan,
) -> Array[RuleFinding] raise {
  let hits : Array[RuleFinding] = []
  for entry in plan.taint_entries {
    apply_planned_taint_rule_to_node(file, entry, node, hits)
  }
  hits
}

///|
fn apply_planned_taint_rule_to_node(
  file : String,
  entry : PlannedTaintRule,
  node : @untyped_cst.CstNode,
  hits : Array[RuleFinding],
) -> Unit raise {
  try @taint.analyze_function_like(node, entry.spec) catch {
    @taint.TaintAnalysisError::UnsupportedFunctionLike(..) => ()
    err => raise err
  } noraise {
    result =>
      for finding in result.findings {
        hits.push({
          file,
          rule_id: entry.rule.rule_id,
          description: entry.rule.description,
          pattern_index: sink_pattern_index(finding.sink_id, entry.sink_count),
          loc: finding.sink_loc,
        })
      }
  }
}

///|
fn sink_pattern_index(
  sink_id : @taint.SinkId,
  sink_count : Int,
) -> Int raise RuleApplyError {
  match sink_id {
    @taint.SinkId::PatternIndex(index) if index >= 0 && index < sink_count =>
      index
    _ => raise RuleApplyError::InvalidTaintSinkId(sink_id~, sink_count~)
  }
}
