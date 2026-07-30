///|
priv enum EllipsisItemSlot {
  EllipsisExprSlot
  EllipsisArgumentSlot
  EllipsisPatternSlot
  EllipsisConstrPatternArgumentSlot
  EllipsisArrayPatternSlot
  EllipsisTypeSlot
  EllipsisParameterSlot
  EllipsisSpreadableExprSlot
}

///|
priv struct EllipsisOccurrence {
  name : String
  explicit_kind : @matching.EllipsisMetavarKind?
  slot : EllipsisItemSlot
}

///|
fn compile_ellipsis_metavars(
  path : String,
  context : String,
  ast : @untyped_ast.Node,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
  constant_metavars : Array[String],
  arg_metavars : Array[String],
  type_metavars : Array[String],
  pattern_metavars : Array[String],
) -> Array[@matching.EllipsisMetavar] raise {
  let occurrences : Array[EllipsisOccurrence] = []
  collect_ellipsis_occurrences(path, context, ast, occurrences)
  let explicit_kinds : Map[String, @matching.EllipsisMetavarKind] = Map([])
  for occurrence in occurrences {
    if occurrence.name != "_" {
      validate_declared_metavar(path, context, occurrence.name, true)
      if array_contains(expr_metavars, occurrence.name) ||
        array_contains(identifier_metavars, occurrence.name) ||
        array_contains(constant_metavars, occurrence.name) ||
        array_contains(arg_metavars, occurrence.name) ||
        array_contains(type_metavars, occurrence.name) ||
        array_contains(pattern_metavars, occurrence.name) {
        raise RuleLoadError::InvalidRule(
          path~,
          info="\{shape_context_name(context)} cannot use \{occurrence.name} as both an ellipsis metavar and a single-node metavar",
        )
      }
      if occurrence.explicit_kind is Some(kind) {
        if explicit_kinds.get(occurrence.name) is Some(previous) &&
          previous != kind {
          raise RuleLoadError::InvalidRule(
            path~,
            info="\{shape_context_name(context)} declares ellipsis metavar \{occurrence.name} as multiple metavar kinds",
          )
        }
        explicit_kinds[occurrence.name] = kind
      }
    }
  }
  let result : Array[@matching.EllipsisMetavar] = []
  for occurrence in occurrences {
    let kind = if occurrence.name != "_" &&
      explicit_kinds.get(occurrence.name) is Some(explicit) {
      explicit
    } else {
      occurrence.explicit_kind.unwrap_or(AnyItem)
    }
    if !ellipsis_kind_allowed_in_slot(kind, occurrence.slot) {
      raise RuleLoadError::InvalidRule(
        path~,
        info="\{shape_context_name(context)} uses ellipsis kind \{ellipsis_kind_text(kind)} in an incompatible ordered-list item position",
      )
    }
    if occurrence.name != "_" &&
      !ellipsis_metavars_contain(result, occurrence.name) {
      result.push({ name: occurrence.name, kind })
    }
  }
  result
}

///|
fn collect_ellipsis_occurrences(
  path : String,
  context : String,
  node : @untyped_ast.Node,
  occurrences : Array[EllipsisOccurrence],
) -> Unit raise {
  if ellipsis_direct_raw(node) is Some(raw) {
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{shape_context_name(context)} uses ellipsis metavar \{raw} outside a complete ordered AST list item",
    )
  }
  for child_entry in node.children {
    let (name, child) = child_entry
    if name is None &&
      ellipsis_item_occurrence(path, context, child) is Some(occurrence) {
      occurrences.push(occurrence)
    } else {
      collect_ellipsis_occurrences(path, context, child, occurrences)
    }
  }
}

///|
fn ellipsis_item_occurrence(
  path : String,
  context : String,
  item : @untyped_ast.Node,
) -> EllipsisOccurrence? raise {
  if ellipsis_direct_raw(item) is Some(raw) {
    let slot = match item.kind {
      Expr_Ident => EllipsisExprSlot
      Pattern_Var => EllipsisPatternSlot
      Type_Name => EllipsisTypeSlot
      _ => return None
    }
    return Some(ellipsis_occurrence_from_raw(path, context, raw, slot))
  }
  match item.kind {
    Argument => {
      guard ellipsis_child(item, "kind") is Some(kind) &&
        kind.kind == ArgumentKind_Positional else {
        return None
      }
      guard ellipsis_child(item, "value") is Some(value) else { return None }
      guard ellipsis_direct_raw(value) is Some(raw) else { return None }
      Some(
        ellipsis_occurrence_from_raw(path, context, raw, EllipsisArgumentSlot),
      )
    }
    ConstrPatArg => {
      guard ellipsis_child(item, "kind") is Some(kind) &&
        kind.kind == ArgumentKind_Positional else {
        return None
      }
      guard ellipsis_child(item, "pat") is Some(pattern) else { return None }
      guard ellipsis_direct_raw(pattern) is Some(raw) else { return None }
      Some(
        ellipsis_occurrence_from_raw(
          path,
          context,
          raw,
          EllipsisConstrPatternArgumentSlot,
        ),
      )
    }
    ArrayPattern_Pattern => {
      guard ellipsis_child(item, "value") is Some(pattern) else { return None }
      guard ellipsis_direct_raw(pattern) is Some(raw) else { return None }
      Some(
        ellipsis_occurrence_from_raw(
          path,
          context,
          raw,
          EllipsisArrayPatternSlot,
        ),
      )
    }
    Parameter_Positional => {
      guard ellipsis_child(item, "binder") is Some(binder) else { return None }
      guard ellipsis_direct_raw(binder) is Some(raw) else { return None }
      guard ellipsis_child(item, "ty") is Some(ty) && ellipsis_is_null(ty) else {
        return None
      }
      Some(
        ellipsis_occurrence_from_raw(path, context, raw, EllipsisParameterSlot),
      )
    }
    SpreadableElem_Regular => {
      guard ellipsis_child(item, "value") is Some(expr) else { return None }
      guard ellipsis_direct_raw(expr) is Some(raw) else { return None }
      Some(
        ellipsis_occurrence_from_raw(
          path,
          context,
          raw,
          EllipsisSpreadableExprSlot,
        ),
      )
    }
    _ => None
  }
}

