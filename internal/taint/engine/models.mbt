///|
priv struct BoundCall {
  custom : (CallInfo) -> CallTransfer?
  effects : Array[CallEffect]
  matched : Bool
}

///|
fn matches(info : CallInfo, matcher : CallMatcher) -> Bool {
  match matcher {
    AnyCall => true
    CalleeName(name) => info.callee_name == Some(name)
    CalleeBinding(binding) => info.callee_binding == Some(binding)
    MethodName(name) =>
      info.kind is (DotApply | Pipe) && info.callee_name == Some(name)
  }
}

///|
fn bind_call(info : CallInfo, spec : TaintSpec) -> BoundCall {
  let effects : Array[CallEffect] = []
  let mut matched = false
  for source in spec.sources {
    if source is CallReturn(matcher, origin, note, path) &&
      matches(info, matcher) {
      matched = true
      effects.push(ReturnFreshSource(origin, note, path))
    }
  }
  for model in spec.call_models {
    if matches(info, model.matcher) {
      matched = true
      for effect in model.effects {
        effects.push(effect)
      }
    }
  }
  { custom: (spec.bind_call)(info), effects, matched, }
}

///|
fn transfer_call(
  bound : BoundCall,
  info : CallInfo,
  spec : TaintSpec,
) -> CallTransfer {
  if (bound.custom)(info) is Some(transfer) {
    return transfer
  }
  let mut value = TaintValue::clean()
  let mut exceptional : CallOutcome? = None
  let writes : Array[@model.StorageWrite] = []
  let findings : Array[SinkFinding] = []
  let mut normal = true
  for effect in bound.effects {
    match effect {
      ReturnFreshSource(origin_id, note, path) => {
        let origin : TaintOrigin = {
          rule_id: spec.rule_id,
          origin_id,
          note,
          site: CallResult(info.callee_name, info.loc),
        }
        value = value.join(
          TaintValue::clean().write(path, TaintValue::source(origin)),
        )
      }
      PropagateArgToReturn(index) =>
        if info.argument_at(index) is Some(arg) {
          value = value.join(arg.taint)
        }
      PropagateReceiverToReturn => value = value.join(info.receiver_taint)
      PropagateArgSubpathToReturn(index, path) =>
        if info.argument_at(index) is Some(arg) {
          value = value.join(arg.taint.project(path))
        }
      KillArg(index) =>
        if info.argument_at(index) is Some(arg) && arg.path is Some(path) {
          writes.push(Sanitize(path))
        }
      KillReceiver =>
        if info.receiver_path is Some(path) {
          writes.push(Sanitize(path))
        }
      ReportSinkArg(sink_id, index) =>
        if info.argument_at(index) is Some(arg) && !arg.taint.is_clean() {
          findings.push({ sink_id, sink_loc: arg.loc, })
        }
      ReportSinkReceiver(sink_id) =>
        if info.receiver_site is Some(_) && !info.receiver_taint.is_clean() {
          findings.push({ sink_id, sink_loc: info.loc, })
        }
      RaiseArg(index) => {
        let thrown = info
          .argument_at(index)
          .map(arg => arg.taint)
          .unwrap_or(TaintValue::clean())
        exceptional = Some({
          value: exceptional
          .map(outcome => outcome.value.join(thrown))
          .unwrap_or(thrown),
          writes: [],
        })
      }
      NoReturn => normal = false
    }
  }
  if !bound.matched && spec.unknown_call_policy is PropagateArgumentsToReturn {
    value = info.receiver_taint
    for argument in info.arguments {
      value = value.join(argument.taint)
    }
  }
  {
    normal: if normal {
      Some({ value, writes, })
    } else {
      None
    },
    exceptional,
    findings,
  }
}
