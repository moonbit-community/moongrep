///|
priv struct SequencePosition {
  list : Int
  start : Int
}

///|
priv enum CandidateTraversalContext {
  DirectTraversal
  IndexedTraversal(SourceIndex)
}

///|
fn SequencePosition::advance(
  self : SequencePosition,
  offset : Int,
) -> SequencePosition {
  { list: self.list, start: self.start + offset, }
}

///|
fn CandidateTraversalContext::sequence(
  self : CandidateTraversalContext,
  node : @untyped_cst.CstNode,
) -> (ArrayView[@untyped_cst.CstNode], SequencePosition?) {
  match self {
    DirectTraversal => {
      let values = if node.kind is Expression {
        expression_nodes(node)
      } else {
        sequence_items(node)
      }
      (values[:], None)
    }
    IndexedTraversal(index) => {
      let id = index.node_id(node)
      guard index.nodes[id].sequence is Some(list) else {
        abort("indexed sequence candidate has no source sequence")
      }
      (index.sequences[list].values[:], Some({ list, start: 0, }))
    }
  }
}

///|
/// Tokens, documentation, and location metadata cannot participate in source
/// traversal. Interpolation wrappers remain indexed so their expression child
/// can be reached from a source root.
fn is_indexable_cst_child(
  label : String?,
  child : @untyped_cst.CstNode,
) -> Bool {
  if label == Some("doc") ||
    is_location_label(label) ||
    is_pure_punctuation_kind(child.kind) {
    return false
  }
  !is_syntax_kind(child.kind) || child.kind is Syntax_Interpolation
}

///|
/// Visit expression-matching candidates below a source root without building
/// a source index. `Continue` descends into the candidate, `Prune` skips only
/// its descendants, and `Return` stops the whole traversal.
pub fn visit_expr_match_candidate_roots(
  root : @untyped_cst.CstNode,
  visitor : (ExprMatchCandidate) -> NodeVisitAction,
) -> Unit {
  ignore(
    visit_candidate_roots(DirectTraversal, root, fn(candidate, _) {
      visitor(candidate)
    }),
  )
}

///|
/// Visit the immediate expression-matching children of `candidate`.
///
/// Each child is pruned after `visitor` returns. Callers that need different
/// state in each subtree can recurse with that state from the callback.
pub fn visit_expr_match_candidate_children(
  candidate : ExprMatchCandidate,
  visitor : (ExprMatchCandidate) -> Unit,
) -> Unit {
  ignore(
    visit_candidate_children(DirectTraversal, candidate, None, fn(child, _) {
      visitor(child)
      NodeVisitPrune
    }),
  )
}

///|
fn visit_candidate_roots(
  context : CandidateTraversalContext,
  node : @untyped_cst.CstNode,
  visitor : (ExprMatchCandidate, SequencePosition?) -> NodeVisitAction,
) -> NodeVisitAction {
  if node.kind.is_expr() || node.kind is Expression {
    return visit_candidate_from_node(context, node, visitor)
  }
  match node.kind {
    Impl_Function | Impl_Test =>
      visit_function_body_candidate(context, node, visitor)
    Impl_ImplMethod =>
      if raw_child(node, "method") is Some(method_node) {
        visit_function_body_candidate(context, method_node, visitor)
      } else {
        NodeVisitContinue
      }
    Impl_Let | Impl_Const =>
      visit_raw_named_candidate_roots(context, node, "expr", visitor)
    _ => {
      for (label, child) in node.children {
        if !is_indexable_cst_child(label, child) {
          continue
        }
        if visit_candidate_roots(context, child, visitor) is NodeVisitReturn {
          return NodeVisitReturn
        }
      }
      NodeVisitContinue
    }
  }
}

///|
fn visit_raw_named_candidate_roots(
  context : CandidateTraversalContext,
  node : @untyped_cst.CstNode,
  label : String,
  visitor : (ExprMatchCandidate, SequencePosition?) -> NodeVisitAction,
) -> NodeVisitAction {
  if raw_child(node, label) is Some(child) {
    visit_candidate_roots(context, child, visitor)
  } else {
    NodeVisitContinue
  }
}

///|
fn visit_function_body_candidate(
  context : CandidateTraversalContext,
  node : @untyped_cst.CstNode,
  visitor : (ExprMatchCandidate, SequencePosition?) -> NodeVisitAction,
) -> NodeVisitAction {
  guard raw_child(node, "body") is Some(body) else { return NodeVisitContinue }
  if body.kind is Expr_Block {
    let (expressions, position) = context.sequence(body)
    visit_candidate(context, Sequence(expressions), position, visitor)
  } else {
    visit_candidate_from_node(context, body, visitor)
  }
}

