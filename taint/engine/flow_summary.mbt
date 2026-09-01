///|
// Each reachable control-flow partition owns its abstract state and expression
// value. Keeping these together prevents states from unrelated exit kinds from
// being merged and then attributed to whichever branch happened to come first.
priv struct FlowPath {
  state : TaintState
  value : TaintTree
}

///|
priv struct LabelledFlowPath {
  label : String?
  path : FlowPath
}

///|
// Evaluation may reach several control-flow exits at once. Break and continue
// paths remain partitioned by target label until the matching block or loop
// consumes them.
priv struct EvalResult {
  normal : FlowPath?
  returned : FlowPath?
  raised : FlowPath?
  breaks : Array[LabelledFlowPath]
  continues : Array[LabelledFlowPath]
}

///|
priv struct EvalArgumentsPath {
  state : TaintState
  arguments : Array[CallArgument]
}

///|
priv struct EvalArgumentsResult {
  normal : EvalArgumentsPath?
  exits : EvalResult
}

///|
priv struct ConditionPath {
  base_state : TaintState
  true_state : TaintState
  bound_roots : Array[String]
  value : TaintTree
}

///|
priv struct ConditionEval {
  normal : ConditionPath?
  exits : EvalResult
}

///|
priv struct ConsumedLoopFlow {
  back_edge : FlowPath?
  break_exit : FlowPath?
  exits : EvalResult
}

///|
fn empty_flow_summary() -> EvalResult {
  { normal: None, returned: None, raised: None, breaks: [], continues: [], }
}

///|
fn normal_result(state : TaintState, value : TaintTree) -> EvalResult {
  {
    normal: Some({ state, value, }),
    returned: None,
    raised: None,
    breaks: [],
    continues: [],
  }
}

///|
fn return_result(state : TaintState, value : TaintTree) -> EvalResult {
  {
    normal: None,
    returned: Some({ state, value, }),
    raised: None,
    breaks: [],
    continues: [],
  }
}

///|
fn raise_result(state : TaintState, value : TaintTree) -> EvalResult {
  {
    normal: None,
    returned: None,
    raised: Some({ state, value, }),
    breaks: [],
    continues: [],
  }
}

///|
fn break_result(
  label : String?,
  state : TaintState,
  value : TaintTree,
) -> EvalResult {
  {
    normal: None,
    returned: None,
    raised: None,
    breaks: [{ label, path: { state, value, }, }],
    continues: [],
  }
}

///|
fn merge_flow_paths(left : FlowPath, right : FlowPath) -> FlowPath {
  {
    state: state_merge(left.state, right.state),
    value: tree_merge(left.value, right.value),
  }
}

///|
fn merge_optional_flow_paths(left : FlowPath?, right : FlowPath?) -> FlowPath? {
  match (left, right) {
    (Some(left), Some(right)) => Some(merge_flow_paths(left, right))
    (Some(path), None) | (None, Some(path)) => Some(path)
    (None, None) => None
  }
}

///|
fn add_labelled_flow_path(
  paths : Array[LabelledFlowPath],
  entry : LabelledFlowPath,
) -> Unit {
  for index in 0..<paths.length() {
    if paths[index].label == entry.label {
      paths[index] = {
        label: entry.label,
        path: merge_flow_paths(paths[index].path, entry.path),
      }
      return
    }
  }
  paths.push(entry)
}

///|
fn merge_labelled_flow_paths(
  left : Array[LabelledFlowPath],
  right : Array[LabelledFlowPath],
) -> Array[LabelledFlowPath] {
  let merged : Array[LabelledFlowPath] = []
  for entry in left {
    add_labelled_flow_path(merged, entry)
  }
  for entry in right {
    add_labelled_flow_path(merged, entry)
  }
  merged
}

