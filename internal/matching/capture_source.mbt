///|
/// Identifier provenance is private to indexed rule evaluation. BoundValue
/// continues to contain the original name or complete ordered-list items.
pub(all) enum IdentifierCaptureSource {
  SingleIdentifier(@cst.IdentifierSource)
  MultipleIdentifiers(Array[@cst.IdentifierSource])
} derive(Eq, Hash, Debug)

///|
fn identifier_bindings_match(
  inherited : @cst.IdentifierSource,
  occurrence : @cst.IdentifierSource,
) -> Bool {
  match (inherited.binding, occurrence.binding) {
    (Lexical(left), Lexical(right)) => left == right
    _ => true
  }
}

///|
fn IdentifierCaptureSource::matches(
  self : IdentifierCaptureSource,
  occurrence : IdentifierCaptureSource,
) -> Bool {
  match (self, occurrence) {
    (SingleIdentifier(left), SingleIdentifier(right)) =>
      identifier_bindings_match(left, right)
    (MultipleIdentifiers(left), MultipleIdentifiers(right)) => {
      guard left.length() == right.length() else { return false }
      for i in 0..<left.length() {
        if !identifier_bindings_match(left[i], right[i]) {
          return false
        }
      }
      true
    }
    _ => false
  }
}

///|
fn MatchContext::accept_source(
  self : MatchContext,
  name : String,
  source : IdentifierCaptureSource,
) -> Bool {
  if self.inherited_sources.get(name) is Some(inherited) &&
    !inherited.matches(source) {
    return false
  }
  // Repeated new captures keep their first source and their existing equality
  // rules. Only captures inherited from an ancestor constrain bindings.
  if self.sources.get(name) is None {
    self.sources[name] = source
  }
  true
}

///|
fn bind_identifier(
  bindings : MatchContext,
  name : String,
  value : @untyped_cst.CstNode,
) -> Bool {
  guard bind_value(bindings, name, value) else { return false }
  if bindings.index is Some(index) &&
    index.identifier_source(value) is Some(source) &&
    !bindings.accept_source(name, SingleIdentifier(source)) {
    return false
  }
  true
}

///|
// Extract the identifier from a full list item without changing the public
// captured value. Parameter types, labels, and defaults are not occurrences.
fn ellipsis_identifier_node(
  raw : @untyped_cst.CstNode,
) -> @untyped_cst.CstNode? {
  let node = @cst.unwrap_groups(raw)
  match node.kind {
    Expr_Ident | Pattern_Var => @cst.name_node(node)
    Argument_Positional =>
      @cst.argument_value(node).bind(ellipsis_identifier_node)
    ArrayElement_Regular =>
      @cst.raw_child(node, "expr").bind(ellipsis_identifier_node)
    ArrayPattern_Pattern =>
      first_pattern_child(node).bind(ellipsis_identifier_node)
    Parameter_Positional
    | Parameter_Labelled
    | Parameter_Optional
    | Parameter_QuestionOptional =>
      parameter_pattern(node).bind(ellipsis_identifier_node)
    Name_Binder => Some(node)
    _ => None
  }
}

///|
fn bind_identifier_list(
  bindings : MatchContext,
  name : String,
  values : Array[@untyped_cst.CstNode],
) -> Bool {
  guard bind_multiple(bindings, name, values) else { return false }
  if bindings.index is Some(index) {
    let sources : Array[@cst.IdentifierSource] = []
    for value in values {
      guard ellipsis_identifier_node(value).bind(node => {
          index.identifier_source(node)
        })
        is Some(source) else {
        return false
      }
      sources.push(source)
    }
    if !bindings.accept_source(name, MultipleIdentifiers(sources)) {
      return false
    }
  }
  true
}
