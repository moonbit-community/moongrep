///|
using @model {
  type CompiledRule,
  type CompiledRuleGuard,
  type CompiledRulePattern,
  type CompiledStructuralRule,
  type CompiledTaintRule,
  type RuleFinding,
}

///|
using @taint_lowering {lower_compiled_taint_rule}

///|
priv enum RuleTraversalAction {
  RuleContinue
  RulePrune
}

///|
priv enum InsideTargetScanAction {
  InsideTargetContinue
  InsideTargetPrune
  InsideTargetReject
}

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
  taint_rule : CompiledTaintRule
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
          taint_rule,
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
        apply_inside_toplevel_cst_bucketed(
          file,
          entry.rule,
          entry.structural,
          entry.inside_pattern_buckets,
          entry.pattern_buckets,
          entry.negative_pattern_buckets,
          node,
          hits,
        )
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
  if !entry.structural.inside_expr.is_empty() {
    apply_inside_expr_cst_bucketed(
      file,
      entry.rule,
      entry.structural,
      entry.inside_pattern_buckets,
      entry.pattern_buckets,
      entry.negative_pattern_buckets,
      scoped_candidate.candidate,
      hits,
    )
    RuleContinue
  } else if !entry.structural.inside_toplevel.is_empty() {
    RulePrune
  } else {
    apply_cst_patterns_at_candidate(
      file,
      entry.rule,
      entry.pattern_buckets,
      entry.negative_pattern_buckets,
      scoped_candidate.candidate,
      None,
      hits,
    )
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
          pattern_index: sink_pattern_index(entry.taint_rule, finding.sink_id),
          loc: finding.sink_loc,
        })
      }
  }
}

///|
fn sink_pattern_index(taint_rule : CompiledTaintRule, sink_id : String) -> Int {
  for index in 0..<taint_rule.sinks.length() {
    if sink_id == "sink:\{index}" {
      return index
    }
  }
  0
}

///|
fn apply_inside_toplevel_cst_bucketed(
  file : String,
  rule : CompiledRule,
  structural : CompiledStructuralRule,
  inside_pattern_buckets : ExprPatternBuckets,
  pattern_buckets : ExprPatternBuckets,
  negative_pattern_buckets : ExprPatternBuckets,
  toplevel : @untyped_cst.CstNode,
  hits : Array[RuleFinding],
) -> Unit {
  ignore(
    apply_inside_context_cst_bucketed(
      file,
      rule,
      structural,
      inside_pattern_buckets,
      pattern_buckets,
      negative_pattern_buckets,
      @cst.Direct(toplevel),
      hits,
    ),
  )
}

///|
fn apply_inside_expr_cst_bucketed(
  file : String,
  rule : CompiledRule,
  structural : CompiledStructuralRule,
  inside_pattern_buckets : ExprPatternBuckets,
  pattern_buckets : ExprPatternBuckets,
  negative_pattern_buckets : ExprPatternBuckets,
  candidate : @cst.ExprMatchCandidate,
  hits : Array[RuleFinding],
) -> Unit {
  let context_hits : Array[RuleFinding] = []
  let context_loc = apply_inside_context_cst_bucketed(
    file, rule, structural, inside_pattern_buckets, pattern_buckets, negative_pattern_buckets,
    candidate, context_hits,
  )
  if context_hits.get(0) is Some(first) && context_loc is Some(loc) {
    hits.push({
      file: first.file,
      rule_id: first.rule_id,
      description: first.description,
      pattern_index: first.pattern_index,
      loc,
    })
  }
}

