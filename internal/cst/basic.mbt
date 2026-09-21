///|
/// Return the first raw child with `label`.
pub fn raw_child(
  node : @untyped_cst.CstNode,
  label : String,
) -> @untyped_cst.CstNode? {
  for entry in node.children {
    if entry.0 == Some(label) {
      return Some(entry.1)
    }
  }
  None
}

///|
/// Return all raw children with `label`.
pub fn raw_children(
  node : @untyped_cst.CstNode,
  label : String,
) -> Array[@untyped_cst.CstNode] {
  let result : Array[@untyped_cst.CstNode] = []
  for entry in node.children {
    if entry.0 == Some(label) {
      result.push(entry.1)
    }
  }
  result
}

///|
pub fn is_syntax_kind(kind : @untyped_cst.NodeKind) -> Bool {
  match kind {
    Syntax_Keyword
    | Syntax_Delimiter
    | Syntax_Separator
    | Syntax_Operator
    | Syntax_Identifier
    | Syntax_Label
    | Syntax_Accessor
    | Syntax_Literal
    | Syntax_Interpolation
    | Syntax_Attribute
    | Syntax_Comment
    | Syntax_Eof
    | Syntax_Unexpected => true
    _ => false
  }
}

///|
fn is_pure_punctuation_kind(kind : @untyped_cst.NodeKind) -> Bool {
  match kind {
    Syntax_Delimiter
    | Syntax_Separator
    | Syntax_Eof
    | Syntax_Comment
    | Aggregate_Span
    | TrailingMark_Comma
    | TrailingMark_Semi
    | TrailingMark_None
    | ConstructorExtraInfo_None
    | ConstructorExtraInfo_Package
    | ConstructorExtraInfo_TypeName
    | ConstructorExtraInfo_TypeNameWithConstrPackage => true
    _ => false
  }
}

///|
fn is_location_label(label : String?) -> Bool {
  if label is Some(name) {
    name.has_suffix("_loc")
  } else {
    false
  }
}

///|
fn semantic_label(label : String?) -> String? {
  match label {
    Some("semantic_name") => Some("name")
    Some("semantic_constant") => Some("constant")
    Some("item") => None
    other => other
  }
}

///|
fn append_syntax_semantics(
  result : Array[(String?, @untyped_cst.CstNode)],
  outer_label : String?,
  parent : @untyped_cst.CstNode,
  syntax : @untyped_cst.CstNode,
) -> Unit {
  match syntax.kind {
    Syntax_Attribute =>
      for entry in syntax.children {
        if entry.1.kind
          is (Attribute_Simple | Attribute_Qualified) {
          result.push((outer_label, entry.1))
        }
      }
    Syntax_Interpolation =>
      for entry in syntax.children {
        match entry.1.kind {
          InterpSegment_Literal
          | InterpSegment_Source =>
            result.push((semantic_label(entry.0), entry.1))
          _ => ()
        }
      }
    Syntax_Identifier | Syntax_Label =>
      if raw_child(parent, "semantic_name") is None {
        if raw_child(syntax, "name_value") is Some(name) {
          result.push((outer_label, name))
        }
      }
    Syntax_Accessor =>
      if raw_child(parent, "semantic_name") is None &&
        raw_child(parent, "field") is None {
        if raw_child(syntax, "accessor") is Some(accessor) {
          result.push((outer_label, accessor))
        } else if raw_child(syntax, "name_value") is Some(name) {
          result.push((outer_label, name))
        }
      }
    Syntax_Operator => {
      let duplicate = raw_child(parent, "operator")
        .map(node => !is_syntax_kind(node.kind))
        .unwrap_or(false)
      if !duplicate {
        if raw_child(syntax, "operator") is Some(operator) {
          result.push((outer_label, operator))
        }
      }
    }
    Syntax_Literal =>
      if raw_child(parent, "semantic_constant") is None {
        if raw_child(syntax, "constant") is Some(constant) {
          result.push((outer_label, constant))
        }
      }
    _ => ()
  }
}

///|
/// Return children that carry language semantics rather than concrete syntax.
///
/// Tokens, comments (including docstrings), delimiters, separators, location
/// anchors, and duplicate token metadata are omitted. List items are returned
/// without a field label, matching their ordered-list semantics.
pub fn semantic_children(
  node : @untyped_cst.CstNode,
) -> Array[(String?, @untyped_cst.CstNode)] {
  let result : Array[(String?, @untyped_cst.CstNode)] = []
  let has_semantic_constant = raw_child(node, "semantic_constant") is Some(_)
  for entry in node.children {
    let (label, child) = entry
    if label == Some("doc") ||
      is_location_label(label) ||
      (
        node.kind is InterpSegment_Source &&
        label == Some("payload")
      ) ||
      is_pure_punctuation_kind(child.kind) {
      continue
    }
    if is_syntax_kind(child.kind) {
      append_syntax_semantics(result, label, node, child)
      continue
    }
    if has_semantic_constant && label == Some("constant") {
      continue
    }
    result.push((semantic_label(label), unwrap_groups(child)))
  }
  result
}

