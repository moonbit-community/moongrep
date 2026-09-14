///|
fn match_plain_rule_pattern(
  pattern : CompiledRulePattern,
  candidate : @cst.ExprMatchCandidate,
) -> @matching.ExprMatch? {
  match @matching.match_expr_pattern_candidate(pattern.compiled, candidate) {
    Some(matched) if cst_guards_match(pattern.guards, matched.bindings) =>
      Some(matched)
    _ => None
  }
}

///|
fn evaluate_plain_group_candidate(
  group : PlannedStructuralGroup,
  candidate : @cst.ExprMatchCandidate,
) -> GroupCandidateResult {
  for indexed in group.positive.patterns_for_candidate(candidate) {
    if match_plain_rule_pattern(indexed.pattern, candidate) is Some(matched) {
      return GroupHit(indexed.pattern_index, matched.loc)
    }
  }
  for indexed in group.negative.patterns_for_candidate(candidate) {
    if match_plain_rule_pattern(indexed.pattern, candidate) is Some(_) {
      return GroupNegative
    }
  }
  GroupMiss
}

///|
fn apply_plain_structural_entries_to_node(
  file : String,
  node : @untyped_cst.CstNode,
  plan : ScanPlan,
) -> Array[RuleFinding] {
  let hits : Array[RuleFinding] = []
  @cst.visit_expr_match_candidate_roots(node, fn(candidate) {
    apply_plain_structural_entries_to_candidate(
      file,
      plan,
      plan.structural_entries,
      candidate,
      hits,
    )
    @cst.NodeVisitPrune
  })
  hits
}

///|
fn apply_plain_structural_entries_to_candidate(
  file : String,
  plan : ScanPlan,
  entries : Array[CstStructuralRuleEntry],
  candidate : @cst.ExprMatchCandidate,
  hits : Array[RuleFinding],
) -> Unit {
  let child_entries : Array[CstStructuralRuleEntry] = []
  for entry in entries {
    match evaluate_plain_group_candidate(plan.groups[entry.group], candidate) {
      GroupHit(index, loc) =>
        push_structural_hit(file, entry.rule, index, loc, hits)
      GroupNegative => ()
      GroupMiss => child_entries.push(entry)
    }
  }
  if child_entries.is_empty() {
    return
  }
  @cst.visit_expr_match_candidate_children(candidate, fn(child) {
    apply_plain_structural_entries_to_candidate(
      file, plan, child_entries, child, hits,
    )
  })
}
