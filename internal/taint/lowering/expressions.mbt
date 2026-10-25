///|
/// Explicit executable-node support table. Recovery and unlisted syntax must
/// produce an incomplete diagnostic; it may never silently evaluate clean.
pub fn supports(kind : @untyped_cst.NodeKind) -> Bool {
  match kind {
    Expr_Block
    | Expr_Sequence
    | Expr_Ident
    | Expr_Constant
    | Expr_Unit
    | Expr_Constr
    | Expr_Method
    | Expr_MultilineString
    | Expr_Group
    | Expr_Constraint
    | Expr_Field
    | Expr_ArrayGet
    | Expr_ArrayGetSlice
    | Expr_Tuple
    | Expr_Array
    | Expr_Record
    | Expr_RecordUpdate
    | Expr_Map
    | Expr_Infix
    | Expr_Unary
    | Expr_As
    | Expr_Apply
    | Expr_DotApply
    | Expr_Pipe
    | Expr_RevPipe
    | Expr_Assign
    | Expr_Mutate
    | Expr_ArraySet
    | Expr_ArrayAugmentedSet
    | Expr_If
    | Expr_Match
    | Expr_Try
    | Expr_TryOperator
    | Expr_For
    | Expr_ForEach
    | Expr_While
    | Expr_Function
    | Expr_Is
    | Expr_RegexMatch
    | Expr_LexMatch
    | Expr_LexScan
    | Expr_Interp
    | Expr_BytesInterp
    | Expr_Return
    | Expr_Raise
    | Expr_Break
    | Expr_Continue
    | Expr_LabelledBlock
    | Expr_Let
    | Expr_LetMut
    | Expr_LetFn
    | Expr_LetAnd
    | Expr_Guard
    | Expr_Defer
    | Expr_ErrDefer
    | Expr_ProofAssert => true
    _ => false
  }
}

///|
fn Builder::sequence(
  self : Builder,
  node : @untyped_cst.CstNode,
  outer : Context,
) -> ValueId raise LoweringError {
  let mut ctx = { ..outer, scope: self.scope_for(node, outer.scope), }
  let mut value = self.emit(Clean)
  for statement in @cst.sequence_items(node) {
    // Still inspect the support table for unreachable statements.
    if !supports(statement.kind) {
      raise UnsupportedSyntax(
        statement.loc,
        "unsupported executable syntax \{Repr(statement.kind)}",
      )
    }
    if self.current is None {
      continue
    }
    match statement.kind {
      Expr_Let | Expr_LetMut => {
        value = self.lower(required(statement, "expr"), ctx)
        ctx = self.pattern(required(statement, "pattern"), value, ctx)
      }
      Expr_LetFn => {
        value = self.emit(Clean)
        ctx = self.bind_value(ctx, statement, value)
      }
      Expr_LetAnd => {
        value = self.emit(Clean)
        for binding in @cst.raw_children(statement, "binding") {
          ctx = self.bind_value(ctx, binding, value)
        }
      }
      Expr_Defer | Expr_ErrDefer => {
        let id = self.cleanups.length()
        self.cleanups.push({
          expr: required(statement, "expr"),
          context: ctx,
          error_only: statement.kind is Expr_ErrDefer,
        })
        let cleanups = ctx.cleanups.copy()
        cleanups.push(id)
        ctx = { ..ctx, cleanups, }
        value = self.emit(Clean)
      }
      Expr_Guard => {
        let success = self.block(0, statement.loc)
        let failure = self.block(0, statement.loc)
        let next = self.condition(
          required(statement, "cond"),
          ctx,
          success,
          failure,
        )
        self.current = Some(failure)
        if @cst.child(statement, "else") is Some(otherwise) {
          let _ = self.lower(otherwise, ctx)
        }
        self.end(Abort)
        self.current = Some(success)
        ctx = next
        value = self.emit(Clean)
      }
      _ => value = self.lower(statement, ctx)
    }
  }
  if ctx.cleanups.length() > outer.cleanups.length() && self.current is Some(_) {
    let after = self.block(1, node.loc)
    self.exit(
      ctx,
      { block: after, depth: outer.cleanups.length(), kind: Normal, },
      [value],
    )
    self.current = Some(after)
    value = self.blocks[after.0].parameters[0]
  }
  value
}

