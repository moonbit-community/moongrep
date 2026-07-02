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
using @taint_lowering {lower_compiled_taint_rule_with_matcher}

///|
using @traverse {collect_scoped_exprs, type ScopedExpr}

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
  inside_root_key : String?
  matcher_mode : @matching.MatcherMode
}

///|
/// Applies only structural rules to the supplied parser AST nodes.
///
/// Supported expression subtrees collected by `collect_impl_exprs` and
/// `collect_exprs` are visited in source-tree order. For a single expression
/// and rule, the first matching pattern wins and determines `pattern_index`.
pub fn apply_structural_rules(
  file : String,
  impls : @list.List[@syntax.Impl],
  rules : Array[CompiledRule],
) -> Array[RuleFinding] {
  apply_structural_rules_with_matcher(file, impls, rules, @matching.AstMatcher)
}

///|
pub fn apply_structural_rules_with_matcher(
  file : String,
  impls : @list.List[@syntax.Impl],
  rules : Array[CompiledRule],
  matcher_mode : @matching.MatcherMode,
) -> Array[RuleFinding] {
  let hits : Array[RuleFinding] = []
  for node in impls {
    let node_hits = apply_structural_rules_to_impl_with_matcher(
      file, node, rules, matcher_mode,
    )
    for hit in node_hits {
      hits.push(hit)
    }
  }
  hits
}

///|
pub fn apply_structural_rules_to_impl(
  file : String,
  node : @syntax.Impl,
  rules : Array[CompiledRule],
) -> Array[RuleFinding] {
  apply_structural_rules_to_impl_with_matcher(
    file,
    node,
    rules,
    @matching.AstMatcher,
  )
}

///|
pub fn apply_structural_rules_to_impl_with_matcher(
  file : String,
  node : @syntax.Impl,
  rules : Array[CompiledRule],
  matcher_mode : @matching.MatcherMode,
) -> Array[RuleFinding] {
  let hits : Array[RuleFinding] = []
  let entries = ast_structural_rule_entries(rules, matcher_mode)
  @traverse.visit_impl_scoped_expr_roots(node, fn(scoped_expr) {
    apply_ast_structural_rule_entries_to_scoped_expr(
      file, entries, scoped_expr, hits,
    )
  })
  hits
}

///|
fn ast_structural_rule_entries(
  rules : Array[CompiledRule],
  matcher_mode : @matching.MatcherMode,
) -> Array[AstStructuralRuleEntry] {
  let entries : Array[AstStructuralRuleEntry] = []
  for rule in rules {
    match rule.definition {
      Structural(structural) => {
        let inside_root_key = if structural.inside_expr is Some(inside) {
          Some(compiled_pattern_root_key(inside))
        } else {
          None
        }
        entries.push({
          rule,
          structural,
          pattern_buckets: ExprPatternBuckets::from_patterns(
            structural.patterns,
          ),
          negative_pattern_buckets: ExprPatternBuckets::from_patterns(
            structural.patterns_not,
          ),
          inside_root_key,
          matcher_mode,
        })
      }
      _ => ()
    }
  }
  entries
}

///|
fn apply_ast_structural_rule_entries_to_scoped_expr(
  file : String,
  entries : Array[AstStructuralRuleEntry],
  scoped_expr : ScopedExpr,
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
  @traverse.visit_scoped_expr_children(scoped_expr, fn(child) {
    apply_ast_structural_rule_entries_to_scoped_expr(
      file, child_entries, child, hits,
    )
  })
}

///|
fn apply_ast_structural_rule_entry_to_scoped_expr(
  file : String,
  entry : AstStructuralRuleEntry,
  scoped_expr : ScopedExpr,
  hits : Array[RuleFinding],
) -> RuleTraversalAction {
  if entry.structural.inside_expr is Some(inside) {
    let inside_root_key = if entry.inside_root_key is Some(key) {
      key
    } else {
      ast_bucket_wildcard_key()
    }
    apply_inside_expr_ast_bucketed(
      file,
      entry.rule,
      entry.structural,
      inside,
      inside_root_key,
      entry.pattern_buckets,
      entry.negative_pattern_buckets,
      scoped_expr.expr,
      hits,
      entry.matcher_mode,
    )
    RuleContinue
  } else {
    apply_ast_patterns_at_expr(
      file,
      entry.rule,
      entry.pattern_buckets,
      entry.negative_pattern_buckets,
      scoped_expr.expr,
      None,
      None,
      hits,
      entry.matcher_mode,
    )
  }
}

