///|
/// Returns whether `candidate` has the same AST shape as `pattern`.
///
/// This convenience entry point does not enable declared metavars. It still
/// treats the exact identifier `$_` as an ignore placeholder.
pub fn expr_matches(
  pattern : @untyped_ast.Node,
  candidate : @untyped_ast.Node,
) -> Bool {
  let compiled : CompiledExprPattern = {
    ast: pattern,
    expr_metavars: [],
    identifier_metavars: [],
    constant_metavars: [],
    arg_metavars: [],
    type_metavars: [],
    ellipsis_metavars: [],
    target_metavar: None,
    source_metavar: None,
    ignored_fields: [],
  }
  match_expr_pattern(compiled, candidate) is Some(_)
}

///|
/// Matches `candidate` against a compiled expression pattern.
///
/// This attempts a single root-level match of `compiled.ast` against
/// `candidate`. It does not traverse candidate descendants; callers that need
/// search should pass each candidate expression subtree separately.
///
/// The returned bindings are fresh for this call. A failed match returns
/// `None` and does not expose partial bindings.
pub fn match_expr_pattern(
  compiled : CompiledExprPattern,
  candidate : @untyped_ast.Node,
) -> ExprMatch? {
  let bindings : @hashmap.HashMap[String, BoundValue] = HashMap([])
  match_expr_pattern_with_bindings(compiled, candidate, bindings)
}

///|
/// Matches with a caller-supplied binding context.
///
/// This is used by inside-context rules: the outer match establishes bindings,
/// then candidate target expressions are matched with those bindings already in
/// scope. The input map is copied before matching, so failed attempts cannot
/// mutate the caller's context.
pub fn match_expr_pattern_with_bindings(
  compiled : CompiledExprPattern,
  candidate : @untyped_ast.Node,
  initial_bindings : @hashmap.HashMap[String, BoundValue],
) -> ExprMatch? {
  let bindings = initial_bindings.copy()
  if match_node(compiled.ast, candidate, compiled, bindings) {
    Some({ root: candidate, bindings })
  } else {
    None
  }
}

///|
fn match_node(
  pattern : @untyped_ast.Node,
  candidate : @untyped_ast.Node,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  if match_expr_placeholder(pattern, candidate, compiled, bindings)
    is Some(result) {
    result
  } else if match_type_placeholder(pattern, candidate, compiled, bindings)
    is Some(result) {
    result
  } else if match_pattern_placeholder(pattern, candidate, compiled, bindings)
    is Some(result) {
    result
  } else if match_argument_placeholder(pattern, candidate, compiled, bindings)
    is Some(result) {
    result
  } else {
    match pattern.kind {
      Expr_Let => match_let_node(pattern, candidate, compiled, bindings)
      InterpElem_Source => candidate.kind == InterpElem_Source
      Var => match_var(pattern, candidate, compiled, bindings)
      Binder => match_binder(pattern, candidate, compiled, bindings)
      Label => match_label(pattern, candidate, compiled, bindings)
      Constructor => match_constructor(pattern, candidate, compiled, bindings)
      TypeName => match_type_name(pattern, candidate, compiled, bindings)
      _ => structural_match(pattern, candidate, compiled, bindings)
    }
  }
}

