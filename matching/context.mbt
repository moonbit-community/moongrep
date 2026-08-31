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
  metavars : MetavarRegistry
  ignored_fields : Array[IgnoredPatternField]
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
