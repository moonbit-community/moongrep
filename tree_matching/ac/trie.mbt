///|
/// Node implementation for Aho-Corasick automaton
priv struct TrieNode[T] {
  parent : TrieNode[T]?
  goto : Map[T, TrieNode[T]]
  mut suffix : TrieNode[T]?
  mut output : TrieNode[T]?
  mut pattern : ImmutArray[T]
  mut metavar : String?
}

///|
impl[T : ToJson + Show] ToJson for TrieNode[T] with fn to_json(self) {
  if self.goto.is_empty() {
    Json::array(self.pattern.map(c => c.to_json()).to_array())
  } else {
    self.goto.to_json()
  }
}

///|
/// Create a new node with parent reference
fn[T : Hash + Eq] TrieNode::new(parent : TrieNode[T]?) -> TrieNode[T] {
  {
    parent,
    goto: Map([]),
    suffix: None,
    output: None,
    pattern: @immutvector.new(),
    metavar: None,
  }
}

///|
/// Get patterns from this node and the nodes reachable through output links.
fn[T] TrieNode::outputs(node : TrieNode[T]) -> Array[ImmutArray[T]] {
  let out = []
  let mut current = Some(node)
  while true {
    if current is Some(n) {
      if n.pattern.length() > 0 {
        out.push(n.pattern)
      }
      current = n.output
    } else {
      break
    }
  }
  out
}

///|
/// After `Trie::compute`, follow a goto edge if present; otherwise chase suffix
/// links to find the next state.
fn[T : Eq + Hash] TrieNode::follow(node : TrieNode[T], x : T) -> TrieNode[T] {
  if node.goto.get(x) is Some(target) {
    target
  } else {
    // direct move failed, follow suffix links
    fn fail(link : TrieNode[T], x : T) -> TrieNode[T] {
      if link.parent is None {
        // Root case
        if link.goto.get(x) is Some(actual) {
          actual
        } else {
          link
        }
      } else if link.goto.get(x) is Some(actual) {
        actual
      } else {
        let suffix = link.suffix.unwrap()
        fail(suffix, x)
      }
    }

    fail(node.suffix.unwrap(), x)
  }
}

///|
/// Trie/Aho-Corasick automaton structure
priv struct Trie[T] {
  root : TrieNode[T]
}

///|
/// Create an empty trie
fn[T : Hash + Eq] Trie::new() -> Trie[T] {
  Trie::{ root: TrieNode::new(None) }
}

///|
/// Add a pattern to the trie
fn[T : Eq + Hash] Trie::add(
  trie : Trie[T],
  pattern : ImmutArray[T],
  metavar? : String,
) -> Unit {
  let mut current_node = trie.root
  for x in pattern {
    if current_node.goto.get(x) is Some(next_node) {
      current_node = next_node
    } else {
      let new_node = TrieNode::new(Some(current_node))
      current_node.goto[x] = new_node
      current_node = new_node
    }
  }
  current_node.pattern = pattern
  current_node.metavar = metavar
}

///|
/// Compute suffix and output links for the automaton
fn[T : Eq + Hash] Trie::compute(trie : Trie[T]) -> Unit {
  let root = trie.root
  root.suffix = Some(root)
  let q : @queue.Queue[(T, TrieNode[T])] = @queue.Queue([])

  // Root and its children have root as their suffix
  // Queue root's grandchildren for BFS suffix computation
  root.goto.each(fn(_key, child) {
    child.suffix = Some(root)
    child.goto.each(fn(x, grandchild) { q.push((x, grandchild)) })
  })

  // Process queue
  while q.pop() is Some((x, node)) {
    let parent = node.parent.unwrap()
    let parent_suffix = parent.suffix.unwrap()

    // start at a node's parent's suffix, if no edge labelled x
    // exists then continually chase up suffix links. If you
    // reach the root, break to avoid looping indefinitely.
    fn follow_from_parent(
      s : TrieNode[T],
      x : T,
      root : TrieNode[T],
    ) -> TrieNode[T] {
      if s.parent is None {
        // s is root
        if s.goto.get(x) is Some(actual) {
          actual
        } else {
          root
        }
      } else if s.goto.get(x) is Some(node) {
        node
      } else {
        let suffix = s.suffix.unwrap()
        follow_from_parent(suffix, x, root)
      }
    }

    let suffix = follow_from_parent(parent_suffix, x, root)
    node.suffix = Some(suffix)

    // This implementation links directly to the suffix node when it stores a
    // pattern; otherwise it falls back to that suffix node's suffix link.
    let output = if suffix.pattern.length() > 0 {
      Some(suffix)
    } else {
      suffix.suffix
    }
    node.output = output

    // Queue the children of processed node
    node.goto.each(fn(x, child) { q.push((x, child)) })
  }
}
