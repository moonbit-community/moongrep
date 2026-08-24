///|
/// One semantic CST field that a compiled pattern deliberately omits from
/// structural comparison.
pub(all) struct IgnoredPatternField {
  parent_kind : @untyped_cst.NodeKind
  child_name : String
}

///|
/// A compiled structural pattern backed directly by parser CST nodes.
pub(all) struct CompiledExprPattern {
  cst : @untyped_cst.CstNode
  expr_metavars : Array[String]
  identifier_metavars : Array[String]
  constant_metavars : Array[String]
  arg_metavars : Array[String]
  type_metavars : Array[String]
  ellipsis_metavars : Array[EllipsisMetavar]
  target_metavar : String?
  source_metavar : String?
  ignored_fields : Array[IgnoredPatternField]
}

///|
/// The per-item constraint applied by an ellipsis metavar.
pub(all) enum EllipsisMetavarKind {
  AnyItem
  ExpItem
  IdItem
  ConstItem
  ArgItem
  PatItem
  TypeItem
} derive(Eq)

///|
/// A named ellipsis metavar discovered while compiling a pattern.
pub(all) struct EllipsisMetavar {
  name : String
  kind : EllipsisMetavarKind
}

///|
/// Values captured while matching a `CompiledExprPattern`.
///
/// Identifier captures retain the parser's semantic name node rather than a
/// synthesized string leaf. A captured flattened continuation uses `Multiple`
/// when it contains zero or more than one CST expression node.
pub(all) enum BoundValue {
  Single(@untyped_cst.CstNode)
  Multiple(Array[@untyped_cst.CstNode])
}

///|
/// Result of a successful expression-pattern match.
pub(all) struct ExprMatch {
  root : @untyped_cst.CstNode
  bindings : @hashmap.HashMap[String, BoundValue]
  loc : @basic.Location
}
