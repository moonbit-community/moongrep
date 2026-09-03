///|
fn condition_from_eval_result(result : EvalResult) -> ConditionEval {
  {
    normal: match result.normal {
      Some(path) =>
        Some({
          base_state: path.state,
          true_state: path.state,
          bound_roots: [],
          value: path.value,
        })
      None => None
    },
    exits: flow_without_normal(result),
  }
}

///|
fn eval_condition_scope(
  cond : @untyped_cst.CstNode,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> ConditionEval raise {
  match cond.kind {
    @untyped_cst.Expr_Group | @untyped_cst.Expr_Constraint =>
      if node_child(cond, "expr") is Some(expr) {
        eval_condition_scope(expr, state, spec, findings)
      } else {
        condition_from_eval_result(normal_result(state, []))
      }
    @untyped_cst.Expr_Is =>
      match (node_child(cond, "expr"), node_child(cond, "pat")) {
        (Some(expr), Some(pat)) => {
          let matched = eval_expr(expr, state, spec, findings)
          {
            normal: match matched.normal {
              Some(path) =>
                Some({
                  base_state: path.state,
                  true_state: bind_pattern(pat, path.value, path.state),
                  bound_roots: pattern_bound_roots(pat),
                  value: path.value,
                })
              None => None
            },
            exits: flow_without_normal(matched),
          }
        }
        _ => condition_from_eval_result(normal_result(state, []))
      }
    @untyped_cst.Expr_RegexMatch =>
      match (node_child(cond, "expr"), node_child(cond, "pat")) {
        (Some(expr), Some(pat)) => {
          let matched = eval_expr(expr, state, spec, findings)
          let bindings = node_child_items(cond, "bindings")
          let roots = merge_root_names(
            regex_pattern_bound_roots(pat),
            regex_bindings_bound_roots(bindings),
          )
          {
            normal: match matched.normal {
              Some(path) => {
                let pattern_state = bind_regex_pattern(
                  pat,
                  path.value,
                  path.state,
                )
                Some({
                  base_state: path.state,
                  true_state: bind_regex_bindings(
                    bindings,
                    path.value,
                    pattern_state,
                  ),
                  bound_roots: roots,
                  value: path.value,
                })
              }
              None => None
            },
            exits: flow_without_normal(matched),
          }
        }
        _ => condition_from_eval_result(normal_result(state, []))
      }
    @untyped_cst.Expr_Infix =>
      if is_logical_and_expr(cond) &&
        node_child(cond, "lhs") is Some(lhs) &&
        node_child(cond, "rhs") is Some(rhs) {
        eval_and_condition_scope(lhs, rhs, state, spec, findings)
      } else {
        condition_from_eval_result(eval_expr(cond, state, spec, findings))
      }
    _ => condition_from_eval_result(eval_expr(cond, state, spec, findings))
  }
}

///|
fn eval_and_condition_scope(
  lhs : @untyped_cst.CstNode,
  rhs : @untyped_cst.CstNode,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> ConditionEval raise {
  let left = eval_condition_scope(lhs, state, spec, findings)
  match left.normal {
    Some(left_path) => {
      let right = eval_condition_scope(
        rhs,
        left_path.true_state,
        spec,
        findings,
      )
      let right_exits = restore_result_scoped_roots(
        right.exits,
        left_path.base_state,
        left_path.bound_roots,
      )
      {
        normal: match right.normal {
          Some(right_path) =>
            Some({
              base_state: restore_scoped_roots(
                left_path.base_state,
                right_path.base_state,
                left_path.bound_roots,
              ),
              true_state: right_path.true_state,
              bound_roots: merge_root_names(
                left_path.bound_roots,
                right_path.bound_roots,
              ),
              value: tree_merge(left_path.value, right_path.value),
            })
          None => None
        },
        exits: flow_join(left.exits, right_exits),
      }
    }
    None => left
  }
}

///|
fn is_logical_and_expr(expr : @untyped_cst.CstNode) -> Bool {
  if node_child(expr, "op") is Some(op) {
    node_var_name(op) == Some("&&")
  } else {
    false
  }
}

///|
fn regex_pattern_bound_roots(pattern : @untyped_cst.CstNode) -> Array[String] {
  let roots : Array[String] = []
  add_regex_pattern_bound_roots(roots, pattern)
  roots
}

///|
fn add_regex_pattern_bound_roots(
  roots : Array[String],
  pattern : @untyped_cst.CstNode,
) -> Unit {
  match pattern.kind {
    RegexPattern_Alias => {
      if node_child(pattern, "pat") is Some(pat) {
        add_regex_pattern_bound_roots(roots, pat)
      }
      add_binder_root_name(roots, pattern)
    }
    RegexPattern_Alternation | RegexPattern_Sequence => {
      if node_child(pattern, "lhs") is Some(pat1) {
        add_regex_pattern_bound_roots(roots, pat1)
      }
      if node_child(pattern, "rhs") is Some(pat2) {
        add_regex_pattern_bound_roots(roots, pat2)
      }
    }
    RegexPattern_Placeholder =>
      if node_child(pattern, "pattern") is Some(inner) {
        add_regex_pattern_bound_roots(roots, inner)
      }
    RegexPattern_Literal | RegexPattern_Reference => ()
    _ => ()
  }
}

///|
fn regex_bindings_bound_roots(
  bindings : Array[@untyped_cst.CstNode],
) -> Array[String] {
  let roots : Array[String] = []
  for binding in bindings {
    if node_optional_child(binding, "binder") is Some(binder) {
      add_binder_root_name(roots, binder)
    }
  }
  roots
}

///|
fn bind_regex_pattern(
  pattern : @untyped_cst.CstNode,
  value : TaintTree,
  state : TaintState,
) -> TaintState {
  match pattern.kind {
    RegexPattern_Alias => {
      let next = if node_child(pattern, "pat") is Some(pat) {
        bind_regex_pattern(pat, value, state)
      } else {
        state
      }
      bind_binder(pattern, value, next)
    }
    RegexPattern_Alternation =>
      match (node_child(pattern, "lhs"), node_child(pattern, "rhs")) {
        (Some(pat1), Some(pat2)) =>
          state_merge(
            bind_regex_pattern(pat1, value, state),
            bind_regex_pattern(pat2, value, state),
          )
        _ => state
      }
    RegexPattern_Sequence =>
      match (node_child(pattern, "lhs"), node_child(pattern, "rhs")) {
        (Some(pat1), Some(pat2)) =>
          bind_regex_pattern(
            pat2,
            value,
            bind_regex_pattern(pat1, value, state),
          )
        _ => state
      }
    RegexPattern_Placeholder =>
      if node_child(pattern, "pattern") is Some(inner) {
        bind_regex_pattern(inner, value, state)
      } else {
        state
      }
    RegexPattern_Literal | RegexPattern_Reference => state
    _ => state
  }
}

///|
fn bind_regex_bindings(
  bindings : Array[@untyped_cst.CstNode],
  value : TaintTree,
  state : TaintState,
) -> TaintState {
  let mut next = state
  for binding in bindings {
    if node_optional_child(binding, "binder") is Some(binder) {
      next = bind_binder(binder, value, next)
    }
  }
  next
}
