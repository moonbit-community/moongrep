///|
fn eval_labelled_block(
  label : String?,
  body : @untyped_cst.CstNode,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  consume_labelled_block_break(eval_expr(body, state, spec, findings), label)
}

///|
fn eval_cst_sequence(
  expressions : Array[@untyped_cst.CstNode],
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  let outer_state = state
  let local_roots : Array[String] = []
  let mut current = state
  let mut value : TaintTree = []
  let mut exits = empty_flow_summary()
  for expr in expressions {
    let result = match expr.kind {
      @untyped_cst.Expr_Let | @untyped_cst.Expr_LetMut =>
        match (@cst.raw_child(expr, "pattern"), @cst.raw_child(expr, "expr")) {
          (Some(pattern), Some(bound_expr)) => {
            let bound = eval_expr(bound_expr, current, spec, findings)
            match bound.normal {
              Some(path) => {
                let roots = pattern_bound_roots(pattern)
                for root in roots {
                  add_unique_root_name(local_roots, root)
                }
                flow_with_normal(
                  bound,
                  Some({
                    state: bind_pattern(pattern, path.value, path.state),
                    value: path.value,
                  }),
                )
              }
              None => bound
            }
          }
          _ => normal_result(current, [])
        }
      @untyped_cst.Expr_LetFn => {
        let roots : Array[String] = []
        add_binder_root_name(roots, expr)
        for root in roots {
          add_unique_root_name(local_roots, root)
        }
        normal_result(clean_bind_roots(current, roots), [])
      }
      @untyped_cst.Expr_LetAnd => {
        let roots = let_and_bound_roots(@cst.raw_children(expr, "binding"))
        for root in roots {
          add_unique_root_name(local_roots, root)
        }
        normal_result(clean_bind_roots(current, roots), [])
      }
      @untyped_cst.Expr_Guard =>
        if @cst.raw_child(expr, "cond") is Some(cond) {
          let condition = eval_condition_scope(cond, current, spec, findings)
          match condition.normal {
            Some(path) => {
              let mut guard_exits = condition.exits
              if @cst.raw_child(expr, "else") is Some(otherwise) {
                guard_exits = flow_join(
                  guard_exits,
                  flow_without_normal(
                    eval_expr(otherwise, path.base_state, spec, findings),
                  ),
                )
              }
              for root in path.bound_roots {
                add_unique_root_name(local_roots, root)
              }
              flow_join(guard_exits, normal_result(path.true_state, path.value))
            }
            None => condition.exits
          }
        } else {
          normal_result(current, [])
        }
      _ => eval_expr(expr, current, spec, findings)
    }
    exits = flow_join(exits, flow_without_normal(result))
    match result.normal {
      Some(path) => {
        current = path.state
        value = path.value
      }
      None =>
        return restore_result_scoped_roots(exits, outer_state, local_roots)
    }
  }
  restore_result_scoped_roots(
    flow_join(exits, normal_result(current, value)),
    outer_state,
    local_roots,
  )
}

///|
fn eval_path_like(
  expr : @untyped_cst.CstNode,
  state : TaintState,
) -> EvalResult {
  if storage_path_from_expr(expr) is Some(path) {
    normal_result(state, state_read_path(state, path))
  } else {
    normal_result(state, [])
  }
}

///|
fn eval_field_expr(
  expr : @untyped_cst.CstNode,
  record : @untyped_cst.CstNode,
  accessor : @untyped_cst.CstNode,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  if storage_path_from_expr(expr) is Some(path) {
    normal_result(state, state_read_path(state, path))
  } else {
    let record_result = eval_expr(record, state, spec, findings)
    match record_result.normal {
      Some(path) =>
        flow_with_normal(
          record_result,
          Some({
            state: path.state,
            value: match segment_from_accessor(accessor) {
              Some(segment) => tree_project(path.value, [segment])
              None => []
            },
          }),
        )
      None => record_result
    }
  }
}

///|
fn eval_array_get_expr(
  expr : @untyped_cst.CstNode,
  array : @untyped_cst.CstNode,
  index : @untyped_cst.CstNode,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  let index_result = eval_expr(index, state, spec, findings)
  match index_result.normal {
    Some(index_path) =>
      if storage_path_from_expr(expr) is Some(path) {
        flow_with_normal(
          index_result,
          Some({
            state: index_path.state,
            value: state_read_path(index_path.state, path),
          }),
        )
      } else {
        let array_result = eval_expr(array, index_path.state, spec, findings)
        let projected = match array_result.normal {
          Some(array_path) =>
            Some({
              state: array_path.state,
              value: tree_project(array_path.value, [
                segment_from_index_expr(index),
              ]),
            })
          None => None
        }
        flow_sequence(index_result, flow_with_normal(array_result, projected))
      }
    None => index_result
  }
}

