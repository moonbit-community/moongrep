///|
// Control-flow exits are tracked so unreachable later expressions do not report
// sinks after `return`, `raise`, `break`, or `continue`.
priv enum FlowExit {
  FlowNormal
  FlowReturn
  FlowRaise
  FlowBreak
  FlowContinue
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
fn analyze_single_function_like(
  node : @untyped_ast.Node,
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
  expr : @untyped_ast.Node,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  match expr.kind {
    Expr_Ident => eval_path_like(expr, state)
    Expr_Field =>
      match (node_child(expr, "record"), node_child(expr, "accessor")) {
        (Some(record), Some(accessor)) =>
          eval_field_expr(expr, record, accessor, state, spec, findings)
        _ => normal_result(state, [])
      }
    Expr_ArrayGet =>
      match (node_child(expr, "array"), node_child(expr, "index")) {
        (Some(array), Some(index)) =>
          eval_array_get_expr(expr, array, index, state, spec, findings)
        _ => normal_result(state, [])
      }
    Expr_Tuple =>
      eval_tuple_expr(node_child_items(expr, "exprs"), state, spec, findings)
    Expr_Array =>
      eval_array_expr(node_child_items(expr, "exprs"), state, spec, findings)
    Expr_Record =>
      eval_record_expr(node_child_items(expr, "fields"), state, spec, findings)
    Expr_Group | Expr_Constraint =>
      match node_child(expr, "expr") {
        Some(inner) => eval_expr(inner, state, spec, findings)
        None => normal_result(state, [])
      }
    Expr_Sequence =>
      match node_child(expr, "last_expr") {
        Some(last_expr) =>
          eval_sequence(
            node_child_items(expr, "exprs"),
            last_expr,
            state,
            spec,
            findings,
          )
        None => normal_result(state, [])
      }
    Expr_Let =>
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
    Expr_LetMut =>
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
    Expr_Assign =>
      match (node_child(expr, "var"), node_child(expr, "expr")) {
        (Some(var_), Some(rhs)) => eval_assign(var_, rhs, state, spec, findings)
        _ => normal_result(state, [])
      }
    Expr_Mutate =>
      match
        (
          node_child(expr, "record"),
          node_child(expr, "accessor"),
          node_child(expr, "field"),
        ) {
        (Some(record), Some(accessor), Some(field)) =>
          eval_mutate(record, accessor, field, state, spec, findings)
        _ => normal_result(state, [])
      }
    Expr_Apply =>
      match (node_child(expr, "func"), node_child(expr, "args")) {
        (Some(func), Some(args)) =>
          eval_apply_call(expr, func, args, expr.loc, state, spec, findings)
        _ => normal_result(state, [])
      }
    Expr_DotApply =>
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
    Expr_Pipe =>
      match (node_child(expr, "lhs"), node_child(expr, "rhs")) {
        (Some(lhs), Some(rhs)) =>
          eval_pipe_call(expr, lhs, rhs, expr.loc, state, spec, findings)
        _ => normal_result(state, [])
      }
    Expr_RevPipe =>
      match (node_child(expr, "lhs"), node_child(expr, "rhs")) {
        (Some(lhs), Some(rhs)) =>
          eval_rev_pipe_call(expr, lhs, rhs, expr.loc, state, spec, findings)
        _ => normal_result(state, [])
      }
    Expr_If =>
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
    Expr_Match =>
      match node_child(expr, "expr") {
        Some(scrutinee) =>
          eval_match(
            scrutinee,
            node_child_items(expr, "cases"),
            state,
            spec,
            findings,
          )
        None => normal_result(state, [])
      }
    Expr_Lexmatch =>
      match node_child(expr, "expr") {
        Some(scrutinee) =>
          eval_lex_match(
            scrutinee,
            node_child_items(expr, "cases"),
            state,
            spec,
            findings,
          )
        None => normal_result(state, [])
      }
    Expr_Try =>
      match node_child(expr, "body") {
        Some(body) =>
          eval_try(
            body,
            node_child_items(expr, "catch"),
            node_optional_child(expr, "try_else"),
            state,
            spec,
            findings,
          )
        None => normal_result(state, [])
      }
    Expr_While =>
      match (node_child(expr, "loop_cond"), node_child(expr, "loop_body")) {
        (Some(loop_cond), Some(loop_body)) =>
          eval_while(
            loop_cond,
            loop_body,
            node_optional_child(expr, "while_else"),
            state,
            spec,
            findings,
          )
        _ => normal_result(state, [])
      }
    Expr_For =>
      match node_child(expr, "body") {
        Some(body) =>
          eval_for(
            node_child_items(expr, "binders"),
            node_optional_child(expr, "condition"),
            node_child_items(expr, "continue_block"),
            body,
            node_optional_child(expr, "for_else"),
            state,
            spec,
            findings,
          )
        None => normal_result(state, [])
      }
    Expr_ForEach =>
      match (node_child(expr, "expr"), node_child(expr, "body")) {
        (Some(collection), Some(body)) =>
          eval_for_each(
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
    Expr_LetFn =>
      match (node_child(expr, "name"), node_child(expr, "body")) {
        (Some(name), Some(body)) => {
          let roots : Array[String] = []
          add_binder_root_name(roots, name)
          eval_clean_root_scope(body, roots, state, spec, findings)
        }
        _ => normal_result(state, [])
      }
    Expr_LetAnd =>
      match node_child(expr, "body") {
        Some(body) =>
          eval_clean_root_scope(
            body,
            let_and_bound_roots(node_child_items(expr, "bindings")),
            state,
            spec,
            findings,
          )
        None => normal_result(state, [])
      }
    Expr_Function => normal_result(state, [])
    Expr_Return =>
      match node_optional_child(expr, "return_value") {
        Some(value) => {
          let result = eval_expr(value, state, spec, findings)
          flow_result(FlowReturn, result.state, result.value)
        }
        None => flow_result(FlowReturn, state, [])
      }
    Expr_Break =>
      match node_optional_child(expr, "arg") {
        Some(value) => {
          let result = eval_expr(value, state, spec, findings)
          flow_result(FlowBreak, result.state, result.value)
        }
        None => flow_result(FlowBreak, state, [])
      }
    Expr_Raise =>
      match node_child(expr, "err_value") {
        Some(value) => {
          let result = eval_expr(value, state, spec, findings)
          flow_result(FlowRaise, result.state, result.value)
        }
        None => flow_result(FlowRaise, state, [])
      }
    Expr_Continue => {
      let result = eval_children(
        node_child_items(expr, "args"),
        state,
        spec,
        findings,
      )
      flow_result(FlowContinue, result.state, result.value)
    }
    _ => eval_unknown_expr(expr, state, spec, findings)
  }
}

///|
fn eval_path_like(expr : @untyped_ast.Node, state : TaintState) -> EvalResult {
  if storage_path_from_expr(expr) is Some(path) {
    normal_result(state, state_read_path(state, path))
  } else {
    normal_result(state, [])
  }
}

///|
fn eval_field_expr(
  expr : @untyped_ast.Node,
  record : @untyped_ast.Node,
  accessor : @untyped_ast.Node,
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
  expr : @untyped_ast.Node,
  array : @untyped_ast.Node,
  index : @untyped_ast.Node,
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
  exprs : Array[@untyped_ast.Node],
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
  exprs : Array[@untyped_ast.Node],
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
  fields : Array[@untyped_ast.Node],
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
fn eval_sequence(
  exprs : Array[@untyped_ast.Node],
  last_expr : @untyped_ast.Node,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let mut current = state
  for item in exprs {
    let result = eval_expr(item, current, spec, findings)
    if result.flow != FlowNormal {
      return result
    }
    current = result.state
  }
  eval_expr(last_expr, current, spec, findings)
}

///|
fn eval_let(
  pattern : @untyped_ast.Node,
  bound_expr : @untyped_ast.Node,
  body : @untyped_ast.Node,
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
  binder : @untyped_ast.Node,
  bound_expr : @untyped_ast.Node,
  body : @untyped_ast.Node,
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
  body : @untyped_ast.Node,
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
  var_ : @untyped_ast.Node,
  rhs : @untyped_ast.Node,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let rhs_result = eval_expr(rhs, state, spec, findings)
  if rhs_result.flow != FlowNormal {
    return rhs_result
  }
  if storage_path_from_var(var_) is Some(path) {
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
  record : @untyped_ast.Node,
  accessor : @untyped_ast.Node,
  field : @untyped_ast.Node,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let record_result = eval_expr(record, state, spec, findings)
  if record_result.flow != FlowNormal {
    return record_result
  }
  let field_result = eval_expr(field, record_result.state, spec, findings)
  if field_result.flow != FlowNormal {
    return field_result
  }
  match (storage_path_from_expr(record), segment_from_accessor(accessor)) {
    (Some(path), Some(segment)) =>
      normal_result(
        state_write_path(
          field_result.state,
          append_path_segment(path, segment),
          field_result.value,
        ),
        field_result.value,
      )
    _ => field_result
  }
}

///|
fn eval_apply_call(
  ast : @untyped_ast.Node,
  func : @untyped_ast.Node,
  args : @untyped_ast.Node,
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
    ast,
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
  ast : @untyped_ast.Node,
  self : @untyped_ast.Node,
  method_name : @untyped_ast.Node,
  args : @untyped_ast.Node,
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
    ast,
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
  ast : @untyped_ast.Node,
  lhs : @untyped_ast.Node,
  rhs : @untyped_ast.Node,
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
    Expr_Apply =>
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
            ast,
            loc,
            callee_name_from_expr(func),
            arguments,
          )
          apply_call_transfer(info, args_result.state, spec, findings)
        }
        _ => normal_result(lhs_result.state, lhs_result.value)
      }
    Expr_DotApply =>
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
            ast,
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
        ast,
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
  ast : @untyped_ast.Node,
  lhs : @untyped_ast.Node,
  rhs : @untyped_ast.Node,
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
    ast,
    loc,
    callee_name_from_expr(lhs),
    [arg],
  )
  apply_call_transfer(info, rhs_result.state, spec, findings)
}

///|
fn eval_arguments(
  args : @untyped_ast.Node,
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
    match (node_child(arg, "value"), node_child(arg, "kind")) {
      (Some(value), Some(kind)) => {
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
            argument_label(kind),
            value,
            result,
          ),
        )
      }
      _ => ()
    }
  }
  { state: current, arguments, flow: FlowNormal, value: [] }
}

