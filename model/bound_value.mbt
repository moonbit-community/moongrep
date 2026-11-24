///|
/// A syntax node or node sequence captured by a metavariable in an expression
/// query.
///
/// - `Single`: captures one CST node, including semantic name nodes for `id`
///   metavariables and single-statement continuation suffixes.
/// - `Multiple`: captures zero or more ordered sibling CST nodes from an
///   ellipsis metavariable or an empty/multi-statement continuation suffix.
pub(all) enum BoundValue {
  Single(@untyped_cst.CstNode)
  Multiple(Array[@untyped_cst.CstNode])
}
