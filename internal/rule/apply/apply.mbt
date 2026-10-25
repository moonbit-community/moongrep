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
  InvalidTaintSinkId(sink_id~ : @taint.SinkId, sink_count~ : Int32)
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
  let collector = StructuralFindingCollector::new()
  if plan.has_only_plain_structural_entries() {
    return apply_plain_structural_entries_to_node(file, node, plan, collector)
  }
  apply_scan_session(file, node, ScanSession::new(plan, node), collector)
}

///|
fn apply_scan_session(
  file : String,
  node : @untyped_cst.CstNode,
  session : ScanSession,
  collector : StructuralFindingCollector,
) -> Array[RuleFinding] {
  let toplevel = if node.kind is Impls {
    @cst.toplevel_nodes(node)
  } else {
    [node]
  }
  for node in toplevel {
    if node.kind.is_impl() {
      for entry in session.plan.structural_entries {
        if !entry.structural.inside_toplevel.is_empty() {
          session.apply_toplevel_group(file, entry, node, collector)
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
      Concat(left, right) => {
        pending.push((right, entries))
        pending.push((left, entries))
      }
      Visit(region, next) => {
        session.publication_visits += 1
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
            GroupHit(index, loc) => collector.add(file, entry.rule, index, loc)
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
  collector.findings
}

///|
pub(all) struct TaintDiagnostic {
  file : String
  loc : @basic.Location
  rule_ids : Array[String]
  reason : String
}

///|
pub(all) struct TaintScanResult {
  findings : Array[RuleFinding]
  diagnostics : Array[TaintDiagnostic]
}

///|
pub fn ScanPlan::taint_rule_ids(self : ScanPlan) -> Array[String] {
  self.taint_entries.map(entry => entry.rule.rule_id)
}

///|
pub fn apply_taint_scan_plan_to_node(
  file : String,
  node : @untyped_cst.CstNode,
  plan : ScanPlan,
) -> TaintScanResult raise {
  apply_taint_with_preparer(file, node, plan, @taint.prepare_function_like)
}

///|
fn apply_taint_with_preparer(
  file : String,
  node : @untyped_cst.CstNode,
  plan : ScanPlan,
  prepare : (@untyped_cst.CstNode) -> @taint.Preparation raise @taint.InvalidGraph,
) -> TaintScanResult raise {
  let findings : Array[RuleFinding] = []
  let diagnostics : Array[TaintDiagnostic] = []
  if plan.taint_entries.is_empty() {
    return { findings, diagnostics, }
  }
  match prepare(node) {
    NotApplicable => ()
    Unsupported(reasons) =>
      for diagnostic in reasons {
        add_taint_diagnostic(diagnostics, {
          file,
          loc: diagnostic.loc,
          reason: diagnostic.reason,
          rule_ids: plan.taint_rule_ids(),
        })
      }
    Prepared(prepared) =>
      for entry in plan.taint_entries {
        match @taint.analyze(prepared, entry.spec) {
          Incomplete(reasons) =>
            for diagnostic in reasons {
              add_taint_diagnostic(diagnostics, {
                file,
                loc: diagnostic.loc,
                reason: diagnostic.reason,
                rule_ids: [entry.rule.rule_id],
              })
            }
          Complete(hits) =>
            for finding in hits {
              findings.push({
                file,
                rule_id: entry.rule.rule_id,
                description: entry.rule.description,
                pattern_index: sink_pattern_index(
                  finding.sink_id,
                  entry.sink_count,
                ),
                loc: finding.sink_loc,
              })
            }
        }
      }
  }
  { findings, diagnostics, }
}

///|
fn sink_pattern_index(
  sink_id : @taint.SinkId,
  sink_count : Int32,
) -> Int32 raise RuleApplyError {
  match sink_id {
    PatternIndex(index) if index >= 0 && index < sink_count => index
    _ => raise InvalidTaintSinkId(sink_id~, sink_count~)
  }
}

///|
fn add_taint_diagnostic(
  diagnostics : Array[TaintDiagnostic],
  diagnostic : TaintDiagnostic,
) -> Unit {
  for i in 0..<diagnostics.length() {
    let previous = diagnostics[i]
    if previous.file == diagnostic.file &&
      previous.loc == diagnostic.loc &&
      previous.reason == diagnostic.reason {
      let rule_ids = previous.rule_ids.copy()
      for id in diagnostic.rule_ids {
        if !rule_ids.contains(id) {
          rule_ids.push(id)
        }
      }
      diagnostics[i] = { ..previous, rule_ids, }
      return
    }
  }
  diagnostics.push(diagnostic)
}