///|
fn apply_inside_context_cst_bucketed(
  file : String,
  rule : CompiledRule,
  structural : CompiledStructuralRule,
  inside_pattern_buckets : ExprPatternBuckets,
  pattern_buckets : ExprPatternBuckets,
  negative_pattern_buckets : ExprPatternBuckets,
  context_candidate : @cst.ExprMatchCandidate,
  hits : Array[RuleFinding],
) -> @basic.Location? {
  for
    indexed in inside_pattern_buckets.patterns_for_candidate(context_candidate) {
    let inside = indexed.pattern
    if match_candidate_rule_pattern(inside, context_candidate, None)
      is Some(result) {
      let context_loc = result.loc
      if result.bindings.get("__TARGET__") is Some(target) {
        let target_candidate = inside_target_match_candidate(
          context_candidate, target,
        )
        if structural.patterns.is_empty() {
          let target_exprs : Array[@cst.ScopedExprMatchCandidate] = []
          collect_target_match_candidates(target_candidate, target_exprs)
          apply_inside_context_only_cst_bucketed(
            file,
            rule,
            negative_pattern_buckets,
            target_exprs,
            context_loc,
            result.bindings,
            inside.compiled.metavars,
            hits,
          )
        } else {
          match structural.patterns_not_mode {
            RejectUncoveredNegative =>
              apply_cst_bucketed_covered_patterns_in_target_subtree(
                file,
                rule,
                pattern_buckets,
                negative_pattern_buckets,
                target_candidate,
                result.bindings,
                inside.compiled.metavars,
                hits,
              )
            PruneOnNegative =>
              apply_cst_bucketed_patterns_in_target_subtree(
                file,
                rule,
                pattern_buckets,
                negative_pattern_buckets,
                target_candidate,
                result.bindings,
                inside.compiled.metavars,
                hits,
              )
          }
        }
      }
      // Outer alternatives are ordered. Once shape and guards select one,
      // later alternatives are not considered even if the target has no hit.
      return Some(context_loc)
    }
  }
  None
}

///|
fn inside_target_match_candidate(
  context : @cst.ExprMatchCandidate,
  target : @matching.BoundValue,
) -> @cst.ExprMatchCandidate {
  match target {
    Single(target) =>
      if target.kind is @untyped_cst.Expression {
        @cst.Sequence(@cst.expression_nodes(target))
      } else if target.kind is @untyped_cst.Expr_Block &&
        match_candidate_contains_function_body_target(context, target) {
        @cst.Sequence(@cst.sequence_items(target))
      } else {
        @cst.Direct(target)
      }
    Multiple(targets) => @cst.Sequence(targets)
  }
}

///|
fn match_candidate_contains_function_body_target(
  context : @cst.ExprMatchCandidate,
  target : @untyped_cst.CstNode,
) -> Bool {
  match context {
    @cst.Direct(node) => node_contains_function_body_target(node, target)
    @cst.Sequence(items) => {
      for item in items {
        if node_contains_function_body_target(item, target) {
          return true
        }
      }
      false
    }
  }
}

///|
fn node_contains_function_body_target(
  node : @untyped_cst.CstNode,
  target : @untyped_cst.CstNode,
) -> Bool {
  let body = match node.kind {
    @untyped_cst.Impl_Function
    | @untyped_cst.Impl_Test
    | @untyped_cst.Expr_Function
    | @untyped_cst.Expr_LetFn
    | @untyped_cst.Binding_LetRec => @cst.raw_child(node, "body")
    @untyped_cst.Impl_ImplMethod =>
      @cst.raw_child(node, "method").bind(method_node => {
        @cst.raw_child(method_node, "body")
      })
    _ => None
  }
  if body is Some(found) && same_cst_span(found, target) {
    return true
  }
  for entry in node.children {
    if node_contains_function_body_target(entry.1, target) {
      return true
    }
  }
  false
}

///|
fn same_cst_span(
  left : @untyped_cst.CstNode,
  right : @untyped_cst.CstNode,
) -> Bool {
  left.source_span.0 == right.source_span.0 &&
  left.source_span.1 == right.source_span.1 &&
  left.loc.start.fname == right.loc.start.fname
}

///|
fn collect_target_match_candidates(
  target : @cst.ExprMatchCandidate,
  output : Array[@cst.ScopedExprMatchCandidate],
) -> Unit {
  @cst.visit_scoped_expr_match_candidate(target, [], fn(item) {
    output.push(item)
    @cst.NodeVisitContinue
  })
}

