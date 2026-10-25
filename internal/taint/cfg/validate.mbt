///|
// Check value availability on all reachable incoming paths. Initialize cyclic
// blocks at top and intersect predecessors to compute definite definitions.
fn Graph::validate_definitions(self : Graph, errors : Array[String]) -> Unit {
  let reachable = Array::make(self.blocks.length(), false)
  let pending = [self.entry]
  while pending.pop() is Some(id) {
    if reachable[id.0] {
      continue
    }
    reachable[id.0] = true
    for edge in self.blocks[id.0].terminator.edges() {
      pending.push(edge.target)
    }
  }
  let incoming = Array::makei(self.blocks.length(), i => {
    Array::make(self.value_count, i != self.entry.0)
  })
  let mut changed = true
  while changed {
    changed = false
    let next = Array::makei(self.blocks.length(), _ => {
      Array::make(self.value_count, true)
    })
    next[self.entry.0] = Array::make(self.value_count, false)
    for i in 0..<self.blocks.length() {
      if !reachable[i] {
        continue
      }
      let available = incoming[i].copy()
      let block = self.blocks[i]
      for value in block.parameters {
        available[value.0] = true
      }
      for instruction in block.instructions {
        available[instruction.result.0] = true
      }
      for j in 0..<block.terminator.edges().length() {
        let edge = block.terminator.edges()[j]
        let edge_available = available.copy()
        if block.terminator is Invoke(call, _, _) {
          let output = if j == 0 {
            self.calls[call].result
          } else {
            self.calls[call].error
          }
          edge_available[output.0] = true
        }
        for value in 0..<self.value_count {
          next[edge.target.0][value] = next[edge.target.0][value] &&
            edge_available[value]
        }
      }
    }
    for i in 0..<self.blocks.length() {
      if reachable[i] && incoming[i] != next[i] {
        incoming[i] = next[i]
        changed = true
      }
    }
  }
  for i in 0..<self.blocks.length() {
    if !reachable[i] {
      continue
    }
    let available = incoming[i].copy()
    let block = self.blocks[i]
    for value in block.parameters {
      available[value.0] = true
    }
    fn require(value : ValueId) {
      if !available[value.0] {
        errors.push("value used before definition")
      }
    }
    for instruction in block.instructions {
      for value in instruction.operation.inputs() {
        require(value)
      }
      available[instruction.result.0] = true
    }
    match block.terminator {
      Branch(value, _, _) | Return(value) | Raise(value) => require(value)
      Invoke(call, _, _) => {
        for argument in self.calls[call].arguments {
          require(argument.value)
        }
        if self.calls[call].receiver is Some(receiver) {
          require(receiver.value)
        }
      }
      _ => ()
    }
    let edges = block.terminator.edges()
    for j in 0..<edges.length() {
      for argument in edges[j].arguments {
        if block.terminator is Invoke(call, _, _) {
          let output = if j == 0 {
            self.calls[call].result
          } else {
            self.calls[call].error
          }
          if argument == output {
            continue
          }
        }
        require(argument)
      }
    }
  }
}
