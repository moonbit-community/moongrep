///|
fn apply_cst_patterns_at_candidate(
  file : String,
  rule : CompiledRule,
  pattern_buckets : ExprPatternBuckets,
  negative_pattern_buckets : ExprPatternBuckets,
  candidate : @cst.ExprMatchCandidate,
  initial_bindings : @hashmap.HashMap[String, @bound_value_model.BoundValue]?,
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
  initial_bindings : @hashmap.HashMap[String, @bound_value_model.BoundValue]?,
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
  initial_bindings : @hashmap.HashMap[String, @bound_value_model.BoundValue],
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
  initial_bindings : @hashmap.HashMap[String, @bound_value_model.BoundValue],
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
  outer_bindings : @hashmap.HashMap[String, @bound_value_model.BoundValue],
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
  initial_bindings : @hashmap.HashMap[String, @bound_value_model.BoundValue]?,
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
  bindings : @hashmap.HashMap[String, @bound_value_model.BoundValue],
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
