///|
fn SourceIndex::bind_name(
  self : SourceIndex,
  scope : ScopeId,
  id : NodeId,
  name : String,
) -> ScopeId {
  self.mark_identifier(id, VariableBinder(id))
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
  if name_node(self.node(id)).bind(normalized_name) is Some(name) {
    self.bind_name(scope, id, name)
  } else {
    scope
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
  let seen : Map[String, BindingId] = Map([])
  let mut current = scope
  while pending.pop() is Some(id) {
    let node = self.node(id)
    if node.kind is Binding_Regex {
      if self.raw(id, "semantic_binder") is Some(binder) &&
        normalized_name(self.node(binder)) is Some(name) &&
        name != "_" {
        let binding = if seen.get(name) is Some(binding) {
          self.mark_identifier(binder, VariableBinder(binding))
          binding
        } else {
          current = self.bind_name(current, binder, name)
          seen[name] = binder
          binder
        }
        if self.raw(id, "binder") is Some(syntax) {
          self.mark_name_tree(syntax, VariableBinder(binding))
        }
      }
      // Labels are not variables. The semantic binder is already handled, and
      // an absent or wildcard binder must not introduce a binding on descent.
      continue
    }
    let binder = match node.kind {
      Name_Binder => normalized_name(node)
      Pattern_Var => normalized_pattern_identifier_name(node)
      Pattern_Alias | RegexPattern_Alias =>
        raw_child(node, "name").bind(normalized_name)
      Field_Pattern if raw_child(node, "pattern") is None =>
        raw_child(node, "name").bind(normalized_name)
      Pattern_Rest =>
        raw_child(node, "name")
        .bind(normalized_name)
        .filter(name => name != "_")
      _ => None
    }
    if binder is Some(name) {
      if seen.get(name) is Some(binding) {
        self.mark_identifier(id, VariableBinder(binding))
      } else {
        current = self.bind_name(current, id, name)
        seen[name] = id
      }
    }
    if node.kind is (Name_Binder | Pattern_Var) {
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
    Expr_Group => {
      let mut current = scope
      if self.raw(id, "body") is Some(body) {
        for item in self.raw_all(body, "item") {
          current = self.bind_condition(current, Some(item))
        }
      }
      current
    }
    Expr_Is | Expr_RegexMatch =>
      self.bind_pattern(scope, self.raw(id, "pattern"))
    Expr_Infix if operator_name(self.node(id)) == Some("&&") =>
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
fn SourceIndex::mark_for_updates(self : SourceIndex, id : NodeId) -> Unit {
  guard self.raw(id, "init") is Some(init) &&
    self.raw(id, "continue") is Some(updates) else {
    return
  }
  let bindings : Map[String, BindingId] = Map([])
  for binding in self.raw_all(init, "item") {
    if name_node(self.node(binding)).bind(normalized_name) is Some(name) {
      bindings[name] = binding
    }
  }
  for update in self.raw_all(updates, "item") {
    if name_node(self.node(update)).bind(normalized_name) is Some(name) &&
      bindings.get(name) is Some(binding) {
      // The target is the loop variable even when the condition shadows it.
      self.mark_identifier(update, ResolvedVariableReference(binding))
    }
  }
}

///|
fn SourceIndex::after_statement(
  self : SourceIndex,
  scope : ScopeId,
  id : NodeId,
) -> ScopeId {
  match self.node(id).kind {
    Expr_Let | Expr_LetMut => self.bind_pattern(scope, self.raw(id, "pattern"))
    Expr_LetFn | Expr_ProofLet => self.bind_named(scope, id)
    Expr_LetAnd => self.bind_recursive(scope, id)
    Expr_Guard => self.bind_condition(scope, self.raw(id, "cond"))
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
      Expr_Ident | Expr_Assign =>
        if name_node(node).bind(normalized_name) is Some(name) &&
          !name.contains(".") &&
          !name.contains(":") {
          self.mark_identifier(id, VariableReference(id))
        }
      Expr_Is | Expr_RegexMatch =>
        ignore(self.bind_pattern(scope, self.raw(id, "pattern")))
      Impl_Function | Impl_Test | Expr_Function | Expr_LetFn | Binding_LetRec => {
        let named = if node.kind is Expr_LetFn {
          self.bind_named(scope, id)
        } else {
          scope
        }
        overrides["params"] = named
        overrides["body"] = self.bind_list(named, self.raw(id, "params"))
      }
      Impl_EnumView =>
        // The body field contains constructors; the view function is in expr.
        overrides["expr"] = self.bind_list(scope, self.raw(id, "params"))
      Expr_LetAnd => overrides["binding"] = self.bind_recursive(scope, id)
      Expr_Infix if operator_name(node) == Some("&&") =>
        overrides["rhs"] = self.bind_condition(scope, self.raw(id, "lhs"))
      Expr_If | Expr_While =>
        overrides["body"] = self.bind_condition(scope, self.raw(id, "cond"))
      Expr_For | Expr_ForEach | Expr_ListComprehension => {
        self.mark_for_updates(id)
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
      Case_MatchCase | Case_LexScanCase => {
        let case_scope = self.bind_pattern(scope, self.raw(id, "pattern"))
        overrides["cond"] = case_scope
        overrides["body"] = self.bind_condition(
          case_scope,
          self.raw(id, "cond"),
        )
      }
      Expr_Quantifier =>
        if raw_child(node, "name").bind(normalized_name) is Some(text) {
          overrides["body"] = self.bind_name(scope, id, text)
        }
      _ => ()
    }
    let mut current = scope
    for (label, child) in self.nodes[id].children {
      let statement = (
          node.kind is Expression && self.node(child).kind.is_expr()
        ) ||
        (node.kind is List_BlockStatementList && label == Some("item"))
      let parameter = node.kind is List_ParameterList && label == Some("item")
      let child_scope = if statement || parameter {
        current
      } else {
        label.bind(name => overrides.get(name)).unwrap_or(scope)
      }
      pending.push((child, child_scope))
      if statement {
        current = self.after_statement(current, child)
      } else if parameter {
        // Defaults see earlier parameters, before this parameter is introduced.
        current = if self.raw(child, "pattern") is Some(pattern) {
          self.bind_pattern(current, Some(pattern))
        } else {
          self.bind_named(current, child)
        }
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
    let last_scope = if sequence.nodes.last() is Some(last) {
      self.after_statement(self.nodes[last].scope, last)
    } else {
      self.nodes[sequence.owner].scope
    }
    sequence.scopes.push(last_scope)
  }
  self.scoped = true
}

///|
fn SourceIndex::index_sequences(self : SourceIndex) -> Unit {
  for id, entry in self.nodes {
    match entry.node.kind {
      Expression =>
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
      List_BlockStatementList =>
        ignore(self.add_sequence(id, self.raw_all(id, "item")))
      _ => ()
    }
  }
  for id, entry in self.nodes {
    if entry.node.kind is (Expr_Block | Expr_Sequence) {
      for current = id {
        if self.nodes[current].sequence is Some(list) {
          self.nodes[id].sequence = Some(list)
          break
        }
        if self.raw(current, "body") is Some(body) {
          continue body
        } else {
          break
        }
      }
    }
    if continuation_owner(entry.node.kind) && entry.statement is None {
      ignore(self.add_sequence(id, [id]))
    }
  }
}
