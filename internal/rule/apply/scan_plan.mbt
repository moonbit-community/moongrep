///|
priv struct CstStructuralRuleEntry {
  rule : CompiledRule
  structural : CompiledStructuralRule
  group : Int
  inside_pattern_buckets : ExprPatternBuckets
}

///|
priv struct PlannedTaintRule {
  rule : CompiledRule
  sink_count : Int
  spec : @taint.TaintSpec
}

///|
pub struct ScanPlan {
  priv structural_entries : Array[CstStructuralRuleEntry]
  priv taint_entries : Array[PlannedTaintRule]
  priv groups : Array[PlannedStructuralGroup]
  priv capture_names : Array[String]
}

///|
pub fn ScanPlan::from_rules(rules : Array[CompiledRule]) -> ScanPlan {
  let structural_entries : Array[CstStructuralRuleEntry] = []
  let taint_entries : Array[PlannedTaintRule] = []
  let groups : Array[PlannedStructuralGroup] = []
  let capture_names : Array[String] = []
  for rule in rules {
    match rule.definition {
      Structural(structural) =>
        structural_entries.push(
          cst_structural_rule_entry(rule, structural, groups, capture_names),
        )
      Taint(taint_rule) =>
        taint_entries.push({
          rule,
          sink_count: taint_rule.sinks.length(),
          spec: lower_compiled_taint_rule(rule, taint_rule),
        })
    }
  }
  { structural_entries, taint_entries, groups, capture_names, }
}

///|
pub fn ScanPlan::filter_source(
  self : ScanPlan,
  source : StringView,
) -> ScanPlan {
  let literal_cache : Map[String, Bool] = Map([])
  let structural_entries : Array[CstStructuralRuleEntry] = []
  let taint_entries : Array[PlannedTaintRule] = []
  for entry in self.structural_entries {
    if scan_plan_rule_matches_source(entry.rule, source, literal_cache) {
      structural_entries.push(entry)
    }
  }
  for entry in self.taint_entries {
    if scan_plan_rule_matches_source(entry.rule, source, literal_cache) {
      taint_entries.push(entry)
    }
  }
  { ..self, structural_entries, taint_entries, }
}

///|
pub fn ScanPlan::is_empty(self : ScanPlan) -> Bool {
  self.structural_entries.is_empty() && self.taint_entries.is_empty()
}

///|
fn scan_plan_rule_matches_source(
  rule : CompiledRule,
  source : StringView,
  literal_cache : Map[String, Bool],
) -> Bool {
  @rule_prefilter.prefilter_matches_with_literal_matcher(rule.prefilter, fn(
    literal,
  ) {
    scan_plan_literal_matches(source, literal_cache, literal)
  })
}

///|
fn scan_plan_literal_matches(
  source : StringView,
  literal_cache : Map[String, Bool],
  literal : String,
) -> Bool {
  if literal_cache.get(literal) is Some(matched) {
    matched
  } else {
    let matched = source.contains(literal)
    literal_cache[literal] = matched
    matched
  }
}

///|
fn cst_structural_rule_entry(
  rule : CompiledRule,
  structural : CompiledStructuralRule,
  groups : Array[PlannedStructuralGroup],
  capture_names : Array[String],
) -> CstStructuralRuleEntry {
  for pattern in structural.inside_toplevel {
    ignore(pattern_dependencies(pattern, capture_names))
  }
  {
    rule,
    structural,
    group: plan_structural_group(structural.group, groups, capture_names),
    inside_pattern_buckets: ExprPatternBuckets::from_patterns(
      structural.inside_toplevel,
    ),
  }
}

///|
priv struct PlannedStructuralGroup {
  positive : ExprPatternBuckets
  negative : ExprPatternBuckets
  children : Array[Int?]
  needed : Array[Int]
  has_positive : Bool
  reject_negative : Bool
}

///|
fn capture_id(names : Array[String], name : String) -> Int {
  for id, existing in names {
    if existing == name {
      return id
    }
  }
  let id = names.length()
  names.push(name)
  id
}

///|
fn pattern_dependencies(
  pattern : CompiledRulePattern,
  names : Array[String],
) -> Array[Int] {
  let ids : Array[Int] = []
  for entry in pattern.compiled.metavars.entries {
    ids.push(capture_id(names, entry.name))
  }
  for guard_entry in pattern.guards {
    let id = capture_id(names, guard_entry.name)
    if !ids.contains(id) {
      ids.push(id)
    }
  }
  ids
}

///|
// Flatten with a work list, then compute transitive dependencies bottom up.
fn plan_structural_group(
  root : @model.CompiledStructuralPatternGroup,
  groups : Array[PlannedStructuralGroup],
  names : Array[String],
) -> Int {
  let offset = groups.length()
  let pending = [root]
  let children : Array[Array[Int?]] = []
  for i = 0; i < pending.length(); i = i + 1 {
    let child_ids : Array[Int?] = []
    for pattern in pending[i].patterns {
      if pattern.then_body is Some(body) {
        child_ids.push(Some(offset + pending.length()))
        pending.push(body)
      } else {
        child_ids.push(None)
      }
    }
    children.push(child_ids)
    let group = pending[i]
    let needed : Array[Int] = []
    let patterns = group.patterns.map(p => p.pattern)
    for pattern in patterns + group.patterns_not {
      for id in pattern_dependencies(pattern, names) {
        if !needed.contains(id) {
          needed.push(id)
        }
      }
    }
    groups.push({
      positive: ExprPatternBuckets::from_patterns(patterns),
      negative: ExprPatternBuckets::from_patterns(group.patterns_not),
      children: child_ids,
      needed,
      has_positive: !group.patterns.is_empty(),
      reject_negative: group.patterns_not_mode is RejectUncoveredNegative,
    })
  }
  for i = groups.length() - 1; i >= offset; i = i - 1 {
    for child in children[i - offset] {
      if child is Some(child) {
        for id in groups[child].needed {
          if !groups[i].needed.contains(id) {
            groups[i].needed.push(id)
          }
        }
      }
    }
    groups[i].needed.sort()
  }
  offset
}
