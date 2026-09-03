///|
priv struct MetavarShape {
  cst : @untyped_cst.CstNode
  metavars : @matching.MetavarRegistry
}

///|
priv enum MetavarPosition {
  ExpressionPosition
  IdentifierPosition
  PatternPosition
  TypePosition
} derive(Eq)

///|
priv struct MetavarOccurrenceContext {
  position : MetavarPosition
  whole_argument : Bool
  ellipsis_slot : EllipsisItemSlot?
  qualified_identifier : Bool
  binder_only_pattern : Bool
}

///|
fn compile_metavar_shape(context : PatternCompileContext) -> MetavarShape raise {
  let (cst, occurrences) = parse_shape(context)
  compile_prepared_metavar_shape(context, cst, occurrences)
}

///|
fn compile_toplevel_metavar_shape(
  context : PatternCompileContext,
) -> MetavarShape raise {
  let (cst, occurrences) = parse_toplevel_shape(context)
  compile_prepared_metavar_shape(context, cst, occurrences)
}

///|
fn compile_prepared_metavar_shape(
  context : PatternCompileContext,
  cst : @untyped_cst.CstNode,
  occurrences : Array[ShapeMetavarOccurrence],
) -> MetavarShape raise {
  let classified = @matching.MetavarRegistry::new()
  let contexts : Array[MetavarOccurrenceContext] = []
  for occurrence in occurrences {
    contexts.push(find_metavar_occurrence_context(context, cst, occurrence))
  }
  for index in 0..<occurrences.length() {
    match occurrences[index].syntax {
      Wildcard if contexts[index].qualified_identifier =>
        raise context.invalid_pattern(
          "the pattern uses $_ in an unsupported qualified identifier position",
        )
      Typed(name, kind) => {
        validate_declared_metavar(context, name, true)
        if occurrence_rejected_by_original_identifier_case(
            kind,
            occurrences[index],
          ) {
          reject_metavar_position(context, kind, name, contexts[index])
        }
        validate_metavar_position(context, kind, name, contexts[index])
        register_metavar_kind(context, classified, kind, name)
      }
      _ => ()
    }
  }
  infer_bare_metavar_kinds(context, occurrences, contexts, classified)
  compile_ellipsis_occurrences(context, occurrences, contexts, classified)
  let metavars = registry_in_occurrence_order(occurrences, classified)
  preserve_toplevel_identifier_order(cst, metavars)
  { cst, metavars, }
}

///|
fn preserve_toplevel_identifier_order(
  cst : @untyped_cst.CstNode,
  metavars : @matching.MetavarRegistry,
) -> Unit {
  guard cst.kind is @untyped_cst.Impl_Function else { return }
  guard @cst.raw_child(cst, "params") is Some(params) else { return }
  let reordered : Array[@matching.MetavarEntry] = []
  for entry in metavars.entries {
    if entry.kind == Identifier &&
      subtree_contains_normalized_name(params, entry.name) {
      reordered.push(entry)
    }
  }
  for entry in metavars.entries {
    if entry.kind == Identifier &&
      !metavar_entries_contain_name(reordered, entry.name) {
      reordered.push(entry)
    }
  }
  let mut next = 0
  for index in 0..<metavars.entries.length() {
    if metavars.entries[index].kind == Identifier {
      metavars.entries[index] = reordered[next]
      next += 1
    }
  }
}

///|
fn registry_in_occurrence_order(
  occurrences : Array[ShapeMetavarOccurrence],
  classified : @matching.MetavarRegistry,
) -> @matching.MetavarRegistry {
  let ordered = @matching.MetavarRegistry::new()
  for occurrence in occurrences {
    let name = match occurrence.syntax {
      Bare(name) | Typed(name, _) => Some(name)
      EllipsisSyntax(name, _) if name != "_" => Some(name)
      _ => None
    }
    if name is Some(name) && classified.kind_of(name) is Some(kind) {
      ignore(ordered.register(name, kind))
    }
  }
  ordered
}

///|
fn metavar_entries_contain_name(
  entries : Array[@matching.MetavarEntry],
  name : String,
) -> Bool {
  for entry in entries {
    if entry.name == name {
      return true
    }
  }
  false
}

