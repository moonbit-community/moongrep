///|
fn eval_if(
  cond : @untyped_cst.CstNode,
  ifso : @untyped_cst.CstNode,
  ifnot : @untyped_cst.CstNode?,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  let cond_result = eval_condition_scope(cond, state, spec, findings)
  match cond_result.normal {
    Some(path) => {
      let then_result = restore_result_scoped_roots(
        eval_expr(ifso, path.true_state, spec, findings),
        path.base_state,
        path.bound_roots,
      )
      let else_result = match ifnot {
        Some(expr) => eval_expr(expr, path.base_state, spec, findings)
        None => normal_result(path.base_state, [])
      }
      flow_join(
        cond_result.exits,
        merge_branch_results(then_result, else_result),
      )
    }
    None => cond_result.exits
  }
}

///|
fn merge_branch_results(
  then_result : EvalResult,
  else_result : EvalResult,
) -> EvalResult {
  flow_join(then_result, else_result)
}

///|
fn eval_guard(
  cond : @untyped_cst.CstNode,
  otherwise : @untyped_cst.CstNode?,
  body : @untyped_cst.CstNode,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  let cond_result = eval_condition_scope(cond, state, spec, findings)
  match cond_result.normal {
    Some(path) => {
      let body_result = restore_result_scoped_roots(
        eval_expr(body, path.true_state, spec, findings),
        path.base_state,
        path.bound_roots,
      )
      let else_result = match otherwise {
        Some(expr) => eval_expr(expr, path.base_state, spec, findings)
        None => normal_result(path.base_state, [])
      }
      flow_join(
        cond_result.exits,
        merge_branch_results(body_result, else_result),
      )
    }
    None => cond_result.exits
  }
}

///|
fn eval_match(
  scrutinee : @untyped_cst.CstNode,
  cases : Array[@untyped_cst.CstNode],
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  let scrutinee_result = eval_expr(scrutinee, state, spec, findings)
  match scrutinee_result.normal {
    Some(path) => {
      let mut branches = empty_flow_summary()
      for case in cases {
        branches = flow_join(
          branches,
          eval_pattern_case(case, path.value, path.state, spec, findings),
        )
      }
      if cases.is_empty() {
        branches = normal_result(path.state, [])
      }
      flow_sequence(scrutinee_result, branches)
    }
    None => scrutinee_result
  }
}

///|
fn eval_pattern_case(
  case : @untyped_cst.CstNode,
  value : TaintTree,
  base_state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  let pattern = if node_child(case, "pattern") is Some(pattern) {
    pattern
  } else {
    return normal_result(base_state, [])
  }
  let body = if node_child(case, "body") is Some(body) {
    body
  } else {
    return normal_result(base_state, [])
  }
  let roots = pattern_bound_roots(pattern)
  let bound = bind_pattern(pattern, value, base_state)
  let result = if node_optional_child(case, "guard") is Some(guard_expr) {
    let guard_result = eval_condition_scope(guard_expr, bound, spec, findings)
    match guard_result.normal {
      Some(path) =>
        flow_join(
          guard_result.exits,
          restore_result_scoped_roots(
            eval_expr(body, path.true_state, spec, findings),
            path.base_state,
            path.bound_roots,
          ),
        )
      None => guard_result.exits
    }
  } else {
    eval_expr(body, bound, spec, findings)
  }
  restore_result_scoped_roots(result, base_state, roots)
}

///|
fn eval_lex_match(
  scrutinee : @untyped_cst.CstNode,
  cases : Array[@untyped_cst.CstNode],
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  let scrutinee_result = eval_expr(scrutinee, state, spec, findings)
  match scrutinee_result.normal {
    Some(path) => {
      let mut branches = empty_flow_summary()
      for case in cases {
        branches = flow_join(
          branches,
          eval_lex_case(case, path.value, path.state, spec, findings),
        )
      }
      if cases.is_empty() {
        branches = normal_result(path.state, [])
      }
      flow_sequence(scrutinee_result, branches)
    }
    None => scrutinee_result
  }
}

