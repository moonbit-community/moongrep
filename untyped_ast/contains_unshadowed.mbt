///|
/// Returns whether this node contains an expression identifier named `id` that
/// is not shadowed by a local binding between this node and that identifier.
pub fn Node::contains_unshadowed(self : Node, id~ : String) -> Bool {
  let mut found = false
  visit_node_scoped_expr_roots(self, fn(scoped) {
    if scoped.shadowed_names.contains_name(id) {
      NodeVisitPrune
    } else if scoped.expr.normalized_expr_identifier_name() == Some(id) {
      found = true
      NodeVisitReturn
    } else {
      NodeVisitContinue
    }
  })
  found
}

///|
fn Array::contains_name(self : Array[String], id : String) -> Bool {
  for name in self {
    if name == id {
      return true
    }
  }
  false
}
