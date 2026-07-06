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
  node : @syntax.Impl,
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
  expr : @syntax.Expr,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  match expr {
    Ident(..) => eval_path_like(expr, state)
    Field(record~, accessor~, ..) =>
      eval_field_expr(expr, record, accessor, state, spec, findings)
    ArrayGet(array~, index~, ..) =>
      eval_array_get_expr(expr, array, index, state, spec, findings)
    Tuple(exprs~, ..) => eval_tuple_expr(exprs, state, spec, findings)
    Array(exprs~, ..) => eval_array_expr(exprs, state, spec, findings)
    Record(fields~, ..) => eval_record_expr(fields, state, spec, findings)
    Group(expr~, ..) | Constraint(expr~, ..) =>
      eval_expr(expr, state, spec, findings)
    Sequence(exprs~, last_expr~, ..) =>
      eval_sequence(exprs, last_expr, state, spec, findings)
    Let(pattern~, expr=bound_expr, body~, ..) =>
      eval_let(pattern, bound_expr, body, state, spec, findings)
    LetMut(binder~, expr=bound_expr, body~, ..) => {
      let pattern = @syntax.Pattern::Var(binder)
      eval_let(pattern, bound_expr, body, state, spec, findings)
    }
    Assign(var_~, expr=rhs, ..) => eval_assign(var_, rhs, state, spec, findings)
    Mutate(record~, accessor~, field~, ..) =>
      eval_mutate(record, accessor, field, state, spec, findings)
    Apply(func~, args~, loc~) =>
      eval_apply_call(expr, func, args, loc, state, spec, findings)
    DotApply(self~, method_name~, args~, loc~, ..) =>
      eval_dot_apply_call(
        expr, self, method_name, args, loc, state, spec, findings,
      )
    Pipe(lhs~, rhs~, loc~) =>
      eval_pipe_call(expr, lhs, rhs, loc, state, spec, findings)
    RevPipe(lhs~, rhs~, loc~) =>
      eval_rev_pipe_call(expr, lhs, rhs, loc, state, spec, findings)
    If(cond~, ifso~, ifnot~, ..) =>
      eval_if(cond, ifso, ifnot, state, spec, findings)
    Match(expr=scrutinee, cases~, ..) =>
      eval_match(scrutinee, cases, state, spec, findings)
    LexMatch(expr=scrutinee, cases~, ..) =>
      eval_lex_match(scrutinee, cases, state, spec, findings)
    Try(body~, catch_~, try_else~, ..) =>
      eval_try(body, catch_, try_else, state, spec, findings)
    While(loop_cond~, loop_body~, while_else~, ..) =>
      eval_while(loop_cond, loop_body, while_else, state, spec, findings)
    For(binders~, condition~, continue_block~, body~, for_else~, ..) =>
      eval_for(
        binders, condition, continue_block, body, for_else, state, spec, findings,
      )
    ForEach(
      binders~,
      expr=collection,
      init~,
      continue_block~,
      body~,
      else_block~,
      ..
    ) =>
      eval_for_each(
        binders, collection, init, continue_block, body, else_block, state, spec,
        findings,
      )
    LetFn(name~, body~, ..) => {
      let roots : Array[String] = []
      add_binder_root_name(roots, name)
      eval_clean_root_scope(body, roots, state, spec, findings)
    }
    LetAnd(bindings~, body~, ..) =>
      eval_clean_root_scope(
        body,
        let_and_bound_roots(bindings),
        state,
        spec,
        findings,
      )
    Function(..) => normal_result(state, [])
    Return(return_value=Some(value), ..) => {
      let result = eval_expr(value, state, spec, findings)
      flow_result(FlowReturn, result.state, result.value)
    }
    Return(return_value=None, ..) => flow_result(FlowReturn, state, [])
    Break(arg=Some(value), ..) => {
      let result = eval_expr(value, state, spec, findings)
      flow_result(FlowBreak, result.state, result.value)
    }
    Break(arg=None, ..) => flow_result(FlowBreak, state, [])
    Raise(err_value=value, ..) => {
      let result = eval_expr(value, state, spec, findings)
      flow_result(FlowRaise, result.state, result.value)
    }
    Continue(args~, ..) => {
      let result = eval_expr_list(args, state, spec, findings)
      flow_result(FlowContinue, result.state, result.value)
    }
    _ => eval_unknown_expr(expr, state, spec, findings)
  }
}