///|
fn flow_join(left : EvalResult, right : EvalResult) -> EvalResult {
  {
    normal: merge_optional_flow_paths(left.normal, right.normal),
    returned: merge_optional_flow_paths(left.returned, right.returned),
    raised: merge_optional_flow_paths(left.raised, right.raised),
    breaks: merge_labelled_flow_paths(left.breaks, right.breaks),
    continues: merge_labelled_flow_paths(left.continues, right.continues),
  }
}

///|
fn flow_without_normal(result : EvalResult) -> EvalResult {
  {
    normal: None,
    returned: result.returned,
    raised: result.raised,
    breaks: result.breaks,
    continues: result.continues,
  }
}

///|
fn flow_with_normal(result : EvalResult, normal : FlowPath?) -> EvalResult {
  {
    normal,
    returned: result.returned,
    raised: result.raised,
    breaks: result.breaks,
    continues: result.continues,
  }
}

///|
// `next` must have been evaluated only from `prefix.normal`. All earlier exits
// bypass it and are retained unchanged.
fn flow_sequence(prefix : EvalResult, next : EvalResult) -> EvalResult {
  flow_join(flow_without_normal(prefix), next)
}

///|
fn flow_normal_to_return(result : EvalResult) -> EvalResult {
  let converted = flow_without_normal(result)
  {
    ..converted,
    returned: merge_optional_flow_paths(converted.returned, result.normal),
  }
}

///|
fn flow_normal_to_raise(result : EvalResult) -> EvalResult {
  let converted = flow_without_normal(result)
  {
    ..converted,
    raised: merge_optional_flow_paths(converted.raised, result.normal),
  }
}

///|
fn flow_normal_to_break(result : EvalResult, label : String?) -> EvalResult {
  let converted = flow_without_normal(result)
  let breaks = merge_labelled_flow_paths(
    converted.breaks,
    match result.normal {
      Some(path) => [{ label, path, }]
      None => []
    },
  )
  { ..converted, breaks, }
}

///|
fn flow_normal_to_continue(result : EvalResult, label : String?) -> EvalResult {
  let converted = flow_without_normal(result)
  let continues = merge_labelled_flow_paths(
    converted.continues,
    match result.normal {
      Some(path) => [{ label, path, }]
      None => []
    },
  )
  { ..converted, continues, }
}

///|
fn control_targets_loop(target : String?, loop_label : String?) -> Bool {
  match target {
    Some(target) => loop_label == Some(target)
    None => true
  }
}

///|
fn consume_labelled_block_break(
  result : EvalResult,
  label : String?,
) -> EvalResult {
  let remaining : Array[LabelledFlowPath] = []
  let mut consumed : FlowPath? = None
  for entry in result.breaks {
    if entry.label is Some(target) && label == Some(target) {
      consumed = merge_optional_flow_paths(consumed, Some(entry.path))
    } else {
      remaining.push(entry)
    }
  }
  {
    normal: merge_optional_flow_paths(result.normal, consumed),
    returned: result.returned,
    raised: result.raised,
    breaks: remaining,
    continues: result.continues,
  }
}

///|
fn consume_loop_control(
  result : EvalResult,
  loop_label : String?,
) -> ConsumedLoopFlow {
  let mut back_edge = result.normal
  let mut break_exit : FlowPath? = None
  let remaining_breaks : Array[LabelledFlowPath] = []
  let remaining_continues : Array[LabelledFlowPath] = []
  for entry in result.breaks {
    if control_targets_loop(entry.label, loop_label) {
      break_exit = merge_optional_flow_paths(break_exit, Some(entry.path))
    } else {
      remaining_breaks.push(entry)
    }
  }
  for entry in result.continues {
    if control_targets_loop(entry.label, loop_label) {
      back_edge = merge_optional_flow_paths(back_edge, Some(entry.path))
    } else {
      remaining_continues.push(entry)
    }
  }
  {
    back_edge,
    break_exit,
    exits: {
      normal: None,
      returned: result.returned,
      raised: result.raised,
      breaks: remaining_breaks,
      continues: remaining_continues,
    },
  }
}
