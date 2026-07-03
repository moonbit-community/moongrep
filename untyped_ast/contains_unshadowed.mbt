///|
/// Returns whether this node contains an expression identifier named `id` that
/// is not shadowed by a local binding between this node and that identifier.
pub fn Node::contains_unshadowed(self : Node, id~ : String) -> Bool {
  contains_unshadowed_node(self, id, shadowed=false)
}

///|
fn contains_unshadowed_node(node : Node, id : String, shadowed~ : Bool) -> Bool {
  if !shadowed && contains_expr_ident_name(node) == Some(id) {
    return true
  }
  match node.kind {
    Expr_Let => contains_let_unshadowed(node, id, shadowed)
    Expr_LetMut => contains_let_mut_unshadowed(node, id, shadowed)
    Expr_For => contains_for_unshadowed(node, id, shadowed)
    Expr_ForEach => contains_foreach_unshadowed(node, id, shadowed)
    Expr_Match => contains_match_unshadowed(node, id, shadowed)
    Expr_Lexmatch => contains_lexmatch_unshadowed(node, id, shadowed)
    Expr_ListComprehension =>
      contains_list_comprehension_unshadowed(node, id, shadowed)
    Expr_Function => contains_expr_function_unshadowed(node, id, shadowed)
    Func_Lambda => contains_func_unshadowed(node, id, shadowed)
    Expr_LetFn => contains_let_fn_unshadowed(node, id, shadowed)
    Expr_LetAnd => contains_let_and_unshadowed(node, id, shadowed)
    Expr_Quantifier => contains_quantifier_unshadowed(node, id, shadowed)
    Expr_Try => contains_try_unshadowed(node, id, shadowed)
    _ => contains_children_unshadowed(node, id, shadowed)
  }
}

///|
fn contains_let_unshadowed(node : Node, id : String, shadowed : Bool) -> Bool {
  contains_named_child_unshadowed(node, "expr", id, shadowed) ||
  contains_named_child_unshadowed(
    node,
    "body",
    id,
    shadowed || contains_named_child_binding(node, "pattern", id),
  )
}

///|
fn contains_let_mut_unshadowed(
  node : Node,
  id : String,
  shadowed : Bool,
) -> Bool {
  contains_named_child_unshadowed(node, "expr", id, shadowed) ||
  contains_named_child_unshadowed(
    node,
    "body",
    id,
    shadowed || contains_named_child_binding(node, "binder", id),
  )
}

///|
fn contains_for_unshadowed(node : Node, id : String, shadowed : Bool) -> Bool {
  if contains_binding_list_exprs_unshadowed(node, "binders", id, shadowed) {
    return true
  }
  let loop_shadowed = shadowed ||
    contains_binding_list_binding(node, "binders", id)
  contains_named_child_unshadowed(node, "condition", id, loop_shadowed) ||
  contains_binding_list_exprs_unshadowed(
    node, "continue_block", id, loop_shadowed,
  ) ||
  contains_named_child_unshadowed(node, "body", id, loop_shadowed) ||
  contains_named_child_unshadowed(node, "for_else", id, loop_shadowed) ||
  contains_named_child_unshadowed(node, "where_clause", id, loop_shadowed)
}

///|
fn contains_foreach_unshadowed(
  node : Node,
  id : String,
  shadowed : Bool,
) -> Bool {
  if contains_named_child_unshadowed(node, "expr", id, shadowed) ||
    contains_binding_list_exprs_unshadowed(node, "init", id, shadowed) {
    return true
  }
  let loop_shadowed = shadowed ||
    contains_optional_binder_list_binding(node, "binders", id) ||
    contains_binding_list_init_binding(node, "init", id)
  contains_binding_list_exprs_unshadowed(
    node, "continue_block", id, loop_shadowed,
  ) ||
  contains_named_child_unshadowed(node, "body", id, loop_shadowed) ||
  contains_named_child_unshadowed(node, "else_block", id, loop_shadowed) ||
  contains_named_child_unshadowed(node, "where_clause", id, loop_shadowed)
}

///|
fn contains_match_unshadowed(node : Node, id : String, shadowed : Bool) -> Bool {
  contains_named_child_unshadowed(node, "expr", id, shadowed) ||
  contains_case_list_unshadowed(node, "cases", "pattern", id, shadowed)
}

///|
fn contains_lexmatch_unshadowed(
  node : Node,
  id : String,
  shadowed : Bool,
) -> Bool {
  contains_named_child_unshadowed(node, "expr", id, shadowed) ||
  contains_case_list_unshadowed(node, "cases", "pat", id, shadowed)
}

