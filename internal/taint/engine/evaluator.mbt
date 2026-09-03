///|
fn control_label_name(node : @untyped_cst.CstNode) -> String? {
  let label = if node_child(node, "label") is Some(label) {
    label
  } else if @cst.raw_child(node, "label") is Some(label) {
    label
  } else {
    return None
  }
  if node_label_name(label) is Some(name) {
    Some(name)
  } else {
    @cst.raw_child(label, "name_value").bind(@cst.normalized_name)
  }
}

///|
fn analyze_single_function_like(
  node : @untyped_cst.CstNode,
  spec : TaintSpec,
) -> AnalysisResult raise {
  let function_like = function_like_from_impl(node)
  let findings : Array[SinkFinding] = []
  let mut state = empty_state()
  for source in spec.sources {
    match source {
      EntryPath(path, origin_id, note) =>
        if function_has_param_root(function_like, path.root) {
          let origin_site = ValueSite::Path(path)
          let origin : TaintOrigin = {
            rule_id: spec.rule_id,
            origin_id,
            site: origin_site,
            note,
          }
          state = state_write_path(state, path, [
            { path: [], origins: [origin], },
          ])
        }
      CallReturn(_, _, _, _) => ()
    }
  }
  let _ = eval_expr(function_like.body, state, spec, findings)
  {
    rule_id: spec.rule_id,
    function_name: function_like.name,
    function_loc: function_like.loc,
    findings,
  }
}

///|
fn function_has_param_root(function_like : FunctionLike, root : String) -> Bool {
  for path in function_like.params {
    if path.root == root {
      return true
    }
  }
  false
}

///|
fn eval_expr(
  expr : @untyped_cst.CstNode,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  match expr.kind {
    @untyped_cst.Expr_Block =>
      eval_cst_sequence(@cst.sequence_items(expr), state, spec, findings)
    @untyped_cst.Expr_LabelledBlock =>
      if node_child(expr, "body") is Some(body) {
        eval_labelled_block(
          control_label_name(expr),
          body,
          state,
          spec,
          findings,
        )
      } else {
        normal_result(state, [])
      }
    @untyped_cst.Expr_Ident => eval_path_like(expr, state)
    @untyped_cst.Expr_Field =>
      match (node_child(expr, "record"), node_child(expr, "accessor")) {
        (Some(record), Some(accessor)) =>
          eval_field_expr(expr, record, accessor, state, spec, findings)
        _ => normal_result(state, [])
      }
    @untyped_cst.Expr_ArrayGet =>
      match (node_child(expr, "array"), node_child(expr, "index")) {
        (Some(array), Some(index)) =>
          eval_array_get_expr(expr, array, index, state, spec, findings)
        _ => normal_result(state, [])
      }
    @untyped_cst.Expr_Tuple =>
      eval_tuple_expr(node_child_items(expr, "exprs"), state, spec, findings)
    @untyped_cst.Expr_Array =>
      eval_array_expr(node_child_items(expr, "exprs"), state, spec, findings)
    @untyped_cst.Expr_Record =>
      eval_record_expr(node_child_items(expr, "fields"), state, spec, findings)
    @untyped_cst.Expr_Group | @untyped_cst.Expr_Constraint =>
      if node_child(expr, "expr") is Some(inner) {
        eval_expr(inner, state, spec, findings)
      } else {
        normal_result(state, [])
      }
    @untyped_cst.Expr_Sequence =>
      eval_cst_sequence(@cst.sequence_items(expr), state, spec, findings)
    @untyped_cst.Expr_Let =>
      match
        (
          node_child(expr, "pattern"),
          node_child(expr, "expr"),
          node_child(expr, "body"),
        ) {
        (Some(pattern), Some(bound_expr), Some(body)) =>
          eval_let(pattern, bound_expr, body, state, spec, findings)
        _ => normal_result(state, [])
      }
    @untyped_cst.Expr_LetMut =>
      match
        (
          node_child(expr, "binder"),
          node_child(expr, "expr"),
          node_child(expr, "body"),
        ) {
        (Some(binder), Some(bound_expr), Some(body)) =>
          eval_let_binder(binder, bound_expr, body, state, spec, findings)
        _ => normal_result(state, [])
      }
    @untyped_cst.Expr_Assign =>
      if @cst.raw_child(expr, "rhs") is Some(rhs) {
        eval_assign(expr, rhs, state, spec, findings)
      } else {
        normal_result(state, [])
      }
    @untyped_cst.Expr_Mutate =>
      match (@cst.raw_child(expr, "self"), @cst.raw_child(expr, "rhs")) {
        (Some(receiver), Some(rhs)) =>
          eval_mutate(expr, receiver, rhs, state, spec, findings)
        _ => normal_result(state, [])
      }
    @untyped_cst.Expr_Apply =>
      match (node_child(expr, "func"), node_child(expr, "args")) {
        (Some(func), Some(args)) =>
          eval_apply_call(expr, func, args, expr.loc, state, spec, findings)
        _ => normal_result(state, [])
      }
    @untyped_cst.Expr_DotApply =>
      match
        (
          node_child(expr, "self"),
          node_child(expr, "method_name"),
          node_child(expr, "args"),
        ) {
        (Some(self), Some(method_name), Some(args)) =>
          eval_dot_apply_call(
            expr,
            self,
            method_name,
            args,
            expr.loc,
            state,
            spec,
            findings,
          )
        _ => normal_result(state, [])
      }
    @untyped_cst.Expr_Pipe =>
      match (node_child(expr, "lhs"), node_child(expr, "rhs")) {
        (Some(lhs), Some(rhs)) =>
          eval_pipe_call(expr, lhs, rhs, expr.loc, state, spec, findings)
        _ => normal_result(state, [])
      }
    @untyped_cst.Expr_RevPipe =>
      match (node_child(expr, "lhs"), node_child(expr, "rhs")) {
        (Some(lhs), Some(rhs)) =>
          eval_rev_pipe_call(expr, lhs, rhs, expr.loc, state, spec, findings)
        _ => normal_result(state, [])
      }
    @untyped_cst.Expr_If =>
      match (node_child(expr, "cond"), node_child(expr, "ifso")) {
        (Some(cond), Some(ifso)) =>
          eval_if(
            cond,
            ifso,
            node_optional_child(expr, "ifnot"),
            state,
            spec,
            findings,
          )
        _ => normal_result(state, [])
      }
    @untyped_cst.Expr_Match =>
      if node_child(expr, "expr") is Some(scrutinee) {
        eval_match(
          scrutinee,
          node_child_items(expr, "cases"),
          state,
          spec,
          findings,
        )
      } else {
        normal_result(state, [])
      }
    @untyped_cst.Expr_LexMatch =>
      if node_child(expr, "expr") is Some(scrutinee) {
        eval_lex_match(
          scrutinee,
          node_child_items(expr, "cases"),
          state,
          spec,
          findings,
        )
      } else {
        normal_result(state, [])
      }
    @untyped_cst.Expr_LexScan =>
      if node_child(expr, "expr") is Some(scrutinee) {
        eval_lex_scan(
          scrutinee,
          node_child_items(expr, "cases"),
          state,
          spec,
          findings,
        )
      } else {
        normal_result(state, [])
      }
    @untyped_cst.Expr_Try =>
      if node_child(expr, "body") is Some(body) {
        eval_try(
          body,
          node_child_items(expr, "catch"),
          node_optional_child(expr, "try_else"),
          state,
          spec,
          findings,
        )
      } else {
        normal_result(state, [])
      }
    @untyped_cst.Expr_While =>
      match (node_child(expr, "loop_cond"), node_child(expr, "loop_body")) {
        (Some(loop_cond), Some(loop_body)) =>
          eval_while(
            control_label_name(expr),
            expr.loc,
            loop_cond,
            loop_body,
            node_optional_child(expr, "while_else"),
            state,
            spec,
            findings,
          )
        _ => normal_result(state, [])
      }
    @untyped_cst.Expr_For =>
      if node_child(expr, "body") is Some(body) {
        eval_for(
          control_label_name(expr),
          expr.loc,
          node_child_items(expr, "binders"),
          @cst.raw_child(expr, "cond"),
          node_child_items(expr, "continue_block"),
          body,
          @cst.raw_child(expr, "else"),
          state,
          spec,
          findings,
        )
      } else {
        normal_result(state, [])
      }
    @untyped_cst.Expr_ForEach =>
      match (node_child(expr, "expr"), node_child(expr, "body")) {
        (Some(collection), Some(body)) =>
          eval_for_each(
            control_label_name(expr),
            expr.loc,
            node_child_items(expr, "binders"),
            collection,
            node_child_items(expr, "init"),
            node_child_items(expr, "continue_block"),
            body,
            node_optional_child(expr, "else_block"),
            state,
            spec,
            findings,
          )
        _ => normal_result(state, [])
      }
    @untyped_cst.Expr_LetFn =>
      match (node_child(expr, "name"), node_child(expr, "body")) {
        (Some(name), Some(body)) => {
          let roots : Array[String] = []
          add_binder_root_name(roots, name)
          eval_clean_root_scope(body, roots, state, spec, findings)
        }
        _ => normal_result(state, [])
      }
    @untyped_cst.Expr_LetAnd =>
      if node_child(expr, "body") is Some(body) {
        eval_clean_root_scope(
          body,
          let_and_bound_roots(node_child_items(expr, "bindings")),
          state,
          spec,
          findings,
        )
      } else {
        normal_result(state, [])
      }
    @untyped_cst.Expr_Function => normal_result(state, [])
    @untyped_cst.Expr_Return =>
      if node_optional_child(expr, "return_value") is Some(value) {
        flow_normal_to_return(eval_expr(value, state, spec, findings))
      } else {
        return_result(state, [])
      }
    @untyped_cst.Expr_Break =>
      if node_optional_child(expr, "arg") is Some(value) {
        flow_normal_to_break(
          eval_expr(value, state, spec, findings),
          control_label_name(expr),
        )
      } else {
        break_result(control_label_name(expr), state, [])
      }
    @untyped_cst.Expr_Raise =>
      if node_child(expr, "err_value") is Some(value) {
        flow_normal_to_raise(eval_expr(value, state, spec, findings))
      } else {
        raise_result(state, [])
      }
    @untyped_cst.Expr_Continue => {
      let result = eval_children(
        node_child_items(expr, "args"),
        state,
        spec,
        findings,
      )
      flow_normal_to_continue(result, control_label_name(expr))
    }
    _ => eval_unknown_expr(expr, state, spec, findings)
  }
}

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

