///|
fn count_supported_name_in_node(
  node : @untyped_cst.CstNode,
  name : String,
) -> Int {
  match node.kind {
    @untyped_cst.Expr_Ident =>
      if @cst.normalized_expr_identifier_name(node) == Some(name) {
        1
      } else {
        0
      }
    @untyped_cst.Pattern_Var =>
      if @cst.normalized_pattern_identifier_name(node) == Some(name) {
        1
      } else {
        0
      }
    _ =>
      if @cst.normalized_name(node) is Some(found) {
        if found == name {
          1
        } else {
          0
        }
      } else {
        count_supported_name_in_node_children(node, name)
      }
  }
}

///|
fn count_supported_name_in_node_children(
  node : @untyped_cst.CstNode,
  name : String,
) -> Int {
  let mut total = 0
  for entry in @cst.semantic_children(node) {
    let (_, child) = entry
    total += count_supported_name_in_node(child, name)
  }
  total
}
