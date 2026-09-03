///|
priv struct CstStructuralRuleEntry {
  rule : CompiledRule
  structural : CompiledStructuralRule
  pattern_buckets : ExprPatternBuckets
  negative_pattern_buckets : ExprPatternBuckets
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
}

///|
pub fn ScanPlan::from_rules(rules : Array[CompiledRule]) -> ScanPlan {
  let structural_entries : Array[CstStructuralRuleEntry] = []
  let taint_entries : Array[PlannedTaintRule] = []
  for rule in rules {
    match rule.definition {
      Structural(structural) =>
        structural_entries.push(cst_structural_rule_entry(rule, structural))
      Taint(taint_rule) =>
        taint_entries.push({
          rule,
          sink_count: taint_rule.sinks.length(),
          spec: lower_compiled_taint_rule(rule, taint_rule),
        })
    }
  }
  { structural_entries, taint_entries, }
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
  { structural_entries, taint_entries, }
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
) -> CstStructuralRuleEntry {
  let inside_patterns = if !structural.inside_expr.is_empty() {
    structural.inside_expr
  } else {
    structural.inside_toplevel
  }
  {
    rule,
    structural,
    pattern_buckets: ExprPatternBuckets::from_patterns(structural.patterns),
    negative_pattern_buckets: ExprPatternBuckets::from_patterns(
      structural.patterns_not,
    ),
    inside_pattern_buckets: ExprPatternBuckets::from_patterns(inside_patterns),
  }
}