///|
/// Remove pattern/type grouping nodes that exist only in the CST.
pub fn unwrap_groups(node : @untyped_cst.CstNode) -> @untyped_cst.CstNode {
  match node.kind {
    Pattern_Tuple => {
      guard raw_child(node, "pattern_group") is Some(_) else { return node }
      guard raw_child(node, "body") is Some(body) else { return node }
      match raw_children(body, "item") {
        [inner] => unwrap_groups(inner)
        _ => node
      }
    }
    Type_Group => {
      guard raw_child(node, "body") is Some(body) else {
        for entry in node.children {
          if entry.1.kind.is_type() {
            return unwrap_groups(entry.1)
          }
        }
        return node
      }
      match raw_children(body, "item") {
        [inner] => unwrap_groups(inner)
        _ => node
      }
    }
    _ => node
  }
}

///|
pub fn child(
  node : @untyped_cst.CstNode,
  label : String,
) -> @untyped_cst.CstNode? {
  for entry in semantic_children(node) {
    if entry.0 == Some(label) {
      return Some(entry.1)
    }
  }
  None
}

///|
pub fn items(node : @untyped_cst.CstNode) -> Array[@untyped_cst.CstNode] {
  let result : Array[@untyped_cst.CstNode] = []
  for entry in semantic_children(node) {
    if entry.0 is None {
      result.push(entry.1)
    }
  }
  result
}

///|
pub fn payload(node : @untyped_cst.CstNode) -> @untyped_cst.NodePayload? {
  match node.kind {
    Leaf(value) => Some(value)
    _ =>
      if raw_child(node, "payload") is Some(child) {
        match child.kind {
          Leaf(value) => Some(value)
          _ => None
        }
      } else {
        None
      }
  }
}