///|
/// Applies only taint rules to function-like parser AST nodes.
///
/// Unsupported top-level nodes are ignored. Other taint-analysis errors are
/// propagated to the caller.
pub fn apply_taint_rules(
  file : String,
  impls : @list.List[@syntax.Impl],
  rules : Array[CompiledRule],
) -> Array[RuleFinding] raise {
  apply_taint_rules_with_matcher(file, impls, rules, @matching.AstMatcher)
}

///|
pub fn apply_taint_rules_with_matcher(
  file : String,
  impls : @list.List[@syntax.Impl],
  rules : Array[CompiledRule],
  matcher_mode : @matching.MatcherMode,
) -> Array[RuleFinding] raise {
  let hits : Array[RuleFinding] = []
  for node in impls {
    let node_hits = apply_taint_rules_to_impl_with_matcher(
      file, node, rules, matcher_mode,
    )
    for hit in node_hits {
      hits.push(hit)
    }
  }
  hits
}

///|
pub fn apply_taint_rules_to_impl(
  file : String,
  node : @syntax.Impl,
  rules : Array[CompiledRule],
) -> Array[RuleFinding] raise {
  apply_taint_rules_to_impl_with_matcher(
    file,
    node,
    rules,
    @matching.AstMatcher,
  )
}

///|
pub fn apply_taint_rules_to_impl_with_matcher(
  file : String,
  node : @syntax.Impl,
  rules : Array[CompiledRule],
  matcher_mode : @matching.MatcherMode,
) -> Array[RuleFinding] raise {
  let hits : Array[RuleFinding] = []
  for rule in rules {
    match rule.definition {
      Taint(taint_rule) =>
        apply_taint_rule_to_impl(
          file, rule, taint_rule, node, hits, matcher_mode,
        )
      _ => ()
    }
  }
  hits
}

