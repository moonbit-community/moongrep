///|
fn Builder::bind_value(
  self : Builder,
  ctx : Context,
  binder : @untyped_cst.CstNode,
  value : ValueId,
) -> Context raise LoweringError {
  let name = required_name(binder)
  let (next, id) = self.bind(ctx, name, site=binder.loc)
  let _ = self.emit(Write(root_path(id), value))
  next
}

///|
fn Builder::pattern(
  self : Builder,
  pattern : @untyped_cst.CstNode,
  value : ValueId,
  ctx : Context,
) -> Context raise LoweringError {
  let pattern = @cst.unwrap_groups(pattern)
  match pattern.kind {
    Pattern_Var => self.bind_value(ctx, pattern, value)
    Pattern_Any | Pattern_Constant | Pattern_Range => ctx
    Pattern_Constraint => self.pattern(required(pattern, "pattern"), value, ctx)
    Pattern_Alias => {
      let next = self.pattern(required(pattern, "pattern"), value, ctx)
      self.bind_value(next, required(pattern, "name"), value)
    }
    Pattern_Tuple => {
      let mut next = ctx
      let fields = items(pattern, "body")
      for i in 0..<fields.length() {
        next = self.pattern(
          fields[i],
          self.emit(Project(value, TupleIndex(i))),
          next,
        )
      }
      next
    }
    Pattern_Record => {
      let mut next = ctx
      for field in items(pattern, "body") {
        if field.kind is Field_Pattern {
          let projected = self.emit(Project(value, Field(required_name(field))))
          if @cst.child(field, "pattern") is Some(inner) {
            next = self.pattern(inner, projected, next)
          } else {
            next = self.bind_value(next, field, projected)
          }
        }
      }
      next
    }
    Pattern_Array => {
      let body = required(pattern, "body")
      let list = required(body, "body")
      let mut next = ctx
      let mut dynamic = false
      let mut index = 0
      for item in @cst.raw_children(list, "item") {
        let segment : PathSegment = if dynamic || item.kind is Pattern_Rest {
          AnyIndex
        } else {
          ConstIndex(index.to_string())
        }
        let projected = self.emit(Project(value, segment))
        match item.kind {
          ArrayPattern_Pattern =>
            next = self.pattern(required(item, "pattern"), projected, next)
          ArrayPattern_ConstSpread | Pattern_Rest => {
            if name_of(item) is Some(_) {
              next = self.bind_value(next, item, projected)
            }
            dynamic = true
          }
          ArrayPattern_BytesSpread | ArrayPattern_StringSpread => dynamic = true
          _ => raise UnsupportedSyntax(item.loc, "unsupported array pattern")
        }
        index += 1
      }
      next
    }
    Pattern_Constr | Pattern_SpecialConstr => {
      let mut next = ctx
      if @cst.child(pattern, "params") is Some(params) {
        let fields = @cst.raw_children(params, "item")
        for i in 0..<fields.length() {
          let field = fields[i]
          let segment : PathSegment = if @cst.argument_label_name(field)
            is Some(label) {
            Field(label)
          } else {
            TupleIndex(i)
          }
          let projected = self.emit(Project(value, segment))
          if field.kind.is_pattern() {
            next = self.pattern(field, projected, next)
          } else if @cst.child(field, "pattern") is Some(inner) {
            next = self.pattern(inner, projected, next)
          } else if field.kind is Argument_LabelledPun {
            next = self.bind_value(next, field, projected)
          } else {
            raise UnsupportedSyntax(field.loc, "missing constructor pattern")
          }
        }
      }
      next
    }
    Pattern_Map => {
      let mut next = ctx
      for item in items(pattern, "body") {
        next = self.pattern(
          required(item, "pattern"),
          self.emit(Project(value, AnyIndex)),
          next,
        )
      }
      next
    }
    Pattern_Or => {
      // Both alternatives bind the same names. Join their projections into the
      // same identities, rather than shadowing one alternative with the other.
      let left = self.block(0, pattern.loc)
      let right = self.block(0, pattern.loc)
      let join = self.block(0, pattern.loc)
      self.end(Branch(value, edge(left, []), edge(right, [])))
      self.current = Some(left)
      let next = self.pattern(required(pattern, "lhs"), value, ctx)
      self.end(Jump(edge(join, [])))
      self.current = Some(right)
      let other = self.pattern(required(pattern, "rhs"), value, ctx)
      for (name, id) in next.env[ctx.env.length():] {
        if other.resolve(name) is Some(other_id) {
          let rhs = self.emit(Read(root_path(other_id)))
          let _ = self.emit(Write(root_path(id), rhs))
        }
      }
      self.end(Jump(edge(join, [])))
      self.current = Some(join)
      next
    }
    _ =>
      raise UnsupportedSyntax(
        pattern.loc,
        "unsupported pattern \{Repr(pattern.kind)}",
      )
  }
}

