///|
fn SourceIndex::bind_name(
  self : SourceIndex,
  scope : ScopeId,
  id : NodeId,
  name : String,
) -> ScopeId {
  if self.scope_ids.get((scope, id)) is Some(found) {
    return found
  }
  let result = self.scopes.length()
  self.scopes.push({ parent: scope, binding: id, name, })
  self.scope_ids[(scope, id)] = result
  result
}

///|
fn SourceIndex::bind_named(
  self : SourceIndex,
  scope : ScopeId,
  id : NodeId,
) -> ScopeId {
  match name_node(self.node(id)).bind(normalized_name) {
    Some(name) => self.bind_name(scope, id, name)
    None => scope
  }
}

///|
pub fn SourceIndex::resolve(
  self : SourceIndex,
  scope : ScopeId,
  name : String,
) -> BindingId? {
  self.ensure_scopes()
  let path : Array[ScopeId] = []
  let binding = for current = scope {
    if current < 0 {
      break None
    }
    if self.resolutions.get((current, name)) is Some(found) {
      break found
    }
    path.push(current)
    let entry = self.scopes[current]
    if entry.name == name {
      break Some(entry.binding)
    }
    continue entry.parent
  }
  for id in path {
    self.resolutions[(id, name)] = binding
  }
  binding
}

///|
fn SourceIndex::bind_pattern(
  self : SourceIndex,
  scope : ScopeId,
  pattern : NodeId?,
) -> ScopeId {
  guard pattern is Some(pattern) else { return scope }
  let pending = [pattern]
  let seen : Map[String, Bool] = Map([])
  let mut current = scope
  while pending.pop() is Some(id) {
    let node = self.node(id)
    let binder = match node.kind {
      @untyped_cst.Name_Binder => normalized_name(node)
      @untyped_cst.Pattern_Var => normalized_pattern_identifier_name(node)
      @untyped_cst.Pattern_Alias | @untyped_cst.RegexPattern_Alias =>
        raw_child(node, "name").bind(normalized_name)
      @untyped_cst.Field_Pattern if raw_child(node, "pattern") is None =>
        raw_child(node, "name").bind(normalized_name)
      @untyped_cst.Pattern_Rest =>
        raw_child(node, "name")
        .bind(normalized_name)
        .filter(name => name != "_")
      _ => None
    }
    if binder is Some(name) && !seen.contains(name) {
      current = self.bind_name(current, id, name)
      seen[name] = true
    }
    if node.kind is (@untyped_cst.Name_Binder | @untyped_cst.Pattern_Var) {
      continue
    }
    for i = self.nodes[id].children.length() - 1; i >= 0; i = i - 1 {
      let child = self.nodes[id].children[i].1
      if !is_syntax_kind(self.node(child).kind) {
        pending.push(child)
      }
    }
  }
  current
}

///|
fn SourceIndex::bind_condition(
  self : SourceIndex,
  scope : ScopeId,
  condition : NodeId?,
) -> ScopeId {
  guard condition is Some(id) else { return scope }
  match self.node(id).kind {
    @untyped_cst.Expr_Group => {
      let mut current = scope
      if self.raw(id, "body") is Some(body) {
        for item in self.raw_all(body, "item") {
          current = self.bind_condition(current, Some(item))
        }
      }
      current
    }
    @untyped_cst.Expr_Is | @untyped_cst.Expr_RegexMatch =>
      self.bind_pattern(scope, self.raw(id, "pattern"))
    @untyped_cst.Expr_Infix if operator_name(self.node(id)) == Some("&&") =>
      self.bind_condition(
        self.bind_condition(scope, self.raw(id, "lhs")),
        self.raw(id, "rhs"),
      )
    _ => scope
  }
}

///|
fn SourceIndex::bind_list(
  self : SourceIndex,
  scope : ScopeId,
  list : NodeId?,
) -> ScopeId {
  let mut current = scope
  if list is Some(list) {
    for id in self.raw_all(list, "item") {
      current = if self.raw(id, "pattern") is Some(pattern) {
        self.bind_pattern(current, Some(pattern))
      } else {
        self.bind_named(current, id)
      }
    }
  }
  current
}

///|
fn SourceIndex::bind_recursive(
  self : SourceIndex,
  scope : ScopeId,
  id : NodeId,
) -> ScopeId {
  let mut current = scope
  for binding in self.raw_all(id, "binding") {
    current = self.bind_named(current, binding)
  }
  current
}

///|
fn SourceIndex::after_statement(
  self : SourceIndex,
  scope : ScopeId,
  id : NodeId,
) -> ScopeId {
  match self.node(id).kind {
    @untyped_cst.Expr_Let | @untyped_cst.Expr_LetMut =>
      self.bind_pattern(scope, self.raw(id, "pattern"))
    @untyped_cst.Expr_LetFn | @untyped_cst.Expr_ProofLet =>
      self.bind_named(scope, id)
    @untyped_cst.Expr_LetAnd => self.bind_recursive(scope, id)
    @untyped_cst.Expr_Guard => self.bind_condition(scope, self.raw(id, "cond"))
    _ => scope
  }
}

