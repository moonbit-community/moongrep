///|
/// Only lexical variable occurrences participate in inherited binding checks.
pub(all) enum IdentifierBinding {
  Lexical(BindingId?)
  NonLexical
} derive(Eq, Hash, Debug)

///|
pub(all) struct IdentifierSource {
  name : String
  binding : IdentifierBinding
} derive(Eq, Hash, Debug)

///|
priv enum SourceIdentifierRole {
  OtherName
  VariableReference(NodeId)
  ResolvedVariableReference(BindingId)
  VariableBinder(BindingId)
}

///|
fn SourceIndex::mark_name_tree(
  self : SourceIndex,
  id : NodeId,
  role : SourceIdentifierRole,
) -> Unit {
  let pending = [id]
  while pending.pop() is Some(id) {
    self.nodes[id].identifier_role = role
    for (_, child) in self.nodes[id].children {
      pending.push(child)
    }
  }
}

///|
// Mark both the semantic name and its original syntax representation. Bindings
// belong to declarations, not to the scope before the declaration is evaluated.
fn SourceIndex::mark_identifier(
  self : SourceIndex,
  id : NodeId,
  role : SourceIdentifierRole,
) -> Unit {
  if self.node(id).kind is Name_Binder {
    self.mark_name_tree(id, role)
    return
  }
  self.nodes[id].identifier_role = role
  for (label, child) in self.nodes[id].children {
    if label is Some("name" | "semantic_name") {
      self.mark_name_tree(child, role)
    }
  }
}

///|
/// Read the role and binding of an original identifier occurrence.
pub fn SourceIndex::identifier_source(
  self : SourceIndex,
  node : @untyped_cst.CstNode,
) -> IdentifierSource? {
  self.ensure_scopes()
  let id = self.node_id(node)
  guard normalized_name(node) is Some(name) else { return None }
  let binding = match self.nodes[id].identifier_role {
    VariableBinder(binding) | ResolvedVariableReference(binding) =>
      Lexical(Some(binding))
    VariableReference(owner) =>
      Lexical(self.resolve(self.nodes[owner].scope, name))
    OtherName => NonLexical
  }
  Some({ name, binding, })
}

///|
pub extend IdentifierBinding with Eq::{not_equal, equal}

///|
pub extend IdentifierBinding with Hash::{hash, hash_combine}

///|
pub extend IdentifierBinding with Debug::{to_repr}

///|
pub extend IdentifierSource with Eq::{not_equal, equal}

///|
pub extend IdentifierSource with Hash::{hash, hash_combine}

///|
pub extend IdentifierSource with Debug::{to_repr}
