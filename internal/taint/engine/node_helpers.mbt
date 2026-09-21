///|
fn node_child(
  node : @untyped_cst.CstNode,
  name : String,
) -> @untyped_cst.CstNode? {
  match (node.kind, name) {
    (Expr_ArraySet | Expr_ArrayAugmentedSet, "array") =>
      return @cst.child(node, "lhs").bind(lhs => @cst.child(lhs, "self"))
    (Expr_ArraySet | Expr_ArrayAugmentedSet, "index") =>
      return @cst.child(node, "lhs").bind(lhs => @cst.child(lhs, "index"))
    (Expr_ArraySet | Expr_ArrayAugmentedSet, "value") =>
      return @cst.child(node, "rhs")
    (Expr_RecordUpdate, "record") => return record_update_base(node)
    _ => ()
  }
  let actual = match (node.kind, name) {
    (Expr_Field, "record") => "self"
    (Expr_Field, "accessor") => "field"
    (Expr_Apply | Expr_DotApply, "args") => "arg"
    (Expr_DotApply, "method_name") => "field"
    (Expr_If, "ifso") => "body"
    (Expr_If, "ifnot") => "else"
    (Expr_Try, "try_else") => "else"
    (Expr_While, "loop_cond") => "cond"
    (Expr_While, "loop_body") => "body"
    (Expr_While, "while_else") => "else"
    (Expr_ForEach, "else_block") => "else"
    (Expr_Guard, "otherwise") => "else"
    (Expr_ArrayGet | Expr_ArrayGetSlice, "array") => "self"
    (Expr_ArrayGetSlice, "start_index") => "start"
    (Expr_ArrayGetSlice, "end_index") => "end"
    (Expr_Return, "return_value") => "expr"
    (Expr_Raise, "err_value") => "expr"
    (Expr_Break, "arg") => "expr"
    (Expr_Mutate, "record") => "self"
    (Expr_Mutate, "accessor") => "field"
    (Expr_Mutate, "field") => "expr"
    (Expr_Is | Expr_RegexMatch, "pat") => "pattern"
    (Case_MatchCase, "guard") => "cond"
    (Case_LexScanCase, "pat") => "pattern"
    (Pattern_Alias, "pat") => "pattern"
    (Pattern_Alias, "alias") => "name"
    (Pattern_Constraint, "pat") => "pattern"
    (RegexPattern_Alias, "pat") => "pattern"
    (RegexPattern_Alias, "binder") => "name"
    (Binding_For, "binder" | "init") => "name"
    (Field_Definition, "label") => "name"
    _ => name
  }
  @cst.child(node, actual)
}

///|
fn record_update_base(node : @untyped_cst.CstNode) -> @untyped_cst.CstNode? {
  guard @cst.child(node, "body") is Some(body) else { return None }
  for field in node_items(body) {
    if field.kind is Field_RecordSpread {
      return @cst.child(field, "expr")
    }
  }
  None
}

///|
fn node_items(node : @untyped_cst.CstNode) -> Array[@untyped_cst.CstNode] {
  let raw_items = @cst.raw_children(node, "item")
  if !raw_items.is_empty() {
    raw_items
  } else {
    @cst.items(node)
  }
}

///|
fn node_child_items(
  node : @untyped_cst.CstNode,
  name : String,
) -> Array[@untyped_cst.CstNode] {
  match (node.kind, name) {
    (Expr_Match, "cases") => @cst.raw_children(node, "case")
    (Expr_Try, "catch") =>
      if @cst.raw_child(node, "case") is Some(list) {
        case_items(list)
      } else {
        []
      }
    (Expr_LexMatch | Expr_LexScan, "cases") =>
      if @cst.raw_child(node, "case") is Some(list) {
        case_items(list)
      } else {
        []
      }
    (Expr_Tuple, "exprs") | (Expr_Record, "fields") | (Expr_Map, "elems") =>
      if @cst.raw_child(node, "body") is Some(list) {
        node_items(list)
      } else {
        []
      }
    (Expr_Array, "exprs") => array_expr_items(node)
    (Expr_Continue, "args") =>
      if @cst.raw_child(node, "arg") is Some(list) {
        node_items(list)
      } else {
        []
      }
    (Expr_LetAnd, "bindings") => @cst.raw_children(node, "binding")
    (Expr_For, "binders") =>
      if @cst.raw_child(node, "init") is Some(list) {
        node_items(list)
      } else {
        []
      }
    (Expr_For, "continue_block") =>
      if @cst.raw_child(node, "continue") is Some(list) {
        node_items(list)
      } else {
        []
      }
    (Expr_ForEach, "binders") => foreach_binders(node)
    (Expr_ForEach, "continue_block") =>
      if @cst.child(node, "continue") is Some(list) {
        node_items(list)
      } else {
        []
      }
    (Expr_RecordUpdate, "fields") => record_update_fields(node)
    _ =>
      if node_child(node, name) is Some(list) {
        node_items(list)
      } else {
        []
      }
  }
}

///|
fn foreach_binders(node : @untyped_cst.CstNode) -> Array[@untyped_cst.CstNode] {
  guard @cst.child(node, "pattern") is Some(pattern) else { return [] }
  if pattern.kind is Pattern_Tuple {
    if @cst.child(pattern, "body") is Some(body) {
      node_items(body)
    } else {
      []
    }
  } else {
    [pattern]
  }
}

///|
fn array_expr_items(node : @untyped_cst.CstNode) -> Array[@untyped_cst.CstNode] {
  let exprs : Array[@untyped_cst.CstNode] = []
  guard @cst.child(node, "body") is Some(body) else { return exprs }
  for item in node_items(body) {
    if @cst.child(item, "expr") is Some(expr) {
      exprs.push(expr)
    }
  }
  exprs
}

///|
fn record_update_fields(
  node : @untyped_cst.CstNode,
) -> Array[@untyped_cst.CstNode] {
  let fields : Array[@untyped_cst.CstNode] = []
  guard @cst.child(node, "body") is Some(body) else { return fields }
  for field in node_items(body) {
    if !(field.kind is Field_RecordSpread) {
      fields.push(field)
    }
  }
  fields
}

///|
fn case_items(node : @untyped_cst.CstNode) -> Array[@untyped_cst.CstNode] {
  let cases = @cst.raw_children(node, "case")
  if cases.is_empty() {
    node_items(node)
  } else {
    cases
  }
}

///|
fn node_optional_child(
  node : @untyped_cst.CstNode,
  name : String,
) -> @untyped_cst.CstNode? {
  node_child(node, name)
}

///|
fn node_binder_name(node : @untyped_cst.CstNode) -> String? {
  if @cst.normalized_name(node) is Some(name) {
    Some(name)
  } else {
    @cst.name_node(node).bind(@cst.normalized_name)
  }
}

///|
fn node_label_name(node : @untyped_cst.CstNode) -> String? {
  if @cst.normalized_name(node) is Some(name) {
    Some(name)
  } else {
    @cst.name_node(node).bind(@cst.normalized_name)
  }
}

///|
fn node_var_name(node : @untyped_cst.CstNode) -> String? {
  if @cst.normalized_name(node) is Some(name) {
    Some(name)
  } else {
    @cst.name_node(node).bind(@cst.normalized_name)
  }
}

///|
fn node_first_label_name(node : @untyped_cst.CstNode) -> String? {
  @cst.name_node(node).bind(@cst.normalized_name)
}