///|
fn apply_taint_rule_to_impl(
  file : String,
  rule : CompiledRule,
  taint_rule : CompiledTaintRule,
  node : @syntax.Impl,
  hits : Array[RuleFinding],
  matcher_mode : @matching.MatcherMode,
) -> Unit raise {
  let spec = lower_compiled_taint_rule_with_matcher(
    rule, taint_rule, matcher_mode,
  )
  try @taint.analyze_function_like(node, spec) catch {
    @taint.TaintAnalysisError::UnsupportedFunctionLike(..) => ()
    err => raise err
  } noraise {
    result =>
      for finding in result.findings {
        hits.push({
          file,
          rule_id: rule.rule_id,
          description: rule.description,
          pattern_index: sink_pattern_index(taint_rule, finding.sink_id),
          loc: finding.sink_loc,
          outer_loc: None,
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
fn apply_inside_expr_ast_bucketed(
  file : String,
  rule : CompiledRule,
  structural : CompiledStructuralRule,
  inside : CompiledRulePattern,
  inside_root_key : String,
  pattern_buckets : ExprPatternBuckets,
  negative_pattern_buckets : ExprPatternBuckets,
  expr : @syntax.Expr,
  hits : Array[RuleFinding],
  matcher_mode : @matching.MatcherMode,
) -> Unit {
  if !ast_bucket_root_key_matches(inside_root_key, expr) {
    return
  }
  if match_ast_rule_pattern(inside, expr, None, matcher_mode) is Some(result) {
    if result.bindings.get("__TARGET__")
      is Some(@matching.BoundValue::Expr(target)) {
      if structural.patterns.is_empty() {
        let target_exprs : Array[ScopedExpr] = []
        collect_scoped_exprs(target, target_exprs)
        apply_inside_expr_only_ast_bucketed(
          file,
          rule,
          negative_pattern_buckets,
          target_exprs,
          expr.loc(),
          result.bindings,
          inside.compiled.identifier_metavars,
          hits,
          matcher_mode,
        )
      } else {
        match structural.patterns_not_mode {
          @model.StructuralPatternsNotMode::RejectUncoveredNegative =>
            apply_ast_bucketed_covered_patterns_in_target_subtree(
              file,
              rule,
              pattern_buckets,
              negative_pattern_buckets,
              target,
              Some(expr.loc()),
              result.bindings,
              inside.compiled.identifier_metavars,
              hits,
              matcher_mode,
            )
          @model.StructuralPatternsNotMode::PruneOnNegative =>
            apply_ast_bucketed_patterns_in_target_subtree(
              file,
              rule,
              pattern_buckets,
              negative_pattern_buckets,
              target,
              Some(expr.loc()),
              result.bindings,
              inside.compiled.identifier_metavars,
              hits,
              matcher_mode,
            )
        }
      }
    }
  }
}

///|
fn apply_ast_bucketed_patterns_in_target_subtree(
  file : String,
  rule : CompiledRule,
  pattern_buckets : ExprPatternBuckets,
  negative_pattern_buckets : ExprPatternBuckets,
  target : @syntax.Expr,
  outer_loc : @basic.Location?,
  outer_bindings : @hashmap.HashMap[String, @matching.BoundValue],
  inherited_identifier_metavars : Array[String],
  hits : Array[RuleFinding],
  matcher_mode : @matching.MatcherMode,
) -> Unit {
  @traverse.visit_scoped_exprs(target, fn(scoped_expr) {
    match
      apply_ast_bucketed_patterns_at_scoped_expr(
        file, rule, pattern_buckets, negative_pattern_buckets, scoped_expr, outer_loc,
        outer_bindings, inherited_identifier_metavars, hits, matcher_mode,
      ) {
      RulePrune => @traverse.ScopedExprVisitAction::VisitPrune
      RuleContinue => @traverse.ScopedExprVisitAction::VisitContinue
    }
  })
}

///|
fn apply_ast_bucketed_covered_patterns_in_target_subtree(
  file : String,
  rule : CompiledRule,
  pattern_buckets : ExprPatternBuckets,
  negative_pattern_buckets : ExprPatternBuckets,
  target : @syntax.Expr,
  outer_loc : @basic.Location?,
  outer_bindings : @hashmap.HashMap[String, @matching.BoundValue],
  inherited_identifier_metavars : Array[String],
  hits : Array[RuleFinding],
  matcher_mode : @matching.MatcherMode,
) -> Unit {
  let pending_hits : Array[RuleFinding] = []
  let mut rejected = false
  @traverse.visit_scoped_exprs(target, fn(scoped_expr) {
    if rejected {
      @traverse.ScopedExprVisitAction::VisitPrune
    } else {
      match
        apply_ast_bucketed_covered_patterns_at_scoped_expr(
          file, rule, pattern_buckets, negative_pattern_buckets, scoped_expr, outer_loc,
          outer_bindings, inherited_identifier_metavars, pending_hits, matcher_mode,
        ) {
        InsideTargetPrune => @traverse.ScopedExprVisitAction::VisitPrune
        InsideTargetReject => {
          rejected = true
          @traverse.ScopedExprVisitAction::VisitPrune
        }
        InsideTargetContinue => @traverse.ScopedExprVisitAction::VisitContinue
      }
    }
  })
  if !rejected && !pending_hits.is_empty() {
    hits.append(pending_hits)
  }
}

///|
fn apply_inside_expr_only_ast_bucketed(
  file : String,
  rule : CompiledRule,
  negative_pattern_buckets : ExprPatternBuckets,
  target_exprs : Array[ScopedExpr],
  outer_loc : @basic.Location,
  outer_bindings : @hashmap.HashMap[String, @matching.BoundValue],
  inherited_identifier_metavars : Array[String],
  hits : Array[RuleFinding],
  matcher_mode : @matching.MatcherMode,
) -> Unit {
  if ast_bucketed_negative_patterns_match_any_scoped_expr(
      negative_pattern_buckets, target_exprs, outer_bindings, inherited_identifier_metavars,
      matcher_mode,
    ) {
    return
  }
  push_inside_expr_only_hit(file, rule, outer_loc, hits)
}

///|
fn push_inside_expr_only_hit(
  file : String,
  rule : CompiledRule,
  outer_loc : @basic.Location,
  hits : Array[RuleFinding],
) -> Unit {
  hits.push({
    file,
    rule_id: rule.rule_id,
    description: rule.description,
    pattern_index: 0,
    loc: outer_loc,
    outer_loc: Some(outer_loc),
  })
}

///|
fn apply_ast_bucketed_covered_patterns_at_scoped_expr(
  file : String,
  rule : CompiledRule,
  pattern_buckets : ExprPatternBuckets,
  negative_pattern_buckets : ExprPatternBuckets,
  scoped_expr : ScopedExpr,
  outer_loc : @basic.Location?,
  outer_bindings : @hashmap.HashMap[String, @matching.BoundValue],
  inherited_identifier_metavars : Array[String],
  hits : Array[RuleFinding],
  matcher_mode : @matching.MatcherMode,
) -> InsideTargetScanAction {
  for indexed in pattern_buckets.patterns_for_expr(scoped_expr.expr) {
    if ast_pattern_blocked_by_shadowed_outer_id(
        indexed.pattern,
        outer_bindings,
        inherited_identifier_metavars,
        scoped_expr.shadowed_names,
      ) {
      continue
    }
    if match_ast_rule_pattern(
        indexed.pattern,
        scoped_expr.expr,
        Some(outer_bindings),
        matcher_mode,
      )
      is Some(_) {
      hits.push({
        file,
        rule_id: rule.rule_id,
        description: rule.description,
        pattern_index: indexed.pattern_index,
        loc: scoped_expr.expr.loc(),
        outer_loc,
      })
      return InsideTargetPrune
    }
  }
  if ast_bucketed_negative_patterns_match_scoped_expr(
      negative_pattern_buckets, scoped_expr, outer_bindings, inherited_identifier_metavars,
      matcher_mode,
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
  scoped_expr : ScopedExpr,
  outer_loc : @basic.Location?,
  outer_bindings : @hashmap.HashMap[String, @matching.BoundValue],
  inherited_identifier_metavars : Array[String],
  hits : Array[RuleFinding],
  matcher_mode : @matching.MatcherMode,
) -> RuleTraversalAction {
  for indexed in pattern_buckets.patterns_for_expr(scoped_expr.expr) {
    if ast_pattern_blocked_by_shadowed_outer_id(
        indexed.pattern,
        outer_bindings,
        inherited_identifier_metavars,
        scoped_expr.shadowed_names,
      ) {
      continue
    }
    if match_ast_rule_pattern(
        indexed.pattern,
        scoped_expr.expr,
        Some(outer_bindings),
        matcher_mode,
      )
      is Some(_) {
      hits.push({
        file,
        rule_id: rule.rule_id,
        description: rule.description,
        pattern_index: indexed.pattern_index,
        loc: scoped_expr.expr.loc(),
        outer_loc,
      })
      return RulePrune
    }
  }
  if ast_bucketed_negative_patterns_match_scoped_expr(
      negative_pattern_buckets, scoped_expr, outer_bindings, inherited_identifier_metavars,
      matcher_mode,
    ) {
    return RulePrune
  }
  RuleContinue
}

///|
fn apply_ast_patterns_at_expr(
  file : String,
  rule : CompiledRule,
  pattern_buckets : ExprPatternBuckets,
  negative_pattern_buckets : ExprPatternBuckets,
  expr : @syntax.Expr,
  outer_loc : @basic.Location?,
  initial_bindings : @hashmap.HashMap[String, @matching.BoundValue]?,
  hits : Array[RuleFinding],
  matcher_mode : @matching.MatcherMode,
) -> RuleTraversalAction {
  for indexed in pattern_buckets.patterns_for_expr(expr) {
    if match_ast_rule_pattern(
        indexed.pattern,
        expr,
        initial_bindings,
        matcher_mode,
      )
      is Some(_) {
      hits.push({
        file,
        rule_id: rule.rule_id,
        description: rule.description,
        pattern_index: indexed.pattern_index,
        loc: expr.loc(),
        outer_loc,
      })
      return RulePrune
    }
  }
  if ast_negative_patterns_match_expr(
      negative_pattern_buckets, expr, initial_bindings, matcher_mode,
    ) {
    return RulePrune
  }
  RuleContinue
}

///|
fn ast_negative_patterns_match_expr(
  negative_pattern_buckets : ExprPatternBuckets,
  expr : @syntax.Expr,
  initial_bindings : @hashmap.HashMap[String, @matching.BoundValue]?,
  matcher_mode : @matching.MatcherMode,
) -> Bool {
  for indexed in negative_pattern_buckets.patterns_for_expr(expr) {
    if match_ast_rule_pattern(
        indexed.pattern,
        expr,
        initial_bindings,
        matcher_mode,
      )
      is Some(_) {
      return true
    }
  }
  false
}

///|
fn ast_bucketed_negative_patterns_match_scoped_expr(
  negative_pattern_buckets : ExprPatternBuckets,
  scoped_expr : ScopedExpr,
  initial_bindings : @hashmap.HashMap[String, @matching.BoundValue],
  inherited_identifier_metavars : Array[String],
  matcher_mode : @matching.MatcherMode,
) -> Bool {
  for indexed in negative_pattern_buckets.patterns_for_expr(scoped_expr.expr) {
    if ast_pattern_blocked_by_shadowed_outer_id(
        indexed.pattern,
        initial_bindings,
        inherited_identifier_metavars,
        scoped_expr.shadowed_names,
      ) {
      continue
    }
    if match_ast_rule_pattern(
        indexed.pattern,
        scoped_expr.expr,
        Some(initial_bindings),
        matcher_mode,
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
  target_exprs : Array[ScopedExpr],
  initial_bindings : @hashmap.HashMap[String, @matching.BoundValue],
  inherited_identifier_metavars : Array[String],
  matcher_mode : @matching.MatcherMode,
) -> Bool {
  for scoped_expr in target_exprs {
    if ast_bucketed_negative_patterns_match_scoped_expr(
        negative_pattern_buckets, scoped_expr, initial_bindings, inherited_identifier_metavars,
        matcher_mode,
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
      if outer_bindings.get(metavar)
        is Some(@matching.BoundValue::Identifier(bound_name)) {
        if names_contain(shadowed_names, bound_name) {
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
fn match_ast_rule_pattern(
  pattern : CompiledRulePattern,
  expr : @syntax.Expr,
  initial_bindings : @hashmap.HashMap[String, @matching.BoundValue]?,
  matcher_mode : @matching.MatcherMode,
) -> @matching.ExprMatch? {
  let matched = if initial_bindings is Some(bindings) {
    @matching.match_expr_pattern_with_bindings_with_mode(
      pattern.compiled,
      expr,
      bindings,
      matcher_mode,
    )
  } else {
    @matching.match_expr_pattern_with_mode(pattern.compiled, expr, matcher_mode)
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
      @model.RuleGuardCaptureKind::IdentifierGuard =>
        match bindings.get(guard_entry.name) {
          Some(Identifier(value)) =>
            if guard_entry.regex.execute(value) is None {
              return false
            }
          _ => return false
        }
      @model.RuleGuardCaptureKind::ConstantGuard =>
        match bindings.get(guard_entry.name) {
          Some(Constant(value)) =>
            if guard_entry.regex.execute(constant_guard_value(value)) is None {
              return false
            }
          _ => return false
        }
    }
  }
  true
}

///|
fn constant_guard_value(constant : @syntax.Constant) -> String {
  match constant {
    BigInt(value)
    | Byte(value)
    | Bytes(value)
    | Char(value)
    | Double(value)
    | Float(value)
    | Int(value)
    | Int64(value)
    | Regex(value)
    | String(value)
    | UInt(value)
    | UInt64(value) => value
    Bool(value) => value.to_string()
  }
}
