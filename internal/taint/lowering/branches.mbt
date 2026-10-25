///|
fn Builder::if_expr(
  self : Builder,
  node : @untyped_cst.CstNode,
  ctx : Context,
) -> ValueId raise LoweringError {
  let yes = self.block(0, node.loc)
  let no = self.block(0, node.loc)
  let join = self.block(1, node.loc)
  let next = self.condition(required(node, "cond"), ctx, yes, no)
  self.current = Some(yes)
  let value = self.lower(required(node, "body"), next)
  self.end(Jump(edge(join, [value])))
  self.current = Some(no)
  let value = if @cst.child(node, "else") is Some(otherwise) {
    self.lower(otherwise, ctx)
  } else {
    self.emit(Clean)
  }
  self.end(Jump(edge(join, [value])))
  self.current = Some(join)
  self.blocks[join.0].parameters[0]
}

///|
fn case_items(node : @untyped_cst.CstNode) -> Array[@untyped_cst.CstNode] {
  let cases = @cst.raw_children(node, "case")
  if cases.is_empty() {
    @cst.raw_children(node, "item")
  } else {
    cases
  }
}

///|
fn Builder::cases(
  self : Builder,
  cases : Array[@untyped_cst.CstNode],
  value : ValueId,
  ctx : Context,
  lexical : Bool,
  unmatched : Target?,
) -> ValueId raise LoweringError {
  let join = self.block(1, self.loc)
  let mut exhaustive = false
  for case in cases {
    let success = self.block(0, case.loc)
    let failure = self.block(0, case.loc)
    self.end(Branch(value, edge(success, []), edge(failure, [])))
    self.current = Some(success)
    let pattern = required(case, "pattern")
    if !lexical && @cst.child(case, "cond") is None && irrefutable(pattern) {
      exhaustive = true
    }
    let scoped = { ..ctx, scope: self.scope_for(case, ctx.scope), }
    let next = if lexical {
      match
        @cst.raw_child(pattern, "lex_scan_case_pattern").map(item => item.kind) {
        Some(LexScanCasePattern_Binder) =>
          self.bind_value(scoped, pattern, value)
        _ => self.regex_pattern(pattern, value, scoped)
      }
    } else {
      self.pattern(pattern, value, scoped)
    }
    let body_ctx = if @cst.child(case, "cond") is Some(guard_expr) {
      let guarded = self.block(0, case.loc)
      let bound = self.condition(guard_expr, next, guarded, failure)
      self.current = Some(guarded)
      bound
    } else {
      next
    }
    let result = self.lower(required(case, "body"), body_ctx)
    self.end(Jump(edge(join, [result])))
    // Failure keeps guard side effects, then tries the next case using its
    // original lexical environment.
    self.current = Some(failure)
  }
  if unmatched is Some(target) && !exhaustive {
    self.exit(ctx, target, [value])
  } else if cases.is_empty() {
    self.end(Jump(edge(join, [value])))
  } else {
    self.end(Abort)
  }
  self.current = Some(join)
  self.blocks[join.0].parameters[0]
}

///|
fn Builder::try_expr(
  self : Builder,
  node : @untyped_cst.CstNode,
  ctx : Context,
) -> ValueId raise LoweringError {
  let caught = self.block(1, node.loc)
  let join = self.block(1, node.loc)
  let body_ctx = {
    ..ctx,
    handler: { block: caught, depth: ctx.cleanups.length(), kind: Exceptional, },
  }
  let value = self.lower(required(node, "body"), body_ctx)
  let value = if @cst.child(node, "else") is Some(otherwise) {
    self.cases(case_items(otherwise), value, ctx, false, None)
  } else {
    value
  }
  self.end(Jump(edge(join, [value])))
  self.current = Some(caught)
  let error = self.blocks[caught.0].parameters[0]
  let result = self.cases(
    case_items(required(node, "case")),
    error,
    ctx,
    false,
    Some(ctx.handler),
  )
  self.end(Jump(edge(join, [result])))
  self.current = Some(join)
  self.blocks[join.0].parameters[0]
}

///|
// This is a pattern contract, independent of scrutinee feasibility. Without a
// guard these patterns exhaust a catch; an unmatched exception cannot escape.
fn irrefutable(pattern : @untyped_cst.CstNode) -> Bool {
  let pattern = @cst.unwrap_groups(pattern)
  match pattern.kind {
    Pattern_Any | Pattern_Var => true
    Pattern_Alias | Pattern_Constraint =>
      @cst.child(pattern, "pattern").map(irrefutable).unwrap_or(false)
    Pattern_Or =>
      @cst.child(pattern, "lhs").map(irrefutable).unwrap_or(false) ||
      @cst.child(pattern, "rhs").map(irrefutable).unwrap_or(false)
    _ => false
  }
}