///|
fn contains_list_comprehension_unshadowed(
  node : Node,
  id : String,
  shadowed : Bool,
) -> Bool {
  let body_shadowed = if contains_child(node, "kind") is Some(kind) {
    if contains_list_comprehension_kind_unshadowed(kind, id, shadowed)
      is Some(kind_shadowed) {
      kind_shadowed
    } else {
      return true
    }
  } else {
    shadowed
  }
  contains_named_child_unshadowed(node, "guard", id, body_shadowed) ||
  contains_named_child_unshadowed(node, "body", id, body_shadowed)
}

///|
fn contains_list_comprehension_kind_unshadowed(
  kind : Node,
  id : String,
  shadowed : Bool,
) -> Bool? {
  match kind.kind {
    Expr_ListComprehension_Kind_For => {
      if contains_binding_list_exprs_unshadowed(kind, "binders", id, shadowed) {
        return None
      }
      let loop_shadowed = shadowed ||
        contains_binding_list_binding(kind, "binders", id)
      if contains_named_child_unshadowed(kind, "condition", id, loop_shadowed) ||
        contains_binding_list_exprs_unshadowed(
          kind, "continue_block", id, loop_shadowed,
        ) {
        None
      } else {
        Some(loop_shadowed)
      }
    }
    Expr_ListComprehension_Kind_Foreach => {
      if contains_named_child_unshadowed(kind, "expr", id, shadowed) ||
        contains_binding_list_exprs_unshadowed(kind, "init", id, shadowed) {
        return None
      }
      let loop_shadowed = shadowed ||
        contains_optional_binder_list_binding(kind, "binders", id) ||
        contains_binding_list_init_binding(kind, "init", id)
      if contains_binding_list_exprs_unshadowed(
          kind, "continue_block", id, loop_shadowed,
        ) {
        None
      } else {
        Some(loop_shadowed)
      }
    }
    _ =>
      if contains_children_unshadowed(kind, id, shadowed) {
        None
      } else {
        Some(shadowed)
      }
  }
}

///|
fn contains_expr_function_unshadowed(
  node : Node,
  id : String,
  shadowed : Bool,
) -> Bool {
  match contains_child(node, "func") {
    Some(func) => contains_func_unshadowed(func, id, shadowed)
    None => false
  }
}

///|
fn contains_let_fn_unshadowed(
  node : Node,
  id : String,
  shadowed : Bool,
) -> Bool {
  let name_shadowed = shadowed || contains_named_child_binding(node, "name", id)
  contains_named_child_func_unshadowed(node, "func", id, name_shadowed) ||
  contains_named_child_unshadowed(node, "body", id, name_shadowed)
}

///|
fn contains_let_and_unshadowed(
  node : Node,
  id : String,
  shadowed : Bool,
) -> Bool {
  let binding_shadowed = shadowed || contains_let_and_binding_names(node, id)
  if contains_child(node, "bindings") is Some(bindings) {
    for entry in bindings.children {
      let (_, binding) = entry
      if contains_named_child_func_unshadowed(
          binding, "func", id, binding_shadowed,
        ) {
        return true
      }
    }
  }
  contains_named_child_unshadowed(node, "body", id, binding_shadowed)
}

///|
fn contains_quantifier_unshadowed(
  node : Node,
  id : String,
  shadowed : Bool,
) -> Bool {
  contains_named_child_unshadowed(
    node,
    "body",
    id,
    shadowed || contains_named_child_binding(node, "binder", id),
  )
}

///|
fn contains_try_unshadowed(node : Node, id : String, shadowed : Bool) -> Bool {
  contains_named_child_unshadowed(node, "body", id, shadowed) ||
  contains_case_list_unshadowed(node, "catch", "pattern", id, shadowed) ||
  contains_case_list_unshadowed(node, "try_else", "pattern", id, shadowed)
}

///|
fn contains_func_unshadowed(func : Node, id : String, shadowed : Bool) -> Bool {
  contains_named_child_unshadowed(
    func,
    "body",
    id,
    shadowed || contains_parameter_list_binding(func, "parameters", id),
  )
}

///|
fn contains_named_child_func_unshadowed(
  node : Node,
  name : String,
  id : String,
  shadowed : Bool,
) -> Bool {
  match contains_child(node, name) {
    Some(func) => contains_func_unshadowed(func, id, shadowed)
    None => false
  }
}

///|
fn contains_case_list_unshadowed(
  node : Node,
  list_name : String,
  pattern_name : String,
  id : String,
  shadowed : Bool,
) -> Bool {
  guard contains_child(node, list_name) is Some(list) else { return false }
  for entry in list.children {
    let (_, case) = entry
    let case_shadowed = shadowed ||
      contains_named_child_binding(case, pattern_name, id)
    if contains_named_child_unshadowed(case, "guard", id, case_shadowed) ||
      contains_named_child_unshadowed(case, "body", id, case_shadowed) {
      return true
    }
  }
  false
}

