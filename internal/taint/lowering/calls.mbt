///|
fn callee_name(node : @untyped_cst.CstNode) -> String? {
  match node.kind {
    Expr_Ident => @cst.normalized_expr_identifier_name(node)
    Expr_Constr => name_of(node)
    Expr_Field => @cst.child(node, "field").bind(name_of)
    Expr_Method => @cst.child(node, "method_name").bind(name_of)
    Expr_Group | Expr_Constraint => @cst.child(node, "expr").bind(callee_name)
    _ => None
  }
}

///|
fn Builder::argument(
  self : Builder,
  expr : @untyped_cst.CstNode,
  ctx : Context,
  index : Int32,
  label : String?,
) -> @cfg.Argument raise LoweringError {
  let value = self.lower(expr, ctx)
  { index, label, expr, loc: expr.loc, path: storage_path(expr, ctx), value, }
}

///|
fn Builder::call(
  self : Builder,
  node : @untyped_cst.CstNode,
  ctx : Context,
) -> ValueId raise LoweringError {
  let mut kind : @model.CallKind = Apply
  let mut target = node
  let mut receiver : @cfg.Argument? = None
  let arguments : Array[@cfg.Argument] = []
  if node.kind is Expr_Pipe {
    kind = Pipe
    arguments.push(self.argument(required(node, "lhs"), ctx, 0, None))
    target = required(node, "rhs")
  } else if node.kind is Expr_RevPipe {
    kind = RevPipe
    target = required(node, "lhs")
    let _ = self.lower(target, ctx)
    arguments.push(self.argument(required(node, "rhs"), ctx, 0, None))
  }
  let callee_binding = if node.kind is Expr_RevPipe {
    callee_binding_of(target, ctx)
  } else if target.kind is Expr_Apply {
    callee_binding_of(required(target, "func"), ctx)
  } else if target.kind is Expr_DotApply {
    None
  } else {
    callee_binding_of(target, ctx)
  }
  let name = if node.kind is Expr_RevPipe {
    callee_name(target)
  } else if target.kind is Expr_DotApply {
    if node.kind is Expr_DotApply {
      kind = DotApply
    }
    receiver = Some(self.argument(required(target, "self"), ctx, -1, None))
    name_of(required(target, "field"))
  } else if target.kind is Expr_Apply {
    let func = required(target, "func")
    let _ = self.lower(func, ctx)
    callee_name(func)
  } else {
    let _ = self.lower(target, ctx)
    callee_name(target)
  }
  if node.kind is Expr_Apply ||
    node.kind is Expr_DotApply ||
    (node.kind is Expr_Pipe && target.kind is (Expr_Apply | Expr_DotApply)) {
    let raw_args = items(target, "arg")
    let start = arguments.length()
    for i in 0..<raw_args.length() {
      let arg = raw_args[i]
      let expr = required(arg, "expr")
      arguments.push(
        self.argument(expr, ctx, start + i, @cst.argument_label_name(arg)),
      )
    }
  }
  let result = self.value()
  let error = self.value()
  let call_index = self.calls.length()
  self.calls.push({
    kind,
    cst: node,
    loc: node.loc,
    callee_name: name,
    callee_binding,
    receiver,
    arguments,
    result,
    error,
  })
  let normal = self.block(0, node.loc)
  // Every call has a potential edge. Only explicitly modeled exceptional
  // outcomes activate it; unknown calls activate the normal edge only.
  let exceptional = self.cleanup_chain(ctx, ctx.handler, 1)
  self.end(Invoke(call_index, edge(normal, []), edge(exceptional, [error])))
  self.current = Some(normal)
  result
}

///|
fn callee_binding_of(node : @untyped_cst.CstNode, ctx : Context) -> BindingId? {
  match node.kind {
    Expr_Ident =>
      @cst.normalized_expr_identifier_name(node).bind(name => ctx.resolve(name))
    Expr_Group | Expr_Constraint =>
      @cst.child(node, "expr").bind(inner => callee_binding_of(inner, ctx))
    _ => None
  }
}
