///|
fn inside_target_match_candidate(
  context : @cst.ExprMatchCandidate,
  target : @bound_value_model.BoundValue,
) -> @cst.ExprMatchCandidate {
  match target {
    Single(target) =>
      if target.kind is @untyped_cst.Expression {
        @cst.Sequence(@cst.expression_nodes(target))
      } else if target.kind is @untyped_cst.Expr_Block &&
        match_candidate_contains_function_body_target(context, target) {
        @cst.Sequence(@cst.sequence_items(target))
      } else {
        @cst.Direct(target)
      }
    Multiple(targets) => @cst.Sequence(targets)
  }
}

///|
fn match_candidate_contains_function_body_target(
  context : @cst.ExprMatchCandidate,
  target : @untyped_cst.CstNode,
) -> Bool {
  match context {
    @cst.Direct(node) => node_contains_function_body_target(node, target)
    @cst.Sequence(items) => {
      for item in items {
        if node_contains_function_body_target(item, target) {
          return true
        }
      }
      false
    }
  }
}

///|
fn node_contains_function_body_target(
  node : @untyped_cst.CstNode,
  target : @untyped_cst.CstNode,
) -> Bool {
  let body = match node.kind {
    @untyped_cst.Impl_Function
    | @untyped_cst.Impl_Test
    | @untyped_cst.Expr_Function
    | @untyped_cst.Expr_LetFn
    | @untyped_cst.Binding_LetRec => @cst.raw_child(node, "body")
    @untyped_cst.Impl_ImplMethod =>
      @cst.raw_child(node, "method").bind(method_node => {
        @cst.raw_child(method_node, "body")
      })
    _ => None
  }
  if body is Some(found) && same_cst_span(found, target) {
    return true
  }
  for entry in node.children {
    if node_contains_function_body_target(entry.1, target) {
      return true
    }
  }
  false
}

///|
fn same_cst_span(
  left : @untyped_cst.CstNode,
  right : @untyped_cst.CstNode,
) -> Bool {
  left.source_span.0 == right.source_span.0 &&
  left.source_span.1 == right.source_span.1 &&
  left.loc.start.fname == right.loc.start.fname
}