///|
fn apply_cst_bucketed_patterns_in_target_subtree(
  file : String,
  rule : CompiledRule,
  pattern_buckets : ExprPatternBuckets,
  negative_pattern_buckets : ExprPatternBuckets,
  target : @cst.ExprMatchCandidate,
  outer_bindings : @hashmap.HashMap[String, @matching.BoundValue],
  inherited_metavars : @matching.MetavarRegistry,
  hits : Array[RuleFinding],
) -> Unit {
  @cst.visit_scoped_expr_match_candidate(target, [], fn(scoped_candidate) {
    match
      apply_cst_bucketed_patterns_at_scoped_candidate(
        file, rule, pattern_buckets, negative_pattern_buckets, scoped_candidate,
        outer_bindings, inherited_metavars, hits,
      ) {
      RulePrune => @cst.NodeVisitPrune
      RuleContinue => @cst.NodeVisitContinue
    }
  })
}

///|
fn apply_cst_bucketed_covered_patterns_in_target_subtree(
  file : String,
  rule : CompiledRule,
  pattern_buckets : ExprPatternBuckets,
  negative_pattern_buckets : ExprPatternBuckets,
  target : @cst.ExprMatchCandidate,
  outer_bindings : @hashmap.HashMap[String, @matching.BoundValue],
  inherited_metavars : @matching.MetavarRegistry,
  hits : Array[RuleFinding],
) -> Unit {
  let pending_hits : Array[RuleFinding] = []
  let mut rejected = false
  @cst.visit_scoped_expr_match_candidate(target, [], fn(scoped_candidate) {
    if rejected {
      @cst.NodeVisitPrune
    } else {
      match
        apply_cst_bucketed_covered_patterns_at_scoped_candidate(
          file, rule, pattern_buckets, negative_pattern_buckets, scoped_candidate,
          outer_bindings, inherited_metavars, pending_hits,
        ) {
        InsideTargetPrune => @cst.NodeVisitPrune
        InsideTargetReject => {
          rejected = true
          @cst.NodeVisitPrune
        }
        InsideTargetContinue => @cst.NodeVisitContinue
      }
    }
  })
  if !rejected && !pending_hits.is_empty() {
    hits.append(pending_hits)
  }
}

///|
fn apply_inside_context_only_cst_bucketed(
  file : String,
  rule : CompiledRule,
  negative_pattern_buckets : ExprPatternBuckets,
  target_exprs : Array[@cst.ScopedExprMatchCandidate],
  context_loc : @basic.Location,
  outer_bindings : @hashmap.HashMap[String, @matching.BoundValue],
  inherited_metavars : @matching.MetavarRegistry,
  hits : Array[RuleFinding],
) -> Unit {
  if cst_bucketed_negative_patterns_match_any_scoped_candidate(
      negative_pattern_buckets, target_exprs, outer_bindings, inherited_metavars,
    ) {
    return
  }
  push_inside_context_only_hit(file, rule, context_loc, hits)
}

///|
fn push_inside_context_only_hit(
  file : String,
  rule : CompiledRule,
  context_loc : @basic.Location,
  hits : Array[RuleFinding],
) -> Unit {
  hits.push({
    file,
    rule_id: rule.rule_id,
    description: rule.description,
    pattern_index: 0,
    loc: context_loc,
  })
}

