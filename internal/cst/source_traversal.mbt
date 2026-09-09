///|
priv enum TraversalLayer {
  Ordinary
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
  let node = self.node(id)
  let cursor = if node.kind.is_expr() || node.kind is @untyped_cst.Expression {
    self.visit(
      if node.kind is @untyped_cst.Expression {
        self.target(id)
      } else {
        self.direct(id)
      },
    )
  } else {
    match node.kind {
      @untyped_cst.Impl_Function | @untyped_cst.Impl_Test =>
        self.function_body_cursor(id)
      @untyped_cst.Impl_ImplMethod =>
        self
        .raw(id, "method")
        .map(method_node => self.function_body_cursor(method_node))
        .unwrap_or(0)
      @untyped_cst.Impl_Let | @untyped_cst.Impl_Const =>
        self.raw(id, "expr").map(expr => self.node_roots(expr)).unwrap_or(0)
      _ =>
        self.join_nodes(
          self.nodes[id].children.map(entry => entry.1),
          roots=true,
        )
    }
  }
  self.root_cursors[id] = cursor
  cursor
}

///|
fn SourceIndex::function_body_cursor(
  self : SourceIndex,
  id : NodeId,
  full? : Bool = false,
) -> CursorId {
  self
  .raw(id, "body")
  .map(body => {
    if self.node(body).kind.is_expr() ||
      self.node(body).kind is @untyped_cst.Expression {
      if full {
        self.scan(self.target(body))
      } else {
        self.visit(self.target(body))
      }
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
  roots? : Bool = false,
  full? : Bool = false,
) -> CursorId {
  let mut cursor = 0
  for i = nodes.length() - 1; i >= 0; i = i - 1 {
    let child = if roots {
      self.node_roots(nodes[i])
    } else {
      self.descendants(nodes[i], full~)
    }
    cursor = self.concat(child, cursor)
  }
  if full {
    self.finish(cursor)
  } else {
    cursor
  }
}

///|
fn SourceIndex::descendants(
  self : SourceIndex,
  id : NodeId,
  full? : Bool = false,
) -> CursorId {
  if self.descendant_cursors.get((id, full)) is Some(cursor) {
    return cursor
  }
  let cursor = if self.node(id).kind.is_expr() {
    if full {
      self.expression_visit(id)
    } else {
      self.visit(self.direct(id))
    }
  } else {
    self.join_nodes(
      self.nodes[id].children.filter_map(entry => {
        if is_syntax_kind(self.node(entry.1).kind) {
          None
        } else {
          Some(entry.1)
        }
      }),
      full~,
    )
  }
  self.descendant_cursors[(id, full)] = cursor
  cursor
}

///|
fn SourceIndex::named_cursor(
  self : SourceIndex,
  id : NodeId,
  label : String,
  full? : Bool = false,
) -> CursorId {
  self
  .semantic_child(id, label)
  .map(child => self.descendants(child, full~))
  .unwrap_or(0)
}

///|
fn SourceIndex::binding_cursor(
  self : SourceIndex,
  id : NodeId,
  label : String,
  full? : Bool = false,
) -> CursorId {
  let mut cursor = 0
  if self.raw(id, label) is Some(list) {
    let bindings = self.raw_all(list, "item")
    for i = bindings.length() - 1; i >= 0; i = i - 1 {
      cursor = self.concat(
        self.named_cursor(bindings[i], "expr", full~),
        cursor,
      )
    }
  }
  if full {
    self.finish(cursor)
  } else {
    cursor
  }
}

///|
fn SourceIndex::case_cursor(
  self : SourceIndex,
  id : NodeId,
  label : String,
  full? : Bool = false,
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
  for i = cases.length() - 1; i >= 0; i = i - 1 {
    cursor = self.concat(self.named_cursor(cases[i], "body", full~), cursor)
    cursor = self.concat(self.named_cursor(cases[i], "cond", full~), cursor)
  }
  if full {
    self.finish(cursor)
  } else {
    cursor
  }
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
  let cursor = match self.regions[region] {
    Node(id) =>
      self.direct_children(id, layer=if full { Matching } else { Ordinary })
    Slice(list, start, end) =>
      if start == end {
        0
      } else {
        let first = self.sequences[list].nodes[start]
        if continuation_owner(self.node(first).kind) && start + 1 < end {
          self.concat(
            self.direct_children(
              first,
              layer=if full { Matching } else { Ordinary },
            ),
            self.sequence_cursor(list, start + 1, end, full~),
          )
        } else {
          self.sequence_cursor(list, start, end, full~)
        }
      }
  }
  let cursor = if full && self.regions[region] is Slice(_, _, _) {
    self.finish(cursor)
  } else {
    cursor
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
  full? : Bool = false,
) -> CursorId {
  if self.sequence_cursors.get((list, start, end, full)) is Some(cursor) {
    return cursor
  }
  let mut cursor = 0
  for i = end - 1; i >= start; i = i - 1 {
    if self.sequence_cursors.get((list, i, end, full)) is Some(found) {
      cursor = found
      continue
    }
    let id = self.sequences[list].nodes[i]
    cursor = if continuation_owner(self.node(id).kind) && i + 1 < end {
      if full {
        self.scan(self.slice(list, i, end))
      } else {
        self.visit(self.slice(list, i, end))
      }
    } else if full {
      self.concat(self.scan(self.direct(id)), cursor)
    } else {
      self.visit(self.direct(id), next=cursor)
    }
    self.sequence_cursors[(list, i, end, full)] = cursor
  }
  cursor
}

///|
fn SourceIndex::direct_children(
  self : SourceIndex,
  id : NodeId,
  layer? : TraversalLayer = Ordinary,
) -> CursorId {
  if self.direct_cursors.get((id, layer)) is Some(cursor) {
    return cursor
  }
  let full = layer != Ordinary
  let node = self.node(id)
  let pieces : Array[CursorId] = []
  match node.kind {
    @untyped_cst.Expr_Block | @untyped_cst.Expr_Sequence =>
      if self.nodes[id].sequence is Some(list) {
        pieces.push(
          if layer == Expression {
            self.join_nodes(self.sequences[list].nodes, full=true)
          } else if full {
            self.scan(self.slice(list, 0, self.sequences[list].nodes.length()))
          } else {
            self.visit(self.slice(list, 0, self.sequences[list].nodes.length()))
          },
        )
      }
    @untyped_cst.Expr_Function | @untyped_cst.Expr_LetFn =>
      pieces.push(
        if layer == Expression {
          self.named_cursor(id, "body", full=true)
        } else {
          self.function_body_cursor(id, full~)
        },
      )
    @untyped_cst.Expr_LetAnd =>
      for binding in self.raw_all(id, "binding") {
        pieces.push(
          if layer == Expression {
            self.named_cursor(binding, "body", full=true)
          } else {
            self.function_body_cursor(binding, full~)
          },
        )
        pieces.push(
          self
          .raw(binding, "expr")
          .map(expr => {
            if full {
              if layer == Expression {
                self.descendants(expr, full=true)
              } else {
                self.scan(self.target(expr))
              }
            } else {
              self.node_roots(expr)
            }
          })
          .unwrap_or(0),
        )
      }
    @untyped_cst.Expr_Infix if operator_name(node) == Some("&&") => {
      pieces.push(self.named_cursor(id, "lhs", full~))
      pieces.push(self.named_cursor(id, "rhs", full~))
    }
    @untyped_cst.Expr_If | @untyped_cst.Expr_While =>
      for label in ["cond", "body", "else"] {
        pieces.push(self.named_cursor(id, label, full~))
      }
    @untyped_cst.Expr_For
    | @untyped_cst.Expr_ForEach
    | @untyped_cst.Expr_ListComprehension => {
      if self.raw(id, "pattern") is Some(_) {
        pieces.push(self.named_cursor(id, "expr", full~))
      }
      pieces.push(self.binding_cursor(id, "init", full~))
      if self.raw(id, "pattern") is None {
        pieces.push(self.named_cursor(id, "cond", full~))
      }
      pieces.push(self.binding_cursor(id, "continue", full~))
      if node.kind is @untyped_cst.Expr_ListComprehension {
        pieces.push(self.named_cursor(id, "guard", full~))
      }
      pieces.push(self.named_cursor(id, "body", full~))
      if !(node.kind is @untyped_cst.Expr_ListComprehension) {
        pieces.push(self.named_cursor(id, "else", full~))
        pieces.push(self.named_cursor(id, "where", full~))
      }
    }
    @untyped_cst.Expr_Match
    | @untyped_cst.Expr_LexMatch
    | @untyped_cst.Expr_LexScan => {
      pieces.push(self.named_cursor(id, "expr", full~))
      pieces.push(self.case_cursor(id, "case", full~))
    }
    @untyped_cst.Expr_Try => {
      pieces.push(self.named_cursor(id, "body", full~))
      pieces.push(self.case_cursor(id, "case", full~))
      pieces.push(self.case_cursor(id, "else", full~))
    }
    @untyped_cst.Expr_Quantifier =>
      pieces.push(self.named_cursor(id, "body", full~))
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
          full~,
        ),
      )
  }
  let mut cursor = pieces.last().unwrap_or(0)
  for i = pieces.length() - 2; i >= 0; i = i - 1 {
    cursor = if full && cursor == 0 {
      self.finish(pieces[i])
    } else {
      self.concat(pieces[i], cursor)
    }
  }
  if full && node.kind is @untyped_cst.Expr_LetAnd {
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
  let second = self.direct_children(id, layer=Expression)
  self.intern_step(AfterContinue(first, second))
}