///|
fn subtree_contains_normalized_name(
  node : @untyped_cst.CstNode,
  expected : String,
) -> Bool {
  if @cst.normalized_name(node) is Some(found) {
    if found == expected || single_metavar_source_name(found) == Some(expected) {
      return true
    }
  }
  for entry in @cst.semantic_children(node) {
    if subtree_contains_normalized_name(entry.1, expected) {
      return true
    }
  }
  false
}

///|
fn single_metavar_source_name(raw : String) -> String? {
  match @matching.parse_metavar_syntax(raw) {
    Bare(name) | Typed(name, _) => Some(name)
    _ => None
  }
}

///|
fn find_metavar_occurrence_context(
  context : PatternCompileContext,
  root : @untyped_cst.CstNode,
  occurrence : ShapeMetavarOccurrence,
) -> MetavarOccurrenceContext raise {
  let path_nodes : Array[@untyped_cst.CstNode] = []
  let mut best : MetavarOccurrenceContext? = None
  let mut best_priority = -1
  find_metavar_occurrence_context_in(root, occurrence, path_nodes, fn(
    found,
    priority,
  ) {
    if priority > best_priority {
      best = Some(found)
      best_priority = priority
    }
  })
  if best is Some(found) {
    if !found.qualified_identifier &&
      cst_contains_qualified_metavar(root, occurrence) {
      {
        position: found.position,
        whole_argument: found.whole_argument,
        ellipsis_slot: found.ellipsis_slot,
        qualified_identifier: true,
        binder_only_pattern: found.binder_only_pattern,
      }
    } else {
      found
    }
  } else {
    raise context.invalid_pattern(
      "the pattern cannot locate metavar \{occurrence.raw} in parsed CST",
    )
  }
}

///|
fn cst_contains_qualified_metavar(
  node : @untyped_cst.CstNode,
  occurrence : ShapeMetavarOccurrence,
) -> Bool {
  if node.kind is @untyped_cst.LongIdent_Dot &&
    metavar_node_matches_occurrence(node, occurrence) {
    return true
  }
  if node.kind is (@untyped_cst.Expr_Method | @untyped_cst.Expr_Field) &&
    @cst.raw_child(node, "field") is Some(field) &&
    metavar_node_matches_occurrence(field, occurrence) {
    return true
  }
  for entry in node.children {
    if cst_contains_qualified_metavar(entry.1, occurrence) {
      return true
    }
  }
  false
}

///|
fn find_metavar_occurrence_context_in(
  node : @untyped_cst.CstNode,
  occurrence : ShapeMetavarOccurrence,
  path : Array[@untyped_cst.CstNode],
  report : (MetavarOccurrenceContext, Int) -> Unit,
) -> Unit {
  path.push(node)
  if metavar_node_matches_occurrence(node, occurrence) {
    let whole = metavar_node_is_whole(node, occurrence)
    let (position, priority) = match node.kind {
      @untyped_cst.Expr_Ident if whole => (ExpressionPosition, 4)
      @untyped_cst.Pattern_Var if whole => (PatternPosition, 4)
      @untyped_cst.Type_Name if whole => (TypePosition, 4)
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
      | @untyped_cst.Name_Test => (IdentifierPosition, 2)
      _ => (IdentifierPosition, 0)
    }
    report(
      {
        position,
        whole_argument: path_has_whole_argument(path, occurrence),
        ellipsis_slot: ellipsis_slot_from_path(path, occurrence),
        qualified_identifier: normalized_name_is_qualified(node) ||
        path_has_kind(path, fn(kind) { kind is @untyped_cst.LongIdent_Dot }),
        binder_only_pattern: path_has_binder_only_pattern_context(path),
      },
      priority,
    )
  }
  for entry in node.children {
    find_metavar_occurrence_context_in(entry.1, occurrence, path, report)
  }
  ignore(path.pop())
}

///|
fn normalized_name_is_qualified(node : @untyped_cst.CstNode) -> Bool {
  if @cst.normalized_name(node) is Some(name) {
    name.contains(".") || name.contains("::")
  } else {
    false
  }
}