///|
fn visit_candidate_from_node(
  context : CandidateTraversalContext,
  node : @untyped_cst.CstNode,
  visitor : (ExprMatchCandidate, SequencePosition?) -> NodeVisitAction,
) -> NodeVisitAction {
  if node.kind is Expression {
    let (expressions, position) = context.sequence(node)
    visit_candidate(context, Sequence(expressions), position, visitor)
  } else if node.kind.is_expr() {
    visit_candidate(context, Direct(node), None, visitor)
  } else {
    visit_candidate_roots(context, node, visitor)
  }
}

///|
fn visit_candidate(
  context : CandidateTraversalContext,
  candidate : ExprMatchCandidate,
  position : SequencePosition?,
  visitor : (ExprMatchCandidate, SequencePosition?) -> NodeVisitAction,
) -> NodeVisitAction {
  match visitor(candidate, position) {
    NodeVisitPrune => NodeVisitPrune
    NodeVisitReturn => NodeVisitReturn
    NodeVisitContinue =>
      visit_candidate_children(context, candidate, position, visitor)
  }
}

///|
fn visit_candidate_children(
  context : CandidateTraversalContext,
  candidate : ExprMatchCandidate,
  position : SequencePosition?,
  visitor : (ExprMatchCandidate, SequencePosition?) -> NodeVisitAction,
) -> NodeVisitAction {
  match candidate {
    Sequence(expressions) =>
      visit_sequence_children(context, expressions, position, visitor)
    Direct(expr) => visit_direct_candidate_children(context, expr, visitor)
  }
}

///|
fn visit_direct_candidate_children(
  context : CandidateTraversalContext,
  expr : @untyped_cst.CstNode,
  visitor : (ExprMatchCandidate, SequencePosition?) -> NodeVisitAction,
) -> NodeVisitAction {
  match expr.kind {
    Expr_Block | Expr_Sequence => {
      let (expressions, position) = context.sequence(expr)
      visit_candidate(context, Sequence(expressions), position, visitor)
    }
    Expr_Function | Expr_LetFn =>
      visit_function_body_candidate(context, expr, visitor)
    Expr_LetAnd => {
      for binding in raw_children(expr, "binding") {
        if visit_function_body_candidate(context, binding, visitor)
          is NodeVisitReturn {
          return NodeVisitReturn
        }
        if visit_raw_named_candidate_roots(context, binding, "expr", visitor)
          is NodeVisitReturn {
          return NodeVisitReturn
        }
      }
      NodeVisitContinue
    }
    Expr_Infix if operator_name(expr) == Some("&&") => {
      if visit_named_candidate_descendants(context, expr, "lhs", visitor)
        is NodeVisitReturn {
        return NodeVisitReturn
      }
      visit_named_candidate_descendants(context, expr, "rhs", visitor)
    }
    Expr_If | Expr_While =>
      visit_named_candidate_list(
        context,
        expr,
        ["cond", "body", "else"],
        visitor,
      )
    Expr_For
    | Expr_ForEach
    | Expr_ListComprehension => {
      if raw_child(expr, "pattern") is Some(_) &&
        visit_named_candidate_descendants(context, expr, "expr", visitor)
        is NodeVisitReturn {
        return NodeVisitReturn
      }
      if visit_binding_candidates(context, expr, "init", visitor)
        is NodeVisitReturn {
        return NodeVisitReturn
      }
      if raw_child(expr, "pattern") is None &&
        visit_named_candidate_descendants(context, expr, "cond", visitor)
        is NodeVisitReturn {
        return NodeVisitReturn
      }
      if visit_binding_candidates(context, expr, "continue", visitor)
        is NodeVisitReturn {
        return NodeVisitReturn
      }
      if expr.kind is Expr_ListComprehension &&
        visit_named_candidate_descendants(context, expr, "guard", visitor)
        is NodeVisitReturn {
        return NodeVisitReturn
      }
      if visit_named_candidate_descendants(context, expr, "body", visitor)
        is NodeVisitReturn {
        return NodeVisitReturn
      }
      if !(expr.kind is Expr_ListComprehension) {
        if visit_named_candidate_descendants(context, expr, "else", visitor)
          is NodeVisitReturn {
          return NodeVisitReturn
        }
        return visit_named_candidate_descendants(
          context, expr, "where", visitor,
        )
      }
      NodeVisitContinue
    }
    Expr_Match
    | Expr_LexMatch
    | Expr_LexScan => {
      if visit_named_candidate_descendants(context, expr, "expr", visitor)
        is NodeVisitReturn {
        return NodeVisitReturn
      }
      visit_case_candidates(context, expr, "case", visitor)
    }
    Expr_Try => {
      if visit_named_candidate_descendants(context, expr, "body", visitor)
        is NodeVisitReturn {
        return NodeVisitReturn
      }
      if visit_case_candidates(context, expr, "case", visitor)
        is NodeVisitReturn {
        return NodeVisitReturn
      }
      visit_case_candidates(context, expr, "else", visitor)
    }
    Expr_Quantifier =>
      visit_named_candidate_descendants(context, expr, "body", visitor)
    _ => visit_all_candidate_descendants(context, expr, visitor)
  }
}

