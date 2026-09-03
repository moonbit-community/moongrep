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
  context : PatternCompileContext,
  occurrences : Array[ShapeMetavarOccurrence],
  contexts : Array[MetavarOccurrenceContext],
  metavars : @matching.MetavarRegistry,
) -> Unit raise {
  for index in 0..<occurrences.length() {
    match occurrences[index].syntax {
      EllipsisSyntax(name, explicit_kind) => {
        guard contexts[index].ellipsis_slot is Some(_) else {
          raise context.invalid_pattern(
            "the pattern uses ellipsis metavar \{occurrences[index].raw} outside a complete ordered CST list item",
          )
        }
        if name != "_" {
          validate_declared_metavar(context, name, true)
          if explicit_kind is Some(kind) {
            register_metavar_kind(context, metavars, Ellipsis(kind), name)
          }
        }
      }
      _ => ()
    }
  }
  for index in 0..<occurrences.length() {
    match occurrences[index].syntax {
      EllipsisSyntax(name, explicit_kind) => {
        let kind = if name != "_" &&
          metavars.kind_of(name) is Some(Ellipsis(found)) {
          found
        } else {
          explicit_kind.unwrap_or(AnyItem)
        }
        guard contexts[index].ellipsis_slot is Some(slot) else { continue }
        if !ellipsis_kind_allowed_in_slot(kind, slot) {
          raise context.invalid_pattern(
            "the pattern uses ellipsis kind \{ellipsis_kind_text(kind)} in an incompatible ordered-list item position",
          )
        }
        if name != "_" {
          register_metavar_kind(context, metavars, Ellipsis(kind), name)
        }
      }
      _ => ()
    }
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
  kind.syntax_name()
}
