///|
priv enum InsideTargetScanAction {
  InsideTargetContinue
  InsideTargetPrune
  InsideTargetReject
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
  target : @bound_value_model.BoundValue,
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
  outer_bindings : @hashmap.HashMap[String, @bound_value_model.BoundValue],
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
  outer_bindings : @hashmap.HashMap[String, @bound_value_model.BoundValue],
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
  outer_bindings : @hashmap.HashMap[String, @bound_value_model.BoundValue],
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
  outer_bindings : @hashmap.HashMap[String, @bound_value_model.BoundValue],
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
  outer_bindings : @hashmap.HashMap[String, @bound_value_model.BoundValue],
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
