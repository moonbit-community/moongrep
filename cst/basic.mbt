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
    @untyped_cst.Syntax_Keyword
    | @untyped_cst.Syntax_Delimiter
    | @untyped_cst.Syntax_Separator
    | @untyped_cst.Syntax_Operator
    | @untyped_cst.Syntax_Identifier
    | @untyped_cst.Syntax_Label
    | @untyped_cst.Syntax_Accessor
    | @untyped_cst.Syntax_Literal
    | @untyped_cst.Syntax_Interpolation
    | @untyped_cst.Syntax_Attribute
    | @untyped_cst.Syntax_Comment
    | @untyped_cst.Syntax_Eof
    | @untyped_cst.Syntax_Unexpected => true
    _ => false
  }
}

///|
pub fn is_list_kind(kind : @untyped_cst.NodeKind) -> Bool {
  match kind {
    @untyped_cst.List_ArgumentList
    | @untyped_cst.List_ParameterList
    | @untyped_cst.List_TraitMethodParameterList
    | @untyped_cst.List_TypeDeclParameterList
    | @untyped_cst.List_TypeVarBinderList
    | @untyped_cst.List_ConstructorParameterList
    | @untyped_cst.List_TupleStructTypeList
    | @untyped_cst.List_StructFieldList
    | @untyped_cst.List_TraitMethodList
    | @untyped_cst.List_RecordFieldList
    | @untyped_cst.List_MapFieldList
    | @untyped_cst.List_BlockStatementList
    | @untyped_cst.List_ContinueArgumentList
    | @untyped_cst.List_TupleElementList
    | @untyped_cst.List_TupleTypeList
    | @untyped_cst.List_ArrayElementList
    | @untyped_cst.List_TypeArgumentList
    | @untyped_cst.List_TuplePatternList
    | @untyped_cst.List_ConstructorPatternArgumentList
    | @untyped_cst.List_LexTopPatternList
    | @untyped_cst.List_ArrayPatternList
    | @untyped_cst.List_RecordPatternFieldList
    | @untyped_cst.List_MapPatternFieldList
    | @untyped_cst.List_WhereFieldList
    | @untyped_cst.List_ObjectFieldList
    | @untyped_cst.List_ConstructorList
    | @untyped_cst.List_UsingItemList
    | @untyped_cst.List_ImportPackageList
    | @untyped_cst.List_ExtendItemList
    | @untyped_cst.List_DerivingList
    | @untyped_cst.List_MatchCaseList
    | @untyped_cst.List_LexCaseList
    | @untyped_cst.List_LexScanCaseList
    | @untyped_cst.List_RegexBindingList
    | @untyped_cst.List_LexPatternList
    | @untyped_cst.List_ForBindingList
    | @untyped_cst.List_ForEachBindingList
    | @untyped_cst.List_WithBindingList => true
    _ => false
  }
}

