///|
priv struct Entry[T] {
  node : LabelledTree
  state : TrieNode[T]
  mut visited : Int
}

///|
type EntryStack[T] = Array[Entry[T]]

///|
struct AstGrepEnv {
  locations : Array[Json]
}

///|
pub fn AstGrepEnv::new() -> AstGrepEnv {
  AstGrepEnv::{ locations: [] }
}

///|
pub fn AstGrepEnv::grep(
  self : AstGrepEnv,
  pattern : TreePattern,
  subject : LabelledTree,
) -> ArrayView[Json] {
  let trie = Trie::new()
  pattern.each(rtlpath => trie.add(rtlpath))
  trie.compute()
  // move on root label of subject tree
  let first = trie.root.follow(subject.label())
  let stack : EntryStack[Symbol] = Array::new()
  stack.push(Entry::{ node: subject, state: first, visited: -1 })
  fn tabulate(state : TrieNode[Symbol]) -> Unit {
    let outs = state.outputs()
    outs.each(out => {
      let len = out.iter().filter(symbol => symbol is Label(_)).count()
      let entry = stack[stack.length() - len]
      entry.node.hits += 1
      if entry.node.hits == pattern.length() {
        // matches!
        self.locations.push(entry.node.loc)
      }
    })
  }

  tabulate(first)
  while stack.last() is Some({ node, state, visited } as top) {
    if visited == node.arity() - 1 {
      ignore(stack.pop())
    } else {
      top.visited += 1
      let initial_state = state.follow(Child(top.visited))
      tabulate(initial_state)
      let node = node.child(top.visited)
      let state = initial_state.follow(node.label())
      stack.push(Entry::{ node, state, visited: -1 })
      tabulate(state)
    }
  }
  return self.locations
}
