///|
using @model {type BoundValue}

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
/// Result of a successful expression-pattern match.
pub(all) struct ExprMatch {
  root : @untyped_cst.CstNode
  bindings : @hashmap.HashMap[String, BoundValue]
  loc : @basic.Location
}

///|
pub(all) struct TargetRef {
  region : @cst.RegionId
  scope : @cst.ScopeId
}

///|
pub(all) struct IndexedExprMatch {
  result : ExprMatch
  target : TargetRef?
}

///|
priv struct MatchContext {
  values : @hashmap.HashMap[String, BoundValue]
  index : @cst.SourceIndex?
  mut target : TargetRef?
}

///|
fn MatchContext::new(
  values : @hashmap.HashMap[String, BoundValue],
) -> MatchContext {
  { values: values.copy(), index: None, target: None, }
}

///|
fn MatchContext::get(self : MatchContext, name : String) -> BoundValue? {
  self.values.get(name)
}

///|
fn MatchContext::copy(self : MatchContext) -> MatchContext {
  { ..self, values: self.values.copy(), }
}

///|
fn MatchContext::select_node(
  self : MatchContext,
  node : @untyped_cst.CstNode,
) -> Unit {
  if self.index is Some(index) {
    let region = index.target(index.node_id(node))
    self.target = Some({ region, scope: index.scope(region), })
  }
}

///|
fn MatchContext::select_continuation(
  self : MatchContext,
  header : @untyped_cst.CstNode,
  length : Int,
) -> Unit {
  if self.index is Some(index) {
    let region = index.continuation(index.node_id(header), length)
    self.target = Some({ region, scope: index.scope(region), })
  }
}

///|
/// Indexed and standalone matching share the same atomic implementation.
/// The selected source reference is committed with the capture branch.
pub fn match_indexed_expr_pattern(
  compiled : CompiledExprPattern,
  index : @cst.SourceIndex,
  region : @cst.RegionId,
  initial_bindings : @hashmap.HashMap[String, BoundValue],
) -> IndexedExprMatch? {
  let context : MatchContext = {
    values: initial_bindings.copy(),
    index: Some(index),
    target: None,
  }
  match_candidate_in_context(compiled, index.candidate(region), context).map(result => {
    result,
    target: context.target,
  })
}