///|
fn eval_path_like(expr : @syntax.Expr, state : TaintState) -> EvalResult {
  if storage_path_from_expr(expr) is Some(path) {
    normal_result(state, state_read_path(state, path))
  } else {
    normal_result(state, [])
  }
}

///|
fn eval_field_expr(
  expr : @syntax.Expr,
  record : @syntax.Expr,
  accessor : @syntax.Accessor,
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
  expr : @syntax.Expr,
  array : @syntax.Expr,
  index : @syntax.Expr,
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
  exprs : @list.List[@syntax.Expr],
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let mut current = state
  let mut value : TaintTree = []
  let items = exprs.to_array()
  for index in 0..<items.length() {
    let result = eval_expr(items[index], current, spec, findings)
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
  exprs : @list.List[@syntax.Expr],
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let mut current = state
  let mut value : TaintTree = []
  let items = exprs.to_array()
  for index in 0..<items.length() {
    let result = eval_expr(items[index], current, spec, findings)
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
  fields : @list.List[@syntax.FieldDef],
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let mut current = state
  let mut value : TaintTree = []
  for field in fields.to_array() {
    let result = eval_expr(field.expr, current, spec, findings)
    if result.flow != FlowNormal {
      return result
    }
    current = result.state
    value = tree_merge(
      value,
      tree_shift([Field(field.label.name)], result.value),
    )
  }
  normal_result(current, value)
}

///|
fn eval_sequence(
  exprs : @list.List[@syntax.Expr],
  last_expr : @syntax.Expr,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let mut current = state
  for item in exprs.to_array() {
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
  pattern : @syntax.Pattern,
  bound_expr : @syntax.Expr,
  body : @syntax.Expr,
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
fn eval_clean_root_scope(
  body : @syntax.Expr,
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
  var_ : @syntax.Var,
  rhs : @syntax.Expr,
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
  record : @syntax.Expr,
  accessor : @syntax.Accessor,
  field : @syntax.Expr,
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
  ast : @syntax.Expr,
  func : @syntax.Expr,
  args : @list.List[@syntax.Argument],
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
    kind: CallKind::Apply,
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
  ast : @syntax.Expr,
  self : @syntax.Expr,
  method_name : @syntax.Label,
  args : @list.List[@syntax.Argument],
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
    kind: CallKind::DotApply,
    ast,
    loc,
    callee_name: Some(method_name.name),
    receiver_path,
    receiver_site: Some(receiver_site),
    receiver_taint: receiver.value,
    arguments: args_result.arguments,
  }
  apply_call_transfer(info, args_result.state, spec, findings)
}

///|
fn eval_pipe_call(
  ast : @syntax.Expr,
  lhs : @syntax.Expr,
  rhs : @syntax.Expr,
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
  match rhs {
    Apply(func~, args~, ..) => {
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
        CallKind::Pipe,
        ast,
        loc,
        callee_name_from_expr(func),
        arguments,
      )
      apply_call_transfer(info, args_result.state, spec, findings)
    }
    DotApply(self~, method_name~, args~, ..) => {
      let receiver = eval_expr(self, lhs_result.state, spec, findings)
      if receiver.flow != FlowNormal {
        return receiver
      }
      let receiver_path = storage_path_from_expr(self)
      let receiver_site = site_for_expr(self, receiver_path)
      let args_result = eval_arguments(args, 1, receiver.state, spec, findings)
      if args_result.flow != FlowNormal {
        return flow_result(
          args_result.flow,
          args_result.state,
          args_result.value,
        )
      }
      let arguments = prepend_argument(lhs_arg, args_result.arguments)
      let info = {
        kind: CallKind::Pipe,
        ast,
        loc,
        callee_name: Some(method_name.name),
        receiver_path,
        receiver_site: Some(receiver_site),
        receiver_taint: receiver.value,
        arguments,
      }
      apply_call_transfer(info, args_result.state, spec, findings)
    }
    _ => {
      let rhs_result = eval_expr(rhs, lhs_result.state, spec, findings)
      if rhs_result.flow != FlowNormal {
        return rhs_result
      }
      let info = call_info_without_receiver(
        CallKind::Pipe,
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
  ast : @syntax.Expr,
  lhs : @syntax.Expr,
  rhs : @syntax.Expr,
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
    CallKind::RevPipe,
    ast,
    loc,
    callee_name_from_expr(lhs),
    [arg],
  )
  apply_call_transfer(info, rhs_result.state, spec, findings)
}

///|
fn eval_arguments(
  args : @list.List[@syntax.Argument],
  start_index : Int,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalArgumentsResult {
  let mut current = state
  let arguments : Array[CallArgument] = []
  let raw = args.to_array()
  for offset in 0..<raw.length() {
    let arg = raw[offset]
    let result = eval_expr(arg.value, current, spec, findings)
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
        argument_label(arg.kind),
        arg.value,
        result,
      ),
    )
  }
  { state: current, arguments, flow: FlowNormal, value: [] }
}

///|
fn evaled_argument_from_result(
  index : Int,
  label : String?,
  expr : @syntax.Expr,
  result : EvalResult,
) -> CallArgument {
  call_argument_from_result(index, label, expr, result)
}

///|
fn call_argument_from_result(
  index : Int,
  label : String?,
  expr : @syntax.Expr,
  result : EvalResult,
) -> CallArgument {
  let path = storage_path_from_expr(expr)
  {
    index,
    label,
    expr,
    loc: expr.loc(),
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
  ast : @syntax.Expr,
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
fn site_for_expr(expr : @syntax.Expr, path : StoragePath?) -> ValueSite {
  if path is Some(path) {
    Path(path)
  } else {
    Expr(expr.loc(), None)
  }
}

///|
fn callee_name_from_expr(expr : @syntax.Expr) -> String? {
  match expr {
    Ident(id~, ..) => @id.normalize_identifier_name_from_var(id)
    Field(accessor=Label(label), ..) => Some(label.name)
    Method(method_name~, ..) => Some(method_name.name)
    Group(expr~, ..) | Constraint(expr~, ..) => callee_name_from_expr(expr)
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
fn add_binder_root_name(names : Array[String], binder : @syntax.Binder) -> Unit {
  add_unique_root_name(names, binder.name)
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
fn pattern_bound_roots(pattern : @syntax.Pattern) -> Array[String] {
  let roots : Array[String] = []
  add_pattern_bound_roots(roots, pattern)
  roots
}

///|
fn add_pattern_bound_roots(
  roots : Array[String],
  pattern : @syntax.Pattern,
) -> Unit {
  match pattern {
    Var(binder) => add_binder_root_name(roots, binder)
    Alias(pat~, alias_~, ..) => {
      add_pattern_bound_roots(roots, pat)
      add_binder_root_name(roots, alias_)
    }
    Constraint(pat~, ..) => add_pattern_bound_roots(roots, pat)
    Tuple(pats~, ..) =>
      for pat in pats {
        add_pattern_bound_roots(roots, pat)
      }
    Record(fields~, ..) =>
      for field in fields {
        add_pattern_bound_roots(roots, field.pattern)
      }
    Map(elems~, ..) =>
      for elem in elems {
        add_pattern_bound_roots(roots, elem.pat)
      }
    Array(pats~, ..) => add_array_pattern_bound_roots(roots, pats)
    Constr(args=Some(args), ..) =>
      for arg in args {
        add_pattern_bound_roots(roots, arg.pat)
      }
    Constr(args=None, ..) => ()
    SpecialConstr(args~, ..) =>
      for arg in args {
        add_pattern_bound_roots(roots, arg.pat)
      }
    Or(pat1~, pat2~, ..) | Range(lhs=pat1, rhs=pat2, ..) => {
      add_pattern_bound_roots(roots, pat1)
      add_pattern_bound_roots(roots, pat2)
    }
    Any(..) | Constant(..) => ()
  }
}

///|
fn add_array_pattern_bound_roots(
  roots : Array[String],
  patterns : @syntax.ArrayPatterns,
) -> Unit {
  match patterns {
    Closed(items) =>
      for item in items {
        add_array_pattern_item_bound_roots(roots, item)
      }
    Open(left, right, middle) => {
      for item in left {
        add_array_pattern_item_bound_roots(roots, item)
      }
      for item in right {
        add_array_pattern_item_bound_roots(roots, item)
      }
      add_dot_dot_binder_bound_roots(roots, middle)
    }
  }
}

///|
fn add_array_pattern_item_bound_roots(
  roots : Array[String],
  item : @syntax.ArrayPattern,
) -> Unit {
  match item {
    Pattern(pattern) => add_pattern_bound_roots(roots, pattern)
    ConstSpread(binder~, ..) => add_binder_root_name(roots, binder)
    BytesSpread(..) | StringSpread(..) => ()
  }
}

///|
fn add_dot_dot_binder_bound_roots(
  roots : Array[String],
  binder : @syntax.DotDotBinder,
) -> Unit {
  match binder {
    Binder(binder) | BinderAs(binder) => add_binder_root_name(roots, binder)
    NoBinder | Underscore => ()
  }
}

///|
fn let_and_bound_roots(
  bindings : @list.List[(@syntax.Binder, @syntax.Type?, @syntax.Func)],
) -> Array[String] {
  let roots : Array[String] = []
  for binding in bindings {
    let (binder, _ty, _func) = binding
    add_binder_root_name(roots, binder)
  }
  roots
}

///|
fn bind_pattern(
  pattern : @syntax.Pattern,
  value : TaintTree,
  state : TaintState,
) -> TaintState {
  match pattern {
    Var(binder) =>
      state_write_path(state, { root: binder.name, segments: [] }, value)
    Alias(pat~, alias_~, ..) => {
      let state = bind_pattern(pat, value, state)
      state_write_path(state, { root: alias_.name, segments: [] }, value)
    }
    Constraint(pat~, ..) => bind_pattern(pat, value, state)
    Tuple(pats~, ..) => {
      let mut next = state
      let items = pats.to_array()
      for index in 0..<items.length() {
        next = bind_pattern(
          items[index],
          tree_project_for_binding(value, TupleIndex(index)),
          next,
        )
      }
      next
    }
    Record(fields~, ..) => {
      let mut next = state
      for field in fields.to_array() {
        next = bind_pattern(
          field.pattern,
          tree_project_for_binding(value, Field(field.label.name)),
          next,
        )
      }
      next
    }
    Map(elems~, ..) => {
      let mut next = state
      for elem in elems.to_array() {
        next = bind_pattern(elem.pat, value, next)
      }
      next
    }
    Array(pats~, ..) => bind_array_pattern(pats, value, state)
    Constr(args=Some(args), ..) => {
      let mut next = state
      let items = args.to_array()
      for index in 0..<items.length() {
        let segment = segment_from_argument_kind(items[index].kind, index)
        next = bind_pattern(
          items[index].pat,
          tree_project_for_binding(value, segment),
          next,
        )
      }
      next
    }
    SpecialConstr(args~, ..) => {
      let mut next = state
      let items = args.to_array()
      for index in 0..<items.length() {
        let segment = segment_from_argument_kind(items[index].kind, index)
        next = bind_pattern(
          items[index].pat,
          tree_project_for_binding(value, segment),
          next,
        )
      }
      next
    }
    Or(pat1~, pat2~, ..) =>
      state_merge(
        bind_pattern(pat1, value, state),
        bind_pattern(pat2, value, state),
      )
    _ => state
  }
}

///|
fn bind_array_pattern(
  pats : @syntax.ArrayPatterns,
  value : TaintTree,
  state : TaintState,
) -> TaintState {
  match pats {
    Closed(items) => bind_array_pattern_items(items.to_array(), 0, value, state)
    Open(left, right, middle) => {
      let mut next = bind_array_pattern_items(left.to_array(), 0, value, state)
      let right_items = right.to_array()
      for index in 0..<right_items.length() {
        next = bind_array_pattern_item(
          right_items[index],
          AnyIndex,
          value,
          next,
        )
      }
      match middle {
        Binder(binder) | BinderAs(binder) =>
          state_write_path(
            next,
            { root: binder.name, segments: [] },
            tree_project_for_binding(value, AnyIndex),
          )
        NoBinder | Underscore => next
      }
    }
  }
}

///|
fn bind_array_pattern_items(
  items : Array[@syntax.ArrayPattern],
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
  item : @syntax.ArrayPattern,
  segment : PathSegment,
  value : TaintTree,
  state : TaintState,
) -> TaintState {
  match item {
    Pattern(pattern) =>
      bind_pattern(pattern, tree_project_for_binding(value, segment), state)
    ConstSpread(binder~, ..) =>
      state_write_path(
        state,
        { root: binder.name, segments: [] },
        tree_project_for_binding(value, segment),
      )
    BytesSpread(..) | StringSpread(..) => state
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
  cond : @syntax.Expr,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> ConditionEval {
  match cond {
    Group(expr~, ..) | Constraint(expr~, ..) =>
      eval_condition_scope(expr, state, spec, findings)
    Is(expr~, pat~, ..) => {
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
    IsLexMatch(expr~, pat~, ..) => {
      let matched = eval_expr(expr, state, spec, findings)
      if matched.flow != FlowNormal {
        return condition_from_eval_result(matched)
      }
      let pattern_result = eval_lex_top_pattern_exprs(
        pat,
        matched.state,
        spec,
        findings,
      )
      if pattern_result.flow != FlowNormal {
        return condition_from_eval_result(pattern_result)
      }
      let roots = lex_top_patterns_bound_roots(pat)
      {
        base_state: pattern_result.state,
        true_state: bind_lex_top_patterns(
          pat,
          matched.value,
          pattern_result.state,
        ),
        bound_roots: roots,
        flow: FlowNormal,
        value: matched.value,
      }
    }
    RegexMatch(expr~, pat~, bindings~, ..) => {
      let matched = eval_expr(expr, state, spec, findings)
      if matched.flow != FlowNormal {
        return condition_from_eval_result(matched)
      }
      let roots = merge_root_names(
        regex_pattern_bound_roots(pat),
        regex_bindings_bound_roots(bindings),
      )
      let pattern_state = bind_regex_pattern(pat, matched.value, matched.state)
      {
        base_state: matched.state,
        true_state: bind_regex_bindings(bindings, matched.value, pattern_state),
        bound_roots: roots,
        flow: FlowNormal,
        value: matched.value,
      }
    }
    Infix(op~, lhs~, rhs~, ..) =>
      if is_logical_and_var(op) {
        eval_and_condition_scope(lhs, rhs, state, spec, findings)
      } else {
        condition_from_eval_result(eval_expr(cond, state, spec, findings))
      }
    _ => condition_from_eval_result(eval_expr(cond, state, spec, findings))
  }
}

///|
fn eval_and_condition_scope(
  lhs : @syntax.Expr,
  rhs : @syntax.Expr,
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
fn is_logical_and_var(op : @syntax.Var) -> Bool {
  @id.normalize_identifier_name_from_var(op) == Some("&&")
}

///|
fn eval_lex_top_pattern_exprs(
  patterns : @list.List[@syntax.LexTopPattern],
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let mut current = state
  let mut value : TaintTree = []
  for pattern in patterns {
    let result = match pattern {
      Pattern(pattern) =>
        eval_lex_pattern_exprs(pattern, current, spec, findings)
      Binder(_) | Wildcard(..) => normal_result(current, [])
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
  pattern : @syntax.LexPattern,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  match pattern {
    Alias(pat~, ..) => eval_lex_pattern_exprs(pat, state, spec, findings)
    RegexInterp(elems~, ..) => eval_interp_elems(elems, state, spec, findings)
    Sequence(pats~, ..) => {
      let mut current = state
      let mut value : TaintTree = []
      for pat in pats {
        let result = eval_lex_pattern_exprs(pat, current, spec, findings)
        if result.flow != FlowNormal {
          return result
        }
        current = result.state
        value = tree_merge(value, result.value)
      }
      normal_result(current, value)
    }
    ConstantRef(..) | Regex(..) => normal_result(state, [])
  }
}

///|
fn eval_interp_elems(
  elems : @list.List[@syntax.InterpElem],
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let mut current = state
  let mut value : TaintTree = []
  for elem in elems {
    match elem {
      Expr(expr~, ..) => {
        let result = eval_expr(expr, current, spec, findings)
        if result.flow != FlowNormal {
          return result
        }
        current = result.state
        value = tree_merge(value, result.value)
      }
      Literal(..) | Source(_) => ()
    }
  }
  normal_result(current, value)
}

///|
fn lex_top_patterns_bound_roots(
  patterns : @list.List[@syntax.LexTopPattern],
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
  pattern : @syntax.LexTopPattern,
) -> Unit {
  match pattern {
    Binder(binder) => add_binder_root_name(roots, binder)
    Pattern(pattern) => add_lex_pattern_bound_roots(roots, pattern)
    Wildcard(..) => ()
  }
}

///|
fn add_lex_pattern_bound_roots(
  roots : Array[String],
  pattern : @syntax.LexPattern,
) -> Unit {
  match pattern {
    Alias(pat~, binder~, ..) => {
      add_lex_pattern_bound_roots(roots, pat)
      add_binder_root_name(roots, binder)
    }
    Sequence(pats~, ..) =>
      for pat in pats {
        add_lex_pattern_bound_roots(roots, pat)
      }
    ConstantRef(..) | Regex(..) | RegexInterp(..) => ()
  }
}

///|
fn bind_lex_top_patterns(
  patterns : @list.List[@syntax.LexTopPattern],
  value : TaintTree,
  state : TaintState,
) -> TaintState {
  let mut next = state
  for pattern in patterns {
    next = match pattern {
      Binder(binder) =>
        state_write_path(next, { root: binder.name, segments: [] }, value)
      Pattern(pattern) => bind_lex_pattern(pattern, value, next)
      Wildcard(..) => next
    }
  }
  next
}

///|
fn bind_lex_pattern(
  pattern : @syntax.LexPattern,
  value : TaintTree,
  state : TaintState,
) -> TaintState {
  match pattern {
    Alias(pat~, binder~, ..) => {
      let next = bind_lex_pattern(pat, value, state)
      state_write_path(next, { root: binder.name, segments: [] }, value)
    }
    Sequence(pats~, ..) => {
      let mut next = state
      for pat in pats {
        next = bind_lex_pattern(pat, value, next)
      }
      next
    }
    ConstantRef(..) | Regex(..) | RegexInterp(..) => state
  }
}

///|
fn regex_pattern_bound_roots(pattern : @syntax.RegexPattern) -> Array[String] {
  let roots : Array[String] = []
  add_regex_pattern_bound_roots(roots, pattern)
  roots
}

///|
fn add_regex_pattern_bound_roots(
  roots : Array[String],
  pattern : @syntax.RegexPattern,
) -> Unit {
  match pattern {
    Alias(pat~, binder~, ..) => {
      add_regex_pattern_bound_roots(roots, pat)
      add_binder_root_name(roots, binder)
    }
    Alternation(pat1~, pat2~, ..) | Sequence(pat1~, pat2~, ..) => {
      add_regex_pattern_bound_roots(roots, pat1)
      add_regex_pattern_bound_roots(roots, pat2)
    }
    Literal(..) | Reference(..) => ()
  }
}

///|
fn regex_bindings_bound_roots(
  bindings : @list.List[(@syntax.Label, @syntax.Binder?)],
) -> Array[String] {
  let roots : Array[String] = []
  for binding in bindings {
    let (_label, binder) = binding
    if binder is Some(binder) {
      add_binder_root_name(roots, binder)
    }
  }
  roots
}

///|
fn bind_regex_pattern(
  pattern : @syntax.RegexPattern,
  value : TaintTree,
  state : TaintState,
) -> TaintState {
  match pattern {
    Alias(pat~, binder~, ..) => {
      let next = bind_regex_pattern(pat, value, state)
      state_write_path(next, { root: binder.name, segments: [] }, value)
    }
    Alternation(pat1~, pat2~, ..) =>
      state_merge(
        bind_regex_pattern(pat1, value, state),
        bind_regex_pattern(pat2, value, state),
      )
    Sequence(pat1~, pat2~, ..) =>
      bind_regex_pattern(pat2, value, bind_regex_pattern(pat1, value, state))
    Literal(..) | Reference(..) => state
  }
}

///|
fn bind_regex_bindings(
  bindings : @list.List[(@syntax.Label, @syntax.Binder?)],
  value : TaintTree,
  state : TaintState,
) -> TaintState {
  let mut next = state
  for binding in bindings {
    let (_label, binder) = binding
    if binder is Some(binder) {
      next = state_write_path(next, { root: binder.name, segments: [] }, value)
    }
  }
  next
}

///|
fn eval_if(
  cond : @syntax.Expr,
  ifso : @syntax.Expr,
  ifnot : @syntax.Expr?,
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
  cond : @syntax.Expr,
  otherwise : @syntax.Expr?,
  body : @syntax.Expr,
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
  scrutinee : @syntax.Expr,
  cases : @list.List[@syntax.Case],
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
  for case in cases.to_array() {
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
  case : @syntax.Case,
  value : TaintTree,
  base_state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let roots = pattern_bound_roots(case.pattern)
  let bound = bind_pattern(case.pattern, value, base_state)
  let result = if case.guard_ is Some(guard_expr) {
    let guard_result = eval_condition_scope(guard_expr, bound, spec, findings)
    if guard_result.flow == FlowNormal {
      restore_result_scoped_roots(
        eval_expr(case.body, guard_result.true_state, spec, findings),
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
    eval_expr(case.body, bound, spec, findings)
  }
  restore_result_scoped_roots(result, base_state, roots)
}

///|
fn eval_lex_match(
  scrutinee : @syntax.Expr,
  cases : @list.List[@syntax.LexCase],
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
  for case in cases.to_array() {
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
  case : @syntax.LexCase,
  value : TaintTree,
  base_state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let pattern_result = eval_lex_top_pattern_exprs(
    case.pat,
    base_state,
    spec,
    findings,
  )
  if pattern_result.flow != FlowNormal {
    return pattern_result
  }
  let roots = lex_top_patterns_bound_roots(case.pat)
  let bound = bind_lex_top_patterns(case.pat, value, pattern_result.state)
  let result = if case.guard_ is Some(guard_expr) {
    let guard_result = eval_condition_scope(guard_expr, bound, spec, findings)
    if guard_result.flow == FlowNormal {
      restore_result_scoped_roots(
        eval_expr(case.body, guard_result.true_state, spec, findings),
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
    eval_expr(case.body, bound, spec, findings)
  }
  restore_result_scoped_roots(result, pattern_result.state, roots)
}

///|
fn eval_try(
  body : @syntax.Expr,
  catch_ : @list.List[@syntax.Case],
  try_else : @list.List[@syntax.Case]?,
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
  for case in catch_.to_array() {
    let result = eval_pattern_case(case, [], body_result.state, spec, findings)
    if result.flow == FlowNormal {
      branch_states.push(result.state)
      branch_value = tree_merge(branch_value, result.value)
    }
  }
  if try_else is Some(cases) {
    for case in cases.to_array() {
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
  catch_ : @list.List[@syntax.Case],
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let normal_states : Array[TaintState] = []
  let mut branch_value : TaintTree = []
  let exit_states : Array[TaintState] = []
  let mut exit_flow = FlowRaise
  let mut exit_value = raised.value
  for case in catch_.to_array() {
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
  loop_cond : @syntax.Expr,
  loop_body : @syntax.Expr,
  while_else : @syntax.Expr?,
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
  binders : @list.List[(@syntax.Binder, @syntax.Expr)],
  condition : @syntax.Expr?,
  continue_block : @list.List[(@syntax.Binder, @syntax.Expr)],
  body : @syntax.Expr,
  for_else : @syntax.Expr?,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  let loop_roots : Array[String] = []
  let mut loop_base = state
  let mut current = state
  for pair in binders.to_array() {
    let (binder, expr) = pair
    let result = eval_expr(expr, current, spec, findings)
    if result.flow != FlowNormal {
      return restore_result_scoped_roots(result, loop_base, loop_roots)
    }
    current = result.state
    loop_base = restore_scoped_roots(loop_base, current, loop_roots)
    add_binder_root_name(loop_roots, binder)
    current = state_write_path(
      current,
      { root: binder.name, segments: [] },
      result.value,
    )
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
    for pair in continue_block.to_array() {
      let (binder, expr) = pair
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
      loop_base = restore_scoped_roots(loop_base, base_candidate, loop_roots)
      add_binder_root_name(loop_roots, binder)
      next = state_write_path(
        next,
        { root: binder.name, segments: [] },
        result.value,
      )
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
  binders : @list.List[@syntax.Binder?],
  collection : @syntax.Expr,
  init : @list.List[(@syntax.Binder, @syntax.Expr)],
  continue_block : @list.List[(@syntax.Binder, @syntax.Expr)],
  body : @syntax.Expr,
  else_block : @syntax.Expr?,
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
  for pair in init.to_array() {
    let (binder, expr) = pair
    let result = eval_expr(expr, current, spec, findings)
    if result.flow != FlowNormal {
      return restore_result_scoped_roots(result, loop_base, loop_roots)
    }
    current = result.state
    loop_base = restore_scoped_roots(loop_base, current, loop_roots)
    add_binder_root_name(loop_roots, binder)
    current = state_write_path(
      current,
      { root: binder.name, segments: [] },
      result.value,
    )
  }
  for binder in binders.to_array() {
    if binder is Some(binder) {
      add_binder_root_name(loop_roots, binder)
      current = state_write_path(
        current,
        { root: binder.name, segments: [] },
        tree_project_for_binding(collection_result.value, AnyIndex),
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
    for pair in continue_block.to_array() {
      let (binder, expr) = pair
      let result = eval_expr(expr, next, spec, findings)
      if result.flow != FlowNormal {
        return restore_result_scoped_roots(result, loop_base, loop_roots)
      }
      next = result.state
      loop_base = restore_scoped_roots(loop_base, next, loop_roots)
      add_binder_root_name(loop_roots, binder)
      next = state_write_path(
        next,
        { root: binder.name, segments: [] },
        result.value,
      )
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
  expr : @syntax.Expr,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  match expr {
    Infix(lhs~, rhs~, ..) => eval_children([lhs, rhs], state, spec, findings)
    Unary(expr~, ..) => eval_expr(expr, state, spec, findings)
    As(expr~, ..)
    | TryOperator(body=expr, ..)
    | ProofAssert(expr~, ..)
    | TemplateWriting(expr~, ..) => eval_expr(expr, state, spec, findings)
    ArraySet(array~, index~, value~, ..)
    | ArrayAugmentedSet(array~, index~, value~, ..) =>
      eval_children([array, index, value], state, spec, findings)
    ArrayGetSlice(array~, start_index~, end_index~, ..) => {
      let children : Array[@syntax.Expr] = [array]
      if start_index is Some(expr) {
        children.push(expr)
      }
      if end_index is Some(expr) {
        children.push(expr)
      }
      eval_children(children, state, spec, findings)
    }
    Defer(expr~, body~, ..) =>
      eval_children([expr, body], state, spec, findings)
    Guard(cond~, otherwise~, body~, ..) =>
      eval_guard(cond, otherwise, body, state, spec, findings)
    Is(expr~, ..) | RegexMatch(expr~, ..) =>
      eval_expr(expr, state, spec, findings)
    IsLexMatch(expr~, pat~, ..) => {
      let matched = eval_expr(expr, state, spec, findings)
      if matched.flow != FlowNormal {
        return matched
      }
      let pattern_result = eval_lex_top_pattern_exprs(
        pat,
        matched.state,
        spec,
        findings,
      )
      if pattern_result.flow != FlowNormal {
        return pattern_result
      }
      normal_result(pattern_result.state, matched.value)
    }
    Interp(elems~, ..) => {
      let mut current = state
      let mut value : TaintTree = []
      for elem in elems.to_array() {
        match elem {
          Expr(expr~, ..) => {
            let result = eval_expr(expr, current, spec, findings)
            if result.flow != FlowNormal {
              return result
            }
            current = result.state
            value = tree_merge(value, result.value)
          }
          Literal(..) | Source(_) => ()
        }
      }
      normal_result(current, value)
    }
    Map(elems~, ..) => {
      let mut current = state
      let mut value : TaintTree = []
      for elem in elems.to_array() {
        let result = eval_expr(elem.expr, current, spec, findings)
        if result.flow != FlowNormal {
          return result
        }
        current = result.state
        value = tree_merge(value, result.value)
      }
      normal_result(current, value)
    }
    RecordUpdate(record~, fields~, ..) => {
      let base = eval_expr(record, state, spec, findings)
      if base.flow != FlowNormal {
        return base
      }
      eval_record_expr(fields, base.state, spec, findings)
    }
    _ => normal_result(state, [])
  }
}

///|
fn eval_expr_list(
  exprs : @list.List[@syntax.Expr],
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult {
  eval_children(exprs.to_array(), state, spec, findings)
}

///|
fn eval_children(
  children : Array[@syntax.Expr],
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
