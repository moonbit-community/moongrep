///|
fn node_child(
  node : @untyped_cst.CstNode,
  name : String,
) -> @untyped_cst.CstNode? {
  match (node.kind, name) {
    (@untyped_cst.Expr_ArraySet | @untyped_cst.Expr_ArrayAugmentedSet, "array") =>
      return @cst.child(node, "lhs").bind(lhs => @cst.child(lhs, "self"))
    (@untyped_cst.Expr_ArraySet | @untyped_cst.Expr_ArrayAugmentedSet, "index") =>
      return @cst.child(node, "lhs").bind(lhs => @cst.child(lhs, "index"))
    (@untyped_cst.Expr_ArraySet | @untyped_cst.Expr_ArrayAugmentedSet, "value") =>
      return @cst.child(node, "rhs")
    (@untyped_cst.Expr_RecordUpdate, "record") =>
      return record_update_base(node)
    _ => ()
  }
  let actual = match (node.kind, name) {
    (@untyped_cst.Expr_Field, "record") => "self"
    (@untyped_cst.Expr_Field, "accessor") => "field"
    (@untyped_cst.Expr_Apply | @untyped_cst.Expr_DotApply, "args") => "arg"
    (@untyped_cst.Expr_DotApply, "method_name") => "field"
    (@untyped_cst.Expr_If, "ifso") => "body"
    (@untyped_cst.Expr_If, "ifnot") => "else"
    (@untyped_cst.Expr_Try, "try_else") => "else"
    (@untyped_cst.Expr_While, "loop_cond") => "cond"
    (@untyped_cst.Expr_While, "loop_body") => "body"
    (@untyped_cst.Expr_While, "while_else") => "else"
    (@untyped_cst.Expr_ForEach, "else_block") => "else"
    (@untyped_cst.Expr_Guard, "otherwise") => "else"
    (@untyped_cst.Expr_ArrayGet | @untyped_cst.Expr_ArrayGetSlice, "array") =>
      "self"
    (@untyped_cst.Expr_ArrayGetSlice, "start_index") => "start"
    (@untyped_cst.Expr_ArrayGetSlice, "end_index") => "end"
    (@untyped_cst.Expr_Return, "return_value") => "expr"
    (@untyped_cst.Expr_Raise, "err_value") => "expr"
    (@untyped_cst.Expr_Break, "arg") => "expr"
    (@untyped_cst.Expr_Mutate, "record") => "self"
    (@untyped_cst.Expr_Mutate, "accessor") => "field"
    (@untyped_cst.Expr_Mutate, "field") => "expr"
    (@untyped_cst.Expr_Is | @untyped_cst.Expr_RegexMatch, "pat") => "pattern"
    (
      @untyped_cst.Case_MatchCase
      | @untyped_cst.Case_LexCase
      | @untyped_cst.Case_LexScanCase,
      "guard",
    ) => "cond"
    (@untyped_cst.Case_LexCase | @untyped_cst.Case_LexScanCase, "pat") =>
      "pattern"
    (@untyped_cst.Pattern_Alias, "pat") => "pattern"
    (@untyped_cst.Pattern_Alias, "alias") => "name"
    (@untyped_cst.Pattern_Constraint, "pat") => "pattern"
    (@untyped_cst.RegexPattern_Alias | @untyped_cst.LexPattern_Alias, "pat") =>
      "pattern"
    (@untyped_cst.RegexPattern_Alias | @untyped_cst.LexPattern_Alias, "binder") =>
      "name"
    (@untyped_cst.Binding_For, "binder" | "init") => "name"
    (@untyped_cst.Field_Definition, "label") => "name"
    _ => name
  }
  @cst.child(node, actual)
}

///|
fn record_update_base(node : @untyped_cst.CstNode) -> @untyped_cst.CstNode? {
  guard @cst.child(node, "body") is Some(body) else { return None }
  for field in node_items(body) {
    if field.kind is @untyped_cst.Field_RecordSpread {
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
    (@untyped_cst.Expr_Match, "cases") => @cst.raw_children(node, "case")
    (@untyped_cst.Expr_Try, "catch") =>
      if @cst.raw_child(node, "case") is Some(list) {
        case_items(list)
      } else {
        []
      }
    (@untyped_cst.Expr_LexMatch | @untyped_cst.Expr_LexScan, "cases") =>
      if @cst.raw_child(node, "case") is Some(list) {
        case_items(list)
      } else {
        []
      }
    (@untyped_cst.Expr_Tuple, "exprs")
    | (@untyped_cst.Expr_Record, "fields")
    | (@untyped_cst.Expr_Map, "elems") =>
      if @cst.raw_child(node, "body") is Some(list) {
        node_items(list)
      } else {
        []
      }
    (@untyped_cst.Expr_Array, "exprs") => array_expr_items(node)
    (@untyped_cst.Expr_Continue, "args") =>
      if @cst.raw_child(node, "arg") is Some(list) {
        node_items(list)
      } else {
        []
      }
    (@untyped_cst.Expr_LetAnd, "bindings") => @cst.raw_children(node, "binding")
    (@untyped_cst.Expr_For, "binders") =>
      if @cst.raw_child(node, "init") is Some(list) {
        node_items(list)
      } else {
        []
      }
    (@untyped_cst.Expr_For, "continue_block") =>
      if @cst.raw_child(node, "continue") is Some(list) {
        node_items(list)
      } else {
        []
      }
    (@untyped_cst.Expr_ForEach, "binders") => foreach_binders(node)
    (@untyped_cst.Expr_ForEach, "continue_block") =>
      if @cst.child(node, "continue") is Some(list) {
        node_items(list)
      } else {
        []
      }
    (@untyped_cst.Expr_RecordUpdate, "fields") => record_update_fields(node)
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
  if pattern.kind is @untyped_cst.Pattern_Tuple {
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
    if !(field.kind is @untyped_cst.Field_RecordSpread) {
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
fn node_is_null(_node : @untyped_cst.CstNode) -> Bool {
  false
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