///|
fn visit_sequence_children(
  context : CandidateTraversalContext,
  expressions : ArrayView[@untyped_cst.CstNode],
  position : SequencePosition?,
  visitor : (ExprMatchCandidate, SequencePosition?) -> NodeVisitAction,
) -> NodeVisitAction {
  for index in 0..<expressions.length() {
    let expr = expressions[index]
    let has_continuation = continuation_owner(expr.kind) &&
      index + 1 < expressions.length()
    if index == 0 && has_continuation {
      if visit_direct_candidate_children(context, expr, visitor)
        is NodeVisitReturn {
        return NodeVisitReturn
      }
    } else if has_continuation {
      if visit_candidate(
          context,
          Sequence(expressions[index:]),
          position.map(current => current.advance(index)),
          visitor,
        )
        is NodeVisitReturn {
        return NodeVisitReturn
      }
      return NodeVisitContinue
    } else if visit_candidate(context, Direct(expr), None, visitor)
      is NodeVisitReturn {
      return NodeVisitReturn
    }
  }
  NodeVisitContinue
}

///|
fn visit_named_candidate_list(
  context : CandidateTraversalContext,
  node : @untyped_cst.CstNode,
  labels : Array[String],
  visitor : (ExprMatchCandidate, SequencePosition?) -> NodeVisitAction,
) -> NodeVisitAction {
  for label in labels {
    if visit_named_candidate_descendants(context, node, label, visitor)
      is NodeVisitReturn {
      return NodeVisitReturn
    }
  }
  NodeVisitContinue
}

///|
fn visit_named_candidate_descendants(
  context : CandidateTraversalContext,
  node : @untyped_cst.CstNode,
  label : String,
  visitor : (ExprMatchCandidate, SequencePosition?) -> NodeVisitAction,
) -> NodeVisitAction {
  if child(node, label) is Some(child) {
    visit_candidate_descendants(context, child, visitor)
  } else {
    NodeVisitContinue
  }
}

///|
fn visit_binding_candidates(
  context : CandidateTraversalContext,
  node : @untyped_cst.CstNode,
  label : String,
  visitor : (ExprMatchCandidate, SequencePosition?) -> NodeVisitAction,
) -> NodeVisitAction {
  guard raw_child(node, label) is Some(list) else { return NodeVisitContinue }
  for binding in raw_children(list, "item") {
    if visit_named_candidate_descendants(context, binding, "expr", visitor)
      is NodeVisitReturn {
      return NodeVisitReturn
    }
  }
  NodeVisitContinue
}

///|
fn visit_case_candidates(
  context : CandidateTraversalContext,
  node : @untyped_cst.CstNode,
  label : String,
  visitor : (ExprMatchCandidate, SequencePosition?) -> NodeVisitAction,
) -> NodeVisitAction {
  for list in raw_children(node, label) {
    if list.kind
      is (Case_MatchCase | Case_LexScanCase) {
      if visit_one_case_candidates(context, list, visitor) is NodeVisitReturn {
        return NodeVisitReturn
      }
    } else {
      for case in raw_children(list, "case") {
        if visit_one_case_candidates(context, case, visitor) is NodeVisitReturn {
          return NodeVisitReturn
        }
      }
    }
  }
  NodeVisitContinue
}

///|
fn visit_one_case_candidates(
  context : CandidateTraversalContext,
  case : @untyped_cst.CstNode,
  visitor : (ExprMatchCandidate, SequencePosition?) -> NodeVisitAction,
) -> NodeVisitAction {
  if visit_named_candidate_descendants(context, case, "cond", visitor)
    is NodeVisitReturn {
    return NodeVisitReturn
  }
  visit_named_candidate_descendants(context, case, "body", visitor)
}

///|
fn visit_candidate_descendants(
  context : CandidateTraversalContext,
  node : @untyped_cst.CstNode,
  visitor : (ExprMatchCandidate, SequencePosition?) -> NodeVisitAction,
) -> NodeVisitAction {
  if node.kind.is_expr() {
    visit_candidate(context, Direct(node), None, visitor)
  } else {
    visit_all_candidate_descendants(context, node, visitor)
  }
}

///|
fn visit_all_candidate_descendants(
  context : CandidateTraversalContext,
  node : @untyped_cst.CstNode,
  visitor : (ExprMatchCandidate, SequencePosition?) -> NodeVisitAction,
) -> NodeVisitAction {
  for (label, child) in node.children {
    if !is_indexable_cst_child(label, child) || is_syntax_kind(child.kind) {
      continue
    }
    if visit_candidate_descendants(context, child, visitor) is NodeVisitReturn {
      return NodeVisitReturn
    }
  }
  NodeVisitContinue
}
