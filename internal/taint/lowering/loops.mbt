///|
fn binding_items(
  node : @untyped_cst.CstNode,
  field : String,
) -> Array[@untyped_cst.CstNode] {
  if @cst.child(node, field) is Some(list) {
    @cst.raw_children(list, "item")
  } else {
    []
  }
}

///|
fn Builder::loop_expr(
  self : Builder,
  node : @untyped_cst.CstNode,
  outer : Context,
) -> ValueId raise LoweringError {
  let mut ctx = { ..outer, scope: self.scope_for(node, outer.scope), }
  let collection = if node.kind is Expr_ForEach {
    Some(self.lower(required(node, "expr"), outer))
  } else {
    None
  }
  let initial = binding_items(node, "init")
  // Evaluate all initializers in the outer environment before introducing any
  // loop bindings. Their own side effects retain source order.
  let initial_values = initial.map(pair => {
    self.lower(required(pair, "expr"), outer)
  })
  let binders : Array[BindingId] = []
  for pair in initial {
    let (next, id) = self.bind(
      ctx,
      required_name(required(pair, "name")),
      site=pair.loc,
    )
    ctx = next
    binders.push(id)
  }
  let header = self.block(binders.length(), node.loc)
  let body = self.block(0, node.loc)
  let natural = self.block(0, node.loc)
  let update = self.block(0, node.loc)
  let after = self.block(1, node.loc)
  self.end(Jump(edge(header, initial_values)))
  self.current = Some(header)
  for i in 0..<binders.length() {
    let _ = self.emit(
      Write(root_path(binders[i]), self.blocks[header.0].parameters[i]),
    )
  }
  let controls = ctx.controls.copy()
  controls.push({
    label: label_of(node),
    break_to: { block: after, depth: ctx.cleanups.length(), kind: Breaking, },
    continue_to: Some({
      block: header,
      depth: ctx.cleanups.length(),
      kind: Continuing,
    }),
    binders,
  })
  ctx = { ..ctx, controls, }
  let body_ctx = if node.kind is Expr_While || node.kind is Expr_For {
    if @cst.child(node, "cond") is Some(cond) {
      self.condition(cond, ctx, body, natural)
    } else {
      if node.kind is Expr_While {
        raise UnsupportedSyntax(node.loc, "missing while condition")
      }
      self.end(Jump(edge(body, [])))
      ctx
    }
  } else {
    self.end(Branch(collection.unwrap(), edge(body, []), edge(natural, [])))
    ctx
  }
  self.current = Some(body)
  let body_ctx = if collection is Some(collection) {
    let value = self.emit(Project(collection, AnyIndex))
    let pattern = required(node, "pattern")
    if pattern.kind is List_TuplePatternList {
      let mut next = body_ctx
      for pattern in @cst.raw_children(pattern, "item") {
        next = self.pattern(pattern, value, next)
      }
      next
    } else {
      self.pattern(pattern, value, body_ctx)
    }
  } else {
    body_ctx
  }
  let _ = self.lower(required(node, "body"), body_ctx)
  self.end(Jump(edge(update, [])))
  self.current = Some(update)
  let updates = binding_items(node, "continue")
  let values = updates.map(pair => self.lower(required(pair, "expr"), body_ctx))
  let next_values = binders.map(id => {
    let mut updated : ValueId? = None
    for i in 0..<updates.length() {
      if body_ctx.resolve(required_name(required(updates[i], "name"))) ==
        Some(id) {
        updated = Some(values[i])
      }
    }
    updated.unwrap_or_else(() => self.emit(Read(root_path(id))))
  })
  self.end(Jump(edge(header, next_values)))
  self.current = Some(natural)
  let result = if @cst.child(node, "else") is Some(otherwise) {
    self.lower(otherwise, ctx)
  } else {
    self.emit(Clean)
  }
  self.end(Jump(edge(after, [result])))
  self.current = Some(after)
  self.blocks[after.0].parameters[0]
}

///|
fn Builder::control_expr(
  self : Builder,
  node : @untyped_cst.CstNode,
  ctx : Context,
) -> ValueId raise LoweringError {
  let label = label_of(node)
  let continuing = node.kind is Expr_Continue
  let mut target : Control? = None
  for i = ctx.controls.length() - 1; i >= 0; i = i - 1 {
    let control = ctx.controls[i]
    if (label is Some(_) && control.label == label) ||
      (label is None && control.continue_to is Some(_)) {
      target = Some(control)
      break
    }
  }
  guard target is Some(control) else {
    raise UnsupportedSyntax(node.loc, "unresolved control target")
  }
  if continuing {
    guard control.continue_to is Some(target) else {
      raise UnsupportedSyntax(node.loc, "continue targets a non-loop block")
    }
    let raw = binding_items(node, "arg")
    let arguments = if raw.is_empty() {
      control.binders.map(id => self.emit(Read(root_path(id))))
    } else {
      raw.map(expr => self.lower(expr, ctx))
    }
    if arguments.length() != control.binders.length() {
      raise UnsupportedSyntax(
        node.loc,
        "continue argument count does not match loop bindings",
      )
    }
    self.exit(ctx, target, arguments)
  } else {
    let value = if @cst.child(node, "expr") is Some(expr) {
      self.lower(expr, ctx)
    } else {
      self.emit(Clean)
    }
    self.exit(ctx, control.break_to, [value])
  }
  self.value()
}