///|
fn path_has_kind(
  path : Array[@untyped_cst.CstNode],
  predicate : (@untyped_cst.NodeKind) -> Bool,
) -> Bool {
  for node in path {
    if predicate(node.kind) {
      return true
    }
  }
  false
}

///|
fn path_has_binder_only_pattern_context(
  path : Array[@untyped_cst.CstNode],
) -> Bool {
  for index in 0..<path.length() {
    match path[index].kind {
      @untyped_cst.Expr_LetMut
      | @untyped_cst.Expr_LetFn
      | @untyped_cst.Expr_ForEach
      | @untyped_cst.Expr_ListComprehension
      | @untyped_cst.Impl_Let
      | @untyped_cst.Impl_Const
      | @untyped_cst.Parameter_Positional
      | @untyped_cst.Parameter_Labelled
      | @untyped_cst.Parameter_Optional
      | @untyped_cst.Parameter_DiscardPositional =>
        if index + 1 < path.length() && path[index + 1].kind.is_pattern() {
          return true
        }
      _ => ()
    }
  }
  false
}

///|
fn occurrence_rejected_by_original_identifier_case(
  kind : @matching.MetavarKind,
  occurrence : ShapeMetavarOccurrence,
) -> Bool {
  occurrence.uppercase_identifier &&
  (kind == Expr || kind == Constant || kind == Argument || kind == Pattern)
}

///|
fn metavar_node_matches_occurrence(
  node : @untyped_cst.CstNode,
  occurrence : ShapeMetavarOccurrence,
) -> Bool {
  if node.source_span.0 > occurrence.start ||
    node.source_span.1 < occurrence.end {
    return false
  }
  let name = match node.kind {
    @untyped_cst.Expr_Ident => @cst.normalized_expr_identifier_name(node)
    @untyped_cst.Expr_Constr => @cst.name_node(node).bind(@cst.normalized_name)
    @untyped_cst.Pattern_Var => @cst.normalized_pattern_identifier_name(node)
    @untyped_cst.Type_Name => @cst.name_node(node).bind(@cst.normalized_name)
    _ => @cst.normalized_name(node)
  }
  if name is Some(name) {
    name == occurrence.raw ||
    name.has_suffix(".\{occurrence.raw}") ||
    name.has_suffix("::\{occurrence.raw}")
  } else {
    false
  }
}

///|
fn metavar_node_is_whole(
  node : @untyped_cst.CstNode,
  occurrence : ShapeMetavarOccurrence,
) -> Bool {
  node.source_span.0 == occurrence.start && node.source_span.1 == occurrence.end
}

///|
fn path_has_whole_argument(
  path : Array[@untyped_cst.CstNode],
  occurrence : ShapeMetavarOccurrence,
) -> Bool {
  for node in path {
    if node.kind is @untyped_cst.Argument_Positional &&
      @cst.argument_value(node) is Some(value) &&
      metavar_node_matches_occurrence(value, occurrence) &&
      metavar_node_is_whole(value, occurrence) {
      return true
    }
  }
  false
}

///|
fn ellipsis_slot_from_path(
  path : Array[@untyped_cst.CstNode],
  occurrence : ShapeMetavarOccurrence,
) -> EllipsisItemSlot? {
  for index in 0..<path.length() {
    let container = path[index]
    let slot = ellipsis_slot_for_container(container.kind)
    if slot is Some(slot) &&
      index + 1 < path.length() &&
      !ellipsis_container_is_grouping_list(path, index) {
      let item = path[index + 1]
      if ellipsis_item_is_whole_occurrence(item, occurrence) &&
        ellipsis_container_item_is_replaceable(container, item) {
        return Some(slot)
      }
    }
  }
  if path is [root, item] &&
    root.kind is @untyped_cst.Expression &&
    ellipsis_item_is_whole_occurrence(item, occurrence) {
    return Some(EllipsisExprSlot)
  }
  None
}