///|
fn eval_apply_call(
  cst : @untyped_cst.CstNode,
  func : @untyped_cst.CstNode,
  args : @untyped_cst.CstNode,
  loc : @basic.Location,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  let func_result = eval_expr(func, state, spec, findings)
  match func_result.normal {
    Some(func_path) => {
      let args_result = eval_arguments(args, 0, func_path.state, spec, findings)
      let after_args = match args_result.normal {
        Some(args_path) =>
          flow_join(
            args_result.exits,
            apply_call_transfer(
              {
                kind: Apply,
                cst,
                loc,
                callee_name: callee_name_from_expr(func),
                receiver_path: None,
                receiver_site: None,
                receiver_taint: [],
                arguments: args_path.arguments,
              },
              args_path.state,
              spec,
              findings,
            ),
          )
        None => args_result.exits
      }
      flow_sequence(func_result, after_args)
    }
    None => func_result
  }
}

///|
fn eval_dot_apply_call(
  cst : @untyped_cst.CstNode,
  self : @untyped_cst.CstNode,
  method_name : @untyped_cst.CstNode,
  args : @untyped_cst.CstNode,
  loc : @basic.Location,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  let receiver = eval_expr(self, state, spec, findings)
  match receiver.normal {
    Some(receiver_flow) => {
      let receiver_path = storage_path_from_expr(self)
      let receiver_site = site_for_expr(self, receiver_path)
      let args_result = eval_arguments(
        args,
        0,
        receiver_flow.state,
        spec,
        findings,
      )
      let after_args = match args_result.normal {
        Some(args_path) =>
          flow_join(
            args_result.exits,
            apply_call_transfer(
              {
                kind: DotApply,
                cst,
                loc,
                callee_name: node_label_name(method_name),
                receiver_path,
                receiver_site: Some(receiver_site),
                receiver_taint: receiver_flow.value,
                arguments: args_path.arguments,
              },
              args_path.state,
              spec,
              findings,
            ),
          )
        None => args_result.exits
      }
      flow_sequence(receiver, after_args)
    }
    None => receiver
  }
}

