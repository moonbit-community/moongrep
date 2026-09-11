///|
pub type NodeId = Int

///|
pub type RegionId = Int

///|
pub type ScopeId = Int

///|
pub type BindingId = Int

///|
pub type CursorId = Int

///|
/// A forest cursor. Shared suffixes are evaluated independently of their callers.
pub(all) enum SourceStep {
  End
  Visit(RegionId, CursorId)
  Concat(CursorId, CursorId)
  Scan(RegionId)
  Finish(CursorId)
  AfterContinue(CursorId, CursorId)
} derive(Eq, Hash)

///|
priv enum RegionKey {
  Node(NodeId)
  Slice(Int, Int, Int)
} derive(Eq, Hash)

///|
priv struct IndexedNode {
  node : @untyped_cst.CstNode
  children : Array[(String?, NodeId)]
  mut scope : ScopeId
  mut function_body : Bool
  mut sequence : Int?
  mut statement : (Int, Int)?
}

///|
priv struct SourceSequence {
  owner : NodeId
  nodes : Array[NodeId]
  values : Array[@untyped_cst.CstNode]
  scopes : Array[ScopeId]
}

///|
priv struct LexicalScope {
  parent : ScopeId
  binding : BindingId
  name : String
}

///|
/// Owned by one scan, including its lexical-resolution and traversal caches.
pub struct SourceIndex {
  priv mut scoped : Bool
  priv nodes : Array[IndexedNode]
  priv node_buckets : Map[(Int, Int), Array[NodeId]]
  priv sequences : Array[SourceSequence]
  priv scopes : Array[LexicalScope]
  priv scope_ids : Map[(ScopeId, BindingId), ScopeId]
  priv resolutions : Map[(ScopeId, String), BindingId?]
  priv regions : Array[RegionKey]
  priv region_ids : Map[RegionKey, RegionId]
  priv steps : Array[SourceStep]
  priv step_ids : Map[SourceStep, CursorId]
  priv child_cursors : Map[(RegionId, Bool), CursorId]
  priv root_cursors : Map[NodeId, CursorId]
  priv descendant_cursors : Map[(NodeId, Bool), CursorId]
  priv sequence_cursors : Map[(Int, Int, Int, Bool), CursorId]
  priv direct_cursors : Map[(NodeId, TraversalLayer), CursorId]
}

///|
pub fn SourceIndex::new(root : @untyped_cst.CstNode) -> SourceIndex {
  let self : SourceIndex = {
    scoped: false,
    nodes: [],
    node_buckets: Map([]),
    sequences: [],
    scopes: [],
    scope_ids: Map([]),
    resolutions: Map([]),
    regions: [],
    region_ids: Map([]),
    steps: [End],
    step_ids: Map([]),
    child_cursors: Map([]),
    root_cursors: Map([]),
    descendant_cursors: Map([]),
    sequence_cursors: Map([]),
    direct_cursors: Map([]),
  }
  // Index raw occurrences first. Spans only choose an identity lookup bucket;
  // reference equality, never span equality, identifies an original CST node.
  let root_id = self.add_node(root)
  let pending = [root_id]
  while pending.pop() is Some(id) {
    for (label, child) in self.nodes[id].node.children {
      // Tokens and location metadata cannot be expression targets or binders.
      // Interpolations retain their parsed expression subtree for the matcher.
      if (
          is_syntax_kind(child.kind) &&
          !(child.kind is @untyped_cst.Syntax_Interpolation)
        ) ||
        is_pure_punctuation_kind(child.kind) ||
        is_location_label(label) ||
        label == Some("doc") {
        continue
      }
      let child_id = self.add_node(child)
      if label == Some("body") &&
        child.kind is @untyped_cst.Expr_Block &&
        self.nodes[id].node.kind
        is (@untyped_cst.Impl_Function
        | @untyped_cst.Impl_Test
        | @untyped_cst.Expr_Function
        | @untyped_cst.Expr_LetFn
        | @untyped_cst.Binding_LetRec) {
        self.nodes[child_id].function_body = true
      }
      self.nodes[id].children.push((label, child_id))
      pending.push(child_id)
    }
  }
  self.index_sequences()
  self
}

///|
fn SourceIndex::add_node(
  self : SourceIndex,
  node : @untyped_cst.CstNode,
) -> NodeId {
  let id = self.nodes.length()
  self.nodes.push({
    node,
    children: [],
    scope: -1,
    function_body: false,
    sequence: None,
    statement: None,
  })
  match self.node_buckets.get(node.source_span) {
    Some(bucket) => bucket.push(id)
    None => self.node_buckets[node.source_span] = [id]
  }
  id
}

