///|
fn node_child(node : @untyped_ast.Node, name : String) -> @untyped_ast.Node? {
  for entry in node.children {
    let (child_name, value) = entry
    if child_name == Some(name) {
      return Some(value)
    }
  }
  None
}

///|
fn node_first_child(node : @untyped_ast.Node) -> @untyped_ast.Node? {
  if node.children.length() == 0 {
    None
  } else {
    let (_, value) = node.children[0]
    Some(value)
  }
}

///|
fn node_items(node : @untyped_ast.Node) -> Array[@untyped_ast.Node] {
  let items : Array[@untyped_ast.Node] = []
  for entry in node.children {
    let (_, value) = entry
    items.push(value)
  }
  items
}

///|
fn node_child_items(
  node : @untyped_ast.Node,
  name : String,
) -> Array[@untyped_ast.Node] {
  if node_child(node, name) is Some(list) {
    node_items(list)
  } else {
    []
  }
}

///|
fn node_optional_child(
  node : @untyped_ast.Node,
  name : String,
) -> @untyped_ast.Node? {
  match node_child(node, name) {
    Some(child) if !node_is_null(child) => Some(child)
    _ => None
  }
}

///|
fn node_is_null(node : @untyped_ast.Node) -> Bool {
  match node.kind {
    Leaf(PNull) => true
    _ => false
  }
}

///|
fn node_leaf_string(node : @untyped_ast.Node) -> String? {
  match node.kind {
    Leaf(PString(value)) => Some(value)
    _ => None
  }
}

///|
fn node_leaf_number_int(node : @untyped_ast.Node) -> Int? {
  match node.kind {
    Leaf(PNumber(value, repr~)) => {
      ignore(repr)
      Some(value.to_int())
    }
    _ => None
  }
}

///|
fn node_binder_name(node : @untyped_ast.Node) -> String? {
  node.normalized_binder_name()
}

///|
fn node_label_name(node : @untyped_ast.Node) -> String? {
  node.normalized_label_name()
}

///|
fn node_var_name(node : @untyped_ast.Node) -> String? {
  node.normalized_var_name()
}

///|
fn node_first_label_name(node : @untyped_ast.Node) -> String? {
  if node_first_child(node) is Some(child) {
    node_label_name(child)
  } else {
    None
  }
}

///|
fn node_optional_items(
  node : @untyped_ast.Node,
  name : String,
) -> Array[@untyped_ast.Node] {
  if node_optional_child(node, name) is Some(list) {
    node_items(list)
  } else {
    []
  }
}