///|
fn apply_cst_bucketed_covered_patterns_at_scoped_candidate(
  file : String,
  rule : CompiledRule,
  pattern_buckets : ExprPatternBuckets,
  negative_pattern_buckets : ExprPatternBuckets,
  scoped_candidate : @cst.ScopedExprMatchCandidate,
  outer_bindings : @hashmap.HashMap[String, @matching.BoundValue],
  inherited_metavars : @matching.MetavarRegistry,
  hits : Array[RuleFinding],
) -> InsideTargetScanAction {
  for
    indexed in pattern_buckets.patterns_for_candidate(
      scoped_candidate.candidate,
    ) {
    if cst_pattern_blocked_by_shadowed_outer_id(
        indexed.pattern,
        outer_bindings,
        inherited_metavars,
        scoped_candidate.shadowed_names,
      ) {
      continue
    }
    if match_candidate_rule_pattern(
        indexed.pattern,
        scoped_candidate.candidate,
        Some(outer_bindings),
      )
      is Some(result) {
      hits.push({
        file,
        rule_id: rule.rule_id,
        description: rule.description,
        pattern_index: indexed.pattern_index,
        loc: result.loc,
      })
      return InsideTargetPrune
    }
  }
  if cst_bucketed_negative_patterns_match_scoped_candidate(
      negative_pattern_buckets, scoped_candidate, outer_bindings, inherited_metavars,
    ) {
    return InsideTargetReject
  }
  InsideTargetContinue
}

///|
fn apply_cst_bucketed_patterns_at_scoped_candidate(
  file : String,
  rule : CompiledRule,
  pattern_buckets : ExprPatternBuckets,
  negative_pattern_buckets : ExprPatternBuckets,
  scoped_candidate : @cst.ScopedExprMatchCandidate,
  outer_bindings : @hashmap.HashMap[String, @matching.BoundValue],
  inherited_metavars : @matching.MetavarRegistry,
  hits : Array[RuleFinding],
) -> RuleTraversalAction {
  for
    indexed in pattern_buckets.patterns_for_candidate(
      scoped_candidate.candidate,
    ) {
    if cst_pattern_blocked_by_shadowed_outer_id(
        indexed.pattern,
        outer_bindings,
        inherited_metavars,
        scoped_candidate.shadowed_names,
      ) {
      continue
    }
    if match_candidate_rule_pattern(
        indexed.pattern,
        scoped_candidate.candidate,
        Some(outer_bindings),
      )
      is Some(result) {
      hits.push({
        file,
        rule_id: rule.rule_id,
        description: rule.description,
        pattern_index: indexed.pattern_index,
        loc: result.loc,
      })
      return RulePrune
    }
  }
  if cst_bucketed_negative_patterns_match_scoped_candidate(
      negative_pattern_buckets, scoped_candidate, outer_bindings, inherited_metavars,
    ) {
    return RulePrune
  }
  RuleContinue
}

///|
fn apply_cst_patterns_at_candidate(
  file : String,
  rule : CompiledRule,
  pattern_buckets : ExprPatternBuckets,
  negative_pattern_buckets : ExprPatternBuckets,
  candidate : @cst.ExprMatchCandidate,
  initial_bindings : @hashmap.HashMap[String, @matching.BoundValue]?,
  hits : Array[RuleFinding],
) -> RuleTraversalAction {
  for indexed in pattern_buckets.patterns_for_candidate(candidate) {
    if match_candidate_rule_pattern(
        indexed.pattern,
        candidate,
        initial_bindings,
      )
      is Some(result) {
      hits.push({
        file,
        rule_id: rule.rule_id,
        description: rule.description,
        pattern_index: indexed.pattern_index,
        loc: result.loc,
      })
      return RulePrune
    }
  }
  if cst_negative_patterns_match_candidate(
      negative_pattern_buckets, candidate, initial_bindings,
    ) {
    return RulePrune
  }
  RuleContinue
}

///|
fn cst_negative_patterns_match_candidate(
  negative_pattern_buckets : ExprPatternBuckets,
  candidate : @cst.ExprMatchCandidate,
  initial_bindings : @hashmap.HashMap[String, @matching.BoundValue]?,
) -> Bool {
  for indexed in negative_pattern_buckets.patterns_for_candidate(candidate) {
    if match_candidate_rule_pattern(
        indexed.pattern,
        candidate,
        initial_bindings,
      )
      is Some(_) {
      return true
    }
  }
  false
}