///|
/// Resolve an original CST reference while the matcher descends the source.
pub fn SourceIndex::node_id(
  self : SourceIndex,
  node : @untyped_cst.CstNode,
) -> NodeId {
  if self.node_buckets.get(node.source_span) is Some(bucket) {
    for id in bucket {
      if physical_equal(self.nodes[id].node, node) {
        return id
      }
    }
  }
  abort("source cursor does not belong to this index")
}

///|
pub fn SourceIndex::node(
  self : SourceIndex,
  id : NodeId,
) -> @untyped_cst.CstNode {
  self.nodes[id].node
}

///|
fn SourceIndex::raw(self : SourceIndex, id : NodeId, label : String) -> NodeId? {
  for (name, child) in self.nodes[id].children {
    if name == Some(label) {
      return Some(child)
    }
  }
  None
}

///|
fn SourceIndex::raw_all(
  self : SourceIndex,
  id : NodeId,
  label : String,
) -> Array[NodeId] {
  self.nodes[id].children.filter_map(entry => {
    if entry.0 == Some(label) {
      Some(entry.1)
    } else {
      None
    }
  })
}

///|
fn SourceIndex::semantic_child(
  self : SourceIndex,
  id : NodeId,
  label : String,
) -> NodeId? {
  child(self.node(id), label).map(node => self.node_id(node))
}

///|
fn SourceIndex::intern_region(self : SourceIndex, key : RegionKey) -> RegionId {
  if self.region_ids.get(key) is Some(id) {
    return id
  }
  let id = self.regions.length()
  self.regions.push(key)
  self.region_ids[key] = id
  id
}

///|
pub fn SourceIndex::direct(self : SourceIndex, id : NodeId) -> RegionId {
  self.intern_region(Node(id))
}

///|
fn SourceIndex::slice(
  self : SourceIndex,
  list : Int,
  start : Int,
  end : Int,
) -> RegionId {
  self.intern_region(Slice(list, start, end))
}

///|
/// Target conversion is determined by the source's role, including function bodies.
pub fn SourceIndex::target(self : SourceIndex, id : NodeId) -> RegionId {
  let node = self.nodes[id]
  if node.node.kind is @untyped_cst.Expression || node.function_body {
    if node.sequence is Some(list) {
      return self.slice(list, 0, self.sequences[list].nodes.length())
    }
  }
  self.direct(id)
}

///|
/// The exact tail selected by a continuation matcher, including an empty tail.
pub fn SourceIndex::continuation(
  self : SourceIndex,
  header : NodeId,
  length : Int,
) -> RegionId {
  let (list, start) = self.nodes[header].statement.unwrap()
  self.slice(list, start + 1, start + length)
}

///|
pub fn SourceIndex::candidate(
  self : SourceIndex,
  region : RegionId,
) -> ExprMatchCandidate {
  match self.regions[region] {
    Node(id) => Direct(self.node(id))
    Slice(list, start, end) => Sequence(self.sequences[list].values[start:end])
  }
}

///|
pub fn SourceIndex::scope(self : SourceIndex, region : RegionId) -> ScopeId {
  self.ensure_scopes()
  match self.regions[region] {
    Node(id) => self.nodes[id].scope
    Slice(list, start, _) => self.sequences[list].scopes[start]
  }
}

///|
pub fn SourceIndex::step(self : SourceIndex, cursor : CursorId) -> SourceStep {
  self.steps[cursor]
}

///|
fn SourceIndex::intern_step(self : SourceIndex, step : SourceStep) -> CursorId {
  if self.step_ids.get(step) is Some(id) {
    return id
  }
  let id = self.steps.length()
  self.steps.push(step)
  self.step_ids[step] = id
  id
}

///|
pub fn SourceIndex::visit(
  self : SourceIndex,
  region : RegionId,
  next? : CursorId = 0,
) -> CursorId {
  self.intern_step(Visit(region, next))
}

///|
fn SourceIndex::concat(
  self : SourceIndex,
  left : CursorId,
  right : CursorId,
) -> CursorId {
  if left == 0 {
    right
  } else if right == 0 {
    left
  } else {
    self.intern_step(Concat(left, right))
  }
}

///|
pub fn SourceIndex::state_count(self : SourceIndex) -> Int {
  self.regions.length() + self.steps.length()
}

///|
pub fn SourceIndex::scan(self : SourceIndex, region : RegionId) -> CursorId {
  self.intern_step(Scan(region))
}

///|
fn SourceIndex::finish(self : SourceIndex, cursor : CursorId) -> CursorId {
  if cursor == 0 {
    0
  } else {
    self.intern_step(Finish(cursor))
  }
}
