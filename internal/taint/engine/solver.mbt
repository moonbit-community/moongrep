///|
/// Analyze a graph prepared once and shared by all rules. Transfers must be
/// deterministic and have no external side effects.
pub fn analyze(
  prepared : @cfg.PreparedFunction,
  spec : TaintSpec,
  options~ : AnalysisOptions = AnalysisOptions::default(),
  metrics~ : AnalysisMetrics = AnalysisMetrics::new(),
) -> AnalysisResult {
  solve(prepared, spec, options, stats=metrics)
}

///|
pub(all) struct AnalysisMetrics {
  mut block_visits : Int32
  mut input_updates : Int32
  mut bound_calls : Int32
}

///|
fn solve(
  prepared : @cfg.PreparedFunction,
  spec : TaintSpec,
  options : AnalysisOptions,
  reverse~ : Bool = false,
  stats~ : AnalysisMetrics = {
    block_visits: 0,
    input_updates: 0,
    bound_calls: 0,
  },
) -> AnalysisResult {
  let graph = prepared.graph()
  let initial = State::empty(graph)
  for source in spec.sources {
    if source is EntryPath(parameter, origin_id, note) {
      for binding in graph.bindings {
        if binding.parameter && binding.name == parameter.root {
          let path : StoragePath = {
            root: binding.id,
            segments: parameter.segments,
          }
          let origin : TaintOrigin = {
            rule_id: spec.rule_id,
            origin_id,
            note,
            site: Path(path),
          }
          let current = initial.storage[path.root.0].project(path.segments)
          initial.write(path, current.join(TaintValue::source(origin)))
        }
      }
    }
  }
  let clean = State::empty(graph)
  let cache : Map[String, BoundCall] = Map([])
  let bound = graph.calls.map(call => {
    let key = "\{call.loc.start.cnum}:\{call.loc.end.cnum}"
    if cache.get(key) is Some(bound) {
      bound
    } else {
      let bound = bind_call(call_info(call, clean), spec)
      cache[key] = bound
      stats.bound_calls += 1
      bound
    }
  })
  let inputs : Array[State?] = Array::make(graph.blocks.length(), None)
  inputs[graph.entry.0] = Some(initial)
  let dirty = Array::make(graph.blocks.length(), false)
  dirty[graph.entry.0] = true
  let live = prepared.live_values()
  fn propagate(edge : @cfg.Edge, state : State) {
    let next = state.copy()
    let parameters = graph.blocks[edge.target.0].parameters
    // Snapshot all arguments before changing any destination parameter.
    let arguments = edge.arguments.map(value => state.values[value.0])
    for i in 0..<parameters.length() {
      next.values[parameters[i].0] = arguments[i]
    }
    for i in 0..<next.values.length() {
      if !live[edge.target.0][i] {
        next.values[i] = TaintValue::clean()
      }
    }
    let joined = if inputs[edge.target.0] is Some(previous) {
      previous.join(next)
    } else {
      next
    }
    if inputs[edge.target.0] != Some(joined) {
      stats.input_updates += 1
      inputs[edge.target.0] = Some(joined)
      dirty[edge.target.0] = true
    }
  }
  for ordered in prepared.components() {
    let component = if reverse {
      Array::makei(ordered.length(), i => ordered[ordered.length() - 1 - i])
    } else {
      ordered
    }
    let cyclic = component.length() > 1 ||
      graph.blocks[component[0].0].terminator
      .edges()
      .any(edge => edge.target == component[0])
    let mut rounds = 0
    while component.any(block => dirty[block.0]) {
      if cyclic && rounds >= options.max_scc_rounds {
        return Incomplete([
          {
            loc: graph.blocks[component[0].0].loc,
            reason: "SCC did not converge within \{options.max_scc_rounds} rounds",
          },
        ])
      }
      rounds += 1
      for id in component {
        if !dirty[id.0] {
          continue
        }
        stats.block_visits += 1
        dirty[id.0] = false
        guard inputs[id.0] is Some(input) else { continue }
        let state = input.copy()
        let block = graph.blocks[id.0]
        state.instructions(block)
        match block.terminator {
          Jump(edge) => propagate(edge, state)
          Branch(_, yes, no) => {
            propagate(yes, state)
            propagate(no, state)
          }
          Invoke(index, normal, exceptional) => {
            let call = graph.calls[index]
            let transfer = transfer_call(
              bound[index],
              call_info(call, state),
              spec,
            )
            if transfer.normal is Some(outcome) {
              let next = state.copy()
              next.apply(outcome)
              next.values[call.result.0] = outcome.value
              propagate(normal, next)
            }
            if transfer.exceptional is Some(outcome) {
              let next = state.copy()
              next.apply(outcome)
              next.values[call.error.0] = outcome.value
              propagate(exceptional, next)
            }
          }
          Return(_) | Raise(_) | Abort => ()
        }
      }
    }
  }
  // Publish only after every component converges, from final input states.
  let findings : Array[SinkFinding] = []
  for i in 0..<graph.blocks.length() {
    if inputs[i] is Some(input) &&
      graph.blocks[i].terminator is Invoke(index, _, _) {
      let state = input.copy()
      state.instructions(graph.blocks[i])
      let transfer = transfer_call(
        bound[index],
        call_info(graph.calls[index], state),
        spec,
      )
      for finding in transfer.findings {
        if !findings.contains(finding) {
          findings.push(finding)
        }
      }
    }
  }
  findings.sort_by((a, b) => {
    let a_key = (
      a.sink_loc.start.lnum,
      a.sink_loc.start.column(),
      a.sink_loc.end.lnum,
      a.sink_loc.end.column(),
      sink_key(a),
    )
    let b_key = (
      b.sink_loc.start.lnum,
      b.sink_loc.start.column(),
      b.sink_loc.end.lnum,
      b.sink_loc.end.column(),
      sink_key(b),
    )
    a_key.compare(b_key)
  })
  Complete(findings)
}

///|
fn sink_key(finding : SinkFinding) -> String {
  match finding.sink_id {
    Named(name) => "name:\{name}"
    PatternIndex(index) => "pattern:\{index}"
  }
}

///|
pub fn AnalysisMetrics::new() -> AnalysisMetrics {
  { block_visits: 0, input_updates: 0, bound_calls: 0, }
}
