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