///|
fn contains_binding_list_exprs_unshadowed(
  node : Node,
  name : String,
  id : String,
  shadowed : Bool,
) -> Bool {
  guard contains_child(node, name) is Some(list) else { return false }
  for entry in list.children {
    let (_, binding) = entry
    if contains_named_child_unshadowed(binding, "expr", id, shadowed) {
      return true
    }
  }
  false
}

///|
fn contains_named_child_unshadowed(
  node : Node,
  name : String,
  id : String,
  shadowed : Bool,
) -> Bool {
  match contains_child(node, name) {
    Some(child) => contains_unshadowed_node(child, id, shadowed~)
    None => false
  }
}

///|
fn contains_children_unshadowed(
  node : Node,
  id : String,
  shadowed : Bool,
) -> Bool {
  for entry in node.children {
    let (_, child) = entry
    if contains_unshadowed_node(child, id, shadowed~) {
      return true
    }
  }
  false
}

///|
fn contains_named_child_binding(
  node : Node,
  name : String,
  id : String,
) -> Bool {
  match contains_child(node, name) {
    Some(child) => contains_binding_name(child, id)
    None => false
  }
}

///|
fn contains_binding_list_binding(
  node : Node,
  name : String,
  id : String,
) -> Bool {
  guard contains_child(node, name) is Some(list) else { return false }
  for entry in list.children {
    let (_, binding) = entry
    if contains_named_child_binding(binding, "binder", id) {
      return true
    }
  }
  false
}

///|
fn contains_binding_list_init_binding(
  node : Node,
  name : String,
  id : String,
) -> Bool {
  guard contains_child(node, name) is Some(list) else { return false }
  for entry in list.children {
    let (_, binding) = entry
    if contains_named_child_binding(binding, "init", id) {
      return true
    }
  }
  false
}

///|
fn contains_optional_binder_list_binding(
  node : Node,
  name : String,
  id : String,
) -> Bool {
  guard contains_child(node, name) is Some(list) else { return false }
  for entry in list.children {
    let (_, binder) = entry
    if contains_binding_name(binder, id) {
      return true
    }
  }
  false
}

///|
fn contains_parameter_list_binding(
  node : Node,
  name : String,
  id : String,
) -> Bool {
  guard contains_child(node, name) is Some(parameters) else { return false }
  for entry in parameters.children {
    let (_, parameter) = entry
    if contains_named_child_binding(parameter, "binder", id) {
      return true
    }
  }
  false
}

///|
fn contains_let_and_binding_names(node : Node, id : String) -> Bool {
  guard contains_child(node, "bindings") is Some(bindings) else { return false }
  for entry in bindings.children {
    let (_, binding) = entry
    if contains_named_child_binding(binding, "binder", id) {
      return true
    }
  }
  false
}

///|
fn contains_binding_name(node : Node, id : String) -> Bool {
  if contains_binder_name(node) == Some(id) {
    return true
  }
  for entry in node.children {
    let (_, child) = entry
    if contains_binding_name(child, id) {
      return true
    }
  }
  false
}

///|
fn contains_expr_ident_name(node : Node) -> String? {
  guard node.kind == Expr_Ident else { return None }
  guard contains_child(node, "id") is Some(var_node) else { return None }
  guard contains_child(var_node, "name") is Some(long_ident) else {
    return None
  }
  contains_long_ident_name(long_ident)
}

///|
fn contains_long_ident_name(node : Node) -> String? {
  match node.kind {
    LongIdent_Ident => contains_leaf_string_child(node, "value")
    LongIdent_Dot =>
      match
        (
          contains_leaf_string_child(node, "pkg"),
          contains_leaf_string_child(node, "id"),
        ) {
        (Some(pkg), Some(id)) => Some("@\{pkg}.\{id}")
        _ => None
      }
    _ => None
  }
}

///|
fn contains_binder_name(node : Node) -> String? {
  if node.kind == Binder {
    contains_leaf_string_child(node, "name")
  } else {
    None
  }
}

///|
fn contains_child(node : Node, name : String) -> Node? {
  for entry in node.children {
    let (child_name, value) = entry
    if child_name == Some(name) {
      return Some(value)
    }
  }
  None
}

///|
fn contains_leaf_string(node : Node) -> String? {
  match node.kind {
    Leaf(PString(value)) => Some(value)
    _ => None
  }
}

///|
fn contains_leaf_string_child(node : Node, name : String) -> String? {
  match contains_child(node, name) {
    Some(child) => contains_leaf_string(child)
    None => None
  }
}
