///|
/// Tarjan SCCs, in topological order; stable block order inside each SCC.
pub fn Graph::components(self : Graph) -> Array[Array[BlockId]] {
  let count = self.blocks.length()
  let indexes = Array::make(count, -1)
  let low = Array::make(count, -1)
  let on_stack = Array::make(count, false)
  let stack : Array[Int32] = []
  let components : Array[Array[BlockId]] = []
  let mut next = 0
  fn visit(block : Int32) {
    indexes[block] = next
    low[block] = next
    next += 1
    stack.push(block)
    on_stack[block] = true
    for edge in self.blocks[block].terminator.edges() {
      let target = edge.target.0
      if indexes[target] < 0 {
        visit(target)
        low[block] = Int32::min(low[block], low[target])
      } else if on_stack[target] {
        low[block] = Int32::min(low[block], indexes[target])
      }
    }
    if low[block] == indexes[block] {
      let component : Array[BlockId] = []
      while stack.pop() is Some(element) {
        on_stack[element] = false
        component.push(BlockId(element))
        if element == block {
          break
        }
      }
      component.sort()
      components.push(component)
    }
  }
  for block in 0..<count {
    if indexes[block] < 0 {
      visit(block)
    }
  }
  Array::makei(components.length(), i => components[components.length() - 1 - i])
}

///|
/// Values needed at each block entry. Dead temporaries never flow around a
/// cycle, and block parameters are substituted simultaneously on each edge.
pub fn Graph::live_values(self : Graph) -> Array[Array[Bool]] {
  let live = Array::makei(self.blocks.length(), _ => {
    Array::make(self.value_count, false)
  })
  let mut changed = true
  while changed {
    changed = false
    for i = self.blocks.length() - 1; i >= 0; i = i - 1 {
      let block = self.blocks[i]
      let needed = Array::make(self.value_count, false)
      for edge in block.terminator.edges() {
        let target_live = live[edge.target.0]
        let parameters = self.blocks[edge.target.0].parameters
        let contribution = target_live.copy()
        // Remove all destination parameters before adding any argument. This
        // matters for swaps and when one successor retains a parameter that
        // another successor replaces.
        for parameter in parameters {
          contribution[parameter.0] = false
        }
        for j in 0..<parameters.length() {
          if target_live[parameters[j].0] {
            contribution[edge.arguments[j].0] = true
          }
        }
        for value in 0..<self.value_count {
          if contribution[value] {
            needed[value] = true
          }
        }
      }
      match block.terminator {
        Branch(value, _, _) | Return(value) | Raise(value) =>
          needed[value.0] = true
        Invoke(index, _, _) => {
          let call = self.calls[index]
          needed[call.result.0] = false
          needed[call.error.0] = false
          for argument in call.arguments {
            needed[argument.value.0] = true
          }
          if call.receiver is Some(receiver) {
            needed[receiver.value.0] = true
          }
        }
        _ => ()
      }
      for j = block.instructions.length() - 1; j >= 0; j = j - 1 {
        let instruction = block.instructions[j]
        needed[instruction.result.0] = false
        // Reads, projections and computations are pure but keeping their
        // inputs live also makes validation and instrumentation straightforward.
        for value in instruction.operation.inputs() {
          needed[value.0] = true
        }
      }
      if live[i] != needed {
        live[i] = needed
        changed = true
      }
    }
  }
  live
}