///|
pub fn string_payload(node : @untyped_cst.CstNode) -> String? {
  match payload(node) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
pub fn bool_payload(node : @untyped_cst.CstNode) -> Bool? {
  match payload(node) {
    Some(Bool(value)) => Some(value)
    _ => None
  }
}

///|
pub fn int_payload(node : @untyped_cst.CstNode) -> Int? {
  match payload(node) {
    Some(Int(value)) => Some(value)
    _ => None
  }
}

///|
pub fn normalized_long_ident(node : @untyped_cst.CstNode) -> String? {
  guard node.kind is (LongIdent_Ident | LongIdent_Dot) else {
    return None
  }
  let components = raw_children(node, "component")
  guard !components.is_empty() else { return None }
  let groups : Array[String] = []
  let mut package_name : String? = None
  for component in components {
    guard string_payload(component) is Some(name) else { return None }
    if component.kind is Name_Package {
      if package_name is Some(_) {
        return None
      }
      package_name = Some(name)
    } else if package_name is Some(package_value) {
      groups.push("@\{package_value}.\{name}")
      package_name = None
    } else {
      groups.push(name)
    }
  }
  guard package_name is None && !groups.is_empty() else { return None }
  Some(groups.join("::"))
}

///|
fn normalized_constructor_identity(node : @untyped_cst.CstNode) -> String? {
  if node.kind is Expr_Constr &&
    raw_child(node, "type") is Some(type_name) {
    guard normalized_constructor_identity(type_name) is Some(prefix) else {
      return None
    }
    guard name_node(node).bind(normalized_name) is Some(constructor_name) else {
      return None
    }
    Some("\{prefix}::\{constructor_name}")
  } else {
    name_node(node).bind(normalized_name)
  }
}

///|
pub fn normalized_name(node : @untyped_cst.CstNode) -> String? {
  match node.kind {
    Expr_Constr | Pattern_Constr =>
      normalized_constructor_identity(node)
    Syntax_Identifier
    | Syntax_Label
    | Syntax_Accessor =>
      if string_payload(node) is Some(value) {
        Some(value)
      } else {
        for entry in node.children {
          if normalized_name(entry.1) is Some(value) {
            return Some(value)
          }
        }
        None
      }
    Name_Identifier
    | Name_Package
    | Attribute_Name
    | Attribute_Qualifier
    | Attribute_RawPayload
    | Operator_Infix
    | Operator_Augmented
    | Operator_UnaryPlus
    | Operator_UnaryMinus
    | Operator_UnaryNot
    | Accessor_Label => string_payload(node)
    LongIdent_Ident | LongIdent_Dot =>
      normalized_long_ident(node)
    Name_Binder
    | Name_Label
    | Name_Type
    | Name_Constr
    | Name_ConstrId
    | Name_Var
    | Name_Constructor
    | Name_Field
    | Name_AliasTarget
    | Name_Test =>
      if raw_child(node, "long_ident") is Some(name) {
        normalized_long_ident(name)
      } else {
        string_payload(node)
      }
    _ => None
  }
}

///|
pub fn name_node(node : @untyped_cst.CstNode) -> @untyped_cst.CstNode? {
  match node.kind {
    Name_Identifier
    | Name_Package
    | Name_Binder
    | Name_Label
    | Name_Type
    | Name_Constr
    | Name_ConstrId
    | Name_Var
    | Name_Constructor
    | Name_Field
    | Name_AliasTarget
    | Name_Test => Some(node)
    _ =>
      if raw_child(node, "semantic_name") is Some(name) {
        Some(name)
      } else {
        raw_child(node, "name")
      }
  }
}

///|
pub fn normalized_expr_identifier_name(node : @untyped_cst.CstNode) -> String? {
  guard node.kind is Expr_Ident else { return None }
  name_node(node).bind(normalized_name)
}

///|
pub fn normalized_pattern_identifier_name(
  node : @untyped_cst.CstNode,
) -> String? {
  guard node.kind is Pattern_Var else { return None }
  name_node(node).bind(normalized_name)
}

///|
pub fn constant(node : @untyped_cst.CstNode) -> @untyped_cst.CstNode? {
  if node.kind.is_constant() {
    Some(node)
  } else {
    raw_child(node, "semantic_constant")
  }
}

///|
pub fn operator_name(node : @untyped_cst.CstNode) -> String? {
  if raw_child(node, "operator") is Some(operator) {
    normalized_name(operator)
  } else if raw_child(node, "op") is Some(wrapper) {
    raw_child(wrapper, "operator").bind(normalized_name)
  } else {
    None
  }
}

///|
pub fn argument_value(node : @untyped_cst.CstNode) -> @untyped_cst.CstNode? {
  guard node.kind.is_argument() else { return None }
  raw_child(node, "expr")
}

///|
pub fn argument_label_name(node : @untyped_cst.CstNode) -> String? {
  match node.kind {
    Argument_Labelled
    | Argument_LabelledPun
    | Argument_LabelledOption
    | Argument_LabelledOptionPun =>
      name_node(node).bind(normalized_name)
    _ => None
  }
}

///|
pub fn expression_nodes(
  root : @untyped_cst.CstNode,
) -> Array[@untyped_cst.CstNode] {
  let result : Array[@untyped_cst.CstNode] = []
  for entry in root.children {
    if entry.1.kind.is_expr() {
      result.push(unwrap_groups(entry.1))
    }
  }
  result
}

///|
/// Return the ordered statements stored by a block or sequence expression.
/// The parser wraps an all-expression block in `Expr_Sequence`, while blocks
/// beginning with a binding keep the list directly under `Expr_Block`.
pub fn sequence_items(
  node : @untyped_cst.CstNode,
) -> Array[@untyped_cst.CstNode] {
  match node.kind {
    Expr_Block | Expr_Sequence =>
      if raw_child(node, "body") is Some(body) {
        sequence_items(body)
      } else {
        []
      }
    List_BlockStatementList => raw_children(node, "item")
    _ => []
  }
}

///|
/// Return the single expression node, or the `Expression` container when the
/// fragment contains a statement sequence.
pub fn expression_root(root : @untyped_cst.CstNode) -> @untyped_cst.CstNode {
  match expression_nodes(root) {
    [expr] => expr
    _ => root
  }
}

///|
pub fn toplevel_nodes(
  root : @untyped_cst.CstNode,
) -> Array[@untyped_cst.CstNode] {
  let result : Array[@untyped_cst.CstNode] = []
  for entry in root.children {
    if entry.1.kind.is_impl() {
      result.push(entry.1)
    }
  }
  result
}

///|
pub fn source_text(node : @untyped_cst.CstNode, source : String) -> String {
  source[node.source_span.0:node.source_span.1].to_owned()
}

///|
/// Return the first parser recovery node, if the CST is not fully valid.
pub fn first_recovery_node(
  node : @untyped_cst.CstNode,
) -> @untyped_cst.CstNode? {
  if node.kind is (Missing | Error) {
    return Some(node)
  }
  for entry in node.children {
    if first_recovery_node(entry.1) is Some(recovery) {
      return Some(recovery)
    }
  }
  None
}
