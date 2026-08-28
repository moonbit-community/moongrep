///|
priv struct EllipsisPlaceholder {
  name : String
  kind : EllipsisMetavarKind
}

///|
fn ellipsis_placeholder(
  item : @untyped_cst.CstNode,
  compiled : CompiledExprPattern,
) -> EllipsisPlaceholder? {
  guard ellipsis_item_raw(item) is Some(raw) else { return None }
  guard matching_parse_ellipsis_syntax(raw) is Some(parsed) else { return None }
  let (name, raw_kind) = parsed
  if name == "_" {
    Some({ name, kind: raw_kind.unwrap_or(AnyItem), })
  } else if compiled_ellipsis_metavar(compiled, name) is Some(metavar) {
    Some({ name, kind: metavar.kind, })
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
fn ellipsis_item_raw(item : @untyped_cst.CstNode) -> String? {
  if matching_ellipsis_direct_raw(item) is Some(raw) {
    return Some(raw)
  }
  match item.kind {
    @untyped_cst.Argument_Positional =>
      @cst.argument_value(item).bind(matching_ellipsis_direct_raw)
    @untyped_cst.ArrayPattern_Pattern =>
      first_pattern_child(item).bind(matching_ellipsis_direct_raw)
    @untyped_cst.ArrayElement_Regular =>
      @cst.raw_child(item, "expr").bind(matching_ellipsis_direct_raw)
    @untyped_cst.Parameter_Positional =>
      parameter_pattern(item).bind(matching_ellipsis_direct_raw)
    _ => None
  }
}

///|
fn matching_ellipsis_direct_raw(node : @untyped_cst.CstNode) -> String? {
  let raw = match node.kind {
    @untyped_cst.Expr_Ident => @cst.normalized_expr_identifier_name(node)
    @untyped_cst.Pattern_Var => @cst.normalized_pattern_identifier_name(node)
    @untyped_cst.Name_Binder => @cst.normalized_name(node)
    @untyped_cst.Type_Name => @cst.name_node(node).bind(@cst.normalized_name)
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
        let name = raw[4:index].trim()
        let kind = matching_parse_ellipsis_kind(raw[index + 1:end].trim())
        if !name.is_empty() && kind is Some(kind) {
          return Some((name.to_owned(), Some(kind)))
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
fn matching_parse_ellipsis_kind(raw : StringView) -> EllipsisMetavarKind? {
  match raw {
    "any" => Some(AnyItem)
    "exp" => Some(ExpItem)
    "id" => Some(IdItem)
    "const" => Some(ConstItem)
    "arg" => Some(ArgItem)
    "pat" => Some(PatItem)
    "type" => Some(TypeItem)
    _ => None
  }
}

///|
fn ellipsis_candidate_matches(
  pattern_item : @untyped_cst.CstNode,
  candidate_item : @untyped_cst.CstNode,
  kind : EllipsisMetavarKind,
) -> Bool {
  if kind == AnyItem {
    return true
  }
  match pattern_item.kind {
    @untyped_cst.Expr_Ident => matching_ellipsis_expr_kind(candidate_item, kind)
    @untyped_cst.Argument_Positional =>
      matching_ellipsis_argument_kind(candidate_item, kind)
    @untyped_cst.Pattern_Var =>
      matching_ellipsis_pattern_kind(candidate_item, kind)
    @untyped_cst.ArrayPattern_Pattern =>
      matching_ellipsis_array_pattern_kind(candidate_item, kind)
    @untyped_cst.Type_Name => kind == TypeItem && is_type_node(candidate_item)
    @untyped_cst.Parameter_Positional =>
      kind == IdItem && matching_parameter_has_binder(candidate_item)
    @untyped_cst.ArrayElement_Regular =>
      matching_ellipsis_array_element_kind(candidate_item, kind)
    _ => false
  }
}

///|
fn matching_ellipsis_expr_kind(
  candidate : @untyped_cst.CstNode,
  kind : EllipsisMetavarKind,
) -> Bool {
  match kind {
    ExpItem => candidate.kind.is_expr()
    IdItem => @cst.normalized_expr_identifier_name(candidate) is Some(_)
    ConstItem => expr_constant(candidate) is Some(_)
    _ => false
  }
}

///|
fn matching_ellipsis_argument_kind(
  candidate : @untyped_cst.CstNode,
  kind : EllipsisMetavarKind,
) -> Bool {
  guard candidate.kind.is_argument() else { return false }
  if kind == ArgItem {
    return true
  }
  guard candidate.kind is @untyped_cst.Argument_Positional else { return false }
  if @cst.argument_value(candidate) is Some(value) {
    matching_ellipsis_expr_kind(value, kind)
  } else {
    false
  }
}

///|
fn matching_ellipsis_pattern_kind(
  candidate : @untyped_cst.CstNode,
  kind : EllipsisMetavarKind,
) -> Bool {
  let candidate = @cst.unwrap_groups(candidate)
  match kind {
    PatItem => candidate.kind.is_pattern()
    IdItem => @cst.normalized_pattern_identifier_name(candidate) is Some(_)
    ConstItem => pattern_constant(candidate) is Some(_)
    _ => false
  }
}

///|
fn matching_ellipsis_array_pattern_kind(
  candidate : @untyped_cst.CstNode,
  kind : EllipsisMetavarKind,
) -> Bool {
  guard candidate.kind is @untyped_cst.ArrayPattern_Pattern else {
    return false
  }
  if first_pattern_child(candidate) is Some(pattern) {
    matching_ellipsis_pattern_kind(pattern, kind)
  } else {
    false
  }
}

///|
fn matching_ellipsis_array_element_kind(
  candidate : @untyped_cst.CstNode,
  kind : EllipsisMetavarKind,
) -> Bool {
  guard candidate.kind is @untyped_cst.ArrayElement_Regular else {
    return false
  }
  if @cst.raw_child(candidate, "expr") is Some(expr) {
    matching_ellipsis_expr_kind(expr, kind)
  } else {
    false
  }
}

///|
fn first_pattern_child(node : @untyped_cst.CstNode) -> @untyped_cst.CstNode? {
  for entry in node.children {
    if entry.1.kind.is_pattern() {
      return Some(@cst.unwrap_groups(entry.1))
    }
  }
  None
}

///|
fn parameter_pattern(node : @untyped_cst.CstNode) -> @untyped_cst.CstNode? {
  if @cst.raw_child(node, "pattern") is Some(pattern) {
    Some(@cst.unwrap_groups(pattern))
  } else {
    @cst.name_node(node)
  }
}

///|
fn matching_parameter_has_binder(node : @untyped_cst.CstNode) -> Bool {
  match node.kind {
    @untyped_cst.Parameter_Positional
    | @untyped_cst.Parameter_Labelled
    | @untyped_cst.Parameter_Optional
    | @untyped_cst.Parameter_QuestionOptional =>
      parameter_pattern(node).bind(@cst.normalized_name) is Some(_) ||
      parameter_pattern(node).bind(@cst.normalized_pattern_identifier_name)
      is Some(_)
    _ => false
  }
}

///|
fn bind_multiple(
  bindings : @hashmap.HashMap[String, BoundValue],
  name : String,
  values : Array[@untyped_cst.CstNode],
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
