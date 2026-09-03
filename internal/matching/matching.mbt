///|
/// Attempts one root-level match of `compiled.cst` against `candidate`.
pub fn match_expr_pattern(
  compiled : CompiledExprPattern,
  candidate : @untyped_cst.CstNode,
) -> ExprMatch? {
  match_expr_pattern_candidate(compiled, match_candidate_from_node(candidate))
}

///|
/// Attempts one root-level match against a semantic expression candidate.
pub fn match_expr_pattern_candidate(
  compiled : CompiledExprPattern,
  candidate : @cst.ExprMatchCandidate,
) -> ExprMatch? {
  let bindings : @hashmap.HashMap[String, BoundValue] = HashMap([])
  match_expr_pattern_candidate_with_bindings(compiled, candidate, bindings)
}

///|
/// Matches a semantic expression candidate with a copied caller-supplied
/// binding context.
pub fn match_expr_pattern_candidate_with_bindings(
  compiled : CompiledExprPattern,
  candidate : @cst.ExprMatchCandidate,
  initial_bindings : @hashmap.HashMap[String, BoundValue],
) -> ExprMatch? {
  let bindings = initial_bindings.copy()
  match candidate {
    @cst.Direct(node) => {
      let pattern = @cst.unwrap_groups(compiled.cst)
      let matched = if pattern.kind is Expression &&
        match_sequence_continuation_tail(
          @cst.expression_nodes(pattern),
          [node],
          compiled,
          bindings,
        )
        is Some(result) {
        result
      } else {
        match_node(pattern, node, compiled, bindings)
      }
      if matched {
        Some({ root: node, bindings, loc: node.loc, })
      } else {
        None
      }
    }
    @cst.Sequence(items) => {
      guard items is [first, ..] else { return None }
      if match_sequence_candidate(compiled.cst, items, compiled, bindings) {
        let loc = match items {
          [_, .., last] => first.loc.merge(last.loc)
          [_] => first.loc
          [] => first.loc
        }
        Some({ root: first, bindings, loc, })
      } else {
        None
      }
    }
  }
}

///|
fn match_candidate_from_node(
  candidate : @untyped_cst.CstNode,
) -> @cst.ExprMatchCandidate {
  if candidate.kind is @untyped_cst.Expression {
    @cst.Sequence(@cst.expression_nodes(candidate))
  } else {
    @cst.Direct(candidate)
  }
}

///|
fn match_sequence_candidate(
  raw_pattern : @untyped_cst.CstNode,
  candidate_items : Array[@untyped_cst.CstNode],
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  let pattern = @cst.unwrap_groups(raw_pattern)
  if pattern.kind is @untyped_cst.Expression {
    let pattern_items = @cst.expression_nodes(pattern)
    // Keep the fixed-length path so one-statement named and special tails keep
    // their existing `Single` binding. Empty and multi-statement tails need
    // suffix handling because the parser exposes their expressions as siblings.
    if pattern_items.length() != candidate_items.length() &&
      match_sequence_continuation_tail(
        pattern_items, candidate_items, compiled, bindings,
      )
      is Some(result) {
      return result
    }
    return match_children(
      pattern.kind,
      unlabelled(pattern_items),
      unlabelled(candidate_items),
      compiled,
      bindings,
    )
  }
  if pattern.kind is (@untyped_cst.Expr_Let | @untyped_cst.Expr_Guard) {
    return candidate_items is [first, ..] &&
      first.kind == pattern.kind &&
      match_node(pattern, first, compiled, bindings)
  }
  false
}

