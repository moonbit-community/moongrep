///|
priv struct EllipsisMarker {
  name : String
  kind : EllipsisMetavarKind
}

///|
fn ellipsis_marker(
  item : @untyped_ast.Node,
  compiled : CompiledExprPattern,
) -> EllipsisMarker? {
  guard ellipsis_item_raw(item) is Some(raw) else { return None }
  guard matching_parse_ellipsis_syntax(raw) is Some(parsed) else { return None }
  let (name, raw_kind) = parsed
  if name == "_" {
    Some({ name, kind: raw_kind.unwrap_or(AnyItem) })
  } else if compiled_ellipsis_metavar(compiled, name) is Some(metavar) {
    Some({ name, kind: metavar.kind })
  } else {
    None
  }
}

///|
fn compiled_ellipsis_metavar(
  compiled : CompiledExprPattern,
  name : String,
) -> EllipsisMetavar? {
  for metavar in compiled.ellipsis_metavars {
    if metavar.name == name {
      return Some(metavar)
    }
  }
  None
}

///|
fn ellipsis_item_raw(item : @untyped_ast.Node) -> String? {
  if matching_ellipsis_direct_raw(item) is Some(raw) {
    return Some(raw)
  }
  match item.kind {
    Argument => {
      guard child(item, "kind") is Some(kind) &&
        kind.kind == ArgumentKind_Positional else {
        return None
      }
      guard child(item, "value") is Some(value) else { return None }
      matching_ellipsis_direct_raw(value)
    }
    ConstrPatArg => {
      guard child(item, "kind") is Some(kind) &&
        kind.kind == ArgumentKind_Positional else {
        return None
      }
      guard child(item, "pat") is Some(pattern) else { return None }
      matching_ellipsis_direct_raw(pattern)
    }
    ArrayPattern_Pattern | SpreadableElem_Regular =>
      match child(item, "value") {
        Some(value) => matching_ellipsis_direct_raw(value)
        None => None
      }
    Parameter_Positional => {
      guard child(item, "binder") is Some(binder) else { return None }
      guard child(item, "ty") is Some(ty) && matching_is_null(ty) else {
        return None
      }
      matching_ellipsis_direct_raw(binder)
    }
    _ => None
  }
}

///|
fn matching_ellipsis_direct_raw(node : @untyped_ast.Node) -> String? {
  let raw = match node.kind {
    Expr_Ident => node.normalized_expr_identifier_name()
    Pattern_Var =>
      match child(node, "value") {
        Some(binder) => leaf_string_child(binder, "name")
        None => None
      }
    Binder => leaf_string_child(node, "name")
    Type_Name => type_placeholder_name(node)
    _ => None
  }
  match raw {
    Some(raw) if raw.has_prefix("$$$") => Some(raw)
    _ => None
  }
}

///|
fn matching_parse_ellipsis_syntax(
  raw : String,
) -> (String, EllipsisMetavarKind?)? {
  if !raw.has_prefix("$$$") {
    return None
  }
  if raw.has_prefix("$$$(") && raw.has_suffix(")") {
    let end = raw.length() - 1
    for index in 4..<end {
      if raw[index] == ':' {
        let name = raw[4:index].trim().to_owned()
        let kind = match raw[index + 1:end].trim().to_owned() {
          "exp" => Some(ExpItem)
          "id" => Some(IdItem)
          "const" => Some(ConstItem)
          "arg" => Some(ArgItem)
          "pat" => Some(PatItem)
          "type" => Some(TypeItem)
          _ => None
        }
        if name.length() > 0 && kind is Some(_) {
          return Some((name, kind))
        }
        return None
      }
    }
    None
  } else if raw.length() > 3 {
    Some((raw[3:].to_owned(), None))
  } else {
    None
  }
}

