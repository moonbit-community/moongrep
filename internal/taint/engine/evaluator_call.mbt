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
