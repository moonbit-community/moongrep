///|
priv enum TraversalLayer {
  Matching
  Expression
} derive(Eq, Hash)

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
fn SourceIndex::ordinary_children(
  self : SourceIndex,
  region : RegionId,
) -> CursorId {
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
  self.regions_cursor(regions)
}

///|
fn SourceIndex::function_body_cursor(
  self : SourceIndex,
  id : NodeId,
) -> CursorId {
  self
  .raw(id, "body")
  .map(body => {
    if self.node(body).kind.is_expr() ||
      self.node(body).kind is @untyped_cst.Expression {
      self.scan(self.target(body))
    } else {
      self.node_roots(body)
    }
  })
  .unwrap_or(0)
}

///|
fn SourceIndex::join_nodes(
  self : SourceIndex,
  nodes : Array[NodeId],
) -> CursorId {
  let mut cursor = 0
  for node in nodes.rev_iter() {
    cursor = self.concat(self.descendants(node), cursor)
  }
  self.finish(cursor)
}

///|
fn SourceIndex::descendants(self : SourceIndex, id : NodeId) -> CursorId {
  if self.descendant_cursors.get(id) is Some(cursor) {
    return cursor
  }
  let cursor = if self.node(id).kind.is_expr() {
    self.expression_visit(id)
  } else {
    self.join_nodes(
      self.nodes[id].children.filter_map(entry => {
        if is_syntax_kind(self.node(entry.1).kind) {
          None
        } else {
          Some(entry.1)
        }
      }),
    )
  }
  self.descendant_cursors[id] = cursor
  cursor
}

///|
fn SourceIndex::named_cursor(
  self : SourceIndex,
  id : NodeId,
  label : String,
) -> CursorId {
  self
  .semantic_child(id, label)
  .map(child => self.descendants(child))
  .unwrap_or(0)
}

///|
fn SourceIndex::binding_cursor(
  self : SourceIndex,
  id : NodeId,
  label : String,
) -> CursorId {
  let mut cursor = 0
  if self.raw(id, label) is Some(list) {
    let bindings = self.raw_all(list, "item")
    for binding in bindings.rev_iter() {
      cursor = self.concat(self.named_cursor(binding, "expr"), cursor)
    }
  }
  self.finish(cursor)
}

///|
fn SourceIndex::case_cursor(
  self : SourceIndex,
  id : NodeId,
  label : String,
) -> CursorId {
  let cases : Array[NodeId] = []
  for list in self.raw_all(id, label) {
    if self.node(list).kind
      is (@untyped_cst.Case_MatchCase | @untyped_cst.Case_LexScanCase) {
      cases.push(list)
    } else {
      cases.append(self.raw_all(list, "case"))
    }
  }
  let mut cursor = 0
  for case in cases.rev_iter() {
    cursor = self.concat(self.named_cursor(case, "body"), cursor)
    cursor = self.concat(self.named_cursor(case, "cond"), cursor)
  }
  self.finish(cursor)
}

///|
pub fn SourceIndex::children(
  self : SourceIndex,
  region : RegionId,
  full? : Bool = false,
) -> CursorId {
  if self.child_cursors.get((region, full)) is Some(cursor) {
    return cursor
  }
  let cursor = if full {
    let cursor = match self.regions[region] {
      Node(id) => self.direct_children(id, Matching)
      Slice(list, start, end) =>
        if start == end {
          0
        } else {
          let first = self.sequences[list].nodes[start]
          if continuation_owner(self.node(first).kind) && start + 1 < end {
            self.concat(
              self.direct_children(first, Matching),
              self.sequence_cursor(list, start + 1, end),
            )
          } else {
            self.sequence_cursor(list, start, end)
          }
        }
    }
    if self.regions[region] is Slice(_, _, _) {
      self.finish(cursor)
    } else {
      cursor
    }
  } else {
    self.ordinary_children(region)
  }
  self.child_cursors[(region, full)] = cursor
  cursor
}

///|
// A sequence entry after the first either exposes its continuation candidate
// or proceeds to the shared suffix. No suffix array is copied.
fn SourceIndex::sequence_cursor(
  self : SourceIndex,
  list : Int,
  start : Int,
  end : Int,
) -> CursorId {
  if self.sequence_cursors.get((list, start, end)) is Some(cursor) {
    return cursor
  }
  let mut cursor = 0
  for i = end - 1; i >= start; i = i - 1 {
    if self.sequence_cursors.get((list, i, end)) is Some(found) {
      cursor = found
      continue
    }
    let id = self.sequences[list].nodes[i]
    cursor = if continuation_owner(self.node(id).kind) && i + 1 < end {
      self.scan(self.slice(list, i, end))
    } else {
      self.concat(self.scan(self.direct(id)), cursor)
    }
    self.sequence_cursors[(list, i, end)] = cursor
  }
  cursor
}