///|
fn eval_tuple_expr(
  exprs : Array[@untyped_cst.CstNode],
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  let mut current = state
  let mut value : TaintTree = []
  let mut exits = empty_flow_summary()
  for index in 0..<exprs.length() {
    let result = eval_expr(exprs[index], current, spec, findings)
    exits = flow_join(exits, flow_without_normal(result))
    match result.normal {
      Some(path) => {
        current = path.state
        value = tree_merge(value, tree_shift([TupleIndex(index)], path.value))
      }
      None => return exits
    }
  }
  flow_join(exits, normal_result(current, value))
}

///|
fn eval_array_expr(
  exprs : Array[@untyped_cst.CstNode],
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  let mut current = state
  let mut value : TaintTree = []
  let mut exits = empty_flow_summary()
  for index in 0..<exprs.length() {
    let result = eval_expr(exprs[index], current, spec, findings)
    exits = flow_join(exits, flow_without_normal(result))
    match result.normal {
      Some(path) => {
        current = path.state
        value = tree_merge(
          value,
          tree_shift([ConstIndex(index.to_string())], path.value),
        )
        value = tree_merge(value, tree_shift([AnyIndex], path.value))
      }
      None => return exits
    }
  }
  flow_join(exits, normal_result(current, value))
}

///|
fn eval_record_expr(
  fields : Array[@untyped_cst.CstNode],
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  let mut current = state
  let mut value : TaintTree = []
  let mut exits = empty_flow_summary()
  for field in fields {
    match (node_child(field, "label"), node_child(field, "expr")) {
      (Some(label), Some(expr)) => {
        let result = eval_expr(expr, current, spec, findings)
        exits = flow_join(exits, flow_without_normal(result))
        match result.normal {
          Some(path) => {
            current = path.state
            if node_label_name(label) is Some(name) {
              value = tree_merge(value, tree_shift([Field(name)], path.value))
            }
          }
          None => return exits
        }
      }
      _ => ()
    }
  }
  flow_join(exits, normal_result(current, value))
}

///|
fn eval_let(
  pattern : @untyped_cst.CstNode,
  bound_expr : @untyped_cst.CstNode,
  body : @untyped_cst.CstNode,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  let bound = eval_expr(bound_expr, state, spec, findings)
  match bound.normal {
    Some(path) => {
      let bound_state = bind_pattern(pattern, path.value, path.state)
      let result = restore_result_scoped_roots(
        eval_expr(body, bound_state, spec, findings),
        path.state,
        pattern_bound_roots(pattern),
      )
      flow_sequence(bound, result)
    }
    None => bound
  }
}

///|
fn eval_let_binder(
  binder : @untyped_cst.CstNode,
  bound_expr : @untyped_cst.CstNode,
  body : @untyped_cst.CstNode,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  let bound = eval_expr(bound_expr, state, spec, findings)
  match bound.normal {
    Some(path) => {
      let roots : Array[String] = []
      add_binder_root_name(roots, binder)
      let bound_state = bind_binder(binder, path.value, path.state)
      let result = restore_result_scoped_roots(
        eval_expr(body, bound_state, spec, findings),
        path.state,
        roots,
      )
      flow_sequence(bound, result)
    }
    None => bound
  }
}

///|
fn eval_clean_root_scope(
  body : @untyped_cst.CstNode,
  roots : Array[String],
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  let scoped = clean_bind_roots(state, roots)
  let result = eval_expr(body, scoped, spec, findings)
  restore_result_scoped_roots(result, state, roots)
}

///|
fn eval_assign(
  assignment : @untyped_cst.CstNode,
  rhs : @untyped_cst.CstNode,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  let rhs_result = eval_expr(rhs, state, spec, findings)
  match rhs_result.normal {
    Some(normal) =>
      flow_with_normal(
        rhs_result,
        Some({
          state: match storage_path_from_assignment(assignment) {
            Some(path) => state_write_path(normal.state, path, normal.value)
            None => normal.state
          },
          value: normal.value,
        }),
      )
    None => rhs_result
  }
}

///|
fn eval_mutate(
  assignment : @untyped_cst.CstNode,
  receiver : @untyped_cst.CstNode,
  rhs : @untyped_cst.CstNode,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  let receiver_result = eval_expr(receiver, state, spec, findings)
  match receiver_result.normal {
    Some(path) =>
      flow_sequence(
        receiver_result,
        eval_assign(assignment, rhs, path.state, spec, findings),
      )
    None => receiver_result
  }
}
