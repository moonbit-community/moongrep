///|
fn finish_loop_fixpoint(
  summary : LoopFixpointSummary,
  else_expr : @untyped_cst.CstNode?,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  let mut result = summary.exits
  if summary.nobreak_exit is Some(path) {
    let normal_completion = match else_expr {
      Some(expr) => eval_expr(expr, path.state, spec, findings)
      None => normal_result(path.state, [])
    }
    result = flow_join(result, normal_completion)
  }
  if summary.break_exit is Some(path) {
    result = flow_join(result, normal_result(path.state, path.value))
  }
  result
}

///|
fn eval_while(
  loop_label : String?,
  loop_loc : @basic.Location,
  loop_cond : @untyped_cst.CstNode,
  loop_body : @untyped_cst.CstNode,
  while_else : @untyped_cst.CstNode?,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  let summary = run_loop_fixpoint(
    state,
    spec.rule_id,
    "while",
    loop_loc,
    spec.max_fixpoint_iterations,
    current => {
      let condition = eval_condition_scope(loop_cond, current, spec, findings)
      match condition.normal {
        Some(path) => {
          let body_result = restore_result_scoped_roots(
            eval_expr(loop_body, path.true_state, spec, findings),
            path.base_state,
            path.bound_roots,
          )
          let consumed = consume_loop_control(body_result, loop_label)
          {
            nobreak_exit: Some({ state: path.base_state, value: [], }),
            back_edge: consumed.back_edge,
            break_exit: consumed.break_exit,
            exits: flow_join(condition.exits, consumed.exits),
          }
        }
        None =>
          {
            nobreak_exit: None,
            back_edge: None,
            break_exit: None,
            exits: condition.exits,
          }
      }
    },
  )
  finish_loop_fixpoint(summary, while_else, spec, findings)
}

///|
fn eval_for(
  loop_label : String?,
  loop_loc : @basic.Location,
  binders : Array[@untyped_cst.CstNode],
  condition : @untyped_cst.CstNode?,
  continue_block : Array[@untyped_cst.CstNode],
  body : @untyped_cst.CstNode,
  for_else : @untyped_cst.CstNode?,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  let loop_roots : Array[String] = []
  let mut loop_base = state
  let mut current = state
  let mut initial_exits = empty_flow_summary()
  for pair in binders {
    match (node_child(pair, "binder"), node_child(pair, "expr")) {
      (Some(binder), Some(expr)) => {
        let result = eval_expr(expr, current, spec, findings)
        initial_exits = flow_join(
          initial_exits,
          restore_result_scoped_roots(
            flow_without_normal(result),
            loop_base,
            loop_roots,
          ),
        )
        match result.normal {
          Some(path) => {
            current = path.state
            loop_base = restore_scoped_roots(loop_base, current, loop_roots)
            add_binder_root_name(loop_roots, binder)
            current = bind_binder(binder, path.value, current)
          }
          None => return initial_exits
        }
      }
      _ => ()
    }
  }
  let summary = run_loop_fixpoint(
    current,
    spec.rule_id,
    "for",
    loop_loc,
    spec.max_fixpoint_iterations,
    header => {
      let condition_result = match condition {
        Some(expr) => eval_condition_scope(expr, header, spec, findings)
        None =>
          {
            normal: Some({
              base_state: header,
              true_state: header,
              bound_roots: [],
              value: [],
            }),
            exits: empty_flow_summary(),
          }
      }
      match condition_result.normal {
        Some(condition_path) => {
          let raw_body_result = eval_expr(
            body,
            condition_path.true_state,
            spec,
            findings,
          )
          let raw_body = consume_loop_control(raw_body_result, loop_label)
          let body_break = restore_optional_flow_path(
            raw_body.break_exit,
            condition_path.base_state,
            condition_path.bound_roots,
          )
          let body_exits = restore_result_scoped_roots(
            raw_body.exits,
            condition_path.base_state,
            condition_path.bound_roots,
          )
          let updates = match raw_body.back_edge {
            Some(back_edge) => {
              let mut update_normal : FlowPath? = Some(back_edge)
              let mut update_exits = empty_flow_summary()
              for pair in continue_block {
                match
                  (
                    update_normal,
                    node_child(pair, "binder"),
                    node_child(pair, "expr"),
                  ) {
                  (Some(next), Some(binder), Some(expr)) => {
                    let result = eval_expr(expr, next.state, spec, findings)
                    update_exits = flow_join(
                      update_exits,
                      flow_without_normal(result),
                    )
                    update_normal = match result.normal {
                      Some(path) => {
                        let base_candidate = restore_scoped_roots(
                          condition_path.base_state,
                          path.state,
                          condition_path.bound_roots,
                        )
                        loop_base = restore_scoped_roots(
                          loop_base, base_candidate, loop_roots,
                        )
                        add_binder_root_name(loop_roots, binder)
                        Some({
                          state: bind_binder(binder, path.value, path.state),
                          value: path.value,
                        })
                      }
                      None => None
                    }
                  }
                  _ => ()
                }
              }
              let update_result = flow_join(
                update_exits,
                match update_normal {
                  Some(path) => normal_result(path.state, path.value)
                  None => empty_flow_summary()
                },
              )
              consume_loop_control(
                restore_result_scoped_roots(
                  update_result,
                  condition_path.base_state,
                  condition_path.bound_roots,
                ),
                loop_label,
              )
            }
            None =>
              {
                back_edge: None,
                break_exit: None,
                exits: empty_flow_summary(),
              }
          }
          {
            nobreak_exit: match condition {
              Some(_) => Some({ state: condition_path.base_state, value: [], })
              None => None
            },
            back_edge: updates.back_edge,
            break_exit: merge_optional_flow_paths(
              body_break,
              updates.break_exit,
            ),
            exits: flow_join(
              condition_result.exits,
              flow_join(body_exits, updates.exits),
            ),
          }
        }
        None =>
          {
            nobreak_exit: None,
            back_edge: None,
            break_exit: None,
            exits: condition_result.exits,
          }
      }
    },
  )
  let loop_result = restore_result_scoped_roots(
    finish_loop_fixpoint(summary, for_else, spec, findings),
    loop_base,
    loop_roots,
  )
  flow_join(initial_exits, loop_result)
}

