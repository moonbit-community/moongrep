///|
pub fn Node::normalized_long_ident(self : Node) -> String? {
  match self.kind {
    LongIdent_Ident => normalize_leaf_string_child(self, "value")
    LongIdent_Dot =>
      match
        (
          normalize_leaf_string_child(self, "pkg"),
          normalize_leaf_string_child(self, "id"),
        ) {
        (Some(pkg), Some(id)) => Some("@\{pkg}.\{id}")
        _ => None
      }
    _ => None
  }
}

///|
pub fn Node::normalized_var_name(self : Node) -> String? {
  guard self.kind == Var else { return None }
  guard normalize_child(self, "name") is Some(name) else { return None }
  name.normalized_long_ident()
}

///|
pub fn Node::normalized_binder_name(self : Node) -> String? {
  guard self.kind == Binder else { return None }
  normalize_leaf_string_child(self, "name")
}

///|
pub fn Node::normalized_label_name(self : Node) -> String? {
  guard self.kind == Label else { return None }
  normalize_leaf_string_child(self, "name")
}

///|
pub fn Node::normalized_expr_identifier_name(self : Node) -> String? {
  guard self.kind == Expr_Ident else { return None }
  guard normalize_child(self, "id") is Some(var_node) else { return None }
  var_node.normalized_var_name()
}

///|
pub fn Node::normalized_pattern_identifier_name(self : Node) -> String? {
  guard self.kind == Pattern_Var else { return None }
  guard normalize_first_child(self) is Some(binder) else { return None }
  binder.normalized_binder_name()
}

///|
fn normalize_child(node : Node, name : String) -> Node? {
  for entry in node.children {
    let (child_name, value) = entry
    if child_name == Some(name) {
      return Some(value)
    }
  }
  None
}

///|
fn normalize_leaf_string(node : Node) -> String? {
  match node.kind {
    Leaf(PString(value)) => Some(value)
    _ => None
  }
}

///|
fn normalize_leaf_string_child(node : Node, name : String) -> String? {
  if normalize_child(node, name) is Some(value) {
    normalize_leaf_string(value)
  } else {
    None
  }
}

///|
fn normalize_first_child(node : Node) -> Node? {
  if node.children.length() == 0 {
    None
  } else {
    let (_, value) = node.children[0]
    Some(value)
  }
}