///|
fn match_sequence_continuation_tail(
  pattern_items : Array[@untyped_cst.CstNode],
  candidate_items : Array[@untyped_cst.CstNode],
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool? {
  guard pattern_items is [pattern_header, pattern_body] else { return None }
  guard sequence_continuation_owner(pattern_header.kind) else { return None }
  guard continuation_tail_name(pattern_body, compiled) is Some(tail_name) else {
    return None
  }
  guard candidate_items is [candidate_header, ..] else { return Some(false) }
  guard candidate_header.kind == pattern_header.kind else { return None }
  let branch = bindings.copy()
  guard match_node(pattern_header, candidate_header, compiled, branch) else {
    return Some(false)
  }
  if compiled.metavars.is_wildcard(tail_name) {
    replace_bindings(bindings, branch)
    return Some(true)
  }
  let continuation = candidate_items[1:].to_owned()
  if bind_multiple(branch, tail_name, continuation) {
    replace_bindings(bindings, branch)
    Some(true)
  } else {
    Some(false)
  }
}

///|
fn continuation_tail_name(
  pattern : @untyped_cst.CstNode,
  compiled : CompiledExprPattern,
) -> String? {
  guard pattern.kind is Expr_Ident else { return None }
  guard @cst.normalized_expr_identifier_name(pattern) is Some(name) else {
    return None
  }
  match compiled.metavars.resolve(name) {
    Some(ResolvedWildcard(_)) => Some(name)
    Some(ResolvedNamed({ name, kind: Expr, })) => Some(name)
    Some(ResolvedSpecialExpr(name)) => Some(name)
    _ => None
  }
}

///|
fn sequence_continuation_owner(kind : @untyped_cst.NodeKind) -> Bool {
  kind
  is (Expr_Let
  | Expr_LetMut
  | Expr_LetFn
  | Expr_LetAnd
  | Expr_Guard
  | Expr_Defer)
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
  if match_split_pattern_constructor_identity(
      pattern, candidate, compiled, bindings,
    )
    is Some(result) {
    return result
  }
  if match_constructor_identity_placeholder(
      pattern, candidate, compiled, bindings,
    )
    is Some(result) {
    return result
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
fn match_split_pattern_constructor_identity(
  pattern : @untyped_cst.CstNode,
  candidate : @untyped_cst.CstNode,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool? {
  guard pattern.kind is @untyped_cst.Pattern_Constr else { return None }
  let pattern_names = @cst.raw_children(pattern, "name")
  guard pattern_names.length() > 1 else { return None }
  let mut has_identifier_placeholder = false
  for name in pattern_names {
    if @cst.normalized_name(name).bind(raw => {
        resolved_named_metavar(compiled, raw, Identifier)
      })
      is Some(_) {
      has_identifier_placeholder = true
      break
    }
  }
  guard has_identifier_placeholder else { return None }
  guard candidate.kind is @untyped_cst.Pattern_Constr else {
    return Some(false)
  }
  let candidate_names = @cst.raw_children(candidate, "name")
  guard pattern_names.length() == candidate_names.length() else {
    return Some(false)
  }
  for index in 0..<pattern_names.length() {
    if !match_name_node(
        pattern_names[index],
        candidate_names[index],
        compiled,
        bindings,
      ) {
      return Some(false)
    }
  }
  Some(
    match_children(
      pattern.kind,
      constructor_children_without_name(pattern),
      constructor_children_without_name(candidate),
      compiled,
      bindings,
    ),
  )
}

///|
fn constructor_children_without_name(
  node : @untyped_cst.CstNode,
) -> Array[(String?, @untyped_cst.CstNode)] {
  let result : Array[(String?, @untyped_cst.CstNode)] = []
  for entry in @cst.semantic_children(node) {
    if entry.0 != Some("name") {
      result.push(entry)
    }
  }
  result
}

///|
fn match_constructor_identity_placeholder(
  pattern : @untyped_cst.CstNode,
  candidate : @untyped_cst.CstNode,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool? {
  guard pattern.kind is (@untyped_cst.Expr_Constr | @untyped_cst.Pattern_Constr) else {
    return None
  }
  guard @cst.raw_child(pattern, "type") is None else { return None }
  guard @cst.normalized_name(pattern) is Some(pattern_name) else { return None }
  guard metavariable_qualified_prefix(pattern_name) is None else { return None }
  guard resolved_named_metavar(compiled, pattern_name, Identifier)
    is Some(logical) else {
    return None
  }
  guard candidate.kind == pattern.kind &&
    bind_value(bindings, logical, constructor_identity_binding_node(candidate)) else {
    return Some(false)
  }
  if pattern.kind is @untyped_cst.Pattern_Constr {
    Some(
      match_children(
        pattern.kind,
        constructor_children_without_name(pattern),
        constructor_children_without_name(candidate),
        compiled,
        bindings,
      ),
    )
  } else {
    Some(true)
  }
}

///|
fn constructor_identity_binding_node(
  candidate : @untyped_cst.CstNode,
) -> @untyped_cst.CstNode {
  if candidate.kind is @untyped_cst.Pattern_Constr {
    @cst.name_node(candidate).unwrap_or(candidate)
  } else {
    candidate
  }
}

///|
fn match_type_placeholder(
  pattern : @untyped_cst.CstNode,
  candidate : @untyped_cst.CstNode,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool? {
  guard type_placeholder_raw(pattern) is Some(raw) else { return None }
  guard resolved_named_metavar(compiled, raw, Type) is Some(name) else {
    return None
  }
  Some(candidate.kind.is_type() && bind_value(bindings, name, candidate))
}

///|
fn type_placeholder_raw(node : @untyped_cst.CstNode) -> String? {
  guard node.kind is @untyped_cst.Type_Name else { return None }
  for entry in @cst.semantic_children(node) {
    if entry.1.kind.is_type() {
      return None
    }
  }
  @cst.name_node(node).bind(@cst.normalized_name)
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
  guard argument_placeholder_raw(pattern) is Some(raw) else { return None }
  if resolved_named_metavar(compiled, raw, Argument) is Some(name) {
    Some(candidate.kind.is_argument() && bind_value(bindings, name, candidate))
  } else {
    None
  }
}

///|
fn argument_placeholder_raw(node : @untyped_cst.CstNode) -> String? {
  guard node.kind is @untyped_cst.Argument_Positional else { return None }
  @cst.argument_value(node).bind(@cst.normalized_expr_identifier_name)
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
  if metavar_component(name) is Some(component) &&
    component != name &&
    compiled.metavars.is_wildcard(component) {
    return Some(false)
  }
  match compiled.metavars.resolve(name) {
    Some(ResolvedWildcard(_)) => Some(true)
    Some(ResolvedSpecialExpr(logical)) =>
      Some(bind_value(bindings, logical, candidate))
    Some(ResolvedNamed({ name: logical, kind: Expr, })) =>
      Some(bind_value(bindings, logical, candidate))
    Some(ResolvedNamed({ name: logical, kind: Identifier, })) =>
      match
        (
          @cst.normalized_expr_identifier_name(candidate),
          @cst.name_node(candidate),
        ) {
        (Some(candidate_normalized_name), Some(candidate_name)) =>
          if metavariable_qualified_prefix(name) is Some(_) &&
            !same_metavariable_qualified_prefix(name, candidate_normalized_name) {
            Some(false)
          } else {
            Some(bind_value(bindings, logical, candidate_name))
          }
        _ => Some(false)
      }
    Some(ResolvedNamed({ name: logical, kind: Constant, })) =>
      if expr_constant(candidate) is Some(constant) {
        Some(bind_value(bindings, logical, constant))
      } else {
        Some(false)
      }
    _ => None
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
  match compiled.metavars.resolve(name) {
    Some(ResolvedWildcard(_)) => Some(true)
    Some(ResolvedNamed({ name: logical, kind: Pattern, })) =>
      Some(bind_value(bindings, logical, candidate))
    Some(ResolvedNamed({ name: logical, kind: Identifier, })) =>
      match
        (
          @cst.normalized_pattern_identifier_name(candidate),
          @cst.name_node(candidate),
        ) {
        (Some(_), Some(candidate_name)) =>
          Some(bind_value(bindings, logical, candidate_name))
        _ => Some(false)
      }
    Some(ResolvedNamed({ name: logical, kind: Constant, })) =>
      if pattern_constant(candidate) is Some(constant) {
        Some(bind_value(bindings, logical, constant))
      } else {
        Some(false)
      }
    _ => None
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
  if pattern_items.length() != candidate_items.length() &&
    match_sequence_continuation_tail(
      pattern_items, candidate_items, compiled, bindings,
    )
    is Some(result) {
    return result
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
  match compiled.metavars.resolve(pattern_name) {
    Some(ResolvedWildcard(_)) => return true
    Some(ResolvedNamed({ name: logical, kind: Identifier, })) => {
      if metavariable_qualified_prefix(pattern_name) is Some(_) &&
        !same_metavariable_qualified_prefix(pattern_name, candidate_name) {
        return false
      }
      return bind_value(bindings, logical, candidate)
    }
    _ => ()
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
  if candidate_dot is Some(right) {
    candidate[:right + 1] == pattern_prefix
  } else {
    false
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
  let value : BoundValue = Single(value)
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
  if normalized_identity_node(left) && normalized_identity_node(right) {
    match (@cst.normalized_name(left), @cst.normalized_name(right)) {
      (Some(left_name), Some(right_name)) => return left_name == right_name
      _ => ()
    }
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
fn normalized_identity_node(node : @untyped_cst.CstNode) -> Bool {
  is_name_node(node) || node.kind is @untyped_cst.Expr_Constr
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
fn resolved_named_metavar(
  compiled : CompiledExprPattern,
  raw : String,
  kind : MetavarKind,
) -> String? {
  match compiled.metavars.resolve(raw) {
    Some(ResolvedNamed(entry)) if entry.kind == kind => Some(entry.name)
    _ => None
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
