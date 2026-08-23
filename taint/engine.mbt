///|
// Control-flow exits are tracked so unreachable later expressions do not report
// sinks after `return`, `raise`, `break`, or `continue`.
priv enum FlowExit {
  FlowNormal
  FlowReturn
  FlowRaise
  FlowBreak(String?)
  FlowContinue(String?)
} derive(Eq)

///|
priv struct EvalResult {
  state : TaintState
  value : TaintTree
  flow : FlowExit
}

///|
priv struct EvalArgumentsResult {
  state : TaintState
  arguments : Array[CallArgument]
  flow : FlowExit
  value : TaintTree
}

///|
priv struct ConditionEval {
  base_state : TaintState
  true_state : TaintState
  bound_roots : Array[String]
  flow : FlowExit
  value : TaintTree
}

///|
fn normal_result(state : TaintState, value : TaintTree) -> EvalResult {
  { state, value, flow: FlowNormal }
}

///|
fn flow_result(
  flow : FlowExit,
  state : TaintState,
  value : TaintTree,
) -> EvalResult {
  { state, value, flow }
}

///|
fn control_label_name(node : @untyped_cst.CstNode) -> String? {
  let label = match node_child(node, "label") {
    Some(label) => label
    None =>
      match @cst.raw_child(node, "label") {
        Some(label) => label
        None => return None
      }
  }
  match node_label_name(label) {
    Some(name) => Some(name)
    None => @cst.raw_child(label, "name_value").bind(@cst.normalized_name)
  }
}

