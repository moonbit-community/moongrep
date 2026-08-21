///|
/// Returns whether `candidate` has the same semantic CST shape as `pattern`.
pub fn expr_matches(
  pattern : @untyped_cst.CstNode,
  candidate : @untyped_cst.CstNode,
) -> Bool {
  let compiled : CompiledExprPattern = {
    cst: pattern,
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
/// Attempts one root-level match of `compiled.cst` against `candidate`.
pub fn match_expr_pattern(
  compiled : CompiledExprPattern,
  candidate : @untyped_cst.CstNode,
) -> ExprMatch? {
  let bindings : @hashmap.HashMap[String, BoundValue] = HashMap([])
  match_expr_pattern_with_bindings(compiled, candidate, bindings)
}

///|
/// Matches with a copied caller-supplied binding context.
pub fn match_expr_pattern_with_bindings(
  compiled : CompiledExprPattern,
  candidate : @untyped_cst.CstNode,
  initial_bindings : @hashmap.HashMap[String, BoundValue],
) -> ExprMatch? {
  let bindings = initial_bindings.copy()
  if match_node(compiled.cst, candidate, compiled, bindings) {
    Some({ root: candidate, bindings })
  } else {
    None
  }
}

///|
fn match_node(
  raw_pattern : @untyped_cst.CstNode,
  raw_candidate : @untyped_cst.CstNode,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  let pattern = @cst.unwrap_groups(raw_pattern)
  let candidate = @cst.unwrap_groups(raw_candidate)
  if lexical_statement_has_continuation(pattern.kind) &&
    candidate.kind
    is (@untyped_cst.Expression
    | @untyped_cst.Expr_Block
    | @untyped_cst.Expr_Sequence) {
    match sequence_items(candidate) {
      [first, ..] if first.kind == pattern.kind =>
        return match_node(pattern, first, compiled, bindings)
      _ => return false
    }
  }
  if match_expr_placeholder(pattern, candidate, compiled, bindings)
    is Some(result) {
    return result
  }
  if match_type_placeholder(pattern, candidate, compiled, bindings)
    is Some(result) {
    return result
  }
  if match_pattern_placeholder(pattern, candidate, compiled, bindings)
    is Some(result) {
    return result
  }
  if match_argument_placeholder(pattern, candidate, compiled, bindings)
    is Some(result) {
    return result
  }
  if is_name_node(pattern) {
    return match_name_node(pattern, candidate, compiled, bindings)
  }
  if pattern.kind is @untyped_cst.Expression ||
    pattern.kind is @untyped_cst.Expr_Block ||
    pattern.kind is @untyped_cst.Expr_Sequence {
    return match_expression_container(pattern, candidate, compiled, bindings)
  }
  structural_match(pattern, candidate, compiled, bindings)
}

///|
/// These statements scoped the rest of a sequence in the previous
/// representation. The CST stores the header and continuation as siblings.
fn lexical_statement_has_continuation(kind : @untyped_cst.NodeKind) -> Bool {
  match kind {
    @untyped_cst.Expr_Let
    | @untyped_cst.Expr_LetMut
    | @untyped_cst.Expr_LetFn
    | @untyped_cst.Expr_LetAnd
    | @untyped_cst.Expr_Guard
    | @untyped_cst.Expr_ProofLet => true
    _ => false
  }
}

///|
fn match_type_placeholder(
  pattern : @untyped_cst.CstNode,
  candidate : @untyped_cst.CstNode,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool? {
  guard type_placeholder_name(pattern) is Some(parsed_name) else { return None }
  guard contains_name(compiled.type_metavars, parsed_name) else { return None }
  Some(candidate.kind.is_type() && bind_value(bindings, parsed_name, candidate))
}

///|
fn type_placeholder_name(node : @untyped_cst.CstNode) -> String? {
  guard node.kind is @untyped_cst.Type_Name else { return None }
  for entry in @cst.semantic_children(node) {
    if entry.1.kind.is_type() {
      return None
    }
  }
  @cst.name_node(node).bind(@cst.normalized_name).bind(single_metavar_name)
}

///|
fn is_type_node(node : @untyped_cst.CstNode) -> Bool {
  @cst.unwrap_groups(node).kind.is_type()
}

///|
fn match_argument_placeholder(
  pattern : @untyped_cst.CstNode,
  candidate : @untyped_cst.CstNode,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool? {
  guard pattern.kind is @untyped_cst.Argument_Positional else { return None }
  guard argument_placeholder_name(pattern) is Some(name) else { return None }
  if contains_name(compiled.arg_metavars, name) {
    Some(candidate.kind.is_argument() && bind_value(bindings, name, candidate))
  } else {
    None
  }
}

///|
fn argument_placeholder_name(node : @untyped_cst.CstNode) -> String? {
  guard node.kind is @untyped_cst.Argument_Positional else { return None }
  @cst.argument_value(node)
  .bind(@cst.normalized_expr_identifier_name)
  .bind(single_metavar_name)
}

///|
fn match_expr_placeholder(
  pattern : @untyped_cst.CstNode,
  candidate : @untyped_cst.CstNode,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool? {
  guard pattern.kind is @untyped_cst.Expr_Ident else { return None }
  guard @cst.normalized_expr_identifier_name(pattern) is Some(name) else {
    return None
  }
  let logical = single_metavar_name(name)
  if is_ignore_placeholder(name) {
    Some(true)
  } else if logical is Some(logical) {
    if contains_name(compiled.expr_metavars, logical) {
      Some(bind_value(bindings, logical, candidate))
    } else if contains_name(compiled.identifier_metavars, logical) {
      match
        (
          @cst.normalized_expr_identifier_name(candidate),
          @cst.name_node(candidate),
        ) {
        (Some(_), Some(candidate_name)) =>
          Some(bind_value(bindings, logical, candidate_name))
        _ => Some(false)
      }
    } else if contains_name(compiled.constant_metavars, logical) {
      if expr_constant(candidate) is Some(constant) {
        Some(bind_value(bindings, logical, constant))
      } else {
        Some(false)
      }
    } else {
      None
    }
  } else if is_special_expr_metavar(compiled, name) {
    Some(bind_value(bindings, name, candidate))
  } else {
    None
  }
}

///|
fn match_pattern_placeholder(
  pattern : @untyped_cst.CstNode,
  candidate : @untyped_cst.CstNode,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool? {
  guard pattern.kind is @untyped_cst.Pattern_Var else { return None }
  guard @cst.normalized_pattern_identifier_name(pattern) is Some(name) else {
    return None
  }
  if parse_pattern_metavar_name(name) is Some(meta_name) {
    Some(bind_value(bindings, meta_name, candidate))
  } else if is_ignore_placeholder(name) {
    Some(true)
  } else if single_metavar_name(name) is Some(logical) &&
    contains_name(compiled.identifier_metavars, logical) {
    match
      (
        @cst.normalized_pattern_identifier_name(candidate),
        @cst.name_node(candidate),
      ) {
      (Some(_), Some(candidate_name)) =>
        Some(bind_value(bindings, logical, candidate_name))
      _ => Some(false)
    }
  } else if single_metavar_name(name) is Some(logical) &&
    contains_name(compiled.constant_metavars, logical) {
    if pattern_constant(candidate) is Some(constant) {
      Some(bind_value(bindings, logical, constant))
    } else {
      Some(false)
    }
  } else {
    None
  }
}

///|
fn match_expression_container(
  pattern : @untyped_cst.CstNode,
  candidate : @untyped_cst.CstNode,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  if pattern.kind is @untyped_cst.Expr_Block &&
    !(candidate.kind is @untyped_cst.Expr_Block) {
    return false
  }
  if pattern.kind is @untyped_cst.Expr_Sequence &&
    !(candidate.kind is @untyped_cst.Expr_Sequence) {
    return false
  }
  let pattern_items = sequence_items(pattern)
  let candidate_items = sequence_items(candidate)
  if candidate_items is [] {
    if candidate.kind
      is (@untyped_cst.Expression
      | @untyped_cst.Expr_Block
      | @untyped_cst.Expr_Sequence) {
      return pattern_items.is_empty()
    }
    return pattern_items is [single] &&
      match_node(single, candidate, compiled, bindings)
  }
  let pattern_children = unlabelled(pattern_items)
  let candidate_children = unlabelled(candidate_items)
  if match_children(
      pattern.kind,
      pattern_children,
      candidate_children,
      compiled,
      bindings,
    ) {
    return true
  }
  // Earlier versions synthesized a final unit for a body-less let/guard.
  // Preserve that spelling-level compatibility.
  if pattern_items.length() == candidate_items.length() + 1 &&
    pattern_items.last().unwrap().kind is @untyped_cst.Expr_Unit {
    let without_unit = pattern_children[:pattern_children.length() - 1].to_owned()
    return match_children(
      pattern.kind,
      without_unit,
      candidate_children,
      compiled,
      bindings,
    )
  }
  false
}

///|
fn sequence_items(node : @untyped_cst.CstNode) -> Array[@untyped_cst.CstNode] {
  match node.kind {
    @untyped_cst.Expression => @cst.expression_nodes(node)
    @untyped_cst.Expr_Block
    | @untyped_cst.Expr_Sequence
    | @untyped_cst.List_BlockStatementList => @cst.sequence_items(node)
    _ => []
  }
}

///|
fn unlabelled(
  nodes : Array[@untyped_cst.CstNode],
) -> Array[(String?, @untyped_cst.CstNode)] {
  let result : Array[(String?, @untyped_cst.CstNode)] = []
  for node in nodes {
    result.push((None, node))
  }
  result
}

///|
fn structural_match(
  pattern : @untyped_cst.CstNode,
  candidate : @untyped_cst.CstNode,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  if pattern.kind != candidate.kind {
    return false
  }
  match (pattern.kind, candidate.kind) {
    (@untyped_cst.Leaf(_), @untyped_cst.Leaf(_)) =>
      pattern.kind == candidate.kind
    _ =>
      match_children(
        pattern.kind,
        @cst.semantic_children(pattern),
        @cst.semantic_children(candidate),
        compiled,
        bindings,
      )
  }
}

///|
fn match_children(
  parent_kind : @untyped_cst.NodeKind,
  pattern : Array[(String?, @untyped_cst.CstNode)],
  candidate : Array[(String?, @untyped_cst.CstNode)],
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  let filtered_pattern = without_ignored_fields(parent_kind, pattern, compiled)
  let filtered_candidate = without_ignored_fields(
    parent_kind, candidate, compiled,
  )
  match_children_from(
    parent_kind, filtered_pattern, filtered_candidate, 0, 0, compiled, bindings,
  )
}

///|
fn without_ignored_fields(
  parent_kind : @untyped_cst.NodeKind,
  children : Array[(String?, @untyped_cst.CstNode)],
  compiled : CompiledExprPattern,
) -> Array[(String?, @untyped_cst.CstNode)] {
  let result : Array[(String?, @untyped_cst.CstNode)] = []
  for entry in children {
    if entry.0 is Some(name) &&
      compiled_ignores_field(compiled, parent_kind, name) {
      continue
    }
    result.push(entry)
  }
  result
}

///|
fn match_children_from(
  parent_kind : @untyped_cst.NodeKind,
  pattern : Array[(String?, @untyped_cst.CstNode)],
  candidate : Array[(String?, @untyped_cst.CstNode)],
  pattern_index : Int,
  candidate_index : Int,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  if pattern_index == pattern.length() {
    return candidate_index == candidate.length()
  }
  let (pattern_name, pattern_value) = pattern[pattern_index]
  if pattern_name is None &&
    ellipsis_placeholder(pattern_value, compiled) is Some(placeholder) {
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
      let captured : Array[@untyped_cst.CstNode] = []
      let mut compatible = true
      for offset in 0..<length {
        let (candidate_name, candidate_value) = candidate[candidate_index +
          offset]
        if candidate_name is Some(_) ||
          !ellipsis_candidate_matches(
            pattern_value,
            candidate_value,
            placeholder.kind,
          ) {
          compatible = false
          break
        }
        captured.push(candidate_value)
      }
      if compatible {
        let branch = bindings.copy()
        let bound = placeholder.name == "_" ||
          bind_multiple(branch, placeholder.name, captured)
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
    match_child_node(
      pattern_name, pattern_value, candidate_value, compiled, bindings,
    ) &&
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
fn match_child_node(
  label : String?,
  pattern : @untyped_cst.CstNode,
  candidate : @untyped_cst.CstNode,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  if label == Some("body") &&
    pattern.kind is @untyped_cst.Expr_Block &&
    candidate.kind is @untyped_cst.Expr_Block &&
    sequence_items(pattern) is [single] &&
    match_expr_placeholder(single, candidate, compiled, bindings)
    is Some(result) {
    return result
  }
  match_node(pattern, candidate, compiled, bindings)
}

///|
fn compiled_ignores_field(
  compiled : CompiledExprPattern,
  parent_kind : @untyped_cst.NodeKind,
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
  pattern : Array[(String?, @untyped_cst.CstNode)],
  start : Int,
  compiled : CompiledExprPattern,
) -> Int {
  let mut count = 0
  for index in start..<pattern.length() {
    let (name, value) = pattern[index]
    if !(name is None && ellipsis_placeholder(value, compiled) is Some(_)) {
      count += 1
    }
  }
  count
}

///|
fn is_name_node(node : @untyped_cst.CstNode) -> Bool {
  match node.kind {
    @untyped_cst.Name_Identifier
    | @untyped_cst.Name_Package
    | @untyped_cst.LongIdent_Ident
    | @untyped_cst.LongIdent_Dot
    | @untyped_cst.Name_Binder
    | @untyped_cst.Name_Label
    | @untyped_cst.Name_Type
    | @untyped_cst.Name_Constr
    | @untyped_cst.Name_ConstrId
    | @untyped_cst.Name_Var
    | @untyped_cst.Name_Constructor
    | @untyped_cst.Name_Field
    | @untyped_cst.Name_AliasTarget
    | @untyped_cst.Name_Test
    | @untyped_cst.Accessor_Label => true
    _ => false
  }
}

///|
fn match_name_node(
  pattern : @untyped_cst.CstNode,
  candidate : @untyped_cst.CstNode,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  guard @cst.normalized_name(pattern) is Some(pattern_name) else {
    return false
  }
  guard @cst.normalized_name(candidate) is Some(candidate_name) else {
    return false
  }
  if is_ignore_placeholder(pattern_name) {
    return true
  }
  if single_metavar_name(pattern_name) is Some(logical) &&
    contains_name(compiled.identifier_metavars, logical) {
    if metavariable_qualified_prefix(pattern_name) is Some(_) &&
      !same_metavariable_qualified_prefix(pattern_name, candidate_name) {
      return false
    }
    return bind_value(bindings, logical, candidate)
  }
  pattern_name == candidate_name
}

///|
fn same_metavariable_qualified_prefix(
  pattern : String,
  candidate : String,
) -> Bool {
  guard metavariable_qualified_prefix(pattern) is Some(pattern_prefix) else {
    return false
  }
  let candidate_dot = last_separator(candidate)
  match candidate_dot {
    Some(right) => candidate[:right + 1] == pattern_prefix
    None => false
  }
}

///|
fn last_separator(name : String) -> Int? {
  for index = name.length() - 1; index >= 0; index = index - 1 {
    if name[index] == '.' || name[index] == ':' {
      return Some(index)
    }
  }
  None
}

///|
fn bind_value(
  bindings : @hashmap.HashMap[String, BoundValue],
  name : String,
  value : @untyped_cst.CstNode,
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
fn bound_value_equal(left : BoundValue, right : BoundValue) -> Bool {
  match (left, right) {
    (Single(left), Single(right)) => node_equal_ignoring_loc(left, right)
    (Multiple(left), Multiple(right)) => nodes_equal_ignoring_loc(left, right)
    _ => false
  }
}

///|
fn nodes_equal_ignoring_loc(
  left : Array[@untyped_cst.CstNode],
  right : Array[@untyped_cst.CstNode],
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
  raw_left : @untyped_cst.CstNode,
  raw_right : @untyped_cst.CstNode,
) -> Bool {
  let left = @cst.unwrap_groups(raw_left)
  let right = @cst.unwrap_groups(raw_right)
  match (@cst.normalized_name(left), @cst.normalized_name(right)) {
    (Some(left_name), Some(right_name)) => return left_name == right_name
    _ => ()
  }
  if left.kind != right.kind {
    return false
  }
  match (left.kind, right.kind) {
    (@untyped_cst.Leaf(_), @untyped_cst.Leaf(_)) => left.kind == right.kind
    _ =>
      children_equal_ignoring_loc(
        @cst.semantic_children(left),
        @cst.semantic_children(right),
      )
  }
}

///|
fn children_equal_ignoring_loc(
  left : Array[(String?, @untyped_cst.CstNode)],
  right : Array[(String?, @untyped_cst.CstNode)],
) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for index in 0..<left.length() {
    let (left_name, left_value) = left[index]
    let (right_name, right_value) = right[index]
    if left_name != right_name ||
      !node_equal_ignoring_loc(left_value, right_value) {
      return false
    }
  }
  true
}

///|
fn expr_constant(node : @untyped_cst.CstNode) -> @untyped_cst.CstNode? {
  if node.kind is @untyped_cst.Expr_Constant {
    @cst.constant(node)
  } else {
    None
  }
}

///|
fn pattern_constant(node : @untyped_cst.CstNode) -> @untyped_cst.CstNode? {
  if node.kind is @untyped_cst.Pattern_Constant {
    @cst.constant(node)
  } else {
    None
  }
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
  match parse_single_metavar(raw) {
    Some((name, Some("pat"))) => Some(name)
    _ => None
  }
}

///|
fn is_ignore_placeholder(name : String) -> Bool {
  name == "$_"
}

///|
fn single_metavar_name(raw : String) -> String? {
  parse_single_metavar(raw).map(parsed => parsed.0)
}

///|
fn parse_single_metavar(raw : String) -> (String, String?)? {
  guard metavar_component(raw) is Some(component) else { return None }
  if component.has_prefix("$$$") || component == "$_" {
    return None
  }
  if component.has_prefix("$(") && component.has_suffix(")") {
    let end = component.length() - 1
    for index in 2..<end {
      if component[index] == ':' {
        let name = component[2:index].trim()
        let kind = component[index + 1:end].trim()
        if !name.is_empty() && !kind.is_empty() {
          return Some((name.to_owned(), Some(kind.to_owned())))
        }
        return None
      }
    }
    None
  } else if component.has_prefix("$") && component.length() > 1 {
    Some((component[1:].to_owned(), None))
  } else {
    None
  }
}

///|
fn metavar_component(raw : String) -> String? {
  let mut start = -1
  for index in 0..<raw.length() {
    if raw[index] == '$' {
      start = index
    }
  }
  if start >= 0 {
    Some(raw[start:].to_owned())
  } else {
    None
  }
}

///|
fn metavariable_qualified_prefix(raw : String) -> String? {
  for index = raw.length() - 1; index >= 0; index = index - 1 {
    if raw[index] == '$' {
      if index > 0 {
        return Some(raw[:index].to_owned())
      }
      return None
    }
  }
  None
}
