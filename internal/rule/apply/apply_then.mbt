///|
priv struct CaptureEnvironment {
  bindings : @hashmap.HashMap[String, @bound_value_model.BoundValue]
  identifiers : Map[String, String]
  blocked : Map[String, Bool]
}

///|
fn empty_capture_environment() -> CaptureEnvironment {
  { bindings: @hashmap.HashMap([]), identifiers: {}, blocked: {}, }
}

///|
fn shadow_environment(
  env : CaptureEnvironment,
  names : Array[String],
) -> CaptureEnvironment {
  let blocked = env.blocked.copy()
  for capture, name in env.identifiers {
    if names_contain(names, name) {
      blocked[capture] = true
    }
  }
  { ..env, blocked, }
}

///|
fn environment_blocks(
  pattern : CompiledRulePattern,
  env : CaptureEnvironment,
) -> Bool {
  for name, _ in env.blocked {
    if pattern.compiled.metavars.kind_of(name) is Some(_) {
      return true
    }
    for guard_entry in pattern.guards {
      if guard_entry.name == name {
        return true
      }
    }
  }
  false
}

///|
fn target_environment(
  pattern : CompiledRulePattern,
  candidate : @cst.ExprMatchCandidate,
  target : @cst.ExprMatchCandidate,
  result : @matching.ExprMatch,
  env : CaptureEnvironment,
) -> CaptureEnvironment {
  // Only existing captures are shadowed along the shape-to-target path.
  // Captures introduced by this shape begin their scope at its target.
  let inherited = shadow_environment(
    env,
    @cst.names_introduced_to_target(candidate, target),
  )
  let identifiers = inherited.identifiers.copy()
  for name in pattern.compiled.metavars.names(Identifier) {
    if !identifiers.contains(name) &&
      result.bindings.get(name) is Some(Single(node)) &&
      @cst.normalized_name(node) is Some(text) {
      identifiers[name] = text
    }
  }
  let bindings = result.bindings.copy()
  bindings.remove("__TARGET__")
  { bindings, identifiers, blocked: inherited.blocked, }
}

///|
priv enum GroupCandidateResult {
  GroupHit(Int, @basic.Location)
  GroupNegative
  GroupMiss
}

///|
fn evaluate_group_candidate(
  group : PlannedStructuralGroup,
  candidate : @cst.ExprMatchCandidate,
  env : CaptureEnvironment,
) -> GroupCandidateResult {
  for indexed in group.positive.patterns_for_candidate(candidate) {
    let pattern = indexed.pattern
    if environment_blocks(pattern, env) {
      continue
    }
    guard match_candidate_rule_pattern(pattern, candidate, Some(env.bindings))
      is Some(result) else {
      continue
    }
    if group.children[indexed.pattern_index] is Some(body) {
      guard result.bindings.get("__TARGET__") is Some(bound) else { continue }
      let target = inside_target_match_candidate(candidate, bound)
      let child_env = target_environment(
        pattern, candidate, target, result, env,
      )
      if !scan_structural_group(
          body,
          target,
          child_env,
          fn(_, _) { () },
          existence_only=true,
        ) {
        continue
      }
    }
    return GroupHit(indexed.pattern_index, result.loc)
  }
  for indexed in group.negative.patterns_for_candidate(candidate) {
    if !environment_blocks(indexed.pattern, env) &&
      match_candidate_rule_pattern(
        indexed.pattern,
        candidate,
        Some(env.bindings),
      )
      is Some(_) {
      return GroupNegative
    }
  }
  GroupMiss
}

///|
// Findings are staged until every uncovered region satisfies the negatives.
fn scan_structural_group(
  group : PlannedStructuralGroup,
  target : @cst.ExprMatchCandidate,
  env : CaptureEnvironment,
  publish : (Int, @basic.Location) -> Unit,
  existence_only? : Bool = false,
) -> Bool {
  let pending : Array[(Int, @basic.Location)] = []
  let mut rejected = false
  @cst.visit_scoped_expr_match_candidate(target, [], fn(scoped) {
    match
      evaluate_group_candidate(
        group,
        scoped.candidate,
        shadow_environment(env, scoped.shadowed_names),
      ) {
      GroupHit(index, loc) => {
        pending.push((index, loc))
        if existence_only && !group.has_negative {
          @cst.NodeVisitReturn
        } else {
          @cst.NodeVisitPrune
        }
      }
      GroupNegative =>
        if group.reject_negative || !group.has_positive {
          rejected = true
          @cst.NodeVisitReturn
        } else {
          @cst.NodeVisitPrune
        }
      GroupMiss => @cst.NodeVisitContinue
    }
  })
  if rejected || (group.has_positive && pending.is_empty()) {
    return false
  }
  for hit in pending {
    publish(hit.0, hit.1)
  }
  true
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
fn apply_toplevel_group(
  file : String,
  entry : CstStructuralRuleEntry,
  node : @untyped_cst.CstNode,
  hits : Array[RuleFinding],
) -> Unit {
  let candidate = @cst.Direct(node)
  for indexed in entry.inside_pattern_buckets.patterns_for_candidate(candidate) {
    let pattern = indexed.pattern
    if match_candidate_rule_pattern(pattern, candidate, None) is Some(result) {
      if result.bindings.get("__TARGET__") is Some(bound) {
        let target = inside_target_match_candidate(candidate, bound)
        let env = target_environment(
          pattern,
          candidate,
          target,
          result,
          empty_capture_environment(),
        )
        let success = scan_structural_group(entry.group, target, env, fn(
          index,
          loc,
        ) {
          push_structural_hit(file, entry.rule, index, loc, hits)
        })
        if success && !entry.group.has_positive {
          push_structural_hit(file, entry.rule, 0, result.loc, hits)
        }
      }
      return
    }
  }
}