///|
fn eval_lex_case(
  case : @untyped_cst.CstNode,
  value : TaintTree,
  base_state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  let patterns = if node_child(case, "pat") is Some(pattern) {
    lex_top_pattern_items(pattern)
  } else {
    []
  }
  let pattern_result = eval_lex_top_pattern_exprs(
    patterns, base_state, spec, findings,
  )
  match pattern_result.normal {
    Some(pattern_path) => {
      let body = match node_child(case, "body") {
        Some(body) => body
        None =>
          return flow_with_normal(
            pattern_result,
            Some({ state: pattern_path.state, value: [], }),
          )
      }
      let roots = lex_top_patterns_bound_roots(patterns)
      let bound = bind_lex_top_patterns(patterns, value, pattern_path.state)
      let result = if node_optional_child(case, "guard") is Some(guard_expr) {
        let guard_result = eval_condition_scope(
          guard_expr, bound, spec, findings,
        )
        match guard_result.normal {
          Some(path) =>
            flow_join(
              guard_result.exits,
              restore_result_scoped_roots(
                eval_expr(body, path.true_state, spec, findings),
                path.base_state,
                path.bound_roots,
              ),
            )
          None => guard_result.exits
        }
      } else {
        eval_expr(body, bound, spec, findings)
      }
      flow_sequence(
        pattern_result,
        restore_result_scoped_roots(result, pattern_path.state, roots),
      )
    }
    None => pattern_result
  }
}

///|
fn eval_lex_scan(
  scrutinee : @untyped_cst.CstNode,
  cases : Array[@untyped_cst.CstNode],
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  let scrutinee_result = eval_expr(scrutinee, state, spec, findings)
  match scrutinee_result.normal {
    Some(path) => {
      let mut branches = empty_flow_summary()
      for case in cases {
        branches = flow_join(
          branches,
          eval_lex_scan_case(case, path.value, path.state, spec, findings),
        )
      }
      if cases.is_empty() {
        branches = normal_result(path.state, [])
      }
      flow_sequence(scrutinee_result, branches)
    }
    None => scrutinee_result
  }
}

///|
fn eval_lex_scan_case(
  case : @untyped_cst.CstNode,
  value : TaintTree,
  base_state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  let pattern = if node_child(case, "pat") is Some(pattern) {
    pattern
  } else {
    return normal_result(base_state, [])
  }
  let body = if node_child(case, "body") is Some(body) {
    body
  } else {
    return normal_result(base_state, [])
  }
  let roots = lex_scan_pattern_bound_roots(pattern)
  let bound = bind_lex_scan_pattern(pattern, value, base_state)
  let result = if node_optional_child(case, "guard") is Some(guard_expr) {
    let guard_result = eval_condition_scope(guard_expr, bound, spec, findings)
    match guard_result.normal {
      Some(path) =>
        flow_join(
          guard_result.exits,
          restore_result_scoped_roots(
            eval_expr(body, path.true_state, spec, findings),
            path.base_state,
            path.bound_roots,
          ),
        )
      None => guard_result.exits
    }
  } else {
    eval_expr(body, bound, spec, findings)
  }
  restore_result_scoped_roots(result, base_state, roots)
}

///|
fn eval_try(
  body : @untyped_cst.CstNode,
  catch_ : Array[@untyped_cst.CstNode],
  try_else : @untyped_cst.CstNode?,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  let body_result = eval_expr(body, state, spec, findings)
  let passthrough : EvalResult = {
    normal: None,
    returned: body_result.returned,
    raised: None,
    breaks: body_result.breaks,
    continues: body_result.continues,
  }
  let successful = match body_result.normal {
    Some(path) =>
      match try_else {
        Some(cases) => {
          let items = case_items(cases)
          let mut branches = empty_flow_summary()
          for case in items {
            branches = flow_join(
              branches,
              eval_pattern_case(case, path.value, path.state, spec, findings),
            )
          }
          if items.is_empty() {
            normal_result(path.state, path.value)
          } else {
            branches
          }
        }
        None => normal_result(path.state, path.value)
      }
    None => empty_flow_summary()
  }
  let caught = match body_result.raised {
    Some(path) => eval_catch_cases(path, catch_, spec, findings)
    None => empty_flow_summary()
  }
  flow_join(passthrough, flow_join(successful, caught))
}

///|
fn eval_catch_cases(
  raised : FlowPath,
  catch_ : Array[@untyped_cst.CstNode],
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  if catch_.is_empty() {
    return raise_result(raised.state, raised.value)
  }
  let mut branches = empty_flow_summary()
  for case in catch_ {
    branches = flow_join(
      branches,
      eval_pattern_case(case, raised.value, raised.state, spec, findings),
    )
  }
  branches
}