///|
fn eval_pipe_call(
  cst : @untyped_cst.CstNode,
  lhs : @untyped_cst.CstNode,
  rhs : @untyped_cst.CstNode,
  loc : @basic.Location,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  let lhs_result = eval_expr(lhs, state, spec, findings)
  let lhs_path = match lhs_result.normal {
    Some(path) => path
    None => return lhs_result
  }
  let lhs_arg = evaled_argument_from_path(0, None, lhs, lhs_path)
  let rhs_flow = match rhs.kind {
    @untyped_cst.Expr_Apply =>
      match (node_child(rhs, "func"), node_child(rhs, "args")) {
        (Some(func), Some(args)) => {
          let func_result = eval_expr(func, lhs_path.state, spec, findings)
          match func_result.normal {
            Some(func_path) => {
              let args_result = eval_arguments(
                args,
                1,
                func_path.state,
                spec,
                findings,
              )
              let after_args = match args_result.normal {
                Some(args_path) => {
                  let arguments = prepend_argument(lhs_arg, args_path.arguments)
                  flow_join(
                    args_result.exits,
                    apply_call_transfer(
                      call_info_without_receiver(
                        Pipe,
                        cst,
                        loc,
                        callee_name_from_expr(func),
                        arguments,
                      ),
                      args_path.state,
                      spec,
                      findings,
                    ),
                  )
                }
                None => args_result.exits
              }
              flow_sequence(func_result, after_args)
            }
            None => func_result
          }
        }
        _ => normal_result(lhs_path.state, lhs_path.value)
      }
    @untyped_cst.Expr_DotApply =>
      match
        (
          node_child(rhs, "self"),
          node_child(rhs, "method_name"),
          node_child(rhs, "args"),
        ) {
        (Some(self), Some(method_name), Some(args)) => {
          let receiver = eval_expr(self, lhs_path.state, spec, findings)
          match receiver.normal {
            Some(receiver_flow) => {
              let receiver_path = storage_path_from_expr(self)
              let receiver_site = site_for_expr(self, receiver_path)
              let args_result = eval_arguments(
                args,
                1,
                receiver_flow.state,
                spec,
                findings,
              )
              let after_args = match args_result.normal {
                Some(args_path) => {
                  let arguments = prepend_argument(lhs_arg, args_path.arguments)
                  flow_join(
                    args_result.exits,
                    apply_call_transfer(
                      {
                        kind: Pipe,
                        cst,
                        loc,
                        callee_name: node_label_name(method_name),
                        receiver_path,
                        receiver_site: Some(receiver_site),
                        receiver_taint: receiver_flow.value,
                        arguments,
                      },
                      args_path.state,
                      spec,
                      findings,
                    ),
                  )
                }
                None => args_result.exits
              }
              flow_sequence(receiver, after_args)
            }
            None => receiver
          }
        }
        _ => normal_result(lhs_path.state, lhs_path.value)
      }
    _ => {
      let rhs_result = eval_expr(rhs, lhs_path.state, spec, findings)
      match rhs_result.normal {
        Some(rhs_path) =>
          flow_sequence(
            rhs_result,
            apply_call_transfer(
              call_info_without_receiver(
                Pipe,
                cst,
                loc,
                callee_name_from_expr(rhs),
                [lhs_arg],
              ),
              rhs_path.state,
              spec,
              findings,
            ),
          )
        None => rhs_result
      }
    }
  }
  flow_sequence(lhs_result, rhs_flow)
}

///|
fn eval_rev_pipe_call(
  cst : @untyped_cst.CstNode,
  lhs : @untyped_cst.CstNode,
  rhs : @untyped_cst.CstNode,
  loc : @basic.Location,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  let func_result = eval_expr(lhs, state, spec, findings)
  match func_result.normal {
    Some(func_path) => {
      let rhs_result = eval_expr(rhs, func_path.state, spec, findings)
      let after_rhs = match rhs_result.normal {
        Some(rhs_path) =>
          flow_sequence(
            rhs_result,
            apply_call_transfer(
              call_info_without_receiver(
                RevPipe,
                cst,
                loc,
                callee_name_from_expr(lhs),
                [evaled_argument_from_path(0, None, rhs, rhs_path)],
              ),
              rhs_path.state,
              spec,
              findings,
            ),
          )
        None => rhs_result
      }
      flow_sequence(func_result, after_rhs)
    }
    None => func_result
  }
}