///|
fn eval_for_each(
  loop_label : String?,
  loop_loc : @basic.Location,
  binders : Array[@untyped_cst.CstNode],
  collection : @untyped_cst.CstNode,
  init : Array[@untyped_cst.CstNode],
  continue_block : Array[@untyped_cst.CstNode],
  body : @untyped_cst.CstNode,
  else_block : @untyped_cst.CstNode?,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  let collection_result = eval_expr(collection, state, spec, findings)
  let collection_path = match collection_result.normal {
    Some(path) => path
    None => return collection_result
  }
  let loop_roots : Array[String] = []
  let mut loop_base = collection_path.state
  let mut current = collection_path.state
  let mut initial_exits = flow_without_normal(collection_result)
  for pair in init {
    match (node_child(pair, "init"), node_child(pair, "expr")) {
      (Some(binder), Some(expr)) => {
        let result = eval_expr(expr, current, spec, findings)
        initial_exits = flow_join(
          initial_exits,
          restore_result_scoped_roots(
            flow_without_normal(result),
            loop_base,
            loop_roots,
          ),
        )
        match result.normal {
          Some(path) => {
            current = path.state
            loop_base = restore_scoped_roots(loop_base, current, loop_roots)
            add_binder_root_name(loop_roots, binder)
            current = bind_binder(binder, path.value, current)
          }
          None => return initial_exits
        }
      }
      _ => ()
    }
  }
  for binder in binders {
    if !node_is_null(binder) {
      add_binder_root_name(loop_roots, binder)
      current = bind_binder(
        binder,
        tree_project_for_binding(collection_path.value, AnyIndex),
        current,
      )
    }
  }
  let summary = run_loop_fixpoint(
    current,
    spec.rule_id,
    "foreach",
    loop_loc,
    spec.max_fixpoint_iterations,
    header => {
      let body_flow = consume_loop_control(
        eval_expr(body, header, spec, findings),
        loop_label,
      )
      let updates = match body_flow.back_edge {
        Some(back_edge) => {
          let mut update_normal : FlowPath? = Some(back_edge)
          let mut update_exits = empty_flow_summary()
          for pair in continue_block {
            match
              (
                update_normal,
                node_child(pair, "binder"),
                node_child(pair, "expr"),
              ) {
              (Some(next), Some(binder), Some(expr)) => {
                let result = eval_expr(expr, next.state, spec, findings)
                update_exits = flow_join(
                  update_exits,
                  flow_without_normal(result),
                )
                update_normal = match result.normal {
                  Some(path) => {
                    loop_base = restore_scoped_roots(
                      loop_base,
                      path.state,
                      loop_roots,
                    )
                    add_binder_root_name(loop_roots, binder)
                    Some({
                      state: bind_binder(binder, path.value, path.state),
                      value: path.value,
                    })
                  }
                  None => None
                }
              }
              _ => ()
            }
          }
          consume_loop_control(
            flow_join(
              update_exits,
              match update_normal {
                Some(path) => normal_result(path.state, path.value)
                None => empty_flow_summary()
              },
            ),
            loop_label,
          )
        }
        None =>
          { back_edge: None, break_exit: None, exits: empty_flow_summary(), }
      }
      {
        nobreak_exit: Some({ state: header, value: [], }),
        back_edge: updates.back_edge,
        break_exit: merge_optional_flow_paths(
          body_flow.break_exit,
          updates.break_exit,
        ),
        exits: flow_join(body_flow.exits, updates.exits),
      }
    },
  )
  let loop_result = restore_result_scoped_roots(
    finish_loop_fixpoint(summary, else_block, spec, findings),
    loop_base,
    loop_roots,
  )
  flow_join(initial_exits, loop_result)
}