///|
fn is_pure_punctuation_kind(kind : @untyped_cst.NodeKind) -> Bool {
  match kind {
    @untyped_cst.Syntax_Delimiter
    | @untyped_cst.Syntax_Separator
    | @untyped_cst.Syntax_Eof
    | @untyped_cst.Syntax_Comment
    | @untyped_cst.Aggregate_Span
    | @untyped_cst.TrailingMark_Comma
    | @untyped_cst.TrailingMark_Semi
    | @untyped_cst.TrailingMark_None
    | @untyped_cst.ConstructorExtraInfo_None
    | @untyped_cst.ConstructorExtraInfo_Package
    | @untyped_cst.ConstructorExtraInfo_TypeName
    | @untyped_cst.ConstructorExtraInfo_TypeNameWithConstrPackage => true
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
    @untyped_cst.Syntax_Attribute =>
      for entry in syntax.children {
        if entry.1.kind
          is (@untyped_cst.Attribute_Simple | @untyped_cst.Attribute_Qualified) {
          result.push((outer_label, entry.1))
        }
      }
    @untyped_cst.Syntax_Interpolation =>
      for entry in syntax.children {
        match entry.1.kind {
          @untyped_cst.InterpSegment_Literal
          | @untyped_cst.InterpSegment_Source =>
            result.push((semantic_label(entry.0), entry.1))
          _ => ()
        }
      }
    @untyped_cst.Syntax_Identifier | @untyped_cst.Syntax_Label =>
      if raw_child(parent, "semantic_name") is None {
        if raw_child(syntax, "name_value") is Some(name) {
          result.push((outer_label, name))
        }
      }
    @untyped_cst.Syntax_Accessor =>
      if raw_child(parent, "semantic_name") is None &&
        raw_child(parent, "field") is None {
        if raw_child(syntax, "accessor") is Some(accessor) {
          result.push((outer_label, accessor))
        } else if raw_child(syntax, "name_value") is Some(name) {
          result.push((outer_label, name))
        }
      }
    @untyped_cst.Syntax_Operator => {
      let duplicate = raw_child(parent, "operator")
        .map(node => !is_syntax_kind(node.kind))
        .unwrap_or(false)
      if !duplicate {
        if raw_child(syntax, "operator") is Some(operator) {
          result.push((outer_label, operator))
        }
      }
    }
    @untyped_cst.Syntax_Literal =>
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
    @untyped_cst.Pattern_Tuple => {
      guard raw_child(node, "pattern_group") is Some(_) else { return node }
      guard raw_child(node, "body") is Some(body) else { return node }
      match raw_children(body, "item") {
        [inner] => unwrap_groups(inner)
        _ => node
      }
    }
    @untyped_cst.Type_Group => {
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
pub fn children(
  node : @untyped_cst.CstNode,
  label : String,
) -> Array[@untyped_cst.CstNode] {
  let result : Array[@untyped_cst.CstNode] = []
  for entry in semantic_children(node) {
    if entry.0 == Some(label) {
      result.push(entry.1)
    }
  }
  result
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
pub fn first_child(node : @untyped_cst.CstNode) -> @untyped_cst.CstNode? {
  match semantic_children(node) {
    [(_, first), ..] => Some(first)
    [] => None
  }
}

///|
pub fn payload(node : @untyped_cst.CstNode) -> @untyped_cst.NodePayload? {
  match node.kind {
    @untyped_cst.Leaf(value) => Some(value)
    _ =>
      if raw_child(node, "payload") is Some(child) {
        match child.kind {
          @untyped_cst.Leaf(value) => Some(value)
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
    Some(@untyped_cst.NodePayload::String(value)) => Some(value)
    _ => None
  }
}

///|
pub fn bool_payload(node : @untyped_cst.CstNode) -> Bool? {
  match payload(node) {
    Some(@untyped_cst.NodePayload::Bool(value)) => Some(value)
    _ => None
  }
}

///|
pub fn int_payload(node : @untyped_cst.CstNode) -> Int? {
  match payload(node) {
    Some(@untyped_cst.NodePayload::Int(value)) => Some(value)
    _ => None
  }
}

///|
pub fn normalized_long_ident(node : @untyped_cst.CstNode) -> String? {
  guard node.kind is (@untyped_cst.LongIdent_Ident | @untyped_cst.LongIdent_Dot) else {
    return None
  }
  let components = raw_children(node, "component")
  guard components is [first, ..] else { return None }
  guard string_payload(first) is Some(first_name) else { return None }
  if components.length() == 1 {
    return Some(first_name)
  }
  guard string_payload(components.last().unwrap()) is Some(last_name) else {
    return None
  }
  if first.kind is @untyped_cst.Name_Package {
    Some("@\{first_name}.\{last_name}")
  } else {
    Some("\{first_name}::\{last_name}")
  }
}

///|
pub fn normalized_name(node : @untyped_cst.CstNode) -> String? {
  match node.kind {
    @untyped_cst.Syntax_Identifier
    | @untyped_cst.Syntax_Label
    | @untyped_cst.Syntax_Accessor =>
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
    @untyped_cst.Name_Identifier
    | @untyped_cst.Name_Package
    | @untyped_cst.Attribute_Name
    | @untyped_cst.Attribute_Qualifier
    | @untyped_cst.Attribute_RawPayload
    | @untyped_cst.Operator_Infix
    | @untyped_cst.Operator_Augmented
    | @untyped_cst.Operator_UnaryPlus
    | @untyped_cst.Operator_UnaryMinus
    | @untyped_cst.Operator_UnaryNot
    | @untyped_cst.Accessor_Label => string_payload(node)
    @untyped_cst.LongIdent_Ident | @untyped_cst.LongIdent_Dot =>
      normalized_long_ident(node)
    @untyped_cst.Name_Binder
    | @untyped_cst.Name_Label
    | @untyped_cst.Name_Type
    | @untyped_cst.Name_Constr
    | @untyped_cst.Name_ConstrId
    | @untyped_cst.Name_Var
    | @untyped_cst.Name_Constructor
    | @untyped_cst.Name_Field
    | @untyped_cst.Name_AliasTarget
    | @untyped_cst.Name_Test =>
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
    @untyped_cst.Name_Identifier
    | @untyped_cst.Name_Package
    | @untyped_cst.Name_Binder
    | @untyped_cst.Name_Label
    | @untyped_cst.Name_Type
    | @untyped_cst.Name_Constr
    | @untyped_cst.Name_ConstrId
    | @untyped_cst.Name_Var
    | @untyped_cst.Name_Constructor
    | @untyped_cst.Name_Field
    | @untyped_cst.Name_AliasTarget
    | @untyped_cst.Name_Test => Some(node)
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
  guard node.kind is @untyped_cst.Expr_Ident else { return None }
  name_node(node).bind(normalized_name)
}

///|
pub fn normalized_pattern_identifier_name(
  node : @untyped_cst.CstNode,
) -> String? {
  guard node.kind is @untyped_cst.Pattern_Var else { return None }
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
    @untyped_cst.Argument_Labelled
    | @untyped_cst.Argument_LabelledPun
    | @untyped_cst.Argument_LabelledOption
    | @untyped_cst.Argument_LabelledOptionPun =>
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
    @untyped_cst.Expr_Block | @untyped_cst.Expr_Sequence =>
      if raw_child(node, "body") is Some(body) {
        sequence_items(body)
      } else {
        []
      }
    @untyped_cst.List_BlockStatementList => raw_children(node, "item")
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
  if node.kind is (@untyped_cst.Missing | @untyped_cst.Error) {
    return Some(node)
  }
  for entry in node.children {
    if first_recovery_node(entry.1) is Some(recovery) {
      return Some(recovery)
    }
  }
  None
}
