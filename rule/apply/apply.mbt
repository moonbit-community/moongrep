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
priv struct AstStructuralRuleEntry {
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
  priv structural_entries : Array[AstStructuralRuleEntry]
  priv taint_entries : Array[PlannedTaintRule]
}

///|
pub fn ScanPlan::from_rules(rules : Array[CompiledRule]) -> ScanPlan {
  let structural_entries : Array[AstStructuralRuleEntry] = []
  let taint_entries : Array[PlannedTaintRule] = []
  for rule in rules {
    match rule.definition {
      Structural(structural) =>
        structural_entries.push(ast_structural_rule_entry(rule, structural))
      Taint(taint_rule) =>
        taint_entries.push({
          rule,
          taint_rule,
          spec: lower_compiled_taint_rule(rule, taint_rule),
        })
    }
  }
  { structural_entries, taint_entries }
}

///|
pub fn ScanPlan::filter_source(
  self : ScanPlan,
  source : StringView,
) -> ScanPlan {
  let literal_cache : Map[String, Bool] = Map([])
  let structural_entries : Array[AstStructuralRuleEntry] = []
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
  { structural_entries, taint_entries }
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
  node : @untyped_ast.Node,
  plan : ScanPlan,
) -> Array[RuleFinding] {
  let hits : Array[RuleFinding] = []
  apply_toplevel_structural_rule_entries_to_node(
    file,
    plan.structural_entries,
    node,
    hits,
  )
  @untyped_ast.visit_node_scoped_expr_roots(node, fn(scoped_expr) {
    apply_ast_structural_rule_entries_to_scoped_expr(
      file,
      plan.structural_entries,
      scoped_expr,
      hits,
    )
    NodeVisitPrune
  })
  hits
}

