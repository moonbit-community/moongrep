///|
/// A value captured by an expression query.
///
/// Identifier captures retain the parser's semantic name node rather than a
/// synthesized string leaf. A captured flattened continuation uses `Multiple`
/// when it contains zero or more than one CST expression node.
pub(all) enum BoundValue {
  Single(@untyped_cst.CstNode)
  Multiple(Array[@untyped_cst.CstNode])
}