///|
fn ellipsis_candidate_matches(
  pattern_item : @untyped_ast.Node,
  candidate_item : @untyped_ast.Node,
  kind : EllipsisMetavarKind,
) -> Bool {
  if kind == AnyItem {
    return true
  }
  match pattern_item.kind {
    Expr_Ident => matching_ellipsis_expr_kind(candidate_item, kind)
    Argument => matching_ellipsis_argument_kind(candidate_item, kind)
    Pattern_Var => matching_ellipsis_pattern_kind(candidate_item, kind)
    ConstrPatArg =>
      matching_ellipsis_constr_pattern_arg_kind(candidate_item, kind)
    ArrayPattern_Pattern =>
      matching_ellipsis_array_pattern_kind(candidate_item, kind)
    Type_Name => kind == TypeItem && is_type_node(candidate_item)
    Parameter_Positional =>
      kind == IdItem && matching_parameter_has_binder(candidate_item)
    SpreadableElem_Regular =>
      matching_ellipsis_spreadable_expr_kind(candidate_item, kind)
    _ => false
  }
}

///|
fn matching_ellipsis_expr_kind(
  candidate : @untyped_ast.Node,
  kind : EllipsisMetavarKind,
) -> Bool {
  match kind {
    ExpItem => matching_is_expr_node(candidate)
    IdItem => candidate.normalized_expr_identifier_name() is Some(_)
    ConstItem => expr_constant(candidate) is Some(_)
    _ => false
  }
}

///|
fn matching_ellipsis_argument_kind(
  candidate : @untyped_ast.Node,
  kind : EllipsisMetavarKind,
) -> Bool {
  if candidate.kind != Argument {
    return false
  }
  if kind == ArgItem {
    return true
  }
  guard child(candidate, "kind") is Some(argument_kind) &&
    argument_kind.kind == ArgumentKind_Positional else {
    return false
  }
  guard child(candidate, "value") is Some(value) else { return false }
  matching_ellipsis_expr_kind(value, kind)
}

///|
fn matching_ellipsis_pattern_kind(
  candidate : @untyped_ast.Node,
  kind : EllipsisMetavarKind,
) -> Bool {
  match kind {
    PatItem => matching_is_pattern_node(candidate)
    IdItem => candidate.normalized_pattern_identifier_name() is Some(_)
    ConstItem => pattern_constant(candidate) is Some(_)
    _ => false
  }
}

///|
fn matching_ellipsis_constr_pattern_arg_kind(
  candidate : @untyped_ast.Node,
  kind : EllipsisMetavarKind,
) -> Bool {
  guard candidate.kind == ConstrPatArg else { return false }
  guard child(candidate, "pat") is Some(pattern) else { return false }
  matching_ellipsis_pattern_kind(pattern, kind)
}

///|
fn matching_ellipsis_array_pattern_kind(
  candidate : @untyped_ast.Node,
  kind : EllipsisMetavarKind,
) -> Bool {
  guard candidate.kind == ArrayPattern_Pattern else { return false }
  guard child(candidate, "value") is Some(pattern) else { return false }
  matching_ellipsis_pattern_kind(pattern, kind)
}

///|
fn matching_ellipsis_spreadable_expr_kind(
  candidate : @untyped_ast.Node,
  kind : EllipsisMetavarKind,
) -> Bool {
  guard candidate.kind == SpreadableElem_Regular else { return false }
  guard child(candidate, "value") is Some(expr) else { return false }
  matching_ellipsis_expr_kind(expr, kind)
}

///|
fn matching_parameter_has_binder(node : @untyped_ast.Node) -> Bool {
  match node.kind {
    Parameter_Positional
    | Parameter_Labelled
    | Parameter_Optional
    | Parameter_QuestionOptional => child(node, "binder") is Some(_)
    _ => false
  }
}

///|
fn matching_is_expr_node(node : @untyped_ast.Node) -> Bool {
  node.kind.to_string().has_prefix("Expr::")
}

///|
fn matching_is_pattern_node(node : @untyped_ast.Node) -> Bool {
  node.kind.to_string().has_prefix("Pattern::")
}

///|
fn matching_is_null(node : @untyped_ast.Node) -> Bool {
  node.kind == Leaf(PNull)
}

///|
fn bind_multiple(
  bindings : @hashmap.HashMap[String, BoundValue],
  name : String,
  values : Array[@untyped_ast.Node],
) -> Bool {
  let value = Multiple(values)
  if bindings.get(name) is Some(existing) {
    bound_value_equal(existing, value)
  } else {
    bindings[name] = value
    true
  }
}

///|
fn replace_bindings(
  target : @hashmap.HashMap[String, BoundValue],
  source : @hashmap.HashMap[String, BoundValue],
) -> Unit {
  target.clear()
  source.each(fn(name, value) { target[name] = value })
}