///|
fn ellipsis_container_is_grouping_list(
  path : Array[@untyped_cst.CstNode],
  index : Int,
) -> Bool {
  if index == 0 {
    return false
  }
  let parent = path[index - 1]
  match parent.kind {
    @untyped_cst.Expr_Group | @untyped_cst.Type_Group => true
    @untyped_cst.Pattern_Tuple =>
      @cst.raw_child(parent, "pattern_group") is Some(_)
    _ => false
  }
}

///|
fn ellipsis_slot_for_container(
  kind : @untyped_cst.NodeKind,
) -> EllipsisItemSlot? {
  match kind {
    @untyped_cst.Expression | @untyped_cst.List_BlockStatementList =>
      Some(EllipsisExprSlot)
    @untyped_cst.List_ArgumentList => Some(EllipsisArgumentSlot)
    @untyped_cst.List_TuplePatternList => Some(EllipsisPatternSlot)
    @untyped_cst.List_ConstructorPatternArgumentList =>
      Some(EllipsisConstrPatternArgumentSlot)
    @untyped_cst.List_ArrayPatternList => Some(EllipsisArrayPatternSlot)
    @untyped_cst.List_TupleElementList => Some(EllipsisExprSlot)
    @untyped_cst.List_TupleTypeList | @untyped_cst.List_TypeArgumentList =>
      Some(EllipsisTypeSlot)
    @untyped_cst.List_ParameterList
    | @untyped_cst.List_TraitMethodParameterList => Some(EllipsisParameterSlot)
    @untyped_cst.List_ArrayElementList => Some(EllipsisSpreadableExprSlot)
    _ => None
  }
}

///|
fn ellipsis_container_item_is_replaceable(
  container : @untyped_cst.CstNode,
  item : @untyped_cst.CstNode,
) -> Bool {
  match container.kind {
    @untyped_cst.List_BlockStatementList =>
      block_statement_has_separator_after(container, item)
    _ => true
  }
}

///|
/// A block's final item is its value, not a replaceable statement slot. The
/// CST records a separator only for statements that precede another item or
/// have an explicit trailing semicolon.
fn block_statement_has_separator_after(
  container : @untyped_cst.CstNode,
  item : @untyped_cst.CstNode,
) -> Bool {
  let mut found = false
  for entry in container.children {
    if found {
      return entry.1.kind is @untyped_cst.Syntax_Separator
    }
    if entry.1.source_span == item.source_span && entry.1.kind == item.kind {
      found = true
    }
  }
  false
}

///|
fn ellipsis_item_is_whole_occurrence(
  item : @untyped_cst.CstNode,
  occurrence : ShapeMetavarOccurrence,
) -> Bool {
  let value = match item.kind {
    @untyped_cst.Argument_Positional => @cst.argument_value(item)
    @untyped_cst.ArrayPattern_Pattern => first_cst_pattern_child(item)
    @untyped_cst.ArrayElement_Regular => @cst.raw_child(item, "expr")
    @untyped_cst.Parameter_Positional => @cst.raw_child(item, "pattern")
    _ => Some(item)
  }
  if value is Some(value) {
    metavar_node_matches_occurrence(value, occurrence) &&
    metavar_node_is_whole(value, occurrence)
  } else {
    false
  }
}

///|
fn first_cst_pattern_child(
  node : @untyped_cst.CstNode,
) -> @untyped_cst.CstNode? {
  for entry in node.children {
    if entry.1.kind.is_pattern() {
      return Some(entry.1)
    }
  }
  None
}

///|
fn validate_metavar_position(
  context : PatternCompileContext,
  kind : @matching.MetavarKind,
  name : String,
  occurrence : MetavarOccurrenceContext,
) -> Unit raise {
  let valid = match kind {
    Expr => occurrence.position == ExpressionPosition
    Identifier => true
    Constant =>
      occurrence.position == ExpressionPosition ||
      (
        occurrence.position == PatternPosition &&
        !occurrence.binder_only_pattern
      )
    Argument => occurrence.whole_argument
    Type => occurrence.position == TypePosition
    Pattern => occurrence.position == PatternPosition
    Ellipsis(_) => false
  }
  if !valid {
    reject_metavar_position(context, kind, name, occurrence)
  }
}

