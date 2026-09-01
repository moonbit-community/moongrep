///|
// One abstract loop iteration keeps ordinary loop termination, back edges,
// matching breaks, and exits for enclosing constructs separate.
priv struct LoopIterationSummary {
  normal_exit : FlowPath?
  back_edge : FlowPath?
  break_exit : FlowPath?
  exits : EvalResult
}

///|
priv struct LoopFixpointSummary {
  normal_exit : FlowPath?
  break_exit : FlowPath?
  exits : EvalResult
}

///|
fn run_loop_fixpoint(
  initial : TaintState,
  budget : Int,
  step : (TaintState) -> LoopIterationSummary raise,
) -> LoopFixpointSummary raise {
  let mut current = initial
  let mut normal_exit : FlowPath? = None
  let mut break_exit : FlowPath? = None
  let mut exits = empty_flow_summary()
  let mut iteration = 0
  while iteration < budget {
    let iteration_result = step(current)
    normal_exit = merge_optional_flow_paths(
      normal_exit,
      iteration_result.normal_exit,
    )
    break_exit = merge_optional_flow_paths(
      break_exit,
      iteration_result.break_exit,
    )
    exits = flow_join(exits, iteration_result.exits)
    let mut joined = current
    if iteration_result.normal_exit is Some(path) {
      joined = state_merge(joined, path.state)
    }
    if iteration_result.back_edge is Some(path) {
      joined = state_merge(joined, path.state)
    }
    if state_equiv(joined, current) {
      return {
        normal_exit: match normal_exit {
          Some(path) =>
            Some({ state: state_merge(path.state, joined), value: path.value, })
          None => None
        },
        break_exit,
        exits,
      }
    }
    current = joined
    iteration += 1
  }
  {
    normal_exit: match normal_exit {
      Some(path) =>
        Some({ state: state_merge(path.state, current), value: path.value, })
      None => None
    },
    break_exit,
    exits,
  }
}
