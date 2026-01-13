///|
priv struct Entry[T] {
  node : LabelledTree
  state : TrieNode[T]
  mut visited : Int
}

///|
type EntryStack[T] = Array[Entry[T]]

///|
struct MbtAstGrepEnv {
  locations : Map[String, Map[String, Array[String]]]
}

///|
pub fn MbtAstGrepEnv::new() -> MbtAstGrepEnv {
  MbtAstGrepEnv::{ locations: Map::new() }
}

///|
pub fn MbtAstGrepEnv::grep(
  self : MbtAstGrepEnv,
  pattern : TreePattern,
  subject : LabelledTree,
) -> Map[String, Map[String, Array[String]]] {
  let trie = Trie::new()
  pattern.each(pair => {
    let (rtlpath, metavar) = pair
    trie.add(rtlpath, metavar?)
  })
  trie.compute()
  // move on root label of subject tree
  let first = trie.root.follow(subject.label())
  let stack : EntryStack[Symbol] = Array::new()
  stack.push(Entry::{ node: subject, state: first, visited: -1 })
  let metavar_registry = {}
  fn tabulate(state : TrieNode[Symbol]) -> Unit {
    let outs = state.outputs()
    outs.each(out => {
      let len = out.iter().filter(symbol => symbol is Label(_)).count()
      let entry = stack[stack.length() - len]
      entry.node.hits += 1
      // if current state has metavar, registering it to global table
      if state.metavar is Some(name) &&
        stack.last() is Some({ node, state: _, visited }) {
        let metavar_env = metavar_registry.get_or_init(entry.node.loc, () => Map::new())
        match metavar_env.get(name) {
          None => metavar_env[name] = [node.child(visited).loc]
          Some(locs) => locs.push(node.child(visited).loc)
        }
      }
      if entry.node.hits == pattern.length() {
        // matches!
        self.locations.set(
          entry.node.loc,
          metavar_registry.get_or_default(entry.node.loc, Map::new()),
        )
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