///|
// All lexical rules live here. Traversal and target matching read these scopes.
fn SourceIndex::index_scopes(self : SourceIndex, root : NodeId) -> Unit {
  let pending : Array[(NodeId, ScopeId)] = [(root, -1)]
  while pending.pop() is Some((id, scope)) {
    self.nodes[id].scope = scope
    let node = self.node(id)
    let overrides : Map[String, ScopeId] = Map([])
    match node.kind {
      @untyped_cst.Impl_Function
      | @untyped_cst.Impl_Test
      | @untyped_cst.Expr_Function
      | @untyped_cst.Expr_LetFn
      | @untyped_cst.Binding_LetRec => {
        let named = if node.kind is @untyped_cst.Expr_LetFn {
          self.bind_named(scope, id)
        } else {
          scope
        }
        overrides["body"] = self.bind_list(named, self.raw(id, "params"))
      }
      @untyped_cst.Expr_LetAnd =>
        overrides["binding"] = self.bind_recursive(scope, id)
      @untyped_cst.Expr_Infix if operator_name(node) == Some("&&") =>
        overrides["rhs"] = self.bind_condition(scope, self.raw(id, "lhs"))
      @untyped_cst.Expr_If | @untyped_cst.Expr_While =>
        overrides["body"] = self.bind_condition(scope, self.raw(id, "cond"))
      @untyped_cst.Expr_For
      | @untyped_cst.Expr_ForEach
      | @untyped_cst.Expr_ListComprehension => {
        let loop_scope = self.bind_list(
          self.bind_pattern(scope, self.raw(id, "pattern")),
          self.raw(id, "init"),
        )
        let body_scope = self.bind_condition(loop_scope, self.raw(id, "cond"))
        overrides["cond"] = loop_scope
        overrides["continue"] = body_scope
        overrides["else"] = loop_scope
        overrides["where"] = loop_scope
        overrides["guard"] = body_scope
        overrides["body"] = self.bind_condition(
          body_scope,
          self.raw(id, "guard"),
        )
      }
      @untyped_cst.Case_MatchCase | @untyped_cst.Case_LexScanCase => {
        let case_scope = self.bind_pattern(scope, self.raw(id, "pattern"))
        overrides["cond"] = case_scope
        overrides["body"] = self.bind_condition(
          case_scope,
          self.raw(id, "cond"),
        )
      }
      @untyped_cst.Expr_Quantifier =>
        if raw_child(node, "name").bind(normalized_name) is Some(text) {
          overrides["body"] = self.bind_name(scope, id, text)
        }
      _ => ()
    }
    let mut current = scope
    for (label, child) in self.nodes[id].children {
      let statement = (
          node.kind is @untyped_cst.Expression &&
          self.node(child).kind.is_expr()
        ) ||
        (
          node.kind is @untyped_cst.List_BlockStatementList &&
          label == Some("item")
        )
      let child_scope = if statement {
        current
      } else {
        label.bind(name => overrides.get(name)).unwrap_or(scope)
      }
      pending.push((child, child_scope))
      if statement {
        current = self.after_statement(current, child)
      }
    }
  }
}

///|
fn SourceIndex::add_sequence(
  self : SourceIndex,
  owner : NodeId,
  nodes : Array[NodeId],
) -> Int {
  let list = self.sequences.length()
  let scopes : Array[ScopeId] = []
  self.sequences.push({
    owner,
    nodes,
    values: nodes.map(id => self.node(id)),
    scopes,
  })
  for position, id in nodes {
    self.nodes[id].statement = Some((list, position))
  }
  self.nodes[owner].sequence = Some(list)
  list
}

///|
// Plain queries and rules without inherited identifiers only need traversal.
// Initialize the one lexical index on its first use, then share it for the scan.
fn SourceIndex::ensure_scopes(self : SourceIndex) -> Unit {
  if self.scoped {
    return
  }
  self.index_scopes(0)
  for sequence in self.sequences {
    for id in sequence.nodes {
      sequence.scopes.push(self.nodes[id].scope)
    }
    let last_scope = match sequence.nodes.last() {
      Some(last) => self.after_statement(self.nodes[last].scope, last)
      None => self.nodes[sequence.owner].scope
    }
    sequence.scopes.push(last_scope)
  }
  self.scoped = true
}

///|
fn SourceIndex::index_sequences(self : SourceIndex) -> Unit {
  for id, entry in self.nodes {
    match entry.node.kind {
      @untyped_cst.Expression =>
        ignore(
          self.add_sequence(
            id,
            entry.children.filter_map(child => {
              if self.node(child.1).kind.is_expr() {
                Some(child.1)
              } else {
                None
              }
            }),
          ),
        )
      @untyped_cst.List_BlockStatementList =>
        ignore(self.add_sequence(id, self.raw_all(id, "item")))
      _ => ()
    }
  }
  for id, entry in self.nodes {
    if entry.node.kind is (@untyped_cst.Expr_Block | @untyped_cst.Expr_Sequence) {
      for current = id {
        if self.nodes[current].sequence is Some(list) {
          self.nodes[id].sequence = Some(list)
          break
        }
        match self.raw(current, "body") {
          Some(body) => continue body
          None => break
        }
      }
    }
    if continuation_owner(entry.node.kind) && entry.statement is None {
      ignore(self.add_sequence(id, [id]))
    }
  }
}
