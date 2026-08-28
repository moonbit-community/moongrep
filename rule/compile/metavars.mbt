///|
priv struct MetavarShape {
  cst : @untyped_cst.CstNode
  expr_metavars : Array[String]
  identifier_metavars : Array[String]
  constant_metavars : Array[String]
  arg_metavars : Array[String]
  type_metavars : Array[String]
  pattern_metavars : Array[String]
  ellipsis_metavars : Array[@matching.EllipsisMetavar]
}

///|
priv enum MetavarSyntax {
  Explicit(String, String)
  Bare(String)
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
priv struct MetavarCollections {
  expr : Array[String]
  identifier : Array[String]
  constant : Array[String]
  arg : Array[String]
  type_ : Array[String]
  pattern : Array[String]
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
  let collections : MetavarCollections = {
    expr: [],
    identifier: [],
    constant: [],
    arg: [],
    type_: [],
    pattern: [],
  }
  let contexts : Array[MetavarOccurrenceContext] = []
  for occurrence in occurrences {
    contexts.push(find_metavar_occurrence_context(context, cst, occurrence))
  }
  for index in 0..<occurrences.length() {
    match occurrences[index].syntax {
      Explicit(kind, name) => {
        validate_single_metavar_kind(context, kind)
        validate_declared_metavar(context, name, true)
        if occurrence_rejected_by_original_identifier_case(
            kind,
            occurrences[index],
          ) {
          reject_metavar_position(context, kind, name, contexts[index])
        }
        validate_metavar_position(context, kind, name, contexts[index])
        register_metavar_kind(context, collections, kind, name)
      }
      _ => ()
    }
  }
  infer_bare_metavar_kinds(context, occurrences, contexts, collections)
  let ellipsis_metavars = compile_ellipsis_occurrences(
    context, occurrences, contexts, collections,
  )
  preserve_toplevel_identifier_order(cst, collections.identifier)
  {
    cst,
    expr_metavars: collections.expr,
    identifier_metavars: collections.identifier,
    constant_metavars: collections.constant,
    arg_metavars: collections.arg,
    type_metavars: collections.type_,
    pattern_metavars: collections.pattern,
    ellipsis_metavars,
  }
}

///|
fn preserve_toplevel_identifier_order(
  cst : @untyped_cst.CstNode,
  names : Array[String],
) -> Unit {
  guard cst.kind is @untyped_cst.Impl_Function else { return }
  guard @cst.raw_child(cst, "params") is Some(params) else { return }
  let reordered : Array[String] = []
  for name in names {
    if subtree_contains_normalized_name(params, name) {
      reordered.push(name)
    }
  }
  for name in names {
    if !array_contains(reordered, name) {
      reordered.push(name)
    }
  }
  names.clear()
  for name in reordered {
    names.push(name)
  }
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
  let mut start = -1
  for index in 0..<raw.length() {
    if raw[index] == '$' {
      start = index
    }
  }
  if start < 0 {
    return None
  }
  let component = raw[start:]
  if component.has_prefix("$$$") || component is "$_" {
    return None
  }
  if component.has_prefix("$(") && component.has_suffix(")") {
    let end = component.length() - 1
    for index in 2..<end {
      if component[index] == ':' {
        let name = component[2:index].trim()
        if !name.is_empty() {
          return Some(name.to_owned())
        }
        return None
      }
    }
    None
  } else if component.has_prefix("$") && component.length() > 1 {
    Some(component[1:].to_owned())
  } else {
    None
  }
}

///|
fn parse_metavar(
  raw : String,
  context : PatternCompileContext,
) -> MetavarSyntax? raise {
  if raw.has_prefix("$$$") || raw == "$_" || !raw.has_prefix("$") {
    return None
  }
  if !raw.has_prefix("$(") || !raw.has_suffix(")") {
    if raw.length() <= 1 {
      raise context.invalid_pattern(
        "the pattern has invalid metavar \{raw}; use explicit typed syntax like $(value:exp)",
      )
    }
    return Some(Bare(raw[1:].to_owned()))
  }
  let end = raw.length() - 1
  for index in 2..<end {
    if raw[index] == ':' {
      return Some(
        Explicit(
          raw[index + 1:end].trim().to_owned(),
          raw[2:index].trim().to_owned(),
        ),
      )
    }
  }
  raise context.invalid_pattern(
    "the pattern has invalid metavar payload \{raw}; use explicit typed syntax like $(value:exp)",
  )
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
  kind : String,
  occurrence : ShapeMetavarOccurrence,
) -> Bool {
  occurrence.uppercase_identifier &&
  (kind == "exp" || kind == "const" || kind == "arg" || kind == "pat")
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
fn validate_single_metavar_kind(
  context : PatternCompileContext,
  kind : String,
) -> Unit raise {
  if kind != "exp" &&
    kind != "id" &&
    kind != "const" &&
    kind != "arg" &&
    kind != "type" &&
    kind != "pat" {
    raise context.invalid_pattern(
      "the pattern contains unsupported metavar kind \{kind}",
    )
  }
}

///|
fn validate_metavar_position(
  context : PatternCompileContext,
  kind : String,
  name : String,
  occurrence : MetavarOccurrenceContext,
) -> Unit raise {
  let valid = match kind {
    "exp" => occurrence.position == ExpressionPosition
    "id" => true
    "const" =>
      occurrence.position == ExpressionPosition ||
      (
        occurrence.position == PatternPosition &&
        !occurrence.binder_only_pattern
      )
    "arg" => occurrence.whole_argument
    "type" => occurrence.position == TypePosition
    "pat" => occurrence.position == PatternPosition
    _ => false
  }
  if !valid {
    reject_metavar_position(context, kind, name, occurrence)
  }
}

///|
fn reject_metavar_position(
  context : PatternCompileContext,
  kind : String,
  name : String,
  occurrence : MetavarOccurrenceContext,
) -> Unit raise {
  let text = metavar_text(kind, name)
  let info = if kind == "exp" {
    "the pattern uses \{text} outside a bare expression position"
  } else if kind == "pat" {
    "the pattern uses \{text} outside a bare pattern position"
  } else if kind == "arg" {
    "the pattern uses \{text} outside a bare argument position"
  } else if kind == "type" {
    "the pattern uses \{text} outside a whole type position"
  } else if kind == "id" {
    "the pattern uses \{text} outside an identifier position"
  } else if occurrence.qualified_identifier {
    "the pattern uses \{text} in an unsupported qualified identifier position"
  } else {
    "the pattern uses \{text} outside a constant expression or pattern position"
  }
  raise context.invalid_pattern(info)
}

///|
fn register_metavar_kind(
  context : PatternCompileContext,
  collections : MetavarCollections,
  kind : String,
  name : String,
) -> Unit raise {
  let existing = collection_kind(collections, name)
  if existing is Some(previous) && previous != kind {
    raise context.invalid_pattern(
      "the pattern declares metavar \{name} as multiple metavar kinds",
    )
  }
  let target = match kind {
    "exp" => collections.expr
    "id" => collections.identifier
    "const" => collections.constant
    "arg" => collections.arg
    "type" => collections.type_
    "pat" => collections.pattern
    _ => return
  }
  push_unique_string(target, name)
}

///|
fn collection_kind(collections : MetavarCollections, name : String) -> String? {
  if array_contains(collections.expr, name) {
    Some("exp")
  } else if array_contains(collections.identifier, name) {
    Some("id")
  } else if array_contains(collections.constant, name) {
    Some("const")
  } else if array_contains(collections.arg, name) {
    Some("arg")
  } else if array_contains(collections.type_, name) {
    Some("type")
  } else if array_contains(collections.pattern, name) {
    Some("pat")
  } else {
    None
  }
}

///|
fn infer_bare_metavar_kinds(
  context : PatternCompileContext,
  occurrences : Array[ShapeMetavarOccurrence],
  contexts : Array[MetavarOccurrenceContext],
  collections : MetavarCollections,
) -> Unit raise {
  for index in 0..<occurrences.length() {
    match occurrences[index].syntax {
      Bare(name) if contexts[index].position == PatternPosition &&
        collection_kind(collections, name) is None =>
        if contexts[index].binder_only_pattern {
          validate_declared_metavar(context, name, true)
          register_metavar_kind(context, collections, "id", name)
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
            IdentifierPosition => "id"
            TypePosition => "type"
            ExpressionPosition => "exp"
            PatternPosition => abort("unreachable")
          }
          if collection_kind(collections, name) is None {
            register_metavar_kind(context, collections, inferred, name)
          } else if position == TypePosition &&
            collection_kind(collections, name) != Some("type") {
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
        guard collection_kind(collections, name) is Some(kind) else {
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
fn push_unique_string(items : Array[String], item : String) -> Unit {
  if !array_contains(items, item) {
    items.push(item)
  }
}

///|
fn metavar_text(kind : String, name : String) -> String {
  "$(" + name + ":" + kind + ")"
}