///|
fn ast_structural_rule_entry(
  rule : CompiledRule,
  structural : CompiledStructuralRule,
) -> AstStructuralRuleEntry {
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
  entries : Array[AstStructuralRuleEntry],
  node : @untyped_ast.Node,
  hits : Array[RuleFinding],
) -> Unit {
  match node.kind {
    ImplList =>
      for entry in node.children {
        let (_, child) = entry
        apply_toplevel_structural_rule_entries_to_node(
          file, entries, child, hits,
        )
      }
    Impl_TopExpr
    | Impl_TopFuncDef
    | Impl_TopImpl
    | Impl_TopImplRelation
    | Impl_TopLetDef
    | Impl_TopTest
    | Impl_TopTrait
    | Impl_TopTypeDef
    | Impl_TopUsing
    | Impl_TopView =>
      for entry in entries {
        if !entry.structural.inside_toplevel.is_empty() {
          apply_inside_toplevel_ast_bucketed(
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
    _ => ()
  }
}

///|
fn apply_ast_structural_rule_entries_to_scoped_expr(
  file : String,
  entries : Array[AstStructuralRuleEntry],
  scoped_expr : @untyped_ast.ScopedExprNode,
  hits : Array[RuleFinding],
) -> Unit {
  let child_entries : Array[AstStructuralRuleEntry] = []
  for entry in entries {
    match
      apply_ast_structural_rule_entry_to_scoped_expr(
        file, entry, scoped_expr, hits,
      ) {
      RuleContinue => child_entries.push(entry)
      RulePrune => ()
    }
  }
  if child_entries.length() == 0 {
    return
  }
  @untyped_ast.visit_node_scoped_expr_children(
    scoped_expr.expr,
    scoped_expr.shadowed_names,
    fn(child) {
      apply_ast_structural_rule_entries_to_scoped_expr(
        file, child_entries, child, hits,
      )
    },
  )
}

///|
fn apply_ast_structural_rule_entry_to_scoped_expr(
  file : String,
  entry : AstStructuralRuleEntry,
  scoped_expr : @untyped_ast.ScopedExprNode,
  hits : Array[RuleFinding],
) -> RuleTraversalAction {
  if !entry.structural.inside_expr.is_empty() {
    apply_inside_expr_ast_bucketed(
      file,
      entry.rule,
      entry.structural,
      entry.inside_pattern_buckets,
      entry.pattern_buckets,
      entry.negative_pattern_buckets,
      scoped_expr.expr,
      hits,
    )
    RuleContinue
  } else if !entry.structural.inside_toplevel.is_empty() {
    RulePrune
  } else {
    apply_ast_patterns_at_node(
      file,
      entry.rule,
      entry.pattern_buckets,
      entry.negative_pattern_buckets,
      scoped_expr.expr,
      None,
      hits,
    )
  }
}

///|
pub fn apply_taint_scan_plan_to_node(
  file : String,
  node : @untyped_ast.Node,
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
  node : @untyped_ast.Node,
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
fn apply_inside_toplevel_ast_bucketed(
  file : String,
  rule : CompiledRule,
  structural : CompiledStructuralRule,
  inside_pattern_buckets : ExprPatternBuckets,
  pattern_buckets : ExprPatternBuckets,
  negative_pattern_buckets : ExprPatternBuckets,
  toplevel : @untyped_ast.Node,
  hits : Array[RuleFinding],
) -> Unit {
  apply_inside_context_ast_bucketed(
    file, rule, structural, inside_pattern_buckets, pattern_buckets, negative_pattern_buckets,
    toplevel, hits,
  )
}

///|
fn apply_inside_expr_ast_bucketed(
  file : String,
  rule : CompiledRule,
  structural : CompiledStructuralRule,
  inside_pattern_buckets : ExprPatternBuckets,
  pattern_buckets : ExprPatternBuckets,
  negative_pattern_buckets : ExprPatternBuckets,
  expr : @untyped_ast.Node,
  hits : Array[RuleFinding],
) -> Unit {
  let context_hits : Array[RuleFinding] = []
  apply_inside_context_ast_bucketed(
    file, rule, structural, inside_pattern_buckets, pattern_buckets, negative_pattern_buckets,
    expr, context_hits,
  )
  if context_hits.get(0) is Some(first) {
    hits.push({
      file: first.file,
      rule_id: first.rule_id,
      description: first.description,
      pattern_index: first.pattern_index,
      loc: expr.loc,
    })
  }
}

///|
fn apply_inside_context_ast_bucketed(
  file : String,
  rule : CompiledRule,
  structural : CompiledStructuralRule,
  inside_pattern_buckets : ExprPatternBuckets,
  pattern_buckets : ExprPatternBuckets,
  negative_pattern_buckets : ExprPatternBuckets,
  context_node : @untyped_ast.Node,
  hits : Array[RuleFinding],
) -> Unit {
  for indexed in inside_pattern_buckets.patterns_for_node(context_node) {
    let inside = indexed.pattern
    if match_node_rule_pattern(inside, context_node, None) is Some(result) {
      if result.bindings.get("__TARGET__") is Some(Single(target)) {
        if structural.patterns.is_empty() {
          let target_exprs : Array[@untyped_ast.ScopedExprNode] = []
          @untyped_ast.collect_node_scoped_exprs(target, target_exprs)
          apply_inside_context_only_ast_bucketed(
            file,
            rule,
            negative_pattern_buckets,
            target_exprs,
            context_node.loc,
            result.bindings,
            inside.compiled.identifier_metavars,
            hits,
          )
        } else {
          match structural.patterns_not_mode {
            RejectUncoveredNegative =>
              apply_ast_bucketed_covered_patterns_in_target_subtree(
                file,
                rule,
                pattern_buckets,
                negative_pattern_buckets,
                target,
                result.bindings,
                inside.compiled.identifier_metavars,
                hits,
              )
            PruneOnNegative =>
              apply_ast_bucketed_patterns_in_target_subtree(
                file,
                rule,
                pattern_buckets,
                negative_pattern_buckets,
                target,
                result.bindings,
                inside.compiled.identifier_metavars,
                hits,
              )
          }
        }
      }
      // Outer alternatives are ordered. Once shape and guards select one,
      // later alternatives are not considered even if the target has no hit.
      return
    }
  }
}

///|
fn apply_ast_bucketed_patterns_in_target_subtree(
  file : String,
  rule : CompiledRule,
  pattern_buckets : ExprPatternBuckets,
  negative_pattern_buckets : ExprPatternBuckets,
  target : @untyped_ast.Node,
  outer_bindings : @hashmap.HashMap[String, @matching.BoundValue],
  inherited_identifier_metavars : Array[String],
  hits : Array[RuleFinding],
) -> Unit {
  @untyped_ast.visit_node_scoped_exprs(target, fn(scoped_expr) {
    match
      apply_ast_bucketed_patterns_at_scoped_expr(
        file, rule, pattern_buckets, negative_pattern_buckets, scoped_expr, outer_bindings,
        inherited_identifier_metavars, hits,
      ) {
      RulePrune => NodeVisitPrune
      RuleContinue => NodeVisitContinue
    }
  })
}

///|
fn apply_ast_bucketed_covered_patterns_in_target_subtree(
  file : String,
  rule : CompiledRule,
  pattern_buckets : ExprPatternBuckets,
  negative_pattern_buckets : ExprPatternBuckets,
  target : @untyped_ast.Node,
  outer_bindings : @hashmap.HashMap[String, @matching.BoundValue],
  inherited_identifier_metavars : Array[String],
  hits : Array[RuleFinding],
) -> Unit {
  let pending_hits : Array[RuleFinding] = []
  let mut rejected = false
  @untyped_ast.visit_node_scoped_exprs(target, fn(scoped_expr) {
    if rejected {
      NodeVisitPrune
    } else {
      match
        apply_ast_bucketed_covered_patterns_at_scoped_expr(
          file, rule, pattern_buckets, negative_pattern_buckets, scoped_expr, outer_bindings,
          inherited_identifier_metavars, pending_hits,
        ) {
        InsideTargetPrune => NodeVisitPrune
        InsideTargetReject => {
          rejected = true
          NodeVisitPrune
        }
        InsideTargetContinue => NodeVisitContinue
      }
    }
  })
  if !rejected && !pending_hits.is_empty() {
    hits.append(pending_hits)
  }
}

///|
fn apply_inside_context_only_ast_bucketed(
  file : String,
  rule : CompiledRule,
  negative_pattern_buckets : ExprPatternBuckets,
  target_exprs : Array[@untyped_ast.ScopedExprNode],
  context_loc : @basic.Location,
  outer_bindings : @hashmap.HashMap[String, @matching.BoundValue],
  inherited_identifier_metavars : Array[String],
  hits : Array[RuleFinding],
) -> Unit {
  if ast_bucketed_negative_patterns_match_any_scoped_expr(
      negative_pattern_buckets, target_exprs, outer_bindings, inherited_identifier_metavars,
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
fn apply_ast_bucketed_covered_patterns_at_scoped_expr(
  file : String,
  rule : CompiledRule,
  pattern_buckets : ExprPatternBuckets,
  negative_pattern_buckets : ExprPatternBuckets,
  scoped_expr : @untyped_ast.ScopedExprNode,
  outer_bindings : @hashmap.HashMap[String, @matching.BoundValue],
  inherited_identifier_metavars : Array[String],
  hits : Array[RuleFinding],
) -> InsideTargetScanAction {
  for indexed in pattern_buckets.patterns_for_node(scoped_expr.expr) {
    if ast_pattern_blocked_by_shadowed_outer_id(
        indexed.pattern,
        outer_bindings,
        inherited_identifier_metavars,
        scoped_expr.shadowed_names,
      ) {
      continue
    }
    if match_node_rule_pattern(
        indexed.pattern,
        scoped_expr.expr,
        Some(outer_bindings),
      )
      is Some(_) {
      hits.push({
        file,
        rule_id: rule.rule_id,
        description: rule.description,
        pattern_index: indexed.pattern_index,
        loc: scoped_expr.expr.loc,
      })
      return InsideTargetPrune
    }
  }
  if ast_bucketed_negative_patterns_match_scoped_expr(
      negative_pattern_buckets, scoped_expr, outer_bindings, inherited_identifier_metavars,
    ) {
    return InsideTargetReject
  }
  InsideTargetContinue
}

///|
fn apply_ast_bucketed_patterns_at_scoped_expr(
  file : String,
  rule : CompiledRule,
  pattern_buckets : ExprPatternBuckets,
  negative_pattern_buckets : ExprPatternBuckets,
  scoped_expr : @untyped_ast.ScopedExprNode,
  outer_bindings : @hashmap.HashMap[String, @matching.BoundValue],
  inherited_identifier_metavars : Array[String],
  hits : Array[RuleFinding],
) -> RuleTraversalAction {
  for indexed in pattern_buckets.patterns_for_node(scoped_expr.expr) {
    if ast_pattern_blocked_by_shadowed_outer_id(
        indexed.pattern,
        outer_bindings,
        inherited_identifier_metavars,
        scoped_expr.shadowed_names,
      ) {
      continue
    }
    if match_node_rule_pattern(
        indexed.pattern,
        scoped_expr.expr,
        Some(outer_bindings),
      )
      is Some(_) {
      hits.push({
        file,
        rule_id: rule.rule_id,
        description: rule.description,
        pattern_index: indexed.pattern_index,
        loc: scoped_expr.expr.loc,
      })
      return RulePrune
    }
  }
  if ast_bucketed_negative_patterns_match_scoped_expr(
      negative_pattern_buckets, scoped_expr, outer_bindings, inherited_identifier_metavars,
    ) {
    return RulePrune
  }
  RuleContinue
}

///|
fn apply_ast_patterns_at_node(
  file : String,
  rule : CompiledRule,
  pattern_buckets : ExprPatternBuckets,
  negative_pattern_buckets : ExprPatternBuckets,
  expr : @untyped_ast.Node,
  initial_bindings : @hashmap.HashMap[String, @matching.BoundValue]?,
  hits : Array[RuleFinding],
) -> RuleTraversalAction {
  for indexed in pattern_buckets.patterns_for_node(expr) {
    if match_node_rule_pattern(indexed.pattern, expr, initial_bindings)
      is Some(_) {
      hits.push({
        file,
        rule_id: rule.rule_id,
        description: rule.description,
        pattern_index: indexed.pattern_index,
        loc: expr.loc,
      })
      return RulePrune
    }
  }
  if ast_negative_patterns_match_node(
      negative_pattern_buckets, expr, initial_bindings,
    ) {
    return RulePrune
  }
  RuleContinue
}

///|
fn ast_negative_patterns_match_node(
  negative_pattern_buckets : ExprPatternBuckets,
  expr : @untyped_ast.Node,
  initial_bindings : @hashmap.HashMap[String, @matching.BoundValue]?,
) -> Bool {
  for indexed in negative_pattern_buckets.patterns_for_node(expr) {
    if match_node_rule_pattern(indexed.pattern, expr, initial_bindings)
      is Some(_) {
      return true
    }
  }
  false
}

///|
fn ast_bucketed_negative_patterns_match_scoped_expr(
  negative_pattern_buckets : ExprPatternBuckets,
  scoped_expr : @untyped_ast.ScopedExprNode,
  initial_bindings : @hashmap.HashMap[String, @matching.BoundValue],
  inherited_identifier_metavars : Array[String],
) -> Bool {
  for indexed in negative_pattern_buckets.patterns_for_node(scoped_expr.expr) {
    if ast_pattern_blocked_by_shadowed_outer_id(
        indexed.pattern,
        initial_bindings,
        inherited_identifier_metavars,
        scoped_expr.shadowed_names,
      ) {
      continue
    }
    if match_node_rule_pattern(
        indexed.pattern,
        scoped_expr.expr,
        Some(initial_bindings),
      )
      is Some(_) {
      return true
    }
  }
  false
}

///|
fn ast_bucketed_negative_patterns_match_any_scoped_expr(
  negative_pattern_buckets : ExprPatternBuckets,
  target_exprs : Array[@untyped_ast.ScopedExprNode],
  initial_bindings : @hashmap.HashMap[String, @matching.BoundValue],
  inherited_identifier_metavars : Array[String],
) -> Bool {
  for scoped_expr in target_exprs {
    if ast_bucketed_negative_patterns_match_scoped_expr(
        negative_pattern_buckets, scoped_expr, initial_bindings, inherited_identifier_metavars,
      ) {
      return true
    }
  }
  false
}

///|
fn ast_pattern_blocked_by_shadowed_outer_id(
  pattern : CompiledRulePattern,
  outer_bindings : @hashmap.HashMap[String, @matching.BoundValue],
  inherited_identifier_metavars : Array[String],
  shadowed_names : Array[String],
) -> Bool {
  for metavar in inherited_identifier_metavars {
    if names_contain(pattern.compiled.identifier_metavars, metavar) {
      if outer_bindings.get(metavar) is Some(Single(bound_node)) {
        if node_leaf_string(bound_node) is Some(bound_name) &&
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
fn match_node_rule_pattern(
  pattern : CompiledRulePattern,
  expr : @untyped_ast.Node,
  initial_bindings : @hashmap.HashMap[String, @matching.BoundValue]?,
) -> @matching.ExprMatch? {
  let matched = if initial_bindings is Some(bindings) {
    @matching.match_expr_pattern_with_bindings(pattern.compiled, expr, bindings)
  } else {
    @matching.match_expr_pattern(pattern.compiled, expr)
  }
  match matched {
    Some(result) if ast_guards_match(pattern.guards, result.bindings) =>
      Some(result)
    _ => None
  }
}

///|
fn ast_guards_match(
  guards : Array[CompiledRuleGuard],
  bindings : @hashmap.HashMap[String, @matching.BoundValue],
) -> Bool {
  for guard_entry in guards {
    match guard_entry.capture_kind {
      IdentifierGuard =>
        match bindings.get(guard_entry.name) {
          Some(Single(value)) => {
            guard node_leaf_string(value) is Some(text) else { return false }
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
fn constant_guard_value(constant : @untyped_ast.Node) -> String? {
  match constant.kind {
    Constant_Bool =>
      if node_leaf_bool_child(constant, "value") is Some(value) {
        Some(value.to_string())
      } else {
        None
      }
    Constant_BigInt
    | Constant_Byte
    | Constant_Bytes
    | Constant_Char
    | Constant_Double
    | Constant_Float
    | Constant_Int
    | Constant_Int64
    | Constant_Regex
    | Constant_String
    | Constant_UInt
    | Constant_UInt64 => node_leaf_string_child(constant, "value")
    _ => None
  }
}

///|
fn node_child(node : @untyped_ast.Node, name : String) -> @untyped_ast.Node? {
  for entry in node.children {
    let (child_name, value) = entry
    if child_name == Some(name) {
      return Some(value)
    }
  }
  None
}

///|
fn node_leaf_string(node : @untyped_ast.Node) -> String? {
  match node.kind {
    Leaf(PString(value)) => Some(value)
    _ => None
  }
}

///|
fn node_leaf_bool(node : @untyped_ast.Node) -> Bool? {
  match node.kind {
    Leaf(PBool(value)) => Some(value)
    _ => None
  }
}

///|
fn node_leaf_string_child(node : @untyped_ast.Node, name : String) -> String? {
  if node_child(node, name) is Some(value) {
    node_leaf_string(value)
  } else {
    None
  }
}

///|
fn node_leaf_bool_child(node : @untyped_ast.Node, name : String) -> Bool? {
  if node_child(node, name) is Some(value) {
    node_leaf_bool(value)
  } else {
    None
  }
}