///|
fn ellipsis_occurrence_from_raw(
  path : String,
  context : String,
  raw : String,
  slot : EllipsisItemSlot,
) -> EllipsisOccurrence raise {
  guard parse_ellipsis_syntax(path, context, raw) is Some(parsed) else {
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{shape_context_name(context)} contains invalid ellipsis metavar \{raw}",
    )
  }
  let (name, explicit_kind) = parsed
  { name, explicit_kind, slot }
}

///|
fn parse_ellipsis_syntax(
  path : String,
  context : String,
  raw : String,
) -> (String, @matching.EllipsisMetavarKind?)? raise {
  if !raw.has_prefix("$$$") {
    return None
  }
  if raw.has_prefix("$$$(") && raw.has_suffix(")") {
    let end = raw.length() - 1
    for index in 4..<end {
      if raw[index] == ':' {
        let name = raw[4:index].trim().to_owned()
        let kind_text = raw[index + 1:end].trim().to_owned()
        guard name.length() > 0 else { return None }
        return Some((name, Some(parse_ellipsis_kind(path, context, kind_text))))
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
fn parse_ellipsis_kind(
  path : String,
  context : String,
  raw : String,
) -> @matching.EllipsisMetavarKind raise {
  match raw {
    "exp" => ExpItem
    "id" => IdItem
    "const" => ConstItem
    "arg" => ArgItem
    "pat" => PatItem
    "type" => TypeItem
    _ =>
      raise RuleLoadError::InvalidRule(
        path~,
        info="\{shape_context_name(context)} contains unsupported ellipsis metavar kind \{raw}",
      )
  }
}

///|
fn ellipsis_kind_allowed_in_slot(
  kind : @matching.EllipsisMetavarKind,
  slot : EllipsisItemSlot,
) -> Bool {
  match (kind, slot) {
    (AnyItem, _) => true
    (ExpItem | IdItem | ConstItem, EllipsisExprSlot) => true
    (ExpItem | IdItem | ConstItem | ArgItem, EllipsisArgumentSlot) => true
    (PatItem | IdItem | ConstItem, EllipsisPatternSlot) => true
    (
      PatItem
      | IdItem
      | ConstItem,
      EllipsisConstrPatternArgumentSlot
      | EllipsisArrayPatternSlot,
    ) => true
    (TypeItem, EllipsisTypeSlot) => true
    (IdItem, EllipsisParameterSlot) => true
    (ExpItem | IdItem | ConstItem, EllipsisSpreadableExprSlot) => true
    _ => false
  }
}

///|
fn ellipsis_kind_text(kind : @matching.EllipsisMetavarKind) -> String {
  match kind {
    AnyItem => "any"
    ExpItem => "exp"
    IdItem => "id"
    ConstItem => "const"
    ArgItem => "arg"
    PatItem => "pat"
    TypeItem => "type"
  }
}

///|
fn ellipsis_metavars_contain(
  metavars : Array[@matching.EllipsisMetavar],
  name : String,
) -> Bool {
  for metavar in metavars {
    if metavar.name == name {
      return true
    }
  }
  false
}

///|
fn ellipsis_direct_raw(node : @untyped_ast.Node) -> String? {
  let raw = match node.kind {
    Expr_Ident => node.normalized_expr_identifier_name()
    Pattern_Var =>
      if ellipsis_child(node, "value") is Some(binder) {
        ellipsis_leaf_string_child(binder, "name")
      } else {
        None
      }
    Binder => ellipsis_leaf_string_child(node, "name")
    Type_Name => ellipsis_type_placeholder_name(node)
    _ => None
  }
  match raw {
    Some(raw) if raw.has_prefix("$$$") => Some(raw)
    _ => None
  }
}

///|
fn ellipsis_type_placeholder_name(node : @untyped_ast.Node) -> String? {
  guard ellipsis_child(node, "tys") is Some(tys) && tys.children.is_empty() else {
    return None
  }
  guard ellipsis_child(node, "constr_id") is Some(constr_id) else {
    return None
  }
  guard ellipsis_child(constr_id, "id") is Some(long_ident) &&
    long_ident.kind == LongIdent_Ident else {
    return None
  }
  ellipsis_leaf_string_child(long_ident, "value")
}

///|
fn ellipsis_child(
  node : @untyped_ast.Node,
  name : String,
) -> @untyped_ast.Node? {
  for entry in node.children {
    if entry.0 == Some(name) {
      return Some(entry.1)
    }
  }
  None
}

///|
fn ellipsis_leaf_string_child(
  node : @untyped_ast.Node,
  name : String,
) -> String? {
  guard ellipsis_child(node, name) is Some(child) else { return None }
  match child.kind {
    Leaf(PString(value)) => Some(value)
    _ => None
  }
}

///|
fn ellipsis_is_null(node : @untyped_ast.Node) -> Bool {
  node.kind == Leaf(PNull)
}
