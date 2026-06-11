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
    LetFn(body~, ..) | LetAnd(body~, ..) =>
      eval_expr(body, state, spec, findings)
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
  match storage_path_from_expr(expr) {
    Some(path) => normal_result(state, state_read_path(state, path))
    None => normal_result(state, [])
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
  match storage_path_from_expr(expr) {
    Some(path) => normal_result(state, state_read_path(state, path))
    None => {
      let record_result = eval_expr(record, state, spec, findings)
      if record_result.flow != FlowNormal {
        return record_result
      }
      match segment_from_accessor(accessor) {
        Some(segment) =>
          normal_result(
            record_result.state,
            tree_project(record_result.value, [segment]),
          )
        None => normal_result(record_result.state, [])
      }
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
  match storage_path_from_expr(expr) {
    Some(path) =>
      normal_result(
        index_result.state,
        state_read_path(index_result.state, path),
      )
    None => {
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
  eval_expr(body, bound_state, spec, findings)
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
  match storage_path_from_var(var_) {
    Some(path) =>
      normal_result(
        state_write_path(rhs_result.state, path, rhs_result.value),
        rhs_result.value,
      )
    None => rhs_result
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
  match (spec.custom_transfer_call)(info) {
    Some(transfer) => {
      let mut next = state
      for path in transfer.killed_paths {
        next = state_kill_path(next, path)
      }
      for finding in transfer.findings {
        findings.push(finding)
      }
      normal_result(next, transfer.return_taint)
    }
    None => apply_declared_call_transfer(info, state, spec, findings)
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
            match argument_at(info.arguments, index) {
              Some(arg) => return_taint = tree_merge(return_taint, arg.taint)
              None => ()
            }
          PropagateReceiverToReturn =>
            return_taint = tree_merge(return_taint, info.receiver_taint)
          PropagateArgSubpathToReturn(index, path) =>
            match argument_at(info.arguments, index) {
              Some(arg) =>
                return_taint = tree_merge(
                  return_taint,
                  tree_project(arg.taint, path),
                )
              None => ()
            }
          KillArg(index) =>
            match argument_at(info.arguments, index) {
              Some(arg) =>
                match arg.path {
                  Some(path) => next = state_kill_path(next, path)
                  None => ()
                }
              None => ()
            }
          KillReceiver =>
            match info.receiver_path {
              Some(path) => next = state_kill_path(next, path)
              None => ()
            }
          // Argument sinks point at the argument expression. Receiver sinks
          // point at the whole call while keeping the receiver as the value
          // site, because receiver syntax has no standalone call-site location.
          ReportSinkArg(sink_id, index) =>
            match argument_at(info.arguments, index) {
              Some(arg) =>
                push_sink_finding_if_tainted(
                  spec.rule_id,
                  sink_id,
                  arg.loc,
                  arg.site,
                  arg.taint,
                  findings,
                )
              None => ()
            }
          ReportSinkReceiver(sink_id) =>
            match info.receiver_site {
              Some(site) =>
                push_sink_finding_if_tainted(
                  spec.rule_id,
                  sink_id,
                  info.loc,
                  site,
                  info.receiver_taint,
                  findings,
                )
              None => ()
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
      match info.callee_name {
        Some(found) => found == name
        None => false
      }
    MethodName(name) =>
      match info.kind {
        DotApply | Pipe =>
          match info.callee_name {
            Some(found) => found == name
            None => false
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
  match path {
    Some(path) => Path(path)
    None => Expr(expr.loc(), None)
  }
}

///|
fn callee_name_from_expr(expr : @syntax.Expr) -> String? {
  match expr {
    Ident(id~, ..) => @ident.normalize_identifier_name_from_var(id)
    Field(accessor=Label(label), ..) => Some(label.name)
    Method(method_name~, ..) => Some(method_name.name)
    Group(expr~, ..) | Constraint(expr~, ..) => callee_name_from_expr(expr)
    _ => None
  }
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
          tree_project(value, [TupleIndex(index)]),
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
          tree_project(value, [Field(field.label.name)]),
          next,
        )
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
          tree_project(value, [segment]),
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
          tree_project(value, [segment]),
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
            tree_project(value, [AnyIndex]),
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
      bind_pattern(pattern, tree_project(value, [segment]), state)
    ConstSpread(binder~, ..) =>
      state_write_path(
        state,
        { root: binder.name, segments: [] },
        tree_project(value, [segment]),
      )
    BytesSpread(..) | StringSpread(..) => state
  }
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
  let cond_result = eval_expr(cond, state, spec, findings)
  if cond_result.flow != FlowNormal {
    return cond_result
  }
  let then_result = eval_expr(ifso, cond_result.state, spec, findings)
  let else_result = match ifnot {
    Some(expr) => eval_expr(expr, cond_result.state, spec, findings)
    None => normal_result(cond_result.state, [])
  }
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
    let bound = bind_pattern(
      case.pattern,
      scrutinee_result.value,
      scrutinee_result.state,
    )
    let case_result = match case.guard_ {
      Some(guard_expr) => {
        let guard_result = eval_expr(guard_expr, bound, spec, findings)
        if guard_result.flow == FlowNormal {
          eval_expr(case.body, guard_result.state, spec, findings)
        } else {
          guard_result
        }
      }
      None => eval_expr(case.body, bound, spec, findings)
    }
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
    let result = eval_expr(case.body, body_result.state, spec, findings)
    if result.flow == FlowNormal {
      branch_states.push(result.state)
      branch_value = tree_merge(branch_value, result.value)
    }
  }
  match try_else {
    Some(cases) =>
      for case in cases.to_array() {
        let result = eval_expr(case.body, body_result.state, spec, findings)
        if result.flow == FlowNormal {
          branch_states.push(result.state)
          branch_value = tree_merge(branch_value, result.value)
        }
      }
    None => ()
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
    let bound = bind_pattern(case.pattern, raised.value, raised.state)
    let case_result = match case.guard_ {
      Some(guard_expr) => {
        let guard_result = eval_expr(guard_expr, bound, spec, findings)
        if guard_result.flow == FlowNormal {
          eval_expr(case.body, guard_result.state, spec, findings)
        } else {
          guard_result
        }
      }
      None => eval_expr(case.body, bound, spec, findings)
    }
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
  let cond_result = eval_expr(loop_cond, state, spec, findings)
  if cond_result.flow != FlowNormal {
    return cond_result
  }
  let mut current = cond_result.state
  let mut iteration = 0
  // Loops are interpreted to a bounded fixpoint. The condition is evaluated
  // once before the body fixpoint; the state is joined after each body
  // iteration and stops early once another pass adds no new taint facts.
  while iteration < spec.max_fixpoint_iterations {
    let body_result = eval_expr(loop_body, current, spec, findings)
    if body_result.flow == FlowReturn || body_result.flow == FlowRaise {
      return body_result
    }
    if body_result.flow == FlowBreak {
      current = state_merge(current, body_result.state)
      break
    }
    let joined = state_merge(current, body_result.state)
    if state_equiv(joined, current) {
      break
    }
    current = joined
    iteration = iteration + 1
  }
  match while_else {
    Some(expr) => {
      let else_result = eval_expr(expr, current, spec, findings)
      if else_result.flow != FlowNormal {
        return else_result
      }
      normal_result(state_merge(current, else_result.state), else_result.value)
    }
    None => normal_result(current, [])
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
  let mut current = state
  for pair in binders.to_array() {
    let (binder, expr) = pair
    let result = eval_expr(expr, current, spec, findings)
    if result.flow != FlowNormal {
      return result
    }
    current = state_write_path(
      result.state,
      { root: binder.name, segments: [] },
      result.value,
    )
  }
  match condition {
    Some(expr) => {
      let result = eval_expr(expr, current, spec, findings)
      if result.flow != FlowNormal {
        return result
      }
      current = result.state
    }
    None => ()
  }
  let mut iteration = 0
  // `for` uses the same bounded fixpoint strategy as `while`. The optional
  // condition is evaluated once before the body fixpoint, and the continue block
  // is applied between body evaluation and the join.
  while iteration < spec.max_fixpoint_iterations {
    let body_result = eval_expr(body, current, spec, findings)
    if body_result.flow == FlowReturn || body_result.flow == FlowRaise {
      return body_result
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
        return result
      }
      next = state_write_path(
        result.state,
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
  match for_else {
    Some(expr) => {
      let else_result = eval_expr(expr, current, spec, findings)
      if else_result.flow != FlowNormal {
        return else_result
      }
      normal_result(state_merge(current, else_result.state), else_result.value)
    }
    None => normal_result(current, [])
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
  let mut current = collection_result.state
  for pair in init.to_array() {
    let (binder, expr) = pair
    let result = eval_expr(expr, current, spec, findings)
    if result.flow != FlowNormal {
      return result
    }
    current = state_write_path(
      result.state,
      { root: binder.name, segments: [] },
      result.value,
    )
  }
  for binder in binders.to_array() {
    match binder {
      Some(binder) =>
        current = state_write_path(
          current,
          { root: binder.name, segments: [] },
          tree_project(collection_result.value, [AnyIndex]),
        )
      None => ()
    }
  }
  let mut iteration = 0
  // A foreach binder receives the collection's `AnyIndex` taint summary before
  // the loop body fixpoint starts.
  while iteration < spec.max_fixpoint_iterations {
    let body_result = eval_expr(body, current, spec, findings)
    if body_result.flow == FlowReturn || body_result.flow == FlowRaise {
      return body_result
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
        return result
      }
      next = state_write_path(
        result.state,
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
  match else_block {
    Some(expr) => {
      let else_result = eval_expr(expr, current, spec, findings)
      if else_result.flow != FlowNormal {
        return else_result
      }
      normal_result(state_merge(current, else_result.state), else_result.value)
    }
    None => normal_result(current, [])
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
      match start_index {
        Some(expr) => children.push(expr)
        None => ()
      }
      match end_index {
        Some(expr) => children.push(expr)
        None => ()
      }
      eval_children(children, state, spec, findings)
    }
    Defer(expr~, body~, ..) =>
      eval_children([expr, body], state, spec, findings)
    Guard(cond~, otherwise~, body~, ..) => {
      let children : Array[@syntax.Expr] = [cond]
      match otherwise {
        Some(expr) => children.push(expr)
        None => ()
      }
      children.push(body)
      eval_children(children, state, spec, findings)
    }
    Is(expr~, ..) | IsLexMatch(expr~, ..) | RegexMatch(expr~, ..) =>
      eval_expr(expr, state, spec, findings)
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