///|
fn eval_arguments(
  args : @untyped_cst.CstNode,
  start_index : Int,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalArgumentsResult raise {
  let mut current = state
  let arguments : Array[CallArgument] = []
  let mut exits = empty_flow_summary()
  let raw = node_items(args)
  for offset in 0..<raw.length() {
    let arg = raw[offset]
    if @cst.argument_value(arg) is Some(value) {
      let result = eval_expr(value, current, spec, findings)
      exits = flow_join(exits, flow_without_normal(result))
      match result.normal {
        Some(path) => {
          current = path.state
          arguments.push(
            call_argument_from_path(
              start_index + offset,
              argument_label(arg),
              value,
              path,
            ),
          )
        }
        None => return { normal: None, exits, }
      }
    }
  }
  { normal: Some({ state: current, arguments, }), exits, }
}

///|
fn evaled_argument_from_path(
  index : Int,
  label : String?,
  expr : @untyped_cst.CstNode,
  path : FlowPath,
) -> CallArgument {
  call_argument_from_path(index, label, expr, path)
}

///|
fn call_argument_from_path(
  index : Int,
  label : String?,
  expr : @untyped_cst.CstNode,
  flow_path : FlowPath,
) -> CallArgument {
  let path = storage_path_from_expr(expr)
  {
    index,
    label,
    expr,
    loc: expr.loc,
    path,
    site: site_for_expr(expr, path),
    taint: flow_path.value,
  }
}

///|
fn prepend_argument(
  first : CallArgument,
  rest : Array[CallArgument],
) -> Array[CallArgument] {
  let result : Array[CallArgument] = [first]
  for arg in rest {
    result.push(arg)
  }
  result
}

///|
fn call_info_without_receiver(
  kind : CallKind,
  cst : @untyped_cst.CstNode,
  loc : @basic.Location,
  callee_name : String?,
  arguments : Array[CallArgument],
) -> CallInfo {
  {
    kind,
    cst,
    loc,
    callee_name,
    receiver_path: None,
    receiver_site: None,
    receiver_taint: [],
    arguments,
  }
}

///|
fn apply_call_transfer(
  info : CallInfo,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  if (spec.custom_transfer_call)(info) is Some(transfer) {
    let mut next = state
    for path in transfer.killed_paths {
      next = state_kill_path(next, path)
    }
    for finding in transfer.findings {
      findings.push(finding)
    }
    normal_result(next, transfer.return_taint)
  } else {
    apply_declared_call_transfer(info, state, spec, findings)
  }
}

///|
fn apply_declared_call_transfer(
  info : CallInfo,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let mut next = state
  let mut return_taint : TaintTree = []
  let mut matched = false
  for source in spec.sources {
    match source {
      CallReturn(matcher, origin_id, note, path) =>
        if call_matches(info, matcher) {
          matched = true
          return_taint = tree_merge(
            return_taint,
            fresh_source_tree(
              spec.rule_id,
              origin_id,
              note,
              CallResult(info.callee_name, info.loc),
              path,
            ),
          )
        }
      EntryPath(_, _, _) => ()
    }
  }
  for model in spec.call_models {
    if call_matches(info, model.matcher) {
      matched = true
      for effect in model.effects {
        match effect {
          ReturnFreshSource(origin_id, note, path) =>
            return_taint = tree_merge(
              return_taint,
              fresh_source_tree(
                spec.rule_id,
                origin_id,
                note,
                CallResult(info.callee_name, info.loc),
                path,
              ),
            )
          PropagateArgToReturn(index) =>
            if info.argument_at(index) is Some(arg) {
              return_taint = tree_merge(return_taint, arg.taint)
            }
          PropagateReceiverToReturn =>
            return_taint = tree_merge(return_taint, info.receiver_taint)
          PropagateArgSubpathToReturn(index, path) =>
            if info.argument_at(index) is Some(arg) {
              return_taint = tree_merge(
                return_taint,
                tree_project(arg.taint, path),
              )
            }
          KillArg(index) =>
            if info.argument_at(index) is Some(arg) && arg.path is Some(path) {
              next = state_kill_path(next, path)
            }
          KillReceiver =>
            if info.receiver_path is Some(path) {
              next = state_kill_path(next, path)
            }
          // Argument sinks point at the argument expression. Receiver sinks
          // point at the whole call while keeping the receiver as the value
          // site, because receiver syntax has no standalone call-site location.
          ReportSinkArg(sink_id, index) =>
            if info.argument_at(index) is Some(arg) {
              push_sink_finding_if_tainted(
                spec.rule_id,
                sink_id,
                arg.loc,
                arg.site,
                arg.taint,
                findings,
              )
            }
          ReportSinkReceiver(sink_id) =>
            if info.receiver_site is Some(site) {
              push_sink_finding_if_tainted(
                spec.rule_id,
                sink_id,
                info.loc,
                site,
                info.receiver_taint,
                findings,
              )
            }
        }
      }
    }
  }
  if !matched {
    return_taint = unknown_call_return_taint(info, spec.unknown_call_policy)
  }
  normal_result(next, return_taint)
}

///|
fn call_matches(info : CallInfo, matcher : CallMatcher) -> Bool {
  match matcher {
    AnyCall => true
    CalleeName(name) =>
      if info.callee_name is Some(found) {
        found == name
      } else {
        false
      }
    MethodName(name) =>
      match info.kind {
        DotApply | Pipe =>
          if info.callee_name is Some(found) {
            found == name
          } else {
            false
          }
        _ => false
      }
  }
}

///|
fn unknown_call_return_taint(
  info : CallInfo,
  policy : UnknownCallPolicy,
) -> TaintTree {
  match policy {
    NoEffect => []
    PropagateArgumentsToReturn => {
      let mut result = info.receiver_taint
      for arg in info.arguments {
        result = tree_merge(result, arg.taint)
      }
      result
    }
  }
}

///|
fn push_sink_finding_if_tainted(
  rule_id : String,
  sink_id : SinkId,
  loc : @basic.Location,
  site : ValueSite,
  taint : TaintTree,
  findings : Array[SinkFinding],
) -> Unit {
  let origins = taint_tree_origins(taint)
  if origins.length() > 0 {
    findings.push({ rule_id, sink_id, sink_loc: loc, sink_site: site, origins, })
  }
}

///|
fn fresh_source_tree(
  rule_id : String,
  origin_id : String,
  note : String?,
  site : ValueSite,
  path : Array[PathSegment],
) -> TaintTree {
  [{ path, origins: [{ rule_id, origin_id, site, note, }], }]
}

///|
fn tree_shift(prefix : Array[PathSegment], tree : TaintTree) -> TaintTree {
  let shifted : TaintTree = []
  for entry in tree {
    merge_relative_entry(
      shifted,
      append_segments(prefix, entry.path),
      entry.origins,
    )
  }
  shifted
}

///|
fn site_for_expr(expr : @untyped_cst.CstNode, path : StoragePath?) -> ValueSite {
  if path is Some(path) {
    Path(path)
  } else {
    Expr(expr.loc, None)
  }
}

///|
fn callee_name_from_expr(expr : @untyped_cst.CstNode) -> String? {
  match expr.kind {
    @untyped_cst.Expr_Ident => @cst.normalized_expr_identifier_name(expr)
    @untyped_cst.Expr_Field =>
      if node_child(expr, "accessor") is Some(accessor) {
        match accessor.kind {
          @untyped_cst.Accessor_Label => node_first_label_name(accessor)
          _ => None
        }
      } else {
        None
      }
    @untyped_cst.Expr_Method =>
      if node_child(expr, "method_name") is Some(method_name) {
        node_label_name(method_name)
      } else {
        None
      }
    @untyped_cst.Expr_Group | @untyped_cst.Expr_Constraint =>
      if node_child(expr, "expr") is Some(inner) {
        callee_name_from_expr(inner)
      } else {
        None
      }
    _ => None
  }
}

///|
fn copy_root_names(names : Array[String]) -> Array[String] {
  let copied : Array[String] = []
  for name in names {
    copied.push(name)
  }
  copied
}

///|
fn add_unique_root_name(names : Array[String], name : String) -> Unit {
  for existing in names {
    if existing == name {
      return
    }
  }
  names.push(name)
}

///|
fn add_binder_root_name(
  names : Array[String],
  binder : @untyped_cst.CstNode,
) -> Unit {
  if node_binder_name(binder) is Some(name) {
    add_unique_root_name(names, name)
  }
}

///|
fn root_name_in(root : String, names : Array[String]) -> Bool {
  for name in names {
    if root == name {
      return true
    }
  }
  false
}

///|
fn merge_root_names(
  left : Array[String],
  right : Array[String],
) -> Array[String] {
  let merged = copy_root_names(left)
  for name in right {
    add_unique_root_name(merged, name)
  }
  merged
}

///|
fn restore_scoped_roots(
  base : TaintState,
  scoped : TaintState,
  roots : Array[String],
) -> TaintState {
  if roots.is_empty() {
    return scoped
  }
  let builder = new_state_builder()
  for entry in scoped.entries {
    if !root_name_in(entry.path.root, roots) {
      builder.merge_entry(entry)
    }
  }
  for entry in base.entries {
    if root_name_in(entry.path.root, roots) {
      builder.merge_entry(entry)
    }
  }
  builder.finish()
}

///|
fn restore_result_scoped_roots(
  result : EvalResult,
  base : TaintState,
  roots : Array[String],
) -> EvalResult {
  {
    normal: restore_optional_flow_path(result.normal, base, roots),
    returned: restore_optional_flow_path(result.returned, base, roots),
    raised: restore_optional_flow_path(result.raised, base, roots),
    breaks: restore_labelled_flow_paths(result.breaks, base, roots),
    continues: restore_labelled_flow_paths(result.continues, base, roots),
  }
}

///|
fn restore_optional_flow_path(
  path : FlowPath?,
  base : TaintState,
  roots : Array[String],
) -> FlowPath? {
  match path {
    Some(path) =>
      Some({
        state: restore_scoped_roots(base, path.state, roots),
        value: path.value,
      })
    None => None
  }
}

///|
fn restore_labelled_flow_paths(
  paths : Array[LabelledFlowPath],
  base : TaintState,
  roots : Array[String],
) -> Array[LabelledFlowPath] {
  let restored : Array[LabelledFlowPath] = []
  for entry in paths {
    restored.push({
      label: entry.label,
      path: {
        state: restore_scoped_roots(base, entry.path.state, roots),
        value: entry.path.value,
      },
    })
  }
  restored
}

///|
fn clean_bind_roots(state : TaintState, roots : Array[String]) -> TaintState {
  let mut next = state
  for root in roots {
    next = state_write_path(next, { root, segments: [], }, [])
  }
  next
}

///|
fn tree_root_taint(tree : TaintTree) -> TaintTree {
  let root : TaintTree = []
  for entry in tree {
    if entry.path.is_empty() {
      merge_relative_entry(root, [], entry.origins)
    }
  }
  root
}

///|
fn tree_project_for_binding(
  tree : TaintTree,
  segment : PathSegment,
) -> TaintTree {
  tree_merge(tree_project(tree, [segment]), tree_root_taint(tree))
}

///|
fn pattern_bound_roots(pattern : @untyped_cst.CstNode) -> Array[String] {
  let roots : Array[String] = []
  add_pattern_bound_roots(roots, pattern)
  roots
}

///|
fn add_pattern_bound_roots(
  roots : Array[String],
  pattern : @untyped_cst.CstNode,
) -> Unit {
  match pattern.kind {
    @untyped_cst.Pattern_Var =>
      if @cst.normalized_pattern_identifier_name(pattern) is Some(name) {
        add_unique_root_name(roots, name)
      }
    @untyped_cst.Pattern_Alias => {
      if node_child(pattern, "pat") is Some(pat) {
        add_pattern_bound_roots(roots, pat)
      }
      if node_child(pattern, "alias") is Some(alias_) {
        add_binder_root_name(roots, alias_)
      }
    }
    @untyped_cst.Pattern_Constraint =>
      if node_child(pattern, "pat") is Some(pat) {
        add_pattern_bound_roots(roots, pat)
      }
    @untyped_cst.Pattern_Tuple =>
      for pat in pattern_body_items(pattern) {
        add_pattern_bound_roots(roots, pat)
      }
    @untyped_cst.Pattern_Record =>
      for field in pattern_body_items(pattern) {
        if node_child(field, "pattern") is Some(pat) {
          add_pattern_bound_roots(roots, pat)
        } else if field.kind is @untyped_cst.Field_Pattern {
          add_binder_root_name(roots, field)
        }
      }
    @untyped_cst.Pattern_Map =>
      for elem in pattern_body_items(pattern) {
        if node_child(elem, "pattern") is Some(pat) {
          add_pattern_bound_roots(roots, pat)
        }
      }
    @untyped_cst.Pattern_Array =>
      for item in array_pattern_items(pattern) {
        add_array_pattern_item_bound_roots(roots, item)
      }
    @untyped_cst.Pattern_Constr | @untyped_cst.Pattern_SpecialConstr =>
      for arg in constructor_pattern_items(pattern) {
        if arg.kind.is_pattern() {
          add_pattern_bound_roots(roots, arg)
        } else if node_child(arg, "pattern") is Some(pat) {
          add_pattern_bound_roots(roots, pat)
        } else if arg.kind is @untyped_cst.Argument_LabelledPun {
          add_binder_root_name(roots, arg)
        }
      }
    @untyped_cst.Pattern_Or | @untyped_cst.Pattern_Range => {
      if node_child(pattern, "pat1") is Some(pat) {
        add_pattern_bound_roots(roots, pat)
      }
      if node_child(pattern, "pat2") is Some(pat) {
        add_pattern_bound_roots(roots, pat)
      }
      if node_child(pattern, "lhs") is Some(pat) {
        add_pattern_bound_roots(roots, pat)
      }
      if node_child(pattern, "rhs") is Some(pat) {
        add_pattern_bound_roots(roots, pat)
      }
    }
    @untyped_cst.Pattern_Rest => add_binder_root_name(roots, pattern)
    @untyped_cst.Pattern_Any | @untyped_cst.Pattern_Constant => ()
    _ => ()
  }
}

///|
fn pattern_body_items(
  pattern : @untyped_cst.CstNode,
) -> Array[@untyped_cst.CstNode] {
  if @cst.raw_child(pattern, "body") is Some(body) {
    node_items(body)
  } else {
    []
  }
}

///|
fn array_pattern_items(
  pattern : @untyped_cst.CstNode,
) -> Array[@untyped_cst.CstNode] {
  guard @cst.raw_child(pattern, "body") is Some(array_patterns) else {
    return []
  }
  if @cst.raw_child(array_patterns, "body") is Some(list) {
    node_items(list)
  } else {
    []
  }
}

///|
fn constructor_pattern_items(
  pattern : @untyped_cst.CstNode,
) -> Array[@untyped_cst.CstNode] {
  if @cst.raw_child(pattern, "params") is Some(list) {
    node_items(list)
  } else {
    []
  }
}

///|
fn add_array_pattern_item_bound_roots(
  roots : Array[String],
  item : @untyped_cst.CstNode,
) -> Unit {
  match item.kind {
    @untyped_cst.ArrayPattern_Pattern =>
      if @cst.raw_child(item, "pattern") is Some(pattern) {
        add_pattern_bound_roots(roots, pattern)
      }
    @untyped_cst.ArrayPattern_ConstSpread => add_binder_root_name(roots, item)
    @untyped_cst.Pattern_Rest => add_binder_root_name(roots, item)
    @untyped_cst.ArrayPattern_BytesSpread
    | @untyped_cst.ArrayPattern_StringSpread => ()
    _ => ()
  }
}

///|
fn let_and_bound_roots(bindings : Array[@untyped_cst.CstNode]) -> Array[String] {
  let roots : Array[String] = []
  for binding in bindings {
    add_binder_root_name(roots, binding)
  }
  roots
}

///|
fn bind_binder(
  binder : @untyped_cst.CstNode,
  value : TaintTree,
  state : TaintState,
) -> TaintState {
  if node_binder_name(binder) is Some(name) {
    state_write_path(state, { root: name, segments: [], }, value)
  } else {
    state
  }
}

///|
fn bind_pattern(
  pattern : @untyped_cst.CstNode,
  value : TaintTree,
  state : TaintState,
) -> TaintState {
  match pattern.kind {
    @untyped_cst.Pattern_Var => bind_binder(pattern, value, state)
    @untyped_cst.Pattern_Alias => {
      let next = if node_child(pattern, "pat") is Some(pat) {
        bind_pattern(pat, value, state)
      } else {
        state
      }
      if node_child(pattern, "alias") is Some(alias_) {
        bind_binder(alias_, value, next)
      } else {
        next
      }
    }
    @untyped_cst.Pattern_Constraint =>
      if node_child(pattern, "pat") is Some(pat) {
        bind_pattern(pat, value, state)
      } else {
        state
      }
    @untyped_cst.Pattern_Tuple => {
      let mut next = state
      let items = pattern_body_items(pattern)
      for index in 0..<items.length() {
        next = bind_pattern(
          items[index],
          tree_project_for_binding(value, TupleIndex(index)),
          next,
        )
      }
      next
    }
    @untyped_cst.Pattern_Record => {
      let mut next = state
      for field in pattern_body_items(pattern) {
        if node_label_name(field) is Some(name) {
          let projected = tree_project_for_binding(value, Field(name))
          if node_child(field, "pattern") is Some(pat) {
            next = bind_pattern(pat, projected, next)
          } else if field.kind is @untyped_cst.Field_Pattern {
            next = bind_binder(field, projected, next)
          }
        }
      }
      next
    }
    @untyped_cst.Pattern_Map => {
      let mut next = state
      for elem in pattern_body_items(pattern) {
        if node_child(elem, "pattern") is Some(pat) {
          next = bind_pattern(pat, value, next)
        }
      }
      next
    }
    @untyped_cst.Pattern_Array => {
      let mut next = state
      let items = array_pattern_items(pattern)
      let mut after_rest = false
      let mut positional_index = 0
      for item in items {
        let segment : PathSegment = if after_rest ||
          item.kind is @untyped_cst.Pattern_Rest {
          AnyIndex
        } else {
          ConstIndex(positional_index.to_string())
        }
        next = bind_array_pattern_item(item, segment, value, next)
        if item.kind is @untyped_cst.Pattern_Rest {
          after_rest = true
        } else {
          positional_index += 1
        }
      }
      next
    }
    @untyped_cst.Pattern_Constr | @untyped_cst.Pattern_SpecialConstr => {
      let mut next = state
      let items = constructor_pattern_items(pattern)
      for index in 0..<items.length() {
        let item = items[index]
        let segment = segment_from_argument_kind(item, index)
        let projected = tree_project_for_binding(value, segment)
        if item.kind.is_pattern() {
          next = bind_pattern(item, projected, next)
        } else if node_child(item, "pattern") is Some(pat) {
          next = bind_pattern(pat, projected, next)
        } else if item.kind is @untyped_cst.Argument_LabelledPun {
          next = bind_binder(item, projected, next)
        }
      }
      next
    }
    @untyped_cst.Pattern_Or =>
      match (node_child(pattern, "lhs"), node_child(pattern, "rhs")) {
        (Some(pat1), Some(pat2)) =>
          state_merge(
            bind_pattern(pat1, value, state),
            bind_pattern(pat2, value, state),
          )
        _ => state
      }
    _ => state
  }
}

///|
fn bind_array_pattern_item(
  item : @untyped_cst.CstNode,
  segment : PathSegment,
  value : TaintTree,
  state : TaintState,
) -> TaintState {
  match item.kind {
    @untyped_cst.ArrayPattern_Pattern =>
      if @cst.raw_child(item, "pattern") is Some(pattern) {
        bind_pattern(pattern, tree_project_for_binding(value, segment), state)
      } else {
        state
      }
    @untyped_cst.ArrayPattern_ConstSpread | @untyped_cst.Pattern_Rest =>
      bind_binder(item, tree_project_for_binding(value, segment), state)
    @untyped_cst.ArrayPattern_BytesSpread
    | @untyped_cst.ArrayPattern_StringSpread => state
    _ => state
  }
}

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
fn eval_lex_top_pattern_exprs(
  patterns : Array[@untyped_cst.CstNode],
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  let mut current = state
  let mut value : TaintTree = []
  let mut exits = empty_flow_summary()
  for pattern in patterns {
    let result = match lex_top_pattern_kind(pattern) {
      Some(@untyped_cst.LexTopPattern_Pattern) =>
        eval_lex_pattern_exprs(pattern, current, spec, findings)
      Some(@untyped_cst.LexTopPattern_Binder)
      | Some(@untyped_cst.LexTopPattern_Wildcard) => normal_result(current, [])
      _ => normal_result(current, [])
    }
    exits = flow_join(exits, flow_without_normal(result))
    match result.normal {
      Some(path) => {
        current = path.state
        value = tree_merge(value, path.value)
      }
      None => return exits
    }
  }
  flow_join(exits, normal_result(current, value))
}

///|
fn eval_lex_pattern_exprs(
  pattern : @untyped_cst.CstNode,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  match pattern.kind {
    LexPattern_Alias =>
      if node_child(pattern, "pat") is Some(pat) {
        eval_lex_pattern_exprs(pat, state, spec, findings)
      } else {
        normal_result(state, [])
      }
    LexPattern_RegexInterp =>
      eval_interp_elems(
        node_child_items(pattern, "elems"),
        state,
        spec,
        findings,
      )
    LexPattern_Sequence => {
      let mut current = state
      let mut value : TaintTree = []
      let mut exits = empty_flow_summary()
      for pat in pattern_body_items(pattern) {
        let result = eval_lex_pattern_exprs(pat, current, spec, findings)
        exits = flow_join(exits, flow_without_normal(result))
        match result.normal {
          Some(path) => {
            current = path.state
            value = tree_merge(value, path.value)
          }
          None => return exits
        }
      }
      flow_join(exits, normal_result(current, value))
    }
    LexPattern_ConstantRef | LexPattern_Literal => normal_result(state, [])
    _ => normal_result(state, [])
  }
}

///|
fn eval_interp_elems(
  elems : Array[@untyped_cst.CstNode],
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  let mut current = state
  let mut value : TaintTree = []
  let mut exits = empty_flow_summary()
  for elem in elems {
    match elem.kind {
      @untyped_cst.InterpSegment_Source =>
        if node_child(elem, "expr") is Some(expr) {
          let result = eval_expr(expr, current, spec, findings)
          exits = flow_join(exits, flow_without_normal(result))
          match result.normal {
            Some(path) => {
              current = path.state
              value = tree_merge(value, path.value)
            }
            None => return exits
          }
        }
      @untyped_cst.InterpSegment_Literal => ()
      _ => ()
    }
  }
  flow_join(exits, normal_result(current, value))
}

///|
fn lex_top_patterns_bound_roots(
  patterns : Array[@untyped_cst.CstNode],
) -> Array[String] {
  let roots : Array[String] = []
  for pattern in patterns {
    add_lex_top_pattern_bound_roots(roots, pattern)
  }
  roots
}

///|
fn add_lex_top_pattern_bound_roots(
  roots : Array[String],
  pattern : @untyped_cst.CstNode,
) -> Unit {
  match lex_top_pattern_kind(pattern) {
    Some(@untyped_cst.LexTopPattern_Binder) =>
      add_binder_root_name(roots, pattern)
    Some(@untyped_cst.LexTopPattern_Pattern) =>
      add_lex_pattern_bound_roots(roots, pattern)
    Some(@untyped_cst.LexTopPattern_Wildcard) => ()
    _ => ()
  }
}

///|
fn lex_top_pattern_items(
  pattern : @untyped_cst.CstNode,
) -> Array[@untyped_cst.CstNode] {
  if pattern.kind is @untyped_cst.Pattern_Tuple &&
    @cst.raw_child(pattern, "pattern_group") is None {
    pattern_body_items(pattern)
  } else {
    [pattern]
  }
}

///|
fn lex_top_pattern_kind(
  pattern : @untyped_cst.CstNode,
) -> @untyped_cst.NodeKind? {
  @cst.raw_child(pattern, "lex_top_pattern").map(item => item.kind)
}

///|
fn add_lex_pattern_bound_roots(
  roots : Array[String],
  pattern : @untyped_cst.CstNode,
) -> Unit {
  match pattern.kind {
    LexPattern_Alias => {
      if node_child(pattern, "pat") is Some(pat) {
        add_lex_pattern_bound_roots(roots, pat)
      }
      add_binder_root_name(roots, pattern)
    }
    LexPattern_Sequence =>
      for pat in pattern_body_items(pattern) {
        add_lex_pattern_bound_roots(roots, pat)
      }
    LexPattern_ConstantRef | LexPattern_Literal | LexPattern_RegexInterp => ()
    _ => ()
  }
}

///|
fn bind_lex_top_patterns(
  patterns : Array[@untyped_cst.CstNode],
  value : TaintTree,
  state : TaintState,
) -> TaintState {
  let mut next = state
  for pattern in patterns {
    next = match lex_top_pattern_kind(pattern) {
      Some(@untyped_cst.LexTopPattern_Binder) =>
        bind_binder(pattern, value, next)
      Some(@untyped_cst.LexTopPattern_Pattern) =>
        bind_lex_pattern(pattern, value, next)
      Some(@untyped_cst.LexTopPattern_Wildcard) => next
      _ => next
    }
  }
  next
}

///|
fn bind_lex_pattern(
  pattern : @untyped_cst.CstNode,
  value : TaintTree,
  state : TaintState,
) -> TaintState {
  match pattern.kind {
    LexPattern_Alias => {
      let next = if node_child(pattern, "pat") is Some(pat) {
        bind_lex_pattern(pat, value, state)
      } else {
        state
      }
      bind_binder(pattern, value, next)
    }
    LexPattern_Sequence => {
      let mut next = state
      for pat in pattern_body_items(pattern) {
        next = bind_lex_pattern(pat, value, next)
      }
      next
    }
    LexPattern_ConstantRef | LexPattern_Literal | LexPattern_RegexInterp =>
      state
    _ => state
  }
}

///|
fn lex_scan_pattern_bound_roots(
  pattern : @untyped_cst.CstNode,
) -> Array[String] {
  let roots : Array[String] = []
  add_lex_scan_pattern_bound_roots(roots, pattern)
  roots
}

///|
fn add_lex_scan_pattern_bound_roots(
  roots : Array[String],
  pattern : @untyped_cst.CstNode,
) -> Unit {
  match
    @cst.raw_child(pattern, "lex_scan_case_pattern").map(item => item.kind) {
    Some(@untyped_cst.LexScanCasePattern_Binder) =>
      add_binder_root_name(roots, pattern)
    Some(@untyped_cst.LexScanCasePattern_Pattern) =>
      add_regex_pattern_bound_roots(roots, pattern)
    Some(@untyped_cst.LexScanCasePattern_Wildcard) => ()
    _ => ()
  }
}

///|
fn bind_lex_scan_pattern(
  pattern : @untyped_cst.CstNode,
  value : TaintTree,
  state : TaintState,
) -> TaintState {
  match
    @cst.raw_child(pattern, "lex_scan_case_pattern").map(item => item.kind) {
    Some(@untyped_cst.LexScanCasePattern_Binder) =>
      bind_binder(pattern, value, state)
    Some(@untyped_cst.LexScanCasePattern_Pattern) =>
      bind_regex_pattern(pattern, value, state)
    Some(@untyped_cst.LexScanCasePattern_Wildcard) => state
    _ => state
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

///|
fn eval_unknown_expr(
  expr : @untyped_cst.CstNode,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  match expr.kind {
    @untyped_cst.Expr_Infix =>
      eval_children(
        node_children_by_names(expr, ["lhs", "rhs"]),
        state,
        spec,
        findings,
      )
    @untyped_cst.Expr_Unary =>
      if node_child(expr, "expr") is Some(inner) {
        eval_expr(inner, state, spec, findings)
      } else {
        normal_result(state, [])
      }
    @untyped_cst.Expr_As
    | @untyped_cst.Expr_TryOperator
    | @untyped_cst.Expr_ProofAssert
    | @untyped_cst.Expr_TemplateWriting =>
      if node_child(expr, "expr") is Some(inner) {
        eval_expr(inner, state, spec, findings)
      } else if node_child(expr, "body") is Some(body) {
        eval_expr(body, state, spec, findings)
      } else {
        normal_result(state, [])
      }
    @untyped_cst.Expr_ArraySet | @untyped_cst.Expr_ArrayAugmentedSet =>
      eval_children(
        node_children_by_names(expr, ["array", "index", "value"]),
        state,
        spec,
        findings,
      )
    @untyped_cst.Expr_ArrayGetSlice =>
      eval_children(
        node_optional_children_by_names(expr, [
          "array", "start_index", "end_index",
        ]),
        state,
        spec,
        findings,
      )
    @untyped_cst.Expr_Defer =>
      eval_children(
        node_children_by_names(expr, ["expr", "body"]),
        state,
        spec,
        findings,
      )
    @untyped_cst.Expr_Guard =>
      match (node_child(expr, "cond"), node_child(expr, "body")) {
        (Some(cond), Some(body)) =>
          eval_guard(
            cond,
            node_optional_child(expr, "otherwise"),
            body,
            state,
            spec,
            findings,
          )
        _ => normal_result(state, [])
      }
    @untyped_cst.Expr_Is | @untyped_cst.Expr_RegexMatch =>
      if node_child(expr, "expr") is Some(inner) {
        eval_expr(inner, state, spec, findings)
      } else {
        normal_result(state, [])
      }
    @untyped_cst.Expr_Interp | @untyped_cst.Expr_BytesInterp =>
      eval_interp_elems(node_child_items(expr, "elems"), state, spec, findings)
    @untyped_cst.Expr_Map => {
      let mut current = state
      let mut value : TaintTree = []
      let mut exits = empty_flow_summary()
      for elem in node_child_items(expr, "elems") {
        if node_child(elem, "expr") is Some(child) {
          let result = eval_expr(child, current, spec, findings)
          exits = flow_join(exits, flow_without_normal(result))
          match result.normal {
            Some(path) => {
              current = path.state
              value = tree_merge(value, path.value)
            }
            None => return exits
          }
        }
      }
      flow_join(exits, normal_result(current, value))
    }
    @untyped_cst.Expr_RecordUpdate =>
      if node_child(expr, "record") is Some(record) {
        let base = eval_expr(record, state, spec, findings)
        match base.normal {
          Some(path) =>
            flow_sequence(
              base,
              eval_record_expr(
                node_child_items(expr, "fields"),
                path.state,
                spec,
                findings,
              ),
            )
          None => base
        }
      } else {
        normal_result(state, [])
      }
    _ => normal_result(state, [])
  }
}

///|
fn node_children_by_names(
  node : @untyped_cst.CstNode,
  names : Array[String],
) -> Array[@untyped_cst.CstNode] {
  let children : Array[@untyped_cst.CstNode] = []
  for name in names {
    if node_child(node, name) is Some(child) {
      children.push(child)
    }
  }
  children
}

///|
fn node_optional_children_by_names(
  node : @untyped_cst.CstNode,
  names : Array[String],
) -> Array[@untyped_cst.CstNode] {
  let children : Array[@untyped_cst.CstNode] = []
  for name in names {
    if node_optional_child(node, name) is Some(child) {
      children.push(child)
    }
  }
  children
}

///|
fn eval_children(
  children : Array[@untyped_cst.CstNode],
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  let mut current = state
  let mut value : TaintTree = []
  let mut exits = empty_flow_summary()
  for child in children {
    let result = eval_expr(child, current, spec, findings)
    exits = flow_join(exits, flow_without_normal(result))
    match result.normal {
      Some(path) => {
        current = path.state
        value = tree_merge(value, path.value)
      }
      None => return exits
    }
  }
  flow_join(exits, normal_result(current, value))
}
