///|
priv enum SemanticValue {
  Identity(String)
  Leaf(@untyped_cst.NodePayload)
  Node(@untyped_cst.NodeKind, Array[(String?, Int)])
} derive(Eq)

///|
impl Hash for SemanticValue with fn hash_combine(self, hasher) {
  match self {
    Identity(name) => {
      hasher.combine_int(0)
      hasher.combine_string(name)
    }
    Leaf(payload) => {
      hasher.combine_int(1)
      match payload {
        @untyped_cst.String(value) => hasher.combine_string(value)
        @untyped_cst.Int(value) => hasher.combine_int(value)
        @untyped_cst.Bool(value) =>
          hasher.combine_int(if value { 1 } else { 0 })
      }
    }
    // NodeKind has Eq but no Hash. Equal child lists may collide across kinds;
    // Map always checks the complete key, including NodeKind, before sharing.
    Node(_, children) => {
      hasher.combine_int(2)
      Hash::hash_combine(children, hasher)
    }
  }
}

///|
priv enum BoundIdentity {
  SingleIdentity(Int)
  MultipleIdentity(Array[Int])
} derive(Eq, Hash)

///|
/// Intern the matcher's location-insensitive equality, retaining value variants.
pub struct ValueInterner {
  priv nodes : Map[SemanticValue, Int]
  priv values : Map[BoundIdentity, Int]
}

///|
pub fn ValueInterner::new() -> ValueInterner {
  { nodes: Map([]), values: Map([]), }
}

///|
fn ValueInterner::node(self : ValueInterner, raw : @untyped_cst.CstNode) -> Int {
  let node = @cst.unwrap_groups(raw)
  let key = if normalized_identity_node(node) &&
    @cst.normalized_name(node) is Some(name) {
    Identity(name)
  } else {
    match node.kind {
      @untyped_cst.Leaf(payload) => Leaf(payload)
      _ =>
        Node(
          node.kind,
          @cst.semantic_children(node).map(entry => {
            (entry.0, self.node(entry.1))
          }),
        )
    }
  }
  if self.nodes.get(key) is Some(id) {
    return id
  }
  let id = self.nodes.length()
  self.nodes[key] = id
  id
}

///|
pub fn ValueInterner::intern(self : ValueInterner, value : BoundValue) -> Int {
  let key = match value {
    Single(node) => SingleIdentity(self.node(node))
    Multiple(nodes) => MultipleIdentity(nodes.map(node => self.node(node)))
  }
  if self.values.get(key) is Some(id) {
    return id
  }
  let id = self.values.length()
  self.values[key] = id
  id
}
