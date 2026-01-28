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
impl[T : ToJson + Show] ToJson for TrieNode[T] with to_json(self) {
  if self.goto.is_empty() {
    Json::array(self.pattern.map(c => c.to_json()).to_array())
  } else {
    self.goto.to_json()
  }
}

///|
/// Create a new node with parent reference
fn[T] TrieNode::new(parent : TrieNode[T]?) -> TrieNode[T] {
  {
    parent,
    goto: Map::new(),
    suffix: None,
    output: None,
    pattern: @immutarray.new(),
    metavar: None,
  }
}

///|
/// Get all patterns from a node by following output links
fn[T] TrieNode::outputs(node : TrieNode[T]) -> Array[ImmutArray[T]] {
  let out = []
  let mut current = Some(node)
  while true {
    match current {
      Some(n) => {
        if n.pattern.length() > 0 {
          out.push(n.pattern)
        }
        current = n.output
      }
      None => break
    }
  }
  out
}

///|
/// Follow goto or suffix links to find next node
fn[T : Eq + Hash] TrieNode::follow(node : TrieNode[T], x : T) -> TrieNode[T] {
  match node.goto.get(x) {
    Some(target) => target
    None => {
      // direct move failed, follow suffix links
      fn fail(link : TrieNode[T], x : T) -> TrieNode[T] {
        match link.parent {
          None =>
            // Root case
            match link.goto.get(x) {
              Some(actual) => actual
              None => link
            }
          Some(_) =>
            match link.goto.get(x) {
              Some(actual) => actual
              None => {
                let suffix = link.suffix.unwrap()
                fail(suffix, x)
              }
            }
        }
      }

      fail(node.suffix.unwrap(), x)
    }
  }
}

///|
/// Trie/Aho-Corasick automaton structure
priv struct Trie[T] {
  root : TrieNode[T]
}

///|
/// Create an empty trie
fn[T] Trie::new() -> Trie[T] {
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
    match current_node.goto.get(x) {
      Some(next_node) => current_node = next_node
      None => {
        let new_node = TrieNode::new(Some(current_node))
        current_node.goto[x] = new_node
        current_node = new_node
      }
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
  let q : @queue.Queue[(T, TrieNode[T])] = @queue.new()

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
        match s.goto.get(x) {
          Some(actual) => actual
          None => root
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

    // a node's output link is its suffix link if its suffix link
    // has a pattern (is an output node), otherwise it's its suffix's
    // output link.
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
