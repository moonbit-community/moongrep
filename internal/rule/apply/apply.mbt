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
pub fn apply_structural_scan_plan_to_node(
  file : String,
  node : @untyped_cst.CstNode,
  plan : ScanPlan,
) -> Array[RuleFinding] {
  if plan.structural_entries.is_empty() {
    return []
  }
  if plan.has_only_plain_structural_entries() {
    return apply_plain_structural_entries_to_node(file, node, plan)
  }
  apply_scan_session(file, node, ScanSession::new(plan, node))
}

///|
fn apply_scan_session(
  file : String,
  node : @untyped_cst.CstNode,
  session : ScanSession,
) -> Array[RuleFinding] {
  let hits : Array[RuleFinding] = []
  let toplevel = if node.kind is Impls {
    @cst.toplevel_nodes(node)
  } else {
    [node]
  }
  for node in toplevel {
    if node.kind.is_impl() {
      for entry in session.plan.structural_entries {
        if !entry.structural.inside_toplevel.is_empty() {
          session.apply_toplevel_group(file, entry, node, hits)
        }
      }
    }
  }
  let entries = session.plan.structural_entries.filter(entry => {
    entry.structural.inside_toplevel.is_empty()
  })
  let pending = [(session.index.roots(), entries)]
  while pending.pop() is Some((cursor, entries)) {
    if entries.is_empty() {
      continue
    }
    match session.index.step(cursor) {
      End => ()
      Scan(_) | Finish(_) | AfterContinue(_, _) =>
        abort("expected an ordinary root cursor")
      Concat(left, right) => {
        pending.push((right, entries))
        pending.push((left, entries))
      }
      Visit(region, next) => {
        pending.push((next, entries))
        let children : Array[CstStructuralRuleEntry] = []
        for entry in entries {
          let result = if entry.plain_root {
            evaluate_plain_group_candidate(
              session.plan.groups[entry.group],
              session.index.candidate(region),
            )
          } else {
            session.candidate(entry.group, region, 0)
          }
          match result {
            GroupHit(index, loc) =>
              push_structural_hit(file, entry.rule, index, loc, hits)
            GroupNegative => ()
            GroupMiss => children.push(entry)
          }
        }
        if !children.is_empty() {
          pending.push((session.index.children(region), children))
        }
      }
    }
  }
  hits
}

///|
fn push_structural_hit(
  file : String,
  rule : CompiledRule,
  index : Int,
  loc : @basic.Location,
  hits : Array[RuleFinding],
) -> Unit {
  hits.push({
    file,
    rule_id: rule.rule_id,
    description: rule.description,
    pattern_index: index,
    loc,
  })
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
    PatternIndex(index) if index >= 0 && index < sink_count => index
    _ => raise InvalidTaintSinkId(sink_id~, sink_count~)
  }
}
