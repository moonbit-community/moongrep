///|
priv struct Entry[T, Loc] {
  node : LabelledTree[Loc]
  state : TrieNode[T]
  mut visited : Int
}

///|
type EntryStack[T, Loc] = Array[Entry[T, Loc]]

///|
struct MbtAstGrepEnv[Loc] {
  locations : Map[Loc, Map[String, Array[Loc]]]
}

///|
pub fn[Loc : Hash + Eq] MbtAstGrepEnv::new() -> MbtAstGrepEnv[Loc] {
  MbtAstGrepEnv::{ locations: Map([]) }
}

///|
pub fn[Loc : Eq + Hash] MbtAstGrepEnv::grep(
  self : MbtAstGrepEnv[Loc],
  pattern : TreePattern,
  subject : LabelledTree[Loc],
) -> Map[Loc, Map[String, Array[Loc]]] {
  let trie = Trie::new()
  pattern.each(pair => {
    let (rtlpath, metavar) = pair
    trie.add(rtlpath, metavar?)
  })
  trie.compute()
  // move on root label of subject tree
  let first = trie.root.follow(subject.label())
  let stack : EntryStack[Symbol, Loc] = Array::new()
  stack.push(Entry::{ node: subject, state: first, visited: -1 })
  let metavar_registry = {}
  fn tabulate(state : TrieNode[Symbol]) -> Unit {
    let outs = state.outputs()
    outs.each(out => {
      let len = out.iter().filter(symbol => symbol is Label(_)).count()
      let entry = stack[stack.length() - len]
      entry.node.hits += 1
      // If the current state has a metavar, register it in the current search table.
      if state.metavar is Some(name) &&
        stack.last() is Some({ node, state: _, visited }) {
        let metavar_env = metavar_registry.get_or_init(
          entry.node.loc.unwrap_or_else(() => {
            println("internal bug: ac matching got an empty location")
            panic()
          }),
          () => Map([]),
        )
        match metavar_env.get(name) {
          None =>
            metavar_env[name] = [
              node.child(visited).loc.unwrap_or_else(() => {
                println("internal bug: ac matching got an empty location")
                panic()
              }),
            ]
          Some(locs) =>
            locs.push(
              node.child(visited).loc.unwrap_or_else(() => {
                println("internal bug: ac matching got an empty location")
                panic()
              }),
            )
        }
      }
      if entry.node.hits == pattern.length() {
        // matches!
        self.locations.set(
          entry.node.loc.unwrap_or_else(() => {
            println("internal bug: ac matching got an empty location")
            panic()
          }),
          metavar_registry.get_or_default(
            entry.node.loc.unwrap_or_else(() => {
              println("internal bug: ac matching got an empty location")
              panic()
            }),
            Map([]),
          ),
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
