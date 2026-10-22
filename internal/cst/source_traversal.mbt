///|
pub fn SourceIndex::roots(self : SourceIndex) -> CursorId {
  self.node_roots(0)
}

///|
fn SourceIndex::node_roots(self : SourceIndex, id : NodeId) -> CursorId {
  if self.root_cursors.get(id) is Some(cursor) {
    return cursor
  }
  let regions : Array[RegionId] = []
  ignore(
    visit_candidate_roots(IndexedTraversal(self), self.node(id), fn(
      candidate,
      position,
    ) {
      regions.push(self.candidate_region(candidate, position))
      NodeVisitPrune
    }),
  )
  let cursor = self.regions_cursor(regions)
  self.root_cursors[id] = cursor
  cursor
}

///|
fn SourceIndex::candidate_region(
  self : SourceIndex,
  candidate : ExprMatchCandidate,
  position : SequencePosition?,
) -> RegionId {
  match candidate {
    Direct(node) => self.direct(self.node_id(node))
    Sequence(values) =>
      if position is Some(position) {
        self.slice(
          position.list,
          position.start,
          position.start + values.length(),
        )
      } else {
        abort("indexed sequence candidate has no source position")
      }
  }
}

///|
fn SourceIndex::regions_cursor(
  self : SourceIndex,
  regions : Array[RegionId],
) -> CursorId {
  let mut cursor = 0
  for region in regions.rev_iter() {
    cursor = self.visit(region, next=cursor)
  }
  cursor
}

///|
pub fn SourceIndex::children(self : SourceIndex, region : RegionId) -> CursorId {
  if self.child_cursors.get(region) is Some(cursor) {
    return cursor
  }
  let position = match self.regions[region] {
    Node(_) => None
    Slice(list, start, _) => Some({ list, start, })
  }
  let regions : Array[RegionId] = []
  ignore(
    visit_candidate_children(
      IndexedTraversal(self),
      self.candidate(region),
      position,
      fn(candidate, position) {
        regions.push(self.candidate_region(candidate, position))
        NodeVisitPrune
      },
    ),
  )
  let cursor = self.regions_cursor(regions)
  self.child_cursors[region] = cursor
  cursor
}
