///|
// One abstract loop iteration keeps nobreak termination, back edges, matching
// breaks, and exits for enclosing constructs separate.
priv struct LoopIterationSummary {
  nobreak_exit : FlowPath?
  back_edge : FlowPath?
  break_exit : FlowPath?
  exits : EvalResult
}

///|
priv struct LoopFixpointSummary {
  nobreak_exit : FlowPath?
  break_exit : FlowPath?
  exits : EvalResult
}

///|
fn run_loop_fixpoint(
  initial : TaintState,
  rule_id : String,
  loop_kind : String,
  loc : @basic.Location,
  budget : Int,
  step : (TaintState) -> LoopIterationSummary raise,
) -> LoopFixpointSummary raise {
  let mut current = initial
  let mut nobreak_exit : FlowPath? = None
  let mut break_exit : FlowPath? = None
  let mut exits = empty_flow_summary()
  let mut iteration = 0
  while iteration < budget {
    let iteration_result = step(current)
    nobreak_exit = merge_optional_flow_paths(
      nobreak_exit,
      iteration_result.nobreak_exit,
    )
    break_exit = merge_optional_flow_paths(
      break_exit,
      iteration_result.break_exit,
    )
    exits = flow_join(exits, iteration_result.exits)
    let mut joined = current
    if iteration_result.back_edge is Some(path) {
      joined = state_merge(joined, path.state)
    }
    if state_equiv(joined, current) {
      return { nobreak_exit, break_exit, exits, }
    }
    current = joined
    iteration += 1
  }
  raise TaintAnalysisError::FixpointDidNotConverge(
    rule_id~,
    loop_kind~,
    loc~,
    budget~,
  )
}
