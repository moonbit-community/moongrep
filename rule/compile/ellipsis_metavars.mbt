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
fn compile_ellipsis_occurrences(
  path : String,
  context : String,
  occurrences : Array[ShapeMetavarOccurrence],
  contexts : Array[MetavarOccurrenceContext],
  collections : MetavarCollections,
) -> Array[@matching.EllipsisMetavar] raise {
  let explicit_kinds : Map[String, @matching.EllipsisMetavarKind] = Map([])
  for index in 0..<occurrences.length() {
    match occurrences[index].syntax {
      Ellipsis(name, explicit_kind) => {
        guard contexts[index].ellipsis_slot is Some(_) else {
          raise RuleLoadError::InvalidRule(
            path~,
            info="\{shape_context_name(context)} uses ellipsis metavar \{occurrences[index].raw} outside a complete ordered CST list item",
          )
        }
        if name != "_" {
          validate_declared_metavar(path, context, name, true)
          if collection_kind(collections, name) is Some(_) {
            raise RuleLoadError::InvalidRule(
              path~,
              info="\{shape_context_name(context)} cannot use \{name} as both an ellipsis metavar and a single-node metavar",
            )
          }
          if explicit_kind is Some(kind) {
            if explicit_kinds.get(name) is Some(previous) && previous != kind {
              raise RuleLoadError::InvalidRule(
                path~,
                info="\{shape_context_name(context)} declares ellipsis metavar \{name} as multiple metavar kinds",
              )
            }
            explicit_kinds[name] = kind
          }
        }
      }
      _ => ()
    }
  }
  let result : Array[@matching.EllipsisMetavar] = []
  for index in 0..<occurrences.length() {
    match occurrences[index].syntax {
      Ellipsis(name, explicit_kind) => {
        let kind = if name != "_" && explicit_kinds.get(name) is Some(found) {
          found
        } else {
          explicit_kind.unwrap_or(AnyItem)
        }
        guard contexts[index].ellipsis_slot is Some(slot) else { continue }
        if !ellipsis_kind_allowed_in_slot(kind, slot) {
          raise RuleLoadError::InvalidRule(
            path~,
            info="\{shape_context_name(context)} uses ellipsis kind \{ellipsis_kind_text(kind)} in an incompatible ordered-list item position",
          )
        }
        if name != "_" && !ellipsis_metavars_contain(result, name) {
          result.push({ name, kind })
        }
      }
      _ => ()
    }
  }
  result
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