///|
fn evaled_argument_from_result(
  index : Int,
  label : String?,
  expr : @untyped_ast.Node,
  result : EvalResult,
) -> CallArgument {
  call_argument_from_result(index, label, expr, result)
}

///|
fn call_argument_from_result(
  index : Int,
  label : String?,
  expr : @untyped_ast.Node,
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
  ast : @untyped_ast.Node,
  loc : @basic.Location,
  callee_name : String?,
  arguments : Array[CallArgument],
) -> CallInfo {
  {
    kind,
    ast,
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
fn site_for_expr(expr : @untyped_ast.Node, path : StoragePath?) -> ValueSite {
  if path is Some(path) {
    Path(path)
  } else {
    Expr(expr.loc, None)
  }
}

///|
fn callee_name_from_expr(expr : @untyped_ast.Node) -> String? {
  match expr.kind {
    Expr_Ident =>
      match node_child(expr, "id") {
        Some(id) => node_var_name(id)
        None => None
      }
    Expr_Field =>
      match node_child(expr, "accessor") {
        Some(accessor) =>
          match accessor.kind {
            Accessor_Label => node_first_label_name(accessor)
            _ => None
          }
        None => None
      }
    Expr_Method =>
      match node_child(expr, "method_name") {
        Some(method_name) => node_label_name(method_name)
        None => None
      }
    Expr_Group | Expr_Constraint =>
      match node_child(expr, "expr") {
        Some(inner) => callee_name_from_expr(inner)
        None => None
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
  binder : @untyped_ast.Node,
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
fn pattern_bound_roots(pattern : @untyped_ast.Node) -> Array[String] {
  let roots : Array[String] = []
  add_pattern_bound_roots(roots, pattern)
  roots
}

///|
fn add_pattern_bound_roots(
  roots : Array[String],
  pattern : @untyped_ast.Node,
) -> Unit {
  match pattern.kind {
    Pattern_Var =>
      if node_first_child(pattern) is Some(binder) {
        add_binder_root_name(roots, binder)
      }
    Pattern_Alias => {
      if node_child(pattern, "pat") is Some(pat) {
        add_pattern_bound_roots(roots, pat)
      }
      if node_child(pattern, "alias") is Some(alias_) {
        add_binder_root_name(roots, alias_)
      }
    }
    Pattern_Constraint =>
      if node_child(pattern, "pat") is Some(pat) {
        add_pattern_bound_roots(roots, pat)
      }
    Pattern_Tuple =>
      for pat in node_child_items(pattern, "pats") {
        add_pattern_bound_roots(roots, pat)
      }
    Pattern_Record =>
      for field in node_child_items(pattern, "fields") {
        if node_child(field, "pattern") is Some(pat) {
          add_pattern_bound_roots(roots, pat)
        }
      }
    Pattern_Map =>
      for elem in node_child_items(pattern, "elems") {
        if node_child(elem, "pat") is Some(pat) {
          add_pattern_bound_roots(roots, pat)
        }
      }
    Pattern_Array =>
      if node_child(pattern, "pats") is Some(pats) {
        add_array_pattern_bound_roots(roots, pats)
      }
    Pattern_Constr =>
      for arg in node_optional_items(pattern, "args") {
        if node_child(arg, "pat") is Some(pat) {
          add_pattern_bound_roots(roots, pat)
        }
      }
    Pattern_SpecialConstr =>
      for arg in node_child_items(pattern, "args") {
        if node_child(arg, "pat") is Some(pat) {
          add_pattern_bound_roots(roots, pat)
        }
      }
    Pattern_Or | Pattern_Range => {
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
    Pattern_Any | Pattern_Constant => ()
    _ => ()
  }
}

///|
fn add_array_pattern_bound_roots(
  roots : Array[String],
  patterns : @untyped_ast.Node,
) -> Unit {
  match patterns.kind {
    ArrayPatterns_Closed =>
      if node_first_child(patterns) is Some(items) {
        for item in node_items(items) {
          add_array_pattern_item_bound_roots(roots, item)
        }
      }
    ArrayPatterns_Open => {
      if node_child(patterns, "0") is Some(left) {
        for item in node_items(left) {
          add_array_pattern_item_bound_roots(roots, item)
        }
      }
      if node_child(patterns, "1") is Some(right) {
        for item in node_items(right) {
          add_array_pattern_item_bound_roots(roots, item)
        }
      }
      if node_child(patterns, "2") is Some(middle) {
        add_dot_dot_binder_bound_roots(roots, middle)
      }
    }
    _ => ()
  }
}

///|
fn add_array_pattern_item_bound_roots(
  roots : Array[String],
  item : @untyped_ast.Node,
) -> Unit {
  match item.kind {
    ArrayPattern_Pattern =>
      if node_first_child(item) is Some(pattern) {
        add_pattern_bound_roots(roots, pattern)
      }
    ArrayPattern_ConstSpread =>
      if node_child(item, "binder") is Some(binder) {
        add_binder_root_name(roots, binder)
      }
    ArrayPattern_BytesSpread | ArrayPattern_StringSpread => ()
    _ => ()
  }
}

///|
fn add_dot_dot_binder_bound_roots(
  roots : Array[String],
  binder : @untyped_ast.Node,
) -> Unit {
  match binder.kind {
    DotDotBinder_Binder | DotDotBinder_BinderAs =>
      if node_first_child(binder) is Some(value) {
        add_binder_root_name(roots, value)
      }
    DotDotBinder_NoBinder | DotDotBinder_Underscore => ()
    _ => ()
  }
}

///|
fn let_and_bound_roots(bindings : Array[@untyped_ast.Node]) -> Array[String] {
  let roots : Array[String] = []
  for binding in bindings {
    if node_child(binding, "binder") is Some(binder) {
      add_binder_root_name(roots, binder)
    }
  }
  roots
}

///|
fn bind_binder(
  binder : @untyped_ast.Node,
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
  pattern : @untyped_ast.Node,
  value : TaintTree,
  state : TaintState,
) -> TaintState {
  match pattern.kind {
    Pattern_Var =>
      match node_first_child(pattern) {
        Some(binder) => bind_binder(binder, value, state)
        None => state
      }
    Pattern_Alias => {
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
    Pattern_Constraint =>
      match node_child(pattern, "pat") {
        Some(pat) => bind_pattern(pat, value, state)
        None => state
      }
    Pattern_Tuple => {
      let mut next = state
      let items = node_child_items(pattern, "pats")
      for index in 0..<items.length() {
        next = bind_pattern(
          items[index],
          tree_project_for_binding(value, TupleIndex(index)),
          next,
        )
      }
      next
    }
    Pattern_Record => {
      let mut next = state
      for field in node_child_items(pattern, "fields") {
        if node_child(field, "pattern") is Some(pat) &&
          node_child(field, "label") is Some(label) &&
          node_label_name(label) is Some(name) {
          next = bind_pattern(
            pat,
            tree_project_for_binding(value, Field(name)),
            next,
          )
        }
      }
      next
    }
    Pattern_Map => {
      let mut next = state
      for elem in node_child_items(pattern, "elems") {
        if node_child(elem, "pat") is Some(pat) {
          next = bind_pattern(pat, value, next)
        }
      }
      next
    }
    Pattern_Array =>
      match node_child(pattern, "pats") {
        Some(pats) => bind_array_pattern(pats, value, state)
        None => state
      }
    Pattern_Constr => {
      let mut next = state
      let items = node_optional_items(pattern, "args")
      for index in 0..<items.length() {
        match
          (node_child(items[index], "pat"), node_child(items[index], "kind")) {
          (Some(pat), Some(kind)) => {
            let segment = segment_from_argument_kind(kind, index)
            next = bind_pattern(
              pat,
              tree_project_for_binding(value, segment),
              next,
            )
          }
          _ => ()
        }
      }
      next
    }
    Pattern_SpecialConstr => {
      let mut next = state
      let items = node_child_items(pattern, "args")
      for index in 0..<items.length() {
        match
          (node_child(items[index], "pat"), node_child(items[index], "kind")) {
          (Some(pat), Some(kind)) => {
            let segment = segment_from_argument_kind(kind, index)
            next = bind_pattern(
              pat,
              tree_project_for_binding(value, segment),
              next,
            )
          }
          _ => ()
        }
      }
      next
    }
    Pattern_Or =>
      match (node_child(pattern, "pat1"), node_child(pattern, "pat2")) {
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
fn bind_array_pattern(
  pats : @untyped_ast.Node,
  value : TaintTree,
  state : TaintState,
) -> TaintState {
  match pats.kind {
    ArrayPatterns_Closed =>
      if node_first_child(pats) is Some(items) {
        bind_array_pattern_items(node_items(items), 0, value, state)
      } else {
        state
      }
    ArrayPatterns_Open => {
      let mut next = if node_child(pats, "0") is Some(left) {
        bind_array_pattern_items(node_items(left), 0, value, state)
      } else {
        state
      }
      if node_child(pats, "1") is Some(right) {
        let right_items = node_items(right)
        for index in 0..<right_items.length() {
          next = bind_array_pattern_item(
            right_items[index],
            AnyIndex,
            value,
            next,
          )
        }
      }
      if node_child(pats, "2") is Some(middle) {
        match middle.kind {
          DotDotBinder_Binder | DotDotBinder_BinderAs =>
            if node_first_child(middle) is Some(binder) {
              bind_binder(
                binder,
                tree_project_for_binding(value, AnyIndex),
                next,
              )
            } else {
              next
            }
          DotDotBinder_NoBinder | DotDotBinder_Underscore => next
          _ => next
        }
      } else {
        next
      }
    }
    _ => state
  }
}

///|
fn bind_array_pattern_items(
  items : Array[@untyped_ast.Node],
  start : Int,
  value : TaintTree,
  state : TaintState,
) -> TaintState {
  let mut next = state
  for offset in 0..<items.length() {
    next = bind_array_pattern_item(
      items[offset],
      ConstIndex((start + offset).to_string()),
      value,
      next,
    )
  }
  next
}

///|
fn bind_array_pattern_item(
  item : @untyped_ast.Node,
  segment : PathSegment,
  value : TaintTree,
  state : TaintState,
) -> TaintState {
  match item.kind {
    ArrayPattern_Pattern =>
      if node_first_child(item) is Some(pattern) {
        bind_pattern(pattern, tree_project_for_binding(value, segment), state)
      } else {
        state
      }
    ArrayPattern_ConstSpread =>
      if node_child(item, "binder") is Some(binder) {
        bind_binder(binder, tree_project_for_binding(value, segment), state)
      } else {
        state
      }
    ArrayPattern_BytesSpread | ArrayPattern_StringSpread => state
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
  cond : @untyped_ast.Node,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> ConditionEval {
  match cond.kind {
    Expr_Group | Expr_Constraint =>
      match node_child(cond, "expr") {
        Some(expr) => eval_condition_scope(expr, state, spec, findings)
        None => condition_from_eval_result(normal_result(state, []))
      }
    Expr_Is =>
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
    Expr_IsLexmatch =>
      match node_child(cond, "expr") {
        Some(expr) => {
          let matched = eval_expr(expr, state, spec, findings)
          if matched.flow != FlowNormal {
            return condition_from_eval_result(matched)
          }
          let patterns = node_child_items(cond, "pat")
          let pattern_result = eval_lex_top_pattern_exprs(
            patterns,
            matched.state,
            spec,
            findings,
          )
          if pattern_result.flow != FlowNormal {
            return condition_from_eval_result(pattern_result)
          }
          let roots = lex_top_patterns_bound_roots(patterns)
          {
            base_state: pattern_result.state,
            true_state: bind_lex_top_patterns(
              patterns,
              matched.value,
              pattern_result.state,
            ),
            bound_roots: roots,
            flow: FlowNormal,
            value: matched.value,
          }
        }
        None => condition_from_eval_result(normal_result(state, []))
      }
    Expr_RegexMatch =>
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
    Expr_Infix =>
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
  lhs : @untyped_ast.Node,
  rhs : @untyped_ast.Node,
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
fn is_logical_and_expr(expr : @untyped_ast.Node) -> Bool {
  match node_child(expr, "op") {
    Some(op) => node_var_name(op) == Some("&&")
    None => false
  }
}

///|
fn eval_lex_top_pattern_exprs(
  patterns : Array[@untyped_ast.Node],
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let mut current = state
  let mut value : TaintTree = []
  for pattern in patterns {
    let result = match pattern.kind {
      LexTopPattern_Pattern =>
        match node_first_child(pattern) {
          Some(pat) => eval_lex_pattern_exprs(pat, current, spec, findings)
          None => normal_result(current, [])
        }
      LexTopPattern_Binder | LexTopPattern_Wildcard =>
        normal_result(current, [])
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
  pattern : @untyped_ast.Node,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  match pattern.kind {
    LexPattern_Alias =>
      match node_child(pattern, "pat") {
        Some(pat) => eval_lex_pattern_exprs(pat, state, spec, findings)
        None => normal_result(state, [])
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
      for pat in node_child_items(pattern, "pats") {
        let result = eval_lex_pattern_exprs(pat, current, spec, findings)
        if result.flow != FlowNormal {
          return result
        }
        current = result.state
        value = tree_merge(value, result.value)
      }
      normal_result(current, value)
    }
    LexPattern_ConstantRef | LexPattern_Regex => normal_result(state, [])
    _ => normal_result(state, [])
  }
}

///|
fn eval_interp_elems(
  elems : Array[@untyped_ast.Node],
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let mut current = state
  let mut value : TaintTree = []
  for elem in elems {
    match elem.kind {
      InterpElem_Expr =>
        if node_child(elem, "expr") is Some(expr) {
          let result = eval_expr(expr, current, spec, findings)
          if result.flow != FlowNormal {
            return result
          }
          current = result.state
          value = tree_merge(value, result.value)
        }
      InterpElem_Literal | InterpElem_Source => ()
      _ => ()
    }
  }
  normal_result(current, value)
}

///|
fn lex_top_patterns_bound_roots(
  patterns : Array[@untyped_ast.Node],
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
  pattern : @untyped_ast.Node,
) -> Unit {
  match pattern.kind {
    LexTopPattern_Binder =>
      if node_first_child(pattern) is Some(binder) {
        add_binder_root_name(roots, binder)
      }
    LexTopPattern_Pattern =>
      if node_first_child(pattern) is Some(pat) {
        add_lex_pattern_bound_roots(roots, pat)
      }
    LexTopPattern_Wildcard => ()
    _ => ()
  }
}

///|
fn add_lex_pattern_bound_roots(
  roots : Array[String],
  pattern : @untyped_ast.Node,
) -> Unit {
  match pattern.kind {
    LexPattern_Alias => {
      if node_child(pattern, "pat") is Some(pat) {
        add_lex_pattern_bound_roots(roots, pat)
      }
      if node_child(pattern, "binder") is Some(binder) {
        add_binder_root_name(roots, binder)
      }
    }
    LexPattern_Sequence =>
      for pat in node_child_items(pattern, "pats") {
        add_lex_pattern_bound_roots(roots, pat)
      }
    LexPattern_ConstantRef | LexPattern_Regex | LexPattern_RegexInterp => ()
    _ => ()
  }
}

///|
fn bind_lex_top_patterns(
  patterns : Array[@untyped_ast.Node],
  value : TaintTree,
  state : TaintState,
) -> TaintState {
  let mut next = state
  for pattern in patterns {
    next = match pattern.kind {
      LexTopPattern_Binder =>
        if node_first_child(pattern) is Some(binder) {
          bind_binder(binder, value, next)
        } else {
          next
        }
      LexTopPattern_Pattern =>
        if node_first_child(pattern) is Some(pat) {
          bind_lex_pattern(pat, value, next)
        } else {
          next
        }
      LexTopPattern_Wildcard => next
      _ => next
    }
  }
  next
}

///|
fn bind_lex_pattern(
  pattern : @untyped_ast.Node,
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
      if node_child(pattern, "binder") is Some(binder) {
        bind_binder(binder, value, next)
      } else {
        next
      }
    }
    LexPattern_Sequence => {
      let mut next = state
      for pat in node_child_items(pattern, "pats") {
        next = bind_lex_pattern(pat, value, next)
      }
      next
    }
    LexPattern_ConstantRef | LexPattern_Regex | LexPattern_RegexInterp => state
    _ => state
  }
}

///|
fn regex_pattern_bound_roots(pattern : @untyped_ast.Node) -> Array[String] {
  let roots : Array[String] = []
  add_regex_pattern_bound_roots(roots, pattern)
  roots
}

///|
fn add_regex_pattern_bound_roots(
  roots : Array[String],
  pattern : @untyped_ast.Node,
) -> Unit {
  match pattern.kind {
    RegexPattern_Alias => {
      if node_child(pattern, "pat") is Some(pat) {
        add_regex_pattern_bound_roots(roots, pat)
      }
      if node_child(pattern, "binder") is Some(binder) {
        add_binder_root_name(roots, binder)
      }
    }
    RegexPattern_Alternation | RegexPattern_Sequence => {
      if node_child(pattern, "pat1") is Some(pat1) {
        add_regex_pattern_bound_roots(roots, pat1)
      }
      if node_child(pattern, "pat2") is Some(pat2) {
        add_regex_pattern_bound_roots(roots, pat2)
      }
    }
    RegexPattern_Literal | RegexPattern_Reference => ()
    _ => ()
  }
}

///|
fn regex_bindings_bound_roots(
  bindings : Array[@untyped_ast.Node],
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
  pattern : @untyped_ast.Node,
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
      if node_child(pattern, "binder") is Some(binder) {
        bind_binder(binder, value, next)
      } else {
        next
      }
    }
    RegexPattern_Alternation =>
      match (node_child(pattern, "pat1"), node_child(pattern, "pat2")) {
        (Some(pat1), Some(pat2)) =>
          state_merge(
            bind_regex_pattern(pat1, value, state),
            bind_regex_pattern(pat2, value, state),
          )
        _ => state
      }
    RegexPattern_Sequence =>
      match (node_child(pattern, "pat1"), node_child(pattern, "pat2")) {
        (Some(pat1), Some(pat2)) =>
          bind_regex_pattern(
            pat2,
            value,
            bind_regex_pattern(pat1, value, state),
          )
        _ => state
      }
    RegexPattern_Literal | RegexPattern_Reference => state
    _ => state
  }
}

///|
fn bind_regex_bindings(
  bindings : Array[@untyped_ast.Node],
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
  cond : @untyped_ast.Node,
  ifso : @untyped_ast.Node,
  ifnot : @untyped_ast.Node?,
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
  cond : @untyped_ast.Node,
  otherwise : @untyped_ast.Node?,
  body : @untyped_ast.Node,
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
  scrutinee : @untyped_ast.Node,
  cases : Array[@untyped_ast.Node],
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
  case : @untyped_ast.Node,
  value : TaintTree,
  base_state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let pattern = match node_child(case, "pattern") {
    Some(pattern) => pattern
    None => return normal_result(base_state, [])
  }
  let body = match node_child(case, "body") {
    Some(body) => body
    None => return normal_result(base_state, [])
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
  scrutinee : @untyped_ast.Node,
  cases : Array[@untyped_ast.Node],
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
  case : @untyped_ast.Node,
  value : TaintTree,
  base_state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let patterns = node_child_items(case, "pat")
  let pattern_result = eval_lex_top_pattern_exprs(
    patterns, base_state, spec, findings,
  )
  if pattern_result.flow != FlowNormal {
    return pattern_result
  }
  let body = match node_child(case, "body") {
    Some(body) => body
    None => return normal_result(pattern_result.state, [])
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
fn eval_try(
  body : @untyped_ast.Node,
  catch_ : Array[@untyped_ast.Node],
  try_else : @untyped_ast.Node?,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let body_result = eval_expr(body, state, spec, findings)
  if body_result.flow == FlowReturn ||
    body_result.flow == FlowBreak ||
    body_result.flow == FlowContinue {
    return body_result
  }
  if body_result.flow == FlowRaise {
    return eval_catch_cases(body_result, catch_, spec, findings)
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
    for case in node_items(cases) {
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
  catch_ : Array[@untyped_ast.Node],
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
  loop_cond : @untyped_ast.Node,
  loop_body : @untyped_ast.Node,
  while_else : @untyped_ast.Node?,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let mut current = state
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
    if body_result.flow == FlowReturn || body_result.flow == FlowRaise {
      return body_result
    }
    if body_result.flow == FlowBreak {
      current = state_merge(cond_result.base_state, body_result.state)
      break
    }
    let joined = state_merge(cond_result.base_state, body_result.state)
    if state_equiv(joined, current) {
      break
    }
    current = joined
    iteration = iteration + 1
  }
  if while_else is Some(expr) {
    let else_result = eval_expr(expr, current, spec, findings)
    if else_result.flow != FlowNormal {
      return else_result
    }
    normal_result(state_merge(current, else_result.state), else_result.value)
  } else {
    normal_result(current, [])
  }
}

///|
fn eval_for(
  binders : Array[@untyped_ast.Node],
  condition : @untyped_ast.Node?,
  continue_block : Array[@untyped_ast.Node],
  body : @untyped_ast.Node,
  for_else : @untyped_ast.Node?,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let loop_roots : Array[String] = []
  let mut loop_base = state
  let mut current = state
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
    if body_result.flow == FlowReturn || body_result.flow == FlowRaise {
      return restore_result_scoped_roots(body_result, loop_base, loop_roots)
    }
    if body_result.flow == FlowBreak {
      current = state_merge(cond_result.base_state, body_result.state)
      break
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
    iteration = iteration + 1
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
      result.value,
    )
  }
}

///|
fn eval_for_each(
  binders : Array[@untyped_ast.Node],
  collection : @untyped_ast.Node,
  init : Array[@untyped_ast.Node],
  continue_block : Array[@untyped_ast.Node],
  body : @untyped_ast.Node,
  else_block : @untyped_ast.Node?,
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
    if body_result.flow == FlowReturn || body_result.flow == FlowRaise {
      return restore_result_scoped_roots(body_result, loop_base, loop_roots)
    }
    if body_result.flow == FlowBreak {
      current = state_merge(current, body_result.state)
      break
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
    iteration = iteration + 1
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
      result.value,
    )
  }
}

///|
fn eval_unknown_expr(
  expr : @untyped_ast.Node,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  match expr.kind {
    Expr_Infix =>
      eval_children(
        node_children_by_names(expr, ["lhs", "rhs"]),
        state,
        spec,
        findings,
      )
    Expr_Unary =>
      match node_child(expr, "expr") {
        Some(inner) => eval_expr(inner, state, spec, findings)
        None => normal_result(state, [])
      }
    Expr_As | Expr_TryOperator | Expr_ProofAssert | Expr_TemplateWriting =>
      match node_child(expr, "expr") {
        Some(inner) => eval_expr(inner, state, spec, findings)
        None =>
          match node_child(expr, "body") {
            Some(body) => eval_expr(body, state, spec, findings)
            None => normal_result(state, [])
          }
      }
    Expr_ArraySet | Expr_ArrayAugmentedSet =>
      eval_children(
        node_children_by_names(expr, ["array", "index", "value"]),
        state,
        spec,
        findings,
      )
    Expr_ArrayGetSlice =>
      eval_children(
        node_optional_children_by_names(expr, [
          "array", "start_index", "end_index",
        ]),
        state,
        spec,
        findings,
      )
    Expr_Defer =>
      eval_children(
        node_children_by_names(expr, ["expr", "body"]),
        state,
        spec,
        findings,
      )
    Expr_Guard =>
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
    Expr_Is | Expr_RegexMatch =>
      match node_child(expr, "expr") {
        Some(inner) => eval_expr(inner, state, spec, findings)
        None => normal_result(state, [])
      }
    Expr_IsLexmatch =>
      match node_child(expr, "expr") {
        Some(inner) => {
          let matched = eval_expr(inner, state, spec, findings)
          if matched.flow != FlowNormal {
            return matched
          }
          let pattern_result = eval_lex_top_pattern_exprs(
            node_child_items(expr, "pat"),
            matched.state,
            spec,
            findings,
          )
          if pattern_result.flow != FlowNormal {
            return pattern_result
          }
          normal_result(pattern_result.state, matched.value)
        }
        None => normal_result(state, [])
      }
    Expr_Interp =>
      eval_interp_elems(node_child_items(expr, "elems"), state, spec, findings)
    Expr_Map => {
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
    Expr_RecordUpdate =>
      match node_child(expr, "record") {
        Some(record) => {
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
        }
        None => normal_result(state, [])
      }
    _ => normal_result(state, [])
  }
}

///|
fn node_children_by_names(
  node : @untyped_ast.Node,
  names : Array[String],
) -> Array[@untyped_ast.Node] {
  let children : Array[@untyped_ast.Node] = []
  for name in names {
    if node_child(node, name) is Some(child) {
      children.push(child)
    }
  }
  children
}

///|
fn node_optional_children_by_names(
  node : @untyped_ast.Node,
  names : Array[String],
) -> Array[@untyped_ast.Node] {
  let children : Array[@untyped_ast.Node] = []
  for name in names {
    if node_optional_child(node, name) is Some(child) {
      children.push(child)
    }
  }
  children
}

///|
fn eval_children(
  children : Array[@untyped_ast.Node],
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
