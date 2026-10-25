///|
using @model {
  type CompiledRule,
  type CompiledRulePattern,
  type CompiledTaintRule,
  type TaintTarget,
}

///|
priv struct TargetValue {
  loc : @basic.Location
  path : @taint.StoragePath?
  taint : @taint.TaintValue
}

///|
priv enum BoundTarget {
  Argument(Int32)
  Receiver
}

///|
pub fn lower_compiled_taint_rule(
  rule : CompiledRule,
  taint_rule : CompiledTaintRule,
) -> @taint.TaintSpec {
  {
    rule_id: rule.rule_id,
    sources: [],
    call_models: [],
    unknown_call_policy: NoEffect,
    bind_call: call => bind_compiled_taint_call(rule.rule_id, taint_rule, call),
  }
}

///|
// Match each pattern once, before solving. The returned transfer depends only
// on its evaluated snapshots and has no matcher/cache side effects.
fn bind_compiled_taint_call(
  rule_id : String,
  rule : CompiledTaintRule,
  call : @taint.CallInfo,
) -> (@taint.CallInfo) -> @taint.CallTransfer? {
  let sources : Array[Int32] = []
  let sanitizers : Array[BoundTarget] = []
  let sinks : Array[(Int32, BoundTarget)] = []
  for i in 0..<rule.sources.length() {
    if taint_pattern_match(rule.sources[i].pattern, call.cst) is Some(_) {
      sources.push(i)
    }
  }
  for sanitizer in rule.sanitizers {
    if taint_pattern_match(sanitizer.pattern, call.cst) is Some(found) &&
      bind_target(call, sanitizer.target, found) is Some(target) {
      sanitizers.push(target)
    }
  }
  for i in 0..<rule.sinks.length() {
    let sink = rule.sinks[i]
    if taint_pattern_match(sink.pattern, call.cst) is Some(found) &&
      bind_target(call, sink.target, found) is Some(target) {
      sinks.push((i, target))
    }
  }
  call => {
    if sources.is_empty() && sanitizers.is_empty() && sinks.is_empty() {
      return None
    }
    let mut value = @taint.TaintValue::clean()
    for index in sources {
      value = value.join(
        @taint.TaintValue::source({
          rule_id,
          origin_id: "source:\{index}",
          site: CallResult(call.callee_name, call.loc),
          note: None,
        }),
      )
    }
    let killed_paths : Array[@taint.StoragePath] = []
    for target in sanitizers {
      if bound_value(call, target) is Some(value) && value.path is Some(path) {
        killed_paths.push(path)
      }
    }
    let findings : Array[@taint.SinkFinding] = []
    for (index, target) in sinks {
      if bound_value(call, target) is Some(value) && !value.taint.is_clean() {
        findings.push({ sink_id: PatternIndex(index), sink_loc: value.loc, })
      }
    }
    Some(@taint.CallTransfer::normal(value, killed_paths~, findings~))
  }
}

///|
fn bind_target(
  call : @taint.CallInfo,
  target : TaintTarget,
  found : @matching.ExprMatch,
) -> BoundTarget? {
  let selected = target_value_for_match(call, target, found)
  guard selected is Some(selected) else { return None }
  if target is Receiver {
    return Some(Receiver)
  }
  for argument in call.arguments {
    if argument.loc == selected.loc {
      return Some(Argument(argument.index))
    }
  }
  None
}

///|
fn bound_value(call : @taint.CallInfo, target : BoundTarget) -> TargetValue? {
  match target {
    Receiver => target_value(call, Receiver)
    Argument(index) =>
      call
      .argument_at(index)
      .map(arg => { loc: arg.loc, path: arg.path, taint: arg.taint, })
  }
}

///|
fn taint_pattern_match(
  pattern : CompiledRulePattern,
  node : @untyped_cst.CstNode,
) -> @matching.ExprMatch? {
  @matching.match_expr_pattern(pattern.compiled, node)
}

///|
fn target_value_for_match(
  call : @taint.CallInfo,
  target : TaintTarget,
  pattern_match : @matching.ExprMatch,
) -> TargetValue? {
  match target {
    Receiver => target_value(call, target)
    _ =>
      match pattern_match.bindings.get("__SOURCE__") {
        Some(Single(source)) =>
          if target_value_at_expr(call, source) is Some(value) {
            Some(value)
          } else {
            target_value(call, target)
          }
        _ => None
      }
  }
}

///|
fn target_value_at_expr(
  call : @taint.CallInfo,
  source : @untyped_cst.CstNode,
) -> TargetValue? {
  for argument in call.arguments {
    if argument.expr.loc == source.loc {
      return Some({
        loc: argument.loc,
        path: argument.path,
        taint: argument.taint,
      })
    }
  }
  None
}

///|
fn target_value(call : @taint.CallInfo, target : TaintTarget) -> TargetValue? {
  match target {
    Receiver =>
      if call.receiver_site is Some(_) {
        Some({
          loc: call.loc,
          path: call.receiver_path,
          taint: call.receiver_taint,
        })
      } else {
        None
      }
    PositionalArg(index) =>
      if call.argument_at(index) is Some(arg) {
        Some({ loc: arg.loc, path: arg.path, taint: arg.taint, })
      } else {
        None
      }
    LabelledArg(label~, index~) =>
      if call.argument_at(index) is Some(arg) {
        if arg.label == Some(label) {
          Some({ loc: arg.loc, path: arg.path, taint: arg.taint, })
        } else {
          None
        }
      } else {
        None
      }
  }
}
