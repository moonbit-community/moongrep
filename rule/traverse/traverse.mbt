///|
pub fn count_supported_name_in_node(
  node : @untyped_ast.Node,
  name : String,
) -> Int {
  match node.kind {
    Expr_Ident =>
      if node.normalized_expr_identifier_name() == Some(name) {
        1
      } else {
        0
      }
    Pattern_Var =>
      if node.normalized_pattern_identifier_name() == Some(name) {
        1
      } else {
        0
      }
    Var => if node.normalized_var_name() == Some(name) { 1 } else { 0 }
    Binder => if node.normalized_binder_name() == Some(name) { 1 } else { 0 }
    Label => if node.normalized_label_name() == Some(name) { 1 } else { 0 }
    _ => count_supported_name_in_node_children(node, name)
  }
}

///|
fn count_supported_name_in_node_children(
  node : @untyped_ast.Node,
  name : String,
) -> Int {
  let mut total = 0
  for entry in node.children {
    let (_, child) = entry
    total += count_supported_name_in_node(child, name)
  }
  total
}