///|
fn cst_bucketed_negative_patterns_match_scoped_candidate(
  negative_pattern_buckets : ExprPatternBuckets,
  scoped_candidate : @cst.ScopedExprMatchCandidate,
  initial_bindings : @hashmap.HashMap[String, @matching.BoundValue],
  inherited_metavars : @matching.MetavarRegistry,
) -> Bool {
  for
    indexed in negative_pattern_buckets.patterns_for_candidate(
      scoped_candidate.candidate,
    ) {
    if cst_pattern_blocked_by_shadowed_outer_id(
        indexed.pattern,
        initial_bindings,
        inherited_metavars,
        scoped_candidate.shadowed_names,
      ) {
      continue
    }
    if match_candidate_rule_pattern(
        indexed.pattern,
        scoped_candidate.candidate,
        Some(initial_bindings),
      )
      is Some(_) {
      return true
    }
  }
  false
}

///|
fn cst_bucketed_negative_patterns_match_any_scoped_candidate(
  negative_pattern_buckets : ExprPatternBuckets,
  target_exprs : Array[@cst.ScopedExprMatchCandidate],
  initial_bindings : @hashmap.HashMap[String, @matching.BoundValue],
  inherited_metavars : @matching.MetavarRegistry,
) -> Bool {
  for scoped_candidate in target_exprs {
    if cst_bucketed_negative_patterns_match_scoped_candidate(
        negative_pattern_buckets, scoped_candidate, initial_bindings, inherited_metavars,
      ) {
      return true
    }
  }
  false
}

///|
fn cst_pattern_blocked_by_shadowed_outer_id(
  pattern : CompiledRulePattern,
  outer_bindings : @hashmap.HashMap[String, @matching.BoundValue],
  inherited_metavars : @matching.MetavarRegistry,
  shadowed_names : Array[String],
) -> Bool {
  for metavar in inherited_metavars.names(Identifier) {
    if pattern.compiled.metavars.kind_of(metavar) == Some(Identifier) {
      if outer_bindings.get(metavar) is Some(Single(bound_node)) {
        if @cst.normalized_name(bound_node) is Some(bound_name) &&
          names_contain(shadowed_names, bound_name) {
          return true
        }
      }
    }
  }
  false
}

///|
fn names_contain(names : Array[String], needle : String) -> Bool {
  for name in names {
    if name == needle {
      return true
    }
  }
  false
}

///|
fn match_candidate_rule_pattern(
  pattern : CompiledRulePattern,
  candidate : @cst.ExprMatchCandidate,
  initial_bindings : @hashmap.HashMap[String, @matching.BoundValue]?,
) -> @matching.ExprMatch? {
  let matched = if initial_bindings is Some(bindings) {
    @matching.match_expr_pattern_candidate_with_bindings(
      pattern.compiled,
      candidate,
      bindings,
    )
  } else {
    @matching.match_expr_pattern_candidate(pattern.compiled, candidate)
  }
  match matched {
    Some(result) if cst_guards_match(pattern.guards, result.bindings) =>
      Some(result)
    _ => None
  }
}

///|
fn cst_guards_match(
  guards : Array[CompiledRuleGuard],
  bindings : @hashmap.HashMap[String, @matching.BoundValue],
) -> Bool {
  for guard_entry in guards {
    match guard_entry.capture_kind {
      IdentifierGuard =>
        match bindings.get(guard_entry.name) {
          Some(Single(value)) => {
            guard @cst.normalized_name(value) is Some(text) else {
              return false
            }
            if guard_entry.regex.execute(text) is None {
              return false
            }
          }
          _ => return false
        }
      ConstantGuard =>
        match bindings.get(guard_entry.name) {
          Some(Single(value)) => {
            guard constant_guard_value(value) is Some(text) else {
              return false
            }
            if guard_entry.regex.execute(text) is None {
              return false
            }
          }
          _ => return false
        }
    }
  }
  true
}

///|
fn constant_guard_value(constant : @untyped_cst.CstNode) -> String? {
  if @cst.string_payload(constant) is Some(value) {
    Some(value)
  } else if @cst.bool_payload(constant) is Some(value) {
    Some(value.to_string())
  } else {
    None
  }
}