///|
fn Builder::lower(
  self : Builder,
  node : @untyped_cst.CstNode,
  ctx : Context,
) -> ValueId raise LoweringError {
  if !supports(node.kind) {
    raise UnsupportedSyntax(
      node.loc,
      "unsupported executable syntax \{Repr(node.kind)}",
    )
  }
  if self.current is None {
    return self.value()
  }
  match node.kind {
    Expr_Block | Expr_Sequence => self.sequence(node, ctx)
    Expr_Ident => {
      if @cst.normalized_expr_identifier_name(node) is None {
        raise UnsupportedSyntax(node.loc, "missing identifier name")
      }
      if storage_path(node, ctx) is Some(path) {
        self.emit(Read(path))
      } else {
        self.emit(Clean)
      }
    }
    Expr_Constant => {
      if @cst.constant(node) is None {
        raise UnsupportedSyntax(node.loc, "missing constant payload")
      }
      self.emit(Clean)
    }
    Expr_Unit
    | Expr_Constr
    | Expr_Method
    | Expr_MultilineString
    | Expr_Function => self.emit(Clean)
    Expr_Group | Expr_Constraint | Expr_Unary | Expr_As | Expr_ProofAssert =>
      self.lower(required(node, "expr"), ctx)
    Expr_Field => {
      let receiver = self.lower(required(node, "self"), ctx)
      self.emit(Project(receiver, accessor(required(node, "field"))))
    }
    Expr_ArrayGet => {
      let receiver = self.lower(required(node, "self"), ctx)
      let index = required(node, "index")
      let _ = self.lower(index, ctx)
      self.emit(Project(receiver, index_segment(index)))
    }
    Expr_ArrayGetSlice => {
      let receiver = self.lower(required(node, "self"), ctx)
      for field in ["start", "end"] {
        if @cst.child(node, field) is Some(expr) {
          let _ = self.lower(expr, ctx)
        }
      }
      let item = self.emit(Project(receiver, AnyIndex))
      self.emit(Update(self.emit(Clean), AnyIndex, item))
    }
    Expr_Tuple | Expr_Array => {
      let mut result = self.emit(Clean)
      let fields = items(node, "body")
      for i in 0..<fields.length() {
        let field = fields[i]
        let expr = if node.kind is Expr_Array {
          required(field, "expr")
        } else {
          field
        }
        let value = self.lower(expr, ctx)
        let segment : PathSegment = if node.kind is Expr_Array {
          ConstIndex(i.to_string())
        } else {
          TupleIndex(i)
        }
        result = self.emit(Update(result, segment, value))
      }
      result
    }
    Expr_Record | Expr_RecordUpdate => {
      let fields = items(node, "body")
      let mut result = self.emit(Clean)
      for field in fields {
        if field.kind is Field_RecordSpread {
          result = self.lower(required(field, "expr"), ctx)
        }
      }
      for field in fields {
        if !(field.kind is Field_RecordSpread) {
          let value = self.lower(required(field, "expr"), ctx)
          result = self.emit(Update(result, Field(required_name(field)), value))
        }
      }
      result
    }
    Expr_Map => {
      let mut result = self.emit(Clean)
      for field in items(node, "body") {
        // Keys are constants in the current parser. Values execute in order.
        let value = self.lower(required(field, "expr"), ctx)
        result = self.emit(Update(result, AnyIndex, value))
      }
      result
    }
    Expr_Infix => {
      let op = @cst.operator_name(node)
      if op == Some("&&") || op == Some("||") {
        self.predicate_value(node, ctx)
      } else {
        let lhs = self.lower(required(node, "lhs"), ctx)
        let rhs = self.lower(required(node, "rhs"), ctx)
        self.emit(Compute([lhs, rhs]))
      }
    }
    Expr_Assign | Expr_Mutate | Expr_ArraySet | Expr_ArrayAugmentedSet =>
      self.assignment(node, ctx)
    Expr_Apply | Expr_DotApply | Expr_Pipe | Expr_RevPipe =>
      self.call(node, ctx)
    Expr_If => self.if_expr(node, ctx)
    Expr_Is | Expr_RegexMatch => self.predicate_value(node, ctx)
    Expr_Match | Expr_LexMatch | Expr_LexScan => {
      let value = self.lower(required(node, "expr"), ctx)
      let cases = if node.kind is Expr_Match {
        @cst.raw_children(node, "case")
      } else {
        case_items(required(node, "case"))
      }
      self.cases(
        cases,
        value,
        ctx,
        node.kind is (Expr_LexMatch | Expr_LexScan),
        None,
      )
    }
    Expr_Try => self.try_expr(node, ctx)
    Expr_TryOperator => {
      let aborted = self.block(1, node.loc)
      self.blocks[aborted.0].terminator = Abort
      self.lower(required(node, "body"), {
        ..ctx,
        handler: {
          block: aborted,
          depth: ctx.cleanups.length(),
          kind: Exceptional,
        },
      })
    }
    Expr_While | Expr_For | Expr_ForEach => self.loop_expr(node, ctx)
    Expr_Return | Expr_Raise => {
      let value = if @cst.child(node, "expr") is Some(expr) {
        self.lower(expr, ctx)
      } else {
        self.emit(Clean)
      }
      self.exit(
        ctx,
        if node.kind is Expr_Return {
          ctx.returning
        } else {
          ctx.handler
        },
        [value],
      )
      value
    }
    Expr_Break | Expr_Continue => self.control_expr(node, ctx)
    Expr_LabelledBlock => {
      let after = self.block(1, node.loc)
      let controls = ctx.controls.copy()
      controls.push({
        label: label_of(node),
        break_to: {
          block: after,
          depth: ctx.cleanups.length(),
          kind: Breaking,
        },
        continue_to: None,
        binders: [],
      })
      let value = self.lower(required(node, "body"), { ..ctx, controls, })
      self.end(Jump(edge(after, [value])))
      self.current = Some(after)
      self.blocks[after.0].parameters[0]
    }
    Expr_Interp | Expr_BytesInterp => {
      let values : Array[ValueId] = []
      for field in @cst.semantic_children(node) {
        if field.1.kind is InterpSegment_Source {
          values.push(self.lower(required(field.1, "expr"), ctx))
        }
      }
      self.emit(Compute(values))
    }
    _ =>
      raise UnsupportedSyntax(
        node.loc,
        "statement requires a lexical block: \{Repr(node.kind)}",
      )
  }
}