///|
fn control_targets_loop(target : String?, loop_label : String?) -> Bool {
  match target {
    None => true
    Some(target) => loop_label == Some(target)
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
          let origin = {
            rule_id: spec.rule_id,
            origin_id,
            site: origin_site,
            note,
          }
          state = state_write_path(state, path, [
            { path: [], origins: [origin] },
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
) -> EvalResult {
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
        let result = eval_expr(value, state, spec, findings)
        flow_result(FlowReturn, result.state, result.value)
      } else {
        flow_result(FlowReturn, state, [])
      }
    @untyped_cst.Expr_Break =>
      if node_optional_child(expr, "arg") is Some(value) {
        let result = eval_expr(value, state, spec, findings)
        flow_result(
          FlowBreak(control_label_name(expr)),
          result.state,
          result.value,
        )
      } else {
        flow_result(FlowBreak(control_label_name(expr)), state, [])
      }
    @untyped_cst.Expr_Raise =>
      if node_child(expr, "err_value") is Some(value) {
        let result = eval_expr(value, state, spec, findings)
        flow_result(FlowRaise, result.state, result.value)
      } else {
        flow_result(FlowRaise, state, [])
      }
    @untyped_cst.Expr_Continue => {
      let result = eval_children(
        node_child_items(expr, "args"),
        state,
        spec,
        findings,
      )
      flow_result(
        FlowContinue(control_label_name(expr)),
        result.state,
        result.value,
      )
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
) -> EvalResult {
  let result = eval_expr(body, state, spec, findings)
  match result.flow {
    FlowBreak(Some(target)) if label == Some(target) =>
      normal_result(result.state, result.value)
    _ => result
  }
}

///|
fn eval_cst_sequence(
  expressions : Array[@untyped_cst.CstNode],
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let outer_state = state
  let local_roots : Array[String] = []
  let mut current = state
  let mut value : TaintTree = []
  for expr in expressions {
    let result = match expr.kind {
      @untyped_cst.Expr_Let | @untyped_cst.Expr_LetMut =>
        match (@cst.raw_child(expr, "pattern"), @cst.raw_child(expr, "expr")) {
          (Some(pattern), Some(bound_expr)) => {
            let bound = eval_expr(bound_expr, current, spec, findings)
            if bound.flow != FlowNormal {
              bound
            } else {
              let roots = pattern_bound_roots(pattern)
              for root in roots {
                add_unique_root_name(local_roots, root)
              }
              normal_result(
                bind_pattern(pattern, bound.value, bound.state),
                bound.value,
              )
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
          if condition.flow != FlowNormal {
            flow_result(condition.flow, condition.base_state, condition.value)
          } else {
            if @cst.raw_child(expr, "else") is Some(otherwise) {
              ignore(eval_expr(otherwise, condition.base_state, spec, findings))
            }
            for root in condition.bound_roots {
              add_unique_root_name(local_roots, root)
            }
            normal_result(condition.true_state, condition.value)
          }
        } else {
          normal_result(current, [])
        }
      _ => eval_expr(expr, current, spec, findings)
    }
    if result.flow != FlowNormal {
      return restore_result_scoped_roots(result, outer_state, local_roots)
    }
    current = result.state
    value = result.value
  }
  restore_result_scoped_roots(
    normal_result(current, value),
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
) -> EvalResult {
  if storage_path_from_expr(expr) is Some(path) {
    normal_result(state, state_read_path(state, path))
  } else {
    let record_result = eval_expr(record, state, spec, findings)
    if record_result.flow != FlowNormal {
      return record_result
    }
    if segment_from_accessor(accessor) is Some(segment) {
      normal_result(
        record_result.state,
        tree_project(record_result.value, [segment]),
      )
    } else {
      normal_result(record_result.state, [])
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
) -> EvalResult {
  let index_result = eval_expr(index, state, spec, findings)
  if index_result.flow != FlowNormal {
    return index_result
  }
  if storage_path_from_expr(expr) is Some(path) {
    normal_result(index_result.state, state_read_path(index_result.state, path))
  } else {
    let array_result = eval_expr(array, index_result.state, spec, findings)
    if array_result.flow != FlowNormal {
      return array_result
    }
    normal_result(
      array_result.state,
      tree_project(array_result.value, [segment_from_index_expr(index)]),
    )
  }
}

///|
fn eval_tuple_expr(
  exprs : Array[@untyped_cst.CstNode],
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let mut current = state
  let mut value : TaintTree = []
  for index in 0..<exprs.length() {
    let result = eval_expr(exprs[index], current, spec, findings)
    if result.flow != FlowNormal {
      return result
    }
    current = result.state
    value = tree_merge(value, tree_shift([TupleIndex(index)], result.value))
  }
  normal_result(current, value)
}

///|
fn eval_array_expr(
  exprs : Array[@untyped_cst.CstNode],
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let mut current = state
  let mut value : TaintTree = []
  for index in 0..<exprs.length() {
    let result = eval_expr(exprs[index], current, spec, findings)
    if result.flow != FlowNormal {
      return result
    }
    current = result.state
    value = tree_merge(
      value,
      tree_shift([ConstIndex(index.to_string())], result.value),
    )
    value = tree_merge(value, tree_shift([AnyIndex], result.value))
  }
  normal_result(current, value)
}

///|
fn eval_record_expr(
  fields : Array[@untyped_cst.CstNode],
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let mut current = state
  let mut value : TaintTree = []
  for field in fields {
    match (node_child(field, "label"), node_child(field, "expr")) {
      (Some(label), Some(expr)) => {
        let result = eval_expr(expr, current, spec, findings)
        if result.flow != FlowNormal {
          return result
        }
        current = result.state
        if node_label_name(label) is Some(name) {
          value = tree_merge(value, tree_shift([Field(name)], result.value))
        }
      }
      _ => ()
    }
  }
  normal_result(current, value)
}

///|
fn eval_let(
  pattern : @untyped_cst.CstNode,
  bound_expr : @untyped_cst.CstNode,
  body : @untyped_cst.CstNode,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let bound = eval_expr(bound_expr, state, spec, findings)
  if bound.flow != FlowNormal {
    return bound
  }
  let bound_state = bind_pattern(pattern, bound.value, bound.state)
  let result = eval_expr(body, bound_state, spec, findings)
  restore_result_scoped_roots(result, bound.state, pattern_bound_roots(pattern))
}

///|
fn eval_let_binder(
  binder : @untyped_cst.CstNode,
  bound_expr : @untyped_cst.CstNode,
  body : @untyped_cst.CstNode,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let bound = eval_expr(bound_expr, state, spec, findings)
  if bound.flow != FlowNormal {
    return bound
  }
  let roots : Array[String] = []
  add_binder_root_name(roots, binder)
  let bound_state = bind_binder(binder, bound.value, bound.state)
  let result = eval_expr(body, bound_state, spec, findings)
  restore_result_scoped_roots(result, bound.state, roots)
}

///|
fn eval_clean_root_scope(
  body : @untyped_cst.CstNode,
  roots : Array[String],
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
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
) -> EvalResult {
  let rhs_result = eval_expr(rhs, state, spec, findings)
  if rhs_result.flow != FlowNormal {
    return rhs_result
  }
  if storage_path_from_assignment(assignment) is Some(path) {
    normal_result(
      state_write_path(rhs_result.state, path, rhs_result.value),
      rhs_result.value,
    )
  } else {
    rhs_result
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
) -> EvalResult {
  let receiver_result = eval_expr(receiver, state, spec, findings)
  if receiver_result.flow != FlowNormal {
    return receiver_result
  }
  eval_assign(assignment, rhs, receiver_result.state, spec, findings)
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
) -> EvalResult {
  let func_result = eval_expr(func, state, spec, findings)
  if func_result.flow != FlowNormal {
    return func_result
  }
  let args_result = eval_arguments(args, 0, func_result.state, spec, findings)
  if args_result.flow != FlowNormal {
    return flow_result(args_result.flow, args_result.state, args_result.value)
  }
  let info = {
    kind: Apply,
    cst,
    loc,
    callee_name: callee_name_from_expr(func),
    receiver_path: None,
    receiver_site: None,
    receiver_taint: [],
    arguments: args_result.arguments,
  }
  apply_call_transfer(info, args_result.state, spec, findings)
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
) -> EvalResult {
  let receiver = eval_expr(self, state, spec, findings)
  if receiver.flow != FlowNormal {
    return receiver
  }
  let receiver_path = storage_path_from_expr(self)
  let receiver_site = site_for_expr(self, receiver_path)
  let args_result = eval_arguments(args, 0, receiver.state, spec, findings)
  if args_result.flow != FlowNormal {
    return flow_result(args_result.flow, args_result.state, args_result.value)
  }
  let info = {
    kind: DotApply,
    cst,
    loc,
    callee_name: node_label_name(method_name),
    receiver_path,
    receiver_site: Some(receiver_site),
    receiver_taint: receiver.value,
    arguments: args_result.arguments,
  }
  apply_call_transfer(info, args_result.state, spec, findings)
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
) -> EvalResult {
  let lhs_result = eval_expr(lhs, state, spec, findings)
  if lhs_result.flow != FlowNormal {
    return lhs_result
  }
  let lhs_arg = evaled_argument_from_result(0, None, lhs, lhs_result)
  match rhs.kind {
    @untyped_cst.Expr_Apply =>
      match (node_child(rhs, "func"), node_child(rhs, "args")) {
        (Some(func), Some(args)) => {
          let func_result = eval_expr(func, lhs_result.state, spec, findings)
          if func_result.flow != FlowNormal {
            return func_result
          }
          let args_result = eval_arguments(
            args,
            1,
            func_result.state,
            spec,
            findings,
          )
          if args_result.flow != FlowNormal {
            return flow_result(
              args_result.flow,
              args_result.state,
              args_result.value,
            )
          }
          let arguments = prepend_argument(lhs_arg, args_result.arguments)
          let info = call_info_without_receiver(
            Pipe,
            cst,
            loc,
            callee_name_from_expr(func),
            arguments,
          )
          apply_call_transfer(info, args_result.state, spec, findings)
        }
        _ => normal_result(lhs_result.state, lhs_result.value)
      }
    @untyped_cst.Expr_DotApply =>
      match
        (
          node_child(rhs, "self"),
          node_child(rhs, "method_name"),
          node_child(rhs, "args"),
        ) {
        (Some(self), Some(method_name), Some(args)) => {
          let receiver = eval_expr(self, lhs_result.state, spec, findings)
          if receiver.flow != FlowNormal {
            return receiver
          }
          let receiver_path = storage_path_from_expr(self)
          let receiver_site = site_for_expr(self, receiver_path)
          let args_result = eval_arguments(
            args,
            1,
            receiver.state,
            spec,
            findings,
          )
          if args_result.flow != FlowNormal {
            return flow_result(
              args_result.flow,
              args_result.state,
              args_result.value,
            )
          }
          let arguments = prepend_argument(lhs_arg, args_result.arguments)
          let info = {
            kind: Pipe,
            cst,
            loc,
            callee_name: node_label_name(method_name),
            receiver_path,
            receiver_site: Some(receiver_site),
            receiver_taint: receiver.value,
            arguments,
          }
          apply_call_transfer(info, args_result.state, spec, findings)
        }
        _ => normal_result(lhs_result.state, lhs_result.value)
      }
    _ => {
      let rhs_result = eval_expr(rhs, lhs_result.state, spec, findings)
      if rhs_result.flow != FlowNormal {
        return rhs_result
      }
      let info = call_info_without_receiver(
        Pipe,
        cst,
        loc,
        callee_name_from_expr(rhs),
        [lhs_arg],
      )
      apply_call_transfer(info, rhs_result.state, spec, findings)
    }
  }
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
) -> EvalResult {
  let func_result = eval_expr(lhs, state, spec, findings)
  if func_result.flow != FlowNormal {
    return func_result
  }
  let rhs_result = eval_expr(rhs, func_result.state, spec, findings)
  if rhs_result.flow != FlowNormal {
    return rhs_result
  }
  let arg = evaled_argument_from_result(0, None, rhs, rhs_result)
  let info = call_info_without_receiver(
    RevPipe,
    cst,
    loc,
    callee_name_from_expr(lhs),
    [arg],
  )
  apply_call_transfer(info, rhs_result.state, spec, findings)
}

///|
fn eval_arguments(
  args : @untyped_cst.CstNode,
  start_index : Int,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalArgumentsResult {
  let mut current = state
  let arguments : Array[CallArgument] = []
  let raw = node_items(args)
  for offset in 0..<raw.length() {
    let arg = raw[offset]
    if @cst.argument_value(arg) is Some(value) {
      let result = eval_expr(value, current, spec, findings)
      if result.flow != FlowNormal {
        return {
          state: result.state,
          arguments,
          flow: result.flow,
          value: result.value,
        }
      }
      current = result.state
      arguments.push(
        call_argument_from_result(
          start_index + offset,
          argument_label(arg),
          value,
          result,
        ),
      )
    }
  }
  { state: current, arguments, flow: FlowNormal, value: [] }
}

///|
fn evaled_argument_from_result(
  index : Int,
  label : String?,
  expr : @untyped_cst.CstNode,
  result : EvalResult,
) -> CallArgument {
  call_argument_from_result(index, label, expr, result)
}

///|
fn call_argument_from_result(
  index : Int,
  label : String?,
  expr : @untyped_cst.CstNode,
  result : EvalResult,
) -> CallArgument {
  let path = storage_path_from_expr(expr)
  {
    index,
    label,
    expr,
    loc: expr.loc,
    path,
    site: site_for_expr(expr, path),
    taint: result.value,
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
            if argument_at(info.arguments, index) is Some(arg) {
              return_taint = tree_merge(return_taint, arg.taint)
            }
          PropagateReceiverToReturn =>
            return_taint = tree_merge(return_taint, info.receiver_taint)
          PropagateArgSubpathToReturn(index, path) =>
            if argument_at(info.arguments, index) is Some(arg) {
              return_taint = tree_merge(
                return_taint,
                tree_project(arg.taint, path),
              )
            }
          KillArg(index) =>
            if argument_at(info.arguments, index) is Some(arg) &&
              arg.path is Some(path) {
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
            if argument_at(info.arguments, index) is Some(arg) {
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
fn argument_at(args : Array[CallArgument], index : Int) -> CallArgument? {
  for arg in args {
    if arg.index == index {
      return Some(arg)
    }
  }
  None
}

///|
fn push_sink_finding_if_tainted(
  rule_id : String,
  sink_id : String,
  loc : @basic.Location,
  site : ValueSite,
  taint : TaintTree,
  findings : Array[SinkFinding],
) -> Unit {
  let origins = origins_from_tree(taint)
  if origins.length() > 0 {
    findings.push({ rule_id, sink_id, sink_loc: loc, sink_site: site, origins })
  }
}

///|
fn origins_from_tree(tree : TaintTree) -> Array[TaintOrigin] {
  let origins : Array[TaintOrigin] = []
  for entry in tree {
    for origin in entry.origins {
      add_origin_unique(origins, origin)
    }
  }
  origins
}

///|
fn fresh_source_tree(
  rule_id : String,
  origin_id : String,
  note : String?,
  site : ValueSite,
  path : Array[PathSegment],
) -> TaintTree {
  [{ path, origins: [{ rule_id, origin_id, site, note }] }]
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
  let entries : Array[StateEntry] = []
  for entry in scoped.entries {
    if !root_name_in(entry.path.root, roots) {
      merge_state_entry(entries, entry.path, entry.origins)
    }
  }
  for entry in base.entries {
    if root_name_in(entry.path.root, roots) {
      merge_state_entry(entries, entry.path, entry.origins)
    }
  }
  { entries, }
}

///|
fn restore_result_scoped_roots(
  result : EvalResult,
  base : TaintState,
  roots : Array[String],
) -> EvalResult {
  {
    state: restore_scoped_roots(base, result.state, roots),
    value: result.value,
    flow: result.flow,
  }
}

///|
fn clean_bind_roots(state : TaintState, roots : Array[String]) -> TaintState {
  let mut next = state
  for root in roots {
    next = state_write_path(next, { root, segments: [] }, [])
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
    state_write_path(state, { root: name, segments: [] }, value)
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
        let segment = if after_rest || item.kind is @untyped_cst.Pattern_Rest {
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
    base_state: result.state,
    true_state: result.state,
    bound_roots: [],
    flow: result.flow,
    value: result.value,
  }
}

///|
fn eval_condition_scope(
  cond : @untyped_cst.CstNode,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> ConditionEval {
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
          if matched.flow != FlowNormal {
            return condition_from_eval_result(matched)
          }
          let roots = pattern_bound_roots(pat)
          {
            base_state: matched.state,
            true_state: bind_pattern(pat, matched.value, matched.state),
            bound_roots: roots,
            flow: FlowNormal,
            value: matched.value,
          }
        }
        _ => condition_from_eval_result(normal_result(state, []))
      }
    @untyped_cst.Expr_RegexMatch =>
      match (node_child(cond, "expr"), node_child(cond, "pat")) {
        (Some(expr), Some(pat)) => {
          let matched = eval_expr(expr, state, spec, findings)
          if matched.flow != FlowNormal {
            return condition_from_eval_result(matched)
          }
          let bindings = node_child_items(cond, "bindings")
          let roots = merge_root_names(
            regex_pattern_bound_roots(pat),
            regex_bindings_bound_roots(bindings),
          )
          let pattern_state = bind_regex_pattern(
            pat,
            matched.value,
            matched.state,
          )
          {
            base_state: matched.state,
            true_state: bind_regex_bindings(
              bindings,
              matched.value,
              pattern_state,
            ),
            bound_roots: roots,
            flow: FlowNormal,
            value: matched.value,
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
) -> ConditionEval {
  let left = eval_condition_scope(lhs, state, spec, findings)
  if left.flow != FlowNormal {
    return left
  }
  let right = eval_condition_scope(rhs, left.true_state, spec, findings)
  let base = restore_scoped_roots(
    left.base_state,
    right.base_state,
    left.bound_roots,
  )
  {
    base_state: base,
    true_state: right.true_state,
    bound_roots: merge_root_names(left.bound_roots, right.bound_roots),
    flow: right.flow,
    value: tree_merge(left.value, right.value),
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
) -> EvalResult {
  let mut current = state
  let mut value : TaintTree = []
  for pattern in patterns {
    let result = match lex_top_pattern_kind(pattern) {
      Some(@untyped_cst.LexTopPattern_Pattern) =>
        eval_lex_pattern_exprs(pattern, current, spec, findings)
      Some(@untyped_cst.LexTopPattern_Binder)
      | Some(@untyped_cst.LexTopPattern_Wildcard) => normal_result(current, [])
      _ => normal_result(current, [])
    }
    if result.flow != FlowNormal {
      return result
    }
    current = result.state
    value = tree_merge(value, result.value)
  }
  normal_result(current, value)
}

///|
fn eval_lex_pattern_exprs(
  pattern : @untyped_cst.CstNode,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
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
      for pat in pattern_body_items(pattern) {
        let result = eval_lex_pattern_exprs(pat, current, spec, findings)
        if result.flow != FlowNormal {
          return result
        }
        current = result.state
        value = tree_merge(value, result.value)
      }
      normal_result(current, value)
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
) -> EvalResult {
  let mut current = state
  let mut value : TaintTree = []
  for elem in elems {
    match elem.kind {
      @untyped_cst.InterpSegment_Source =>
        if node_child(elem, "expr") is Some(expr) {
          let result = eval_expr(expr, current, spec, findings)
          if result.flow != FlowNormal {
            return result
          }
          current = result.state
          value = tree_merge(value, result.value)
        }
      @untyped_cst.InterpSegment_Literal => ()
      _ => ()
    }
  }
  normal_result(current, value)
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
) -> EvalResult {
  let cond_result = eval_condition_scope(cond, state, spec, findings)
  if cond_result.flow != FlowNormal {
    return {
      state: cond_result.base_state,
      value: cond_result.value,
      flow: cond_result.flow,
    }
  }
  let then_result = restore_result_scoped_roots(
    eval_expr(ifso, cond_result.true_state, spec, findings),
    cond_result.base_state,
    cond_result.bound_roots,
  )
  let else_result = if ifnot is Some(expr) {
    eval_expr(expr, cond_result.base_state, spec, findings)
  } else {
    normal_result(cond_result.base_state, [])
  }
  merge_branch_results(then_result, else_result)
}

///|
fn merge_branch_results(
  then_result : EvalResult,
  else_result : EvalResult,
) -> EvalResult {
  if then_result.flow != FlowNormal && else_result.flow == FlowNormal {
    return else_result
  }
  if else_result.flow != FlowNormal && then_result.flow == FlowNormal {
    return then_result
  }
  if then_result.flow != FlowNormal {
    return then_result
  }
  normal_result(
    state_merge(then_result.state, else_result.state),
    tree_merge(then_result.value, else_result.value),
  )
}

///|
fn eval_guard(
  cond : @untyped_cst.CstNode,
  otherwise : @untyped_cst.CstNode?,
  body : @untyped_cst.CstNode,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let cond_result = eval_condition_scope(cond, state, spec, findings)
  if cond_result.flow != FlowNormal {
    return {
      state: cond_result.base_state,
      value: cond_result.value,
      flow: cond_result.flow,
    }
  }
  let body_result = restore_result_scoped_roots(
    eval_expr(body, cond_result.true_state, spec, findings),
    cond_result.base_state,
    cond_result.bound_roots,
  )
  let else_result = if otherwise is Some(expr) {
    eval_expr(expr, cond_result.base_state, spec, findings)
  } else {
    normal_result(cond_result.base_state, [])
  }
  merge_branch_results(body_result, else_result)
}

///|
fn eval_match(
  scrutinee : @untyped_cst.CstNode,
  cases : Array[@untyped_cst.CstNode],
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let scrutinee_result = eval_expr(scrutinee, state, spec, findings)
  if scrutinee_result.flow != FlowNormal {
    return scrutinee_result
  }
  let normal_states : Array[TaintState] = []
  let mut branch_value : TaintTree = []
  let exit_states : Array[TaintState] = []
  let mut exit_flow = FlowNormal
  let mut exit_value : TaintTree = []
  for case in cases {
    let case_result = eval_pattern_case(
      case,
      scrutinee_result.value,
      scrutinee_result.state,
      spec,
      findings,
    )
    if case_result.flow == FlowNormal {
      normal_states.push(case_result.state)
      branch_value = tree_merge(branch_value, case_result.value)
    } else {
      if exit_states.is_empty() {
        exit_flow = case_result.flow
        exit_value = case_result.value
      }
      exit_states.push(case_result.state)
    }
  }
  if normal_states.length() > 0 {
    normal_result(state_merge_all(normal_states), branch_value)
  } else if exit_states.length() > 0 {
    flow_result(exit_flow, state_merge_all(exit_states), exit_value)
  } else {
    normal_result(scrutinee_result.state, [])
  }
}

///|
fn eval_pattern_case(
  case : @untyped_cst.CstNode,
  value : TaintTree,
  base_state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
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
    if guard_result.flow == FlowNormal {
      restore_result_scoped_roots(
        eval_expr(body, guard_result.true_state, spec, findings),
        guard_result.base_state,
        guard_result.bound_roots,
      )
    } else {
      {
        state: guard_result.base_state,
        value: guard_result.value,
        flow: guard_result.flow,
      }
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
) -> EvalResult {
  let scrutinee_result = eval_expr(scrutinee, state, spec, findings)
  if scrutinee_result.flow != FlowNormal {
    return scrutinee_result
  }
  let normal_states : Array[TaintState] = []
  let mut branch_value : TaintTree = []
  let exit_states : Array[TaintState] = []
  let mut exit_flow = FlowNormal
  let mut exit_value : TaintTree = []
  for case in cases {
    let case_result = eval_lex_case(
      case,
      scrutinee_result.value,
      scrutinee_result.state,
      spec,
      findings,
    )
    if case_result.flow == FlowNormal {
      normal_states.push(case_result.state)
      branch_value = tree_merge(branch_value, case_result.value)
    } else {
      if exit_states.is_empty() {
        exit_flow = case_result.flow
        exit_value = case_result.value
      }
      exit_states.push(case_result.state)
    }
  }
  if normal_states.length() > 0 {
    normal_result(state_merge_all(normal_states), branch_value)
  } else if exit_states.length() > 0 {
    flow_result(exit_flow, state_merge_all(exit_states), exit_value)
  } else {
    normal_result(scrutinee_result.state, [])
  }
}

///|
fn eval_lex_case(
  case : @untyped_cst.CstNode,
  value : TaintTree,
  base_state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let patterns = if node_child(case, "pat") is Some(pattern) {
    lex_top_pattern_items(pattern)
  } else {
    []
  }
  let pattern_result = eval_lex_top_pattern_exprs(
    patterns, base_state, spec, findings,
  )
  if pattern_result.flow != FlowNormal {
    return pattern_result
  }
  let body = if node_child(case, "body") is Some(body) {
    body
  } else {
    return normal_result(pattern_result.state, [])
  }
  let roots = lex_top_patterns_bound_roots(patterns)
  let bound = bind_lex_top_patterns(patterns, value, pattern_result.state)
  let result = if node_optional_child(case, "guard") is Some(guard_expr) {
    let guard_result = eval_condition_scope(guard_expr, bound, spec, findings)
    if guard_result.flow == FlowNormal {
      restore_result_scoped_roots(
        eval_expr(body, guard_result.true_state, spec, findings),
        guard_result.base_state,
        guard_result.bound_roots,
      )
    } else {
      {
        state: guard_result.base_state,
        value: guard_result.value,
        flow: guard_result.flow,
      }
    }
  } else {
    eval_expr(body, bound, spec, findings)
  }
  restore_result_scoped_roots(result, pattern_result.state, roots)
}

///|
fn eval_lex_scan(
  scrutinee : @untyped_cst.CstNode,
  cases : Array[@untyped_cst.CstNode],
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let scrutinee_result = eval_expr(scrutinee, state, spec, findings)
  if scrutinee_result.flow != FlowNormal {
    return scrutinee_result
  }
  let normal_states : Array[TaintState] = []
  let mut branch_value : TaintTree = []
  let exit_states : Array[TaintState] = []
  let mut exit_flow = FlowNormal
  let mut exit_value : TaintTree = []
  for case in cases {
    let case_result = eval_lex_scan_case(
      case,
      scrutinee_result.value,
      scrutinee_result.state,
      spec,
      findings,
    )
    if case_result.flow == FlowNormal {
      normal_states.push(case_result.state)
      branch_value = tree_merge(branch_value, case_result.value)
    } else {
      if exit_states.is_empty() {
        exit_flow = case_result.flow
        exit_value = case_result.value
      }
      exit_states.push(case_result.state)
    }
  }
  if normal_states.length() > 0 {
    normal_result(state_merge_all(normal_states), branch_value)
  } else if exit_states.length() > 0 {
    flow_result(exit_flow, state_merge_all(exit_states), exit_value)
  } else {
    normal_result(scrutinee_result.state, [])
  }
}

///|
fn eval_lex_scan_case(
  case : @untyped_cst.CstNode,
  value : TaintTree,
  base_state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
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
    if guard_result.flow == FlowNormal {
      restore_result_scoped_roots(
        eval_expr(body, guard_result.true_state, spec, findings),
        guard_result.base_state,
        guard_result.bound_roots,
      )
    } else {
      {
        state: guard_result.base_state,
        value: guard_result.value,
        flow: guard_result.flow,
      }
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
) -> EvalResult {
  let body_result = eval_expr(body, state, spec, findings)
  match body_result.flow {
    FlowReturn | FlowBreak(_) | FlowContinue(_) => return body_result
    FlowRaise => return eval_catch_cases(body_result, catch_, spec, findings)
    FlowNormal => ()
  }
  let branch_states : Array[TaintState] = [body_result.state]
  let mut branch_value = body_result.value
  for case in catch_ {
    let result = eval_pattern_case(case, [], body_result.state, spec, findings)
    if result.flow == FlowNormal {
      branch_states.push(result.state)
      branch_value = tree_merge(branch_value, result.value)
    }
  }
  if try_else is Some(cases) {
    for case in case_items(cases) {
      let result = eval_pattern_case(
        case,
        body_result.value,
        body_result.state,
        spec,
        findings,
      )
      if result.flow == FlowNormal {
        branch_states.push(result.state)
        branch_value = tree_merge(branch_value, result.value)
      }
    }
  }
  normal_result(state_merge_all(branch_states), branch_value)
}

///|
fn eval_catch_cases(
  raised : EvalResult,
  catch_ : Array[@untyped_cst.CstNode],
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let normal_states : Array[TaintState] = []
  let mut branch_value : TaintTree = []
  let exit_states : Array[TaintState] = []
  let mut exit_flow = FlowRaise
  let mut exit_value = raised.value
  for case in catch_ {
    let case_result = eval_pattern_case(
      case,
      raised.value,
      raised.state,
      spec,
      findings,
    )
    if case_result.flow == FlowNormal {
      normal_states.push(case_result.state)
      branch_value = tree_merge(branch_value, case_result.value)
    } else {
      if exit_states.is_empty() {
        exit_flow = case_result.flow
        exit_value = case_result.value
      }
      exit_states.push(case_result.state)
    }
  }
  if normal_states.length() > 0 {
    normal_result(state_merge_all(normal_states), branch_value)
  } else if exit_states.length() > 0 {
    flow_result(exit_flow, state_merge_all(exit_states), exit_value)
  } else {
    raised
  }
}

///|
fn eval_while(
  loop_label : String?,
  loop_cond : @untyped_cst.CstNode,
  loop_body : @untyped_cst.CstNode,
  while_else : @untyped_cst.CstNode?,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let mut current = state
  let mut break_value : TaintTree = []
  let mut iteration = 0
  // Loops are interpreted to a bounded fixpoint. The condition is evaluated on
  // each abstract iteration so condition pattern bindings are scoped to the
  // body and restored before the loop state is joined.
  while iteration < spec.max_fixpoint_iterations {
    let cond_result = eval_condition_scope(loop_cond, current, spec, findings)
    if cond_result.flow != FlowNormal {
      return {
        state: cond_result.base_state,
        value: cond_result.value,
        flow: cond_result.flow,
      }
    }
    let body_result = restore_result_scoped_roots(
      eval_expr(loop_body, cond_result.true_state, spec, findings),
      cond_result.base_state,
      cond_result.bound_roots,
    )
    match body_result.flow {
      FlowReturn | FlowRaise => return body_result
      FlowBreak(target) => {
        if !control_targets_loop(target, loop_label) {
          return body_result
        }
        current = state_merge(cond_result.base_state, body_result.state)
        break_value = tree_merge(break_value, body_result.value)
        break
      }
      FlowContinue(target) =>
        if !control_targets_loop(target, loop_label) {
          return body_result
        }
      FlowNormal => ()
    }
    let joined = state_merge(cond_result.base_state, body_result.state)
    if state_equiv(joined, current) {
      break
    }
    current = joined
    iteration += 1
  }
  if while_else is Some(expr) {
    let else_result = eval_expr(expr, current, spec, findings)
    if else_result.flow != FlowNormal {
      return else_result
    }
    normal_result(
      state_merge(current, else_result.state),
      tree_merge(break_value, else_result.value),
    )
  } else {
    normal_result(current, break_value)
  }
}

///|
fn eval_for(
  loop_label : String?,
  binders : Array[@untyped_cst.CstNode],
  condition : @untyped_cst.CstNode?,
  continue_block : Array[@untyped_cst.CstNode],
  body : @untyped_cst.CstNode,
  for_else : @untyped_cst.CstNode?,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let loop_roots : Array[String] = []
  let mut loop_base = state
  let mut current = state
  let mut break_value : TaintTree = []
  for pair in binders {
    match (node_child(pair, "binder"), node_child(pair, "expr")) {
      (Some(binder), Some(expr)) => {
        let result = eval_expr(expr, current, spec, findings)
        if result.flow != FlowNormal {
          return restore_result_scoped_roots(result, loop_base, loop_roots)
        }
        current = result.state
        loop_base = restore_scoped_roots(loop_base, current, loop_roots)
        add_binder_root_name(loop_roots, binder)
        current = bind_binder(binder, result.value, current)
      }
      _ => ()
    }
  }
  let mut iteration = 0
  // `for` uses the same bounded fixpoint strategy as `while`. Loop binders stay
  // available to condition/body/continue/else expressions and are restored
  // after the loop expression finishes.
  while iteration < spec.max_fixpoint_iterations {
    let cond_result = if condition is Some(expr) {
      eval_condition_scope(expr, current, spec, findings)
    } else {
      {
        base_state: current,
        true_state: current,
        bound_roots: [],
        flow: FlowNormal,
        value: [],
      }
    }
    if cond_result.flow != FlowNormal {
      return restore_result_scoped_roots(
        {
          state: cond_result.base_state,
          value: cond_result.value,
          flow: cond_result.flow,
        },
        loop_base,
        loop_roots,
      )
    }
    let raw_body_result = eval_expr(
      body,
      cond_result.true_state,
      spec,
      findings,
    )
    let body_result = restore_result_scoped_roots(
      raw_body_result,
      cond_result.base_state,
      cond_result.bound_roots,
    )
    match body_result.flow {
      FlowReturn | FlowRaise =>
        return restore_result_scoped_roots(body_result, loop_base, loop_roots)
      FlowBreak(target) => {
        if !control_targets_loop(target, loop_label) {
          return restore_result_scoped_roots(body_result, loop_base, loop_roots)
        }
        current = state_merge(cond_result.base_state, body_result.state)
        break_value = tree_merge(break_value, body_result.value)
        break
      }
      FlowContinue(target) =>
        if !control_targets_loop(target, loop_label) {
          return restore_result_scoped_roots(body_result, loop_base, loop_roots)
        }
      FlowNormal => ()
    }
    let mut next = raw_body_result.state
    for pair in continue_block {
      match (node_child(pair, "binder"), node_child(pair, "expr")) {
        (Some(binder), Some(expr)) => {
          let result = eval_expr(expr, next, spec, findings)
          if result.flow != FlowNormal {
            let restored = restore_result_scoped_roots(
              result,
              cond_result.base_state,
              cond_result.bound_roots,
            )
            return restore_result_scoped_roots(restored, loop_base, loop_roots)
          }
          next = result.state
          let base_candidate = restore_scoped_roots(
            cond_result.base_state,
            next,
            cond_result.bound_roots,
          )
          loop_base = restore_scoped_roots(
            loop_base, base_candidate, loop_roots,
          )
          add_binder_root_name(loop_roots, binder)
          next = bind_binder(binder, result.value, next)
        }
        _ => ()
      }
    }
    next = restore_scoped_roots(
      cond_result.base_state,
      next,
      cond_result.bound_roots,
    )
    let joined = state_merge(cond_result.base_state, next)
    if state_equiv(joined, current) {
      break
    }
    current = joined
    iteration += 1
  }
  let result = if for_else is Some(expr) {
    eval_expr(expr, current, spec, findings)
  } else {
    normal_result(current, [])
  }
  if result.flow != FlowNormal {
    restore_result_scoped_roots(result, loop_base, loop_roots)
  } else {
    normal_result(
      restore_scoped_roots(loop_base, result.state, loop_roots),
      tree_merge(break_value, result.value),
    )
  }
}

///|
fn eval_for_each(
  loop_label : String?,
  binders : Array[@untyped_cst.CstNode],
  collection : @untyped_cst.CstNode,
  init : Array[@untyped_cst.CstNode],
  continue_block : Array[@untyped_cst.CstNode],
  body : @untyped_cst.CstNode,
  else_block : @untyped_cst.CstNode?,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let collection_result = eval_expr(collection, state, spec, findings)
  if collection_result.flow != FlowNormal {
    return collection_result
  }
  let loop_roots : Array[String] = []
  let mut loop_base = collection_result.state
  let mut current = collection_result.state
  let mut break_value : TaintTree = []
  for pair in init {
    match (node_child(pair, "init"), node_child(pair, "expr")) {
      (Some(binder), Some(expr)) => {
        let result = eval_expr(expr, current, spec, findings)
        if result.flow != FlowNormal {
          return restore_result_scoped_roots(result, loop_base, loop_roots)
        }
        current = result.state
        loop_base = restore_scoped_roots(loop_base, current, loop_roots)
        add_binder_root_name(loop_roots, binder)
        current = bind_binder(binder, result.value, current)
      }
      _ => ()
    }
  }
  for binder in binders {
    if !node_is_null(binder) {
      add_binder_root_name(loop_roots, binder)
      current = bind_binder(
        binder,
        tree_project_for_binding(collection_result.value, AnyIndex),
        current,
      )
    }
  }
  let mut iteration = 0
  // A foreach binder receives the collection's `AnyIndex` taint summary before
  // the loop body fixpoint starts.
  while iteration < spec.max_fixpoint_iterations {
    let body_result = eval_expr(body, current, spec, findings)
    match body_result.flow {
      FlowReturn | FlowRaise =>
        return restore_result_scoped_roots(body_result, loop_base, loop_roots)
      FlowBreak(target) => {
        if !control_targets_loop(target, loop_label) {
          return restore_result_scoped_roots(body_result, loop_base, loop_roots)
        }
        current = state_merge(current, body_result.state)
        break_value = tree_merge(break_value, body_result.value)
        break
      }
      FlowContinue(target) =>
        if !control_targets_loop(target, loop_label) {
          return restore_result_scoped_roots(body_result, loop_base, loop_roots)
        }
      FlowNormal => ()
    }
    let mut next = body_result.state
    for pair in continue_block {
      match (node_child(pair, "binder"), node_child(pair, "expr")) {
        (Some(binder), Some(expr)) => {
          let result = eval_expr(expr, next, spec, findings)
          if result.flow != FlowNormal {
            return restore_result_scoped_roots(result, loop_base, loop_roots)
          }
          next = result.state
          loop_base = restore_scoped_roots(loop_base, next, loop_roots)
          add_binder_root_name(loop_roots, binder)
          next = bind_binder(binder, result.value, next)
        }
        _ => ()
      }
    }
    let joined = state_merge(current, next)
    if state_equiv(joined, current) {
      break
    }
    current = joined
    iteration += 1
  }
  let result = if else_block is Some(expr) {
    eval_expr(expr, current, spec, findings)
  } else {
    normal_result(current, [])
  }
  if result.flow != FlowNormal {
    restore_result_scoped_roots(result, loop_base, loop_roots)
  } else {
    normal_result(
      restore_scoped_roots(loop_base, result.state, loop_roots),
      tree_merge(break_value, result.value),
    )
  }
}

///|
fn eval_unknown_expr(
  expr : @untyped_cst.CstNode,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
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
      for elem in node_child_items(expr, "elems") {
        if node_child(elem, "expr") is Some(child) {
          let result = eval_expr(child, current, spec, findings)
          if result.flow != FlowNormal {
            return result
          }
          current = result.state
          value = tree_merge(value, result.value)
        }
      }
      normal_result(current, value)
    }
    @untyped_cst.Expr_RecordUpdate =>
      if node_child(expr, "record") is Some(record) {
        let base = eval_expr(record, state, spec, findings)
        if base.flow != FlowNormal {
          return base
        }
        eval_record_expr(
          node_child_items(expr, "fields"),
          base.state,
          spec,
          findings,
        )
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
) -> EvalResult {
  let mut current = state
  let mut value : TaintTree = []
  for child in children {
    let result = eval_expr(child, current, spec, findings)
    if result.flow != FlowNormal {
      return result
    }
    current = result.state
    value = tree_merge(value, result.value)
  }
  normal_result(current, value)
}