///|
fn match_type_placeholder(
  pattern : @untyped_ast.Node,
  candidate : @untyped_ast.Node,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool? {
  guard type_placeholder_name(pattern) is Some(name) else { return None }
  if contains_name(compiled.type_metavars, name) {
    Some(is_type_node(candidate) && bind_value(bindings, name, candidate))
  } else {
    None
  }
}

///|
fn type_placeholder_name(node : @untyped_ast.Node) -> String? {
  if node.kind != Type_Name {
    return None
  }
  guard child(node, "tys") is Some(tys) else { return None }
  if !tys.children.is_empty() {
    return None
  }
  guard child(node, "constr_id") is Some(constr_id) else { return None }
  guard child(constr_id, "id") is Some(long_ident) else { return None }
  guard long_ident.kind == LongIdent_Ident else { return None }
  leaf_string_child(long_ident, "value")
}

///|
fn is_type_node(node : @untyped_ast.Node) -> Bool {
  match node.kind {
    Type_Any
    | Type_Arrow
    | Type_Name
    | Type_Object
    | Type_Option
    | Type_Tuple => true
    _ => false
  }
}

///|
fn match_argument_placeholder(
  pattern : @untyped_ast.Node,
  candidate : @untyped_ast.Node,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool? {
  if pattern.kind != Argument {
    return None
  }
  guard argument_placeholder_name(pattern) is Some(name) else { return None }
  if contains_name(compiled.arg_metavars, name) {
    Some(candidate.kind == Argument && bind_value(bindings, name, candidate))
  } else {
    None
  }
}

///|
fn argument_placeholder_name(node : @untyped_ast.Node) -> String? {
  guard child(node, "kind") is Some(kind) else { return None }
  guard kind.kind == ArgumentKind_Positional else { return None }
  guard child(node, "value") is Some(value) else { return None }
  guard value.kind == Expr_Ident else { return None }
  value.normalized_expr_identifier_name()
}

///|
fn match_expr_placeholder(
  pattern : @untyped_ast.Node,
  candidate : @untyped_ast.Node,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool? {
  if pattern.kind != Expr_Ident {
    return None
  }
  guard pattern.normalized_expr_identifier_name() is Some(name) else {
    return None
  }
  if is_ignore_placeholder(name) {
    Some(true)
  } else if is_special_expr_metavar(compiled, name) ||
    contains_name(compiled.expr_metavars, name) {
    Some(bind_value(bindings, name, candidate))
  } else if contains_name(compiled.identifier_metavars, name) {
    match candidate.normalized_expr_identifier_name() {
      Some(candidate_name) =>
        Some(
          bind_value(bindings, name, string_binding(candidate_name, candidate)),
        )
      None => Some(false)
    }
  } else if contains_name(compiled.constant_metavars, name) {
    match expr_constant(candidate) {
      Some(constant) => Some(bind_value(bindings, name, constant))
      None => Some(false)
    }
  } else {
    None
  }
}

///|
fn match_pattern_placeholder(
  pattern : @untyped_ast.Node,
  candidate : @untyped_ast.Node,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool? {
  if pattern.kind != Pattern_Var {
    return None
  }
  guard pattern.normalized_pattern_identifier_name() is Some(name) else {
    return None
  }
  if parse_pattern_metavar_name(name) is Some(meta_name) {
    Some(bind_value(bindings, meta_name, candidate))
  } else if is_ignore_placeholder(name) {
    Some(true)
  } else if contains_name(compiled.identifier_metavars, name) {
    match candidate.normalized_pattern_identifier_name() {
      Some(candidate_name) =>
        Some(
          bind_value(bindings, name, string_binding(candidate_name, candidate)),
        )
      None => Some(false)
    }
  } else if contains_name(compiled.constant_metavars, name) {
    match pattern_constant(candidate) {
      Some(constant) => Some(bind_value(bindings, name, constant))
      None => Some(false)
    }
  } else {
    None
  }
}

///|
fn match_let_node(
  pattern : @untyped_ast.Node,
  candidate : @untyped_ast.Node,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  if candidate.kind != Expr_Let {
    return false
  }
  guard child(pattern, "pattern") is Some(pattern_pat) else { return false }
  guard child(candidate, "pattern") is Some(candidate_pat) else { return false }
  guard child(pattern, "expr") is Some(pattern_expr) else { return false }
  guard child(candidate, "expr") is Some(candidate_expr) else { return false }
  guard child(pattern, "body") is Some(pattern_body) else { return false }
  guard child(candidate, "body") is Some(candidate_body) else { return false }
  match_node(pattern_pat, candidate_pat, compiled, bindings) &&
  match_node(pattern_expr, candidate_expr, compiled, bindings) &&
  (
    is_faked_unit(pattern_body) ||
    match_node(pattern_body, candidate_body, compiled, bindings)
  )
}

///|
fn structural_match(
  pattern : @untyped_ast.Node,
  candidate : @untyped_ast.Node,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  match (pattern.kind, candidate.kind) {
    (Leaf(_), Leaf(_)) => pattern.kind == candidate.kind
    _ =>
      pattern.kind == candidate.kind &&
      match_children(
        pattern.kind,
        pattern.children,
        candidate.children,
        compiled,
        bindings,
      )
  }
}

///|
fn match_children(
  parent_kind : @untyped_ast.NodeKind,
  pattern : Array[(String?, @untyped_ast.Node)],
  candidate : Array[(String?, @untyped_ast.Node)],
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  match_children_from(parent_kind, pattern, candidate, 0, 0, compiled, bindings)
}

///|
fn match_children_from(
  parent_kind : @untyped_ast.NodeKind,
  pattern : Array[(String?, @untyped_ast.Node)],
  candidate : Array[(String?, @untyped_ast.Node)],
  pattern_index : Int,
  candidate_index : Int,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  if pattern_index == pattern.length() {
    return candidate_index == candidate.length()
  }
  let (pattern_name, pattern_value) = pattern[pattern_index]
  if pattern_name is Some(child_name) &&
    compiled_ignores_field(compiled, parent_kind, child_name) {
    if candidate_index >= candidate.length() {
      return false
    }
    let (candidate_name, _) = candidate[candidate_index]
    return pattern_name == candidate_name &&
      match_children_from(
        parent_kind,
        pattern,
        candidate,
        pattern_index + 1,
        candidate_index + 1,
        compiled,
        bindings,
      )
  }
  if pattern_name is None &&
    ellipsis_marker(pattern_value, compiled) is Some(marker) {
    let fixed_remaining = minimum_fixed_children(
      pattern,
      pattern_index + 1,
      compiled,
    )
    let maximum_length = candidate.length() - candidate_index - fixed_remaining
    if maximum_length < 0 {
      return false
    }
    for length in 0..<=maximum_length {
      let captured : Array[@untyped_ast.Node] = []
      let mut compatible = true
      for offset in 0..<length {
        let (candidate_name, candidate_value) = candidate[candidate_index +
          offset]
        if candidate_name is Some(_) ||
          !ellipsis_candidate_matches(
            pattern_value,
            candidate_value,
            marker.kind,
          ) {
          compatible = false
          break
        }
        captured.push(candidate_value)
      }
      if compatible {
        let branch = bindings.copy()
        let bound = marker.name == "_" ||
          bind_multiple(branch, marker.name, captured)
        if bound &&
          match_children_from(
            parent_kind,
            pattern,
            candidate,
            pattern_index + 1,
            candidate_index + length,
            compiled,
            branch,
          ) {
          replace_bindings(bindings, branch)
          return true
        }
      }
    }
    false
  } else {
    if candidate_index >= candidate.length() {
      return false
    }
    let (candidate_name, candidate_value) = candidate[candidate_index]
    pattern_name == candidate_name &&
    match_node(pattern_value, candidate_value, compiled, bindings) &&
    match_children_from(
      parent_kind,
      pattern,
      candidate,
      pattern_index + 1,
      candidate_index + 1,
      compiled,
      bindings,
    )
  }
}

///|
fn compiled_ignores_field(
  compiled : CompiledExprPattern,
  parent_kind : @untyped_ast.NodeKind,
  child_name : String,
) -> Bool {
  for field in compiled.ignored_fields {
    if field.parent_kind == parent_kind && field.child_name == child_name {
      return true
    }
  }
  false
}

///|
fn minimum_fixed_children(
  pattern : Array[(String?, @untyped_ast.Node)],
  start : Int,
  compiled : CompiledExprPattern,
) -> Int {
  let mut count = 0
  for index in start..<pattern.length() {
    let (name, value) = pattern[index]
    if !(name is None && ellipsis_marker(value, compiled) is Some(_)) {
      count += 1
    }
  }
  count
}

///|
fn match_var(
  pattern : @untyped_ast.Node,
  candidate : @untyped_ast.Node,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  if candidate.kind != Var {
    return false
  }
  match (child(pattern, "name"), child(candidate, "name")) {
    (Some(pattern_name), Some(candidate_name)) =>
      match_long_ident(pattern_name, candidate_name, compiled, bindings)
    _ => false
  }
}

///|
fn match_long_ident(
  pattern : @untyped_ast.Node,
  candidate : @untyped_ast.Node,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  match pattern.kind {
    LongIdent_Ident => {
      guard leaf_string_child(pattern, "value") is Some(pattern_name) else {
        return false
      }
      guard candidate.normalized_long_ident() is Some(candidate_name) else {
        return false
      }
      match_identifier_name(
        pattern_name, candidate_name, candidate_name, candidate, compiled, bindings,
      )
    }
    LongIdent_Dot => {
      if candidate.kind != LongIdent_Dot {
        return false
      }
      guard leaf_string_child(pattern, "pkg") is Some(pattern_pkg) else {
        return false
      }
      guard leaf_string_child(candidate, "pkg") is Some(candidate_pkg) else {
        return false
      }
      guard leaf_string_child(pattern, "id") is Some(pattern_id) else {
        return false
      }
      guard leaf_string_child(candidate, "id") is Some(candidate_id) else {
        return false
      }
      guard candidate.normalized_long_ident() is Some(bound_candidate) else {
        return false
      }
      pattern_pkg == candidate_pkg &&
      match_identifier_name(
        pattern_id, candidate_id, bound_candidate, candidate, compiled, bindings,
      )
    }
    _ => structural_match(pattern, candidate, compiled, bindings)
  }
}

///|
fn match_binder(
  pattern : @untyped_ast.Node,
  candidate : @untyped_ast.Node,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  if candidate.kind != Binder {
    return false
  }
  match (pattern.normalized_binder_name(), candidate.normalized_binder_name()) {
    (Some(pattern_name), Some(candidate_name)) =>
      match_identifier_name(
        pattern_name, candidate_name, candidate_name, candidate, compiled, bindings,
      )
    _ => false
  }
}

///|
fn match_label(
  pattern : @untyped_ast.Node,
  candidate : @untyped_ast.Node,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  if candidate.kind != Label {
    return false
  }
  match (pattern.normalized_label_name(), candidate.normalized_label_name()) {
    (Some(pattern_name), Some(candidate_name)) =>
      match_identifier_name(
        pattern_name, candidate_name, candidate_name, candidate, compiled, bindings,
      )
    _ => false
  }
}

///|
fn match_identifier_name(
  pattern_name : String,
  literal_candidate_name : String,
  bound_candidate_name : String,
  candidate_source : @untyped_ast.Node,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  if is_ignore_placeholder(pattern_name) {
    true
  } else if contains_name(compiled.identifier_metavars, pattern_name) {
    bind_value(
      bindings,
      pattern_name,
      string_binding(bound_candidate_name, candidate_source),
    )
  } else {
    pattern_name == literal_candidate_name
  }
}

///|
fn match_type_name(
  pattern : @untyped_ast.Node,
  candidate : @untyped_ast.Node,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  if candidate.kind != TypeName {
    return false
  }
  guard child(pattern, "name") is Some(pattern_name) else { return false }
  guard child(candidate, "name") is Some(candidate_name) else { return false }
  leaf_bool_child(pattern, "is_object") ==
  leaf_bool_child(candidate, "is_object") &&
  match_long_ident(pattern_name, candidate_name, compiled, bindings)
}

///|
fn match_constructor(
  pattern : @untyped_ast.Node,
  candidate : @untyped_ast.Node,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  if candidate.kind != Constructor {
    return false
  }
  guard constructor_name(pattern) is Some(pattern_name) else { return false }
  guard constructor_name(candidate) is Some(candidate_name) else {
    return false
  }
  guard child(pattern, "extra_info") is Some(pattern_extra) else {
    return false
  }
  guard child(candidate, "extra_info") is Some(candidate_extra) else {
    return false
  }
  if contains_name(compiled.identifier_metavars, pattern_name) {
    let extra_matches = pattern_extra.kind == ConstructorExtraInfo_NoExtraInfo ||
      match_constructor_extra_info(
        pattern_extra, candidate_extra, compiled, bindings,
      )
    extra_matches &&
    bind_value(
      bindings,
      pattern_name,
      string_binding(normalized_constructor(candidate), candidate),
    )
  } else if is_ignore_placeholder(pattern_name) {
    true
  } else {
    pattern_name == candidate_name &&
    match_constructor_extra_info(
      pattern_extra, candidate_extra, compiled, bindings,
    )
  }
}

///|
fn match_constructor_extra_info(
  pattern : @untyped_ast.Node,
  candidate : @untyped_ast.Node,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  match (pattern.kind, candidate.kind) {
    (ConstructorExtraInfo_NoExtraInfo, ConstructorExtraInfo_NoExtraInfo) => true
    (ConstructorExtraInfo_Package, ConstructorExtraInfo_Package) =>
      leaf_string_child(pattern, "value") ==
      leaf_string_child(candidate, "value")
    (ConstructorExtraInfo_TypeName, ConstructorExtraInfo_TypeName) =>
      match (child(pattern, "value"), child(candidate, "value")) {
        (Some(pattern_type), Some(candidate_type)) =>
          match_type_name(pattern_type, candidate_type, compiled, bindings)
        _ => false
      }
    (
      ConstructorExtraInfo_TypeNameWithConstrPackage,
      ConstructorExtraInfo_TypeNameWithConstrPackage,
    ) =>
      leaf_string_child(pattern, "pkg") == leaf_string_child(candidate, "pkg") &&
      (match (child(pattern, "type_name"), child(candidate, "type_name")) {
        (Some(pattern_type), Some(candidate_type)) =>
          match_type_name(pattern_type, candidate_type, compiled, bindings)
        _ => false
      })
    _ => false
  }
}

///|
fn bind_value(
  bindings : @hashmap.HashMap[String, BoundValue],
  name : String,
  value : @untyped_ast.Node,
) -> Bool {
  let value = Single(value)
  if bindings.get(name) is Some(existing) {
    bound_value_equal(existing, value)
  } else {
    bindings[name] = value
    true
  }
}

///|
fn string_binding(
  value : String,
  source : @untyped_ast.Node,
) -> @untyped_ast.Node {
  { kind: Leaf(PString(value)), loc: source.loc, children: [] }
}

///|
fn bound_value_equal(left : BoundValue, right : BoundValue) -> Bool {
  match (left, right) {
    (Single(left), Single(right)) => node_equal_ignoring_loc(left, right)
    (Multiple(left), Multiple(right)) => nodes_equal_ignoring_loc(left, right)
    _ => false
  }
}

///|
fn nodes_equal_ignoring_loc(
  left : Array[@untyped_ast.Node],
  right : Array[@untyped_ast.Node],
) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for index in 0..<left.length() {
    if !node_equal_ignoring_loc(left[index], right[index]) {
      return false
    }
  }
  true
}

///|
fn node_equal_ignoring_loc(
  left : @untyped_ast.Node,
  right : @untyped_ast.Node,
) -> Bool {
  match (left.kind, right.kind) {
    (Leaf(_), Leaf(_)) => left.kind == right.kind
    _ =>
      left.kind == right.kind &&
      children_equal_ignoring_loc(left.children, right.children)
  }
}

///|
fn children_equal_ignoring_loc(
  left : Array[(String?, @untyped_ast.Node)],
  right : Array[(String?, @untyped_ast.Node)],
) -> Bool {
  left.length() == right.length() &&
  ({
    for index in 0..<left.length() {
      let (left_name, left_value) = left[index]
      let (right_name, right_value) = right[index]
      if left_name != right_name ||
        !node_equal_ignoring_loc(left_value, right_value) {
        return false
      }
    }
    true
  })
}

///|
fn child(node : @untyped_ast.Node, name : String) -> @untyped_ast.Node? {
  for entry in node.children {
    let (child_name, value) = entry
    if child_name == Some(name) {
      return Some(value)
    }
  }
  None
}

///|
fn leaf_string(node : @untyped_ast.Node) -> String? {
  match node.kind {
    Leaf(PString(value)) => Some(value)
    _ => None
  }
}

///|
fn leaf_bool(node : @untyped_ast.Node) -> Bool? {
  match node.kind {
    Leaf(PBool(value)) => Some(value)
    _ => None
  }
}

///|
fn leaf_string_child(node : @untyped_ast.Node, name : String) -> String? {
  if child(node, name) is Some(value) {
    leaf_string(value)
  } else {
    None
  }
}

///|
fn leaf_bool_child(node : @untyped_ast.Node, name : String) -> Bool? {
  if child(node, name) is Some(value) {
    leaf_bool(value)
  } else {
    None
  }
}

///|
fn expr_constant(node : @untyped_ast.Node) -> @untyped_ast.Node? {
  if node.kind == Expr_Constant {
    child(node, "constant")
  } else {
    None
  }
}

///|
fn pattern_constant(node : @untyped_ast.Node) -> @untyped_ast.Node? {
  if node.kind == Pattern_Constant {
    child(node, "constant")
  } else {
    None
  }
}

///|
fn constructor_name(node : @untyped_ast.Node) -> String? {
  guard child(node, "name") is Some(name_node) else { return None }
  leaf_string_child(name_node, "name")
}

///|
fn normalized_constructor(constr : @untyped_ast.Node) -> String {
  let name = constructor_name(constr).unwrap_or("")
  match child(constr, "extra_info") {
    Some(extra) =>
      match extra.kind {
        ConstructorExtraInfo_NoExtraInfo => name
        ConstructorExtraInfo_Package =>
          if leaf_string_child(extra, "value") is Some(pkg) {
            "@\{pkg}.\{name}"
          } else {
            name
          }
        ConstructorExtraInfo_TypeName =>
          if child(extra, "value") is Some(type_name) {
            "\{normalized_type_name(type_name)}::\{name}"
          } else {
            name
          }
        ConstructorExtraInfo_TypeNameWithConstrPackage =>
          if child(extra, "type_name") is Some(type_name) {
            if leaf_string_child(extra, "pkg") is Some(pkg) {
              "\{normalized_type_name(type_name)}::@\{pkg}.\{name}"
            } else {
              "\{normalized_type_name(type_name)}::\{name}"
            }
          } else {
            name
          }
        _ => name
      }
    None => name
  }
}

///|
fn normalized_type_name(type_name : @untyped_ast.Node) -> String {
  let name = if child(type_name, "name") is Some(long_ident) {
    long_ident.normalized_long_ident().unwrap_or("")
  } else {
    ""
  }
  if leaf_bool_child(type_name, "is_object") == Some(true) {
    "object \{name}"
  } else {
    name
  }
}

///|
fn is_faked_unit(node : @untyped_ast.Node) -> Bool {
  node.kind == Expr_Unit && leaf_bool_child(node, "faked") == Some(true)
}

///|
fn contains_name(names : Array[String], name : String) -> Bool {
  for item in names {
    if item == name {
      return true
    }
  }
  false
}

///|
fn is_special_expr_metavar(
  compiled : CompiledExprPattern,
  name : String,
) -> Bool {
  compiled.target_metavar == Some(name) || compiled.source_metavar == Some(name)
}

///|
fn parse_pattern_metavar_name(raw : String) -> String? {
  if raw.has_prefix("$(") && raw.has_suffix(")") {
    let end = raw.length() - 1
    for index in 2..<end {
      if raw[index] == ':' && raw[index + 1:end].to_owned() == "pat" {
        let name = raw[2:index]
        if name.length() > 0 {
          return Some(name.to_owned())
        }
      }
    }
  }
  None
}

///|
fn is_ignore_placeholder(name : String) -> Bool {
  name == "$_"
}