///|
fn SourceIndex::direct_children(
  self : SourceIndex,
  id : NodeId,
  layer : TraversalLayer,
) -> CursorId {
  if self.direct_cursors.get((id, layer)) is Some(cursor) {
    return cursor
  }
  let node = self.node(id)
  let pieces : Array[CursorId] = []
  match node.kind {
    @untyped_cst.Expr_Block | @untyped_cst.Expr_Sequence =>
      if self.nodes[id].sequence is Some(list) {
        pieces.push(
          if layer == Expression {
            self.join_nodes(self.sequences[list].nodes)
          } else {
            self.scan(self.slice(list, 0, self.sequences[list].nodes.length()))
          },
        )
      }
    @untyped_cst.Expr_Function | @untyped_cst.Expr_LetFn =>
      pieces.push(
        if layer == Expression {
          self.named_cursor(id, "body")
        } else {
          self.function_body_cursor(id)
        },
      )
    @untyped_cst.Expr_LetAnd =>
      for binding in self.raw_all(id, "binding") {
        pieces.push(
          if layer == Expression {
            self.named_cursor(binding, "body")
          } else {
            self.function_body_cursor(binding)
          },
        )
        pieces.push(
          self
          .raw(binding, "expr")
          .map(expr => {
            if layer == Expression {
              self.descendants(expr)
            } else {
              self.scan(self.target(expr))
            }
          })
          .unwrap_or(0),
        )
      }
    @untyped_cst.Expr_Infix if operator_name(node) == Some("&&") => {
      pieces.push(self.named_cursor(id, "lhs"))
      pieces.push(self.named_cursor(id, "rhs"))
    }
    @untyped_cst.Expr_If | @untyped_cst.Expr_While =>
      for label in ["cond", "body", "else"] {
        pieces.push(self.named_cursor(id, label))
      }
    @untyped_cst.Expr_For
    | @untyped_cst.Expr_ForEach
    | @untyped_cst.Expr_ListComprehension => {
      if self.raw(id, "pattern") is Some(_) {
        pieces.push(self.named_cursor(id, "expr"))
      }
      pieces.push(self.binding_cursor(id, "init"))
      if self.raw(id, "pattern") is None {
        pieces.push(self.named_cursor(id, "cond"))
      }
      pieces.push(self.binding_cursor(id, "continue"))
      if node.kind is @untyped_cst.Expr_ListComprehension {
        pieces.push(self.named_cursor(id, "guard"))
      }
      pieces.push(self.named_cursor(id, "body"))
      if !(node.kind is @untyped_cst.Expr_ListComprehension) {
        pieces.push(self.named_cursor(id, "else"))
        pieces.push(self.named_cursor(id, "where"))
      }
    }
    @untyped_cst.Expr_Match
    | @untyped_cst.Expr_LexMatch
    | @untyped_cst.Expr_LexScan => {
      pieces.push(self.named_cursor(id, "expr"))
      pieces.push(self.case_cursor(id, "case"))
    }
    @untyped_cst.Expr_Try => {
      pieces.push(self.named_cursor(id, "body"))
      pieces.push(self.case_cursor(id, "case"))
      pieces.push(self.case_cursor(id, "else"))
    }
    @untyped_cst.Expr_Quantifier => pieces.push(self.named_cursor(id, "body"))
    _ =>
      pieces.push(
        self.join_nodes(
          self.nodes[id].children.filter_map(entry => {
            if is_syntax_kind(self.node(entry.1).kind) {
              None
            } else {
              Some(entry.1)
            }
          }),
        ),
      )
  }
  let mut cursor = pieces.last().unwrap_or(0)
  for i = pieces.length() - 2; i >= 0; i = i - 1 {
    cursor = if cursor == 0 {
      self.finish(pieces[i])
    } else {
      self.concat(pieces[i], cursor)
    }
  }
  if node.kind is @untyped_cst.Expr_LetAnd {
    cursor = self.finish(cursor)
  }
  self.direct_cursors[(id, layer)] = cursor
  cursor
}

///|
// The old full visitor resumes the expression visitor after a matching visitor
// returns Continue. Represent that control edge once, so repeated publication
// and the additional candidates keep their original order without rematching.
fn SourceIndex::expression_visit(self : SourceIndex, id : NodeId) -> CursorId {
  let first = self.scan(self.direct(id))
  let second = self.direct_children(id, Expression)
  self.intern_step(AfterContinue(first, second))
}
