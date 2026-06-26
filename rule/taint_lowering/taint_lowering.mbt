///|
using @model {type CompiledRule, type CompiledTaintRule, type TaintTarget}

///|
priv struct TargetValue {
  loc : @basic.Location
  site : @taint.ValueSite
  path : @taint.StoragePath?
  taint : @taint.TaintTree
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
    max_fixpoint_iterations: 6,
    custom_transfer_call: call => {
      transfer_compiled_taint_call(rule.rule_id, taint_rule, call)
    },
  }
}

///|
// Implements YAML taint rules as a custom call transfer instead of teaching the
// taint engine about rule syntax. The rule package family owns AST pattern matching;
// the taint package only sees generic call facts and transfer results.
fn transfer_compiled_taint_call(
  rule_id : String,
  taint_rule : CompiledTaintRule,
  call : @taint.CallInfo,
) -> @taint.CallTransfer? {
  let mut matched = false
  let return_taint : @taint.TaintTree = []
  let killed_paths : Array[@taint.StoragePath] = []
  let findings : Array[@taint.SinkFinding] = []
  for index in 0..<taint_rule.sources.length() {
    if @matching.match_expr_pattern(
        taint_rule.sources[index].pattern.compiled,
        call.ast,
      )
      is Some(_) {
      matched = true
      return_taint.push({
        path: [],
        origins: [
          {
            rule_id,
            origin_id: "source:\{index}",
            site: CallResult(call.callee_name, call.loc),
            note: None,
          },
        ],
      })
    }
  }
  for index in 0..<taint_rule.sanitizers.length() {
    let sanitizer = taint_rule.sanitizers[index]
    if @matching.match_expr_pattern(sanitizer.pattern.compiled, call.ast)
      is Some(_) {
      matched = true
      if target_value(call, sanitizer.target) is Some(target) &&
        target.path is Some(path) {
        killed_paths.push(path)
      }
    }
  }
  for index in 0..<taint_rule.sinks.length() {
    let sink = taint_rule.sinks[index]
    if @matching.match_expr_pattern(sink.pattern.compiled, call.ast) is Some(_) {
      matched = true
      if target_value(call, sink.target) is Some(target) {
        let origins = origins_from_taint_tree(target.taint)
        if origins.length() > 0 {
          findings.push({
            rule_id,
            sink_id: "sink:\{index}",
            sink_loc: target.loc,
            sink_site: target.site,
            origins,
          })
        }
      }
    }
  }
  if matched {
    Some({ return_taint, killed_paths, findings })
  } else {
    None
  }
}

///|
fn target_value(call : @taint.CallInfo, target : TaintTarget) -> TargetValue? {
  match target {
    Receiver =>
      if call.receiver_site is Some(site) {
        Some({
          loc: call.loc,
          site,
          path: call.receiver_path,
          taint: call.receiver_taint,
        })
      } else {
        None
      }
    PositionalArg(index) =>
      if call_argument_at(call.arguments, index) is Some(arg) {
        Some({ loc: arg.loc, site: arg.site, path: arg.path, taint: arg.taint })
      } else {
        None
      }
    LabelledArg(label~, index~) =>
      if call_argument_at(call.arguments, index) is Some(arg) {
        if arg.label == Some(label) {
          Some({
            loc: arg.loc,
            site: arg.site,
            path: arg.path,
            taint: arg.taint,
          })
        } else {
          None
        }
      } else {
        None
      }
  }
}

///|
fn call_argument_at(
  args : Array[@taint.CallArgument],
  index : Int,
) -> @taint.CallArgument? {
  for arg in args {
    if arg.index == index {
      return Some(arg)
    }
  }
  None
}

///|
fn origins_from_taint_tree(
  tree : @taint.TaintTree,
) -> Array[@taint.TaintOrigin] {
  let origins : Array[@taint.TaintOrigin] = []
  for entry in tree {
    for origin in entry.origins {
      if !origins.contains(origin) {
        origins.push(origin)
      }
    }
  }
  origins
}