///|
fn Builder::assignment(
  self : Builder,
  node : @untyped_cst.CstNode,
  ctx : Context,
) -> ValueId raise LoweringError {
  let mut old : ValueId? = None
  let augmented = @cst.raw_child(node, "augmented").bind(@cst.bool_payload) ==
    Some(true) ||
    node.kind is Expr_ArrayAugmentedSet
  let path = if node.kind is Expr_Assign {
    let name = required_name(required(node, "semantic_name"))
    ctx.resolve(name).map(root_path)
  } else {
    let receiver = required(node, "self")
    let receiver_value = self.lower(receiver, ctx)
    let segment = if node.kind is Expr_Mutate {
      accessor(required(node, "field"))
    } else {
      let index = required(node, "index")
      let _ = self.lower(index, ctx)
      index_segment(index)
    }
    if augmented {
      old = Some(self.emit(Project(receiver_value, segment)))
    }
    storage_path(receiver, ctx).map(path => child_path(path, segment))
  }
  if augmented && old is None && path is Some(path) {
    old = Some(self.emit(Read(path)))
  }
  let rhs = self.lower(required(node, "rhs"), ctx)
  let value = if old is Some(old) {
    self.emit(Compute([old, rhs]))
  } else {
    rhs
  }
  if path is Some(path) {
    let _ = self.emit(Write(path, value))
  }
  self.emit(Clean)
}