///|
fn reject_metavar_position(
  context : PatternCompileContext,
  kind : @matching.MetavarKind,
  name : String,
  occurrence : MetavarOccurrenceContext,
) -> Unit raise {
  let text = metavar_text(kind, name)
  let info = match kind {
    Expr => "the pattern uses \{text} outside a bare expression position"
    Pattern => "the pattern uses \{text} outside a bare pattern position"
    Argument => "the pattern uses \{text} outside a bare argument position"
    Type => "the pattern uses \{text} outside a whole type position"
    Identifier => "the pattern uses \{text} outside an identifier position"
    Constant if occurrence.qualified_identifier =>
      "the pattern uses \{text} in an unsupported qualified identifier position"
    Constant =>
      "the pattern uses \{text} outside a constant expression or pattern position"
    Ellipsis(_) => abort("ellipsis metavars use ordered-list validation")
  }
  raise context.invalid_pattern(info)
}

///|
fn register_metavar_kind(
  context : PatternCompileContext,
  metavars : @matching.MetavarRegistry,
  kind : @matching.MetavarKind,
  name : String,
) -> Unit raise {
  match metavars.register(name, kind) {
    RegistrationConflict(previous) =>
      match (previous, kind) {
        (Ellipsis(_), Ellipsis(_)) =>
          raise context.invalid_pattern(
            "the pattern declares ellipsis metavar \{name} as multiple metavar kinds",
          )
        (Ellipsis(_), _) | (_, Ellipsis(_)) =>
          raise context.invalid_pattern(
            "the pattern cannot use \{name} as both an ellipsis metavar and a single-node metavar",
          )
        _ =>
          raise context.invalid_pattern(
            "the pattern declares metavar \{name} as multiple metavar kinds",
          )
      }
    _ => ()
  }
}

///|
fn infer_bare_metavar_kinds(
  context : PatternCompileContext,
  occurrences : Array[ShapeMetavarOccurrence],
  contexts : Array[MetavarOccurrenceContext],
  metavars : @matching.MetavarRegistry,
) -> Unit raise {
  for index in 0..<occurrences.length() {
    match occurrences[index].syntax {
      Bare(name) if contexts[index].position == PatternPosition &&
        metavars.kind_of(name) is None =>
        if contexts[index].binder_only_pattern {
          validate_declared_metavar(context, name, true)
          register_metavar_kind(context, metavars, Identifier, name)
        } else {
          raise context.invalid_pattern(
            "the pattern cannot infer kind for bare metavar $\{name} in a pattern variable position; use explicit typed syntax like $(\{name}:id), $(\{name}:const), or $(\{name}:pat)",
          )
        }
      _ => ()
    }
  }
  for position in [IdentifierPosition, TypePosition, ExpressionPosition] {
    for index in 0..<occurrences.length() {
      match occurrences[index].syntax {
        Bare(name) if contexts[index].position == position => {
          validate_declared_metavar(context, name, true)
          let inferred = match position {
            IdentifierPosition => @matching.MetavarKind::Identifier
            TypePosition => Type
            ExpressionPosition => Expr
            PatternPosition => abort("unreachable")
          }
          if metavars.kind_of(name) is None {
            register_metavar_kind(context, metavars, inferred, name)
          } else if position == TypePosition &&
            metavars.kind_of(name) != Some(Type) {
            raise context.invalid_pattern(
              "the pattern declares metavar \{name} as multiple metavar kinds",
            )
          }
        }
        _ => ()
      }
    }
  }
  for index in 0..<occurrences.length() {
    match occurrences[index].syntax {
      Bare(name) => {
        guard metavars.kind_of(name) is Some(kind) else {
          raise context.invalid_pattern(
            "the pattern cannot infer kind for bare metavar $\{name} in a pattern variable position; use explicit typed syntax like $(\{name}:id), $(\{name}:const), or $(\{name}:pat)",
          )
        }
        validate_metavar_position(context, kind, name, contexts[index])
      }
      _ => ()
    }
  }
}

///|
fn metavar_text(kind : @matching.MetavarKind, name : String) -> String {
  "$(" + name + ":" + kind.syntax_name() + ")"
}