///|
fn Builder::regex_pattern(
  self : Builder,
  pattern : @untyped_cst.CstNode,
  value : ValueId,
  ctx : Context,
) -> Context raise LoweringError {
  let mut next = ctx
  match pattern.kind {
    RegexPattern_Alias => {
      next = self.regex_pattern(required(pattern, "pattern"), value, next)
      next = self.bind_value(next, required(pattern, "name"), value)
    }
    RegexPattern_Sequence | RegexPattern_Alternation => {
      next = self.regex_pattern(required(pattern, "lhs"), value, next)
      next = self.regex_pattern(required(pattern, "rhs"), value, next)
    }
    RegexPattern_Placeholder =>
      next = self.regex_pattern(required(pattern, "pattern"), value, next)
    RegexPattern_Literal | RegexPattern_Reference => ()
    _ => ()
  }
  if @cst.child(pattern, "bindings") is Some(bindings) {
    for binding in @cst.raw_children(bindings, "item") {
      if @cst.child(binding, "binder") is Some(binder) {
        next = self.bind_value(next, binder, value)
      }
    }
  }
  next
}

///|
fn Builder::condition(
  self : Builder,
  cond : @untyped_cst.CstNode,
  ctx : Context,
  yes : BlockId,
  no : BlockId,
  accumulator? : BindingId,
) -> Context raise LoweringError {
  if cond.kind is Expr_Infix && @cst.operator_name(cond) == Some("&&") {
    let middle = self.block(0, cond.loc)
    let left_ctx = self.condition(
      required(cond, "lhs"),
      ctx,
      middle,
      no,
      accumulator?,
    )
    self.current = Some(middle)
    return self.condition(
      required(cond, "rhs"),
      left_ctx,
      yes,
      no,
      accumulator?,
    )
  }
  if cond.kind is Expr_Infix && @cst.operator_name(cond) == Some("||") {
    let middle = self.block(0, cond.loc)
    let _ = self.condition(
      required(cond, "lhs"),
      ctx,
      yes,
      middle,
      accumulator?,
    )
    self.current = Some(middle)
    let _ = self.condition(required(cond, "rhs"), ctx, yes, no, accumulator?)
    return ctx
  }
  match cond.kind {
    Expr_Is | Expr_RegexMatch => {
      let value = self.lower(required(cond, "expr"), ctx)
      self.accumulate(accumulator, value)
      let success = self.block(0, cond.loc)
      self.end(Branch(value, edge(success, []), edge(no, [])))
      self.current = Some(success)
      let pattern = required(cond, "pattern")
      let mut next = if cond.kind is Expr_Is {
        self.pattern(pattern, value, ctx)
      } else {
        self.regex_pattern(pattern, value, ctx)
      }
      if @cst.child(cond, "bindings") is Some(bindings) {
        for binding in @cst.raw_children(bindings, "item") {
          if @cst.child(binding, "binder") is Some(binder) {
            next = self.bind_value(next, binder, value)
          }
        }
      }
      self.end(Jump(edge(yes, [])))
      next
    }
    Expr_Group =>
      self.condition(required(cond, "expr"), ctx, yes, no, accumulator?)
    _ => {
      let value = self.lower(cond, ctx)
      self.accumulate(accumulator, value)
      self.end(Branch(value, edge(yes, []), edge(no, [])))
      ctx
    }
  }
}

///|
fn Builder::accumulate(
  self : Builder,
  accumulator : BindingId?,
  value : ValueId,
) -> Unit {
  if accumulator is Some(id) {
    let previous = self.emit(Read(root_path(id)))
    let combined = self.emit(Compute([previous, value]))
    let _ = self.emit(Write(root_path(id), combined))
  }
}

///|
// A boolean value explicitly depends on its evaluated operands. Its condition
// bindings still stay on success edges; no control taint enters branch bodies.
fn Builder::predicate_value(
  self : Builder,
  node : @untyped_cst.CstNode,
  ctx : Context,
) -> ValueId raise LoweringError {
  let (_, accumulator) = self.bind(ctx, "$predicate", site=node.loc)
  let clean = self.emit(Clean)
  let _ = self.emit(Write(root_path(accumulator), clean))
  let yes = self.block(0, node.loc)
  let no = self.block(0, node.loc)
  let join = self.block(0, node.loc)
  let _ = self.condition(node, ctx, yes, no, accumulator~)
  self.current = Some(yes)
  self.end(Jump(edge(join, [])))
  self.current = Some(no)
  self.end(Jump(edge(join, [])))
  self.current = Some(join)
  self.emit(Read(root_path(accumulator)))
}
