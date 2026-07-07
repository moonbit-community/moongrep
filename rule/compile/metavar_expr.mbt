///|
fn MetavarRewriteContext::rewrite_expr(
  ctx : MetavarRewriteContext,
  expr : @syntax.Expr,
) -> @syntax.Expr raise {
  match expr {
    Ident(id~, loc~) => Ident(id=ctx.rewrite_expr_var(id), loc~)
    Apply(func~, args~, loc~) =>
      Apply(func=ctx.rewrite_expr(func), args=ctx.rewrite_arguments(args), loc~)
    DotApply(self~, method_name~, args~, return_self~, loc~) =>
      DotApply(
        self=ctx.rewrite_expr(self),
        method_name=ctx.rewrite_label(method_name),
        args=ctx.rewrite_arguments(args),
        return_self~,
        loc~,
      )
    Infix(op~, lhs~, rhs~, loc~) =>
      Infix(
        op=ctx.rewrite_var(op),
        lhs=ctx.rewrite_expr(lhs),
        rhs=ctx.rewrite_expr(rhs),
        loc~,
      )
    Unary(op~, expr=inner, loc~) =>
      Unary(op=ctx.rewrite_var(op), expr=ctx.rewrite_expr(inner), loc~)
    Assign(var_~, expr=inner, augmented_by~, loc~) =>
      Assign(
        var_=ctx.rewrite_var(var_),
        expr=ctx.rewrite_expr(inner),
        augmented_by=ctx.rewrite_optional_var(augmented_by),
        loc~,
      )
    ArrayAugmentedSet(op~, array~, index~, value~, loc~) =>
      ArrayAugmentedSet(
        op=ctx.rewrite_var(op),
        array=ctx.rewrite_expr(array),
        index=ctx.rewrite_expr(index),
        value=ctx.rewrite_expr(value),
        loc~,
      )
    ArrayGet(array~, index~, loc~) =>
      ArrayGet(
        array=ctx.rewrite_expr(array),
        index=ctx.rewrite_expr(index),
        loc~,
      )
    ArraySet(array~, index~, value~, loc~) =>
      ArraySet(
        array=ctx.rewrite_expr(array),
        index=ctx.rewrite_expr(index),
        value=ctx.rewrite_expr(value),
        loc~,
      )
    ArrayGetSlice(array~, start_index~, end_index~, index_loc~, loc~) =>
      ArrayGetSlice(
        array=ctx.rewrite_expr(array),
        start_index=ctx.rewrite_optional_expr(start_index),
        end_index=ctx.rewrite_optional_expr(end_index),
        index_loc~,
        loc~,
      )
    Array(exprs~, loc~) => Array(exprs=ctx.rewrite_expr_list(exprs), loc~)
    Tuple(exprs~, loc~) => Tuple(exprs=ctx.rewrite_expr_list(exprs), loc~)
    ArraySpread(elems~, loc~) =>
      ArraySpread(elems=ctx.rewrite_spreadable_elems(elems), loc~)
    Group(expr=inner, group~, loc~) =>
      Group(expr=ctx.rewrite_expr(inner), group~, loc~)
    Constraint(expr=inner, ty~, loc~) =>
      Constraint(expr=ctx.rewrite_expr(inner), ty~, loc~)
    As(expr=inner, trait_~, loc~) =>
      As(expr=ctx.rewrite_expr(inner), trait_~, loc~)
    Sequence(exprs~, last_expr~, loc~) =>
      Sequence(
        exprs=ctx.rewrite_expr_list(exprs),
        last_expr=ctx.rewrite_expr(last_expr),
        loc~,
      )
    Break(arg~, label~, loc~) =>
      Break(
        arg=ctx.rewrite_optional_expr(arg),
        label=ctx.rewrite_optional_label(label),
        loc~,
      )
    Continue(args~, label~, loc~) =>
      Continue(
        args=ctx.rewrite_expr_list(args),
        label=ctx.rewrite_optional_label(label),
        loc~,
      )
    Defer(expr=inner, body~, loc~) =>
      Defer(expr=ctx.rewrite_expr(inner), body=ctx.rewrite_expr(body), loc~)
    Return(return_value~, loc~) =>
      Return(return_value=ctx.rewrite_optional_expr(return_value), loc~)
    If(cond~, ifso~, ifnot~, loc~) =>
      If(
        cond=ctx.rewrite_expr(cond),
        ifso=ctx.rewrite_expr(ifso),
        ifnot=ctx.rewrite_optional_expr(ifnot),
        loc~,
      )
    For(
      binders~,
      condition~,
      continue_block~,
      body~,
      for_else~,
      where_clause~,
      label~,
      loc~
    ) =>
      For(
        binders=ctx.rewrite_binder_expr_pairs(binders),
        condition=ctx.rewrite_optional_expr(condition),
        continue_block=ctx.rewrite_binder_expr_pairs(continue_block),
        body=ctx.rewrite_expr(body),
        for_else=ctx.rewrite_optional_expr(for_else),
        where_clause=ctx.rewrite_optional_where_clause(where_clause),
        label=ctx.rewrite_optional_label(label),
        loc~,
      )
    ForEach(
      binders~,
      expr=iter,
      init~,
      continue_block~,
      body~,
      else_block~,
      where_clause~,
      label~,
      loc~
    ) =>
      ForEach(
        binders=ctx.rewrite_optional_binders(binders),
        expr=ctx.rewrite_expr(iter),
        init=ctx.rewrite_binder_expr_pairs(init),
        continue_block=ctx.rewrite_binder_expr_pairs(continue_block),
        body=ctx.rewrite_expr(body),
        else_block=ctx.rewrite_optional_expr(else_block),
        where_clause=ctx.rewrite_optional_where_clause(where_clause),
        label=ctx.rewrite_optional_label(label),
        loc~,
      )
    Function(func~, loc~) => Function(func=ctx.rewrite_func(func), loc~)
    Guard(cond~, otherwise~, body~, loc~) =>
      Guard(
        cond=ctx.rewrite_expr(cond),
        otherwise=ctx.rewrite_optional_expr(otherwise),
        body=ctx.rewrite_expr(body),
        loc~,
      )
    Interp(elems~, loc~) => Interp(elems=ctx.rewrite_interp_elems(elems), loc~)
    Is(expr=inner, pat~, loc~) =>
      Is(expr=ctx.rewrite_expr(inner), pat=ctx.rewrite_pattern(pat), loc~)
    Let(pattern~, expr=bound_expr, body~, loc~) =>
      Let(
        pattern=ctx.rewrite_pattern(pattern),
        expr=ctx.rewrite_expr(bound_expr),
        body=ctx.rewrite_expr(body),
        loc~,
      )
    LetMut(binder~, ty~, expr=bound_expr, body~, loc~) =>
      LetMut(
        binder=ctx.rewrite_binder(binder),
        ty~,
        expr=ctx.rewrite_expr(bound_expr),
        body=ctx.rewrite_expr(body),
        loc~,
      )
    LetFn(name~, func~, body~, loc~) =>
      LetFn(
        name=ctx.rewrite_binder(name),
        func=ctx.rewrite_func(func),
        body=ctx.rewrite_expr(body),
        loc~,
      )
    LetAnd(bindings~, body~, loc~) =>
      LetAnd(
        bindings=ctx.rewrite_let_and_bindings(bindings),
        body=ctx.rewrite_expr(body),
        loc~,
      )
    Map(elems~, loc~) => Map(elems=ctx.rewrite_map_expr_elems(elems), loc~)
    Match(expr=matched, cases~, match_loc~, loc~) =>
      Match(
        expr=ctx.rewrite_expr(matched),
        cases=ctx.rewrite_cases(cases),
        match_loc~,
        loc~,
      )
    Constr(constr~, loc~) =>
      Constr(constr=ctx.rewrite_constructor(constr), loc~)
    Method(type_name~, method_name~, loc~) =>
      Method(type_name~, method_name=ctx.rewrite_label(method_name), loc~)
    MultilineString(elems~, loc~) =>
      MultilineString(elems=ctx.rewrite_multiline_string_elems(elems), loc~)
    Mutate(record~, accessor~, field~, augmented_by~, loc~) =>
      Mutate(
        record=ctx.rewrite_expr(record),
        accessor=ctx.rewrite_accessor(accessor),
        field=ctx.rewrite_expr(field),
        augmented_by=ctx.rewrite_optional_var(augmented_by),
        loc~,
      )
    Pipe(lhs~, rhs~, loc~) =>
      Pipe(lhs=ctx.rewrite_expr(lhs), rhs=ctx.rewrite_expr(rhs), loc~)
    RevPipe(lhs~, rhs~, loc~) =>
      RevPipe(lhs=ctx.rewrite_expr(lhs), rhs=ctx.rewrite_expr(rhs), loc~)
    Implies(lhs~, rhs~, loc~) =>
      Implies(lhs=ctx.rewrite_expr(lhs), rhs=ctx.rewrite_expr(rhs), loc~)
    Record(type_name~, fields~, trailing~, loc~) =>
      Record(type_name~, fields=ctx.rewrite_field_defs(fields), trailing~, loc~)
    RecordUpdate(type_name~, record~, fields~, loc~) =>
      RecordUpdate(
        type_name~,
        record=ctx.rewrite_expr(record),
        fields=ctx.rewrite_field_defs(fields),
        loc~,
      )
    RegexMatch(expr=inner, pat~, bindings~, loc~) =>
      RegexMatch(
        expr=ctx.rewrite_expr(inner),
        pat=ctx.rewrite_regex_pattern(pat),
        bindings=ctx.rewrite_regex_bindings(bindings),
        loc~,
      )
    Try(
      body~,
      catch_~,
      try_else~,
      has_try~,
      try_loc~,
      catch_loc~,
      else_loc~,
      loc~
    ) =>
      Try(
        body=ctx.rewrite_expr(body),
        catch_=ctx.rewrite_cases(catch_),
        try_else=ctx.rewrite_optional_cases(try_else),
        has_try~,
        try_loc~,
        catch_loc~,
        else_loc~,
        loc~,
      )
    TryOperator(body~, kind~, try_loc~, loc~) =>
      TryOperator(body=ctx.rewrite_expr(body), kind~, try_loc~, loc~)
    While(loop_cond~, loop_body~, while_else~, label~, loc~) =>
      While(
        loop_cond=ctx.rewrite_expr(loop_cond),
        loop_body=ctx.rewrite_expr(loop_body),
        while_else=ctx.rewrite_optional_expr(while_else),
        label=ctx.rewrite_optional_label(label),
        loc~,
      )
    ListComprehension(kind~, guard_~, body~, loc~) =>
      ListComprehension(
        kind~,
        guard_=ctx.rewrite_optional_expr(guard_),
        body=ctx.rewrite_expr(body),
        loc~,
      )
    ProofLet(binder~, expr=inner, loc~) =>
      ProofLet(
        binder=ctx.rewrite_binder(binder),
        expr=ctx.rewrite_expr(inner),
        loc~,
      )
    ProofAssert(expr=inner, loc~) =>
      ProofAssert(expr=ctx.rewrite_expr(inner), loc~)
    Raise(err_value~, loc~) =>
      Raise(err_value=ctx.rewrite_expr(err_value), loc~)
    TemplateWriting(expr=inner, template~, loc~) =>
      TemplateWriting(
        expr=ctx.rewrite_expr(inner),
        template=ctx.rewrite_expr(template),
        loc~,
      )
    StaticAssert(asserts~, body~) =>
      StaticAssert(asserts~, body=ctx.rewrite_expr(body))
    _ => expr
  }
}

///|
fn MetavarRewriteContext::rewrite_expr_var(
  ctx : MetavarRewriteContext,
  var_ : @syntax.Var,
) -> @syntax.Var raise {
  match var_.name {
    Ident(name~) =>
      match parse_metavar(name, ctx.path, ctx.context) {
        None => var_
        Some(syntax) =>
          match ctx.collect_or_resolve_metavar(syntax, BareExpressionPosition) {
            None => var_
            Some((kind, meta_name)) => {
              ctx.register_metavar(kind, meta_name)
              { name: Ident(name=meta_name), loc: var_.loc }
            }
          }
      }
    Dot(pkg~, id~) =>
      match parse_metavar(id, ctx.path, ctx.context) {
        None => var_
        Some(syntax) =>
          match ctx.collect_or_resolve_metavar(syntax, BareIdentifierPosition) {
            None => var_
            Some((kind, meta_name)) => {
              if kind == "exp" {
                ctx.reject_metavar_position(kind, meta_name)
              } else if kind == "const" {
                ctx.reject_qualified_metavar(kind, meta_name)
              }
              ctx.register_metavar(kind, meta_name)
              { name: Dot(pkg~, id=meta_name), loc: var_.loc }
            }
          }
      }
  }
}

///|
fn MetavarRewriteContext::rewrite_var(
  ctx : MetavarRewriteContext,
  var_ : @syntax.Var,
) -> @syntax.Var raise {
  match var_.name {
    Ident(name~) =>
      match parse_metavar(name, ctx.path, ctx.context) {
        None => var_
        Some(syntax) =>
          match ctx.collect_or_resolve_metavar(syntax, BareIdentifierPosition) {
            None => var_
            Some((kind, meta_name)) => {
              if kind == "exp" || kind == "const" {
                ctx.reject_metavar_position(kind, meta_name)
              }
              ctx.register_metavar(kind, meta_name)
              { name: Ident(name=meta_name), loc: var_.loc }
            }
          }
      }
    Dot(pkg~, id~) =>
      match parse_metavar(id, ctx.path, ctx.context) {
        None => var_
        Some(syntax) =>
          match ctx.collect_or_resolve_metavar(syntax, BareIdentifierPosition) {
            None => var_
            Some((kind, meta_name)) => {
              if kind == "exp" || kind == "const" {
                ctx.reject_metavar_position(kind, meta_name)
              }
              ctx.register_metavar(kind, meta_name)
              { name: Dot(pkg~, id=meta_name), loc: var_.loc }
            }
          }
      }
  }
}

///|
fn MetavarRewriteContext::rewrite_binder(
  ctx : MetavarRewriteContext,
  binder : @syntax.Binder,
) -> @syntax.Binder raise {
  match parse_metavar(binder.name, ctx.path, ctx.context) {
    None => binder
    Some(syntax) =>
      match ctx.collect_or_resolve_metavar(syntax, BareIdentifierPosition) {
        None => binder
        Some((kind, meta_name)) => {
          if kind == "exp" || kind == "const" {
            ctx.reject_metavar_position(kind, meta_name)
          }
          ctx.register_metavar(kind, meta_name)
          { name: meta_name, loc: binder.loc }
        }
      }
  }
}

///|
fn MetavarRewriteContext::rewrite_label(
  ctx : MetavarRewriteContext,
  label : @syntax.Label,
) -> @syntax.Label raise {
  match parse_metavar(label.name, ctx.path, ctx.context) {
    None => label
    Some(syntax) =>
      match ctx.collect_or_resolve_metavar(syntax, BareIdentifierPosition) {
        None => label
        Some((kind, meta_name)) => {
          if kind == "exp" || kind == "const" {
            ctx.reject_metavar_position(kind, meta_name)
          }
          ctx.register_metavar(kind, meta_name)
          { name: meta_name, loc: label.loc }
        }
      }
  }
}

///|
fn MetavarRewriteContext::rewrite_constructor(
  ctx : MetavarRewriteContext,
  constr : @syntax.Constructor,
) -> @syntax.Constructor raise {
  let extra_info = ctx.rewrite_constructor_extra_info(constr.extra_info)
  let name = ctx.rewrite_constr_name(constr.name)
  { name, extra_info, loc: constr.loc }
}

///|
fn MetavarRewriteContext::rewrite_constr_name(
  ctx : MetavarRewriteContext,
  name : @syntax.ConstrName,
) -> @syntax.ConstrName raise {
  match parse_metavar(name.name, ctx.path, ctx.context) {
    None => name
    Some(syntax) =>
      match ctx.collect_or_resolve_metavar(syntax, BareIdentifierPosition) {
        None => name
        Some((kind, meta_name)) => {
          if kind == "exp" || kind == "const" {
            ctx.reject_metavar_position(kind, meta_name)
          }
          ctx.register_metavar(kind, meta_name)
          { name: meta_name, loc: name.loc }
        }
      }
  }
}

///|
fn MetavarRewriteContext::rewrite_constructor_extra_info(
  ctx : MetavarRewriteContext,
  extra_info : @syntax.ConstructorExtraInfo,
) -> @syntax.ConstructorExtraInfo raise {
  match extra_info {
    NoExtraInfo | Package(_) => extra_info
    TypeName(type_name) => TypeName(ctx.rewrite_type_name(type_name))
    TypeNameWithConstrPackage(type_name~, pkg~) =>
      TypeNameWithConstrPackage(
        type_name=ctx.rewrite_type_name(type_name),
        pkg~,
      )
  }
}

///|
fn MetavarRewriteContext::rewrite_type_name(
  ctx : MetavarRewriteContext,
  type_name : @syntax.TypeName,
) -> @syntax.TypeName raise {
  {
    name: ctx.rewrite_type_long_ident(type_name.name),
    is_object: type_name.is_object,
    loc: type_name.loc,
  }
}

///|
fn MetavarRewriteContext::rewrite_type_long_ident(
  ctx : MetavarRewriteContext,
  long_ident : @syntax.LongIdent,
) -> @syntax.LongIdent raise {
  match long_ident {
    Ident(name~) =>
      match parse_metavar(name, ctx.path, ctx.context) {
        None => long_ident
        Some(syntax) =>
          match ctx.collect_or_resolve_metavar(syntax, BareIdentifierPosition) {
            None => long_ident
            Some((kind, meta_name)) => {
              if kind == "exp" || kind == "const" {
                ctx.reject_metavar_position(kind, meta_name)
              }
              ctx.register_metavar(kind, meta_name)
              Ident(name=meta_name)
            }
          }
      }
    Dot(pkg~, id~) =>
      match parse_metavar(id, ctx.path, ctx.context) {
        None => long_ident
        Some(syntax) =>
          match ctx.collect_or_resolve_metavar(syntax, BareIdentifierPosition) {
            None => long_ident
            Some((kind, meta_name)) => {
              if kind == "exp" || kind == "const" {
                ctx.reject_metavar_position(kind, meta_name)
              }
              ctx.register_metavar(kind, meta_name)
              Dot(pkg~, id=meta_name)
            }
          }
      }
  }
}

///|
fn MetavarRewriteContext::rewrite_optional_expr(
  ctx : MetavarRewriteContext,
  expr : @syntax.Expr?,
) -> @syntax.Expr? raise {
  if expr is Some(expr) {
    Some(ctx.rewrite_expr(expr))
  } else {
    None
  }
}

///|
fn MetavarRewriteContext::rewrite_expr_list(
  ctx : MetavarRewriteContext,
  exprs : @list.List[@syntax.Expr],
) -> @list.List[@syntax.Expr] raise {
  let result : Array[@syntax.Expr] = []
  for expr in exprs {
    result.push(ctx.rewrite_expr(expr))
  }
  List(result)
}

///|
fn MetavarRewriteContext::rewrite_arguments(
  ctx : MetavarRewriteContext,
  args : @list.List[@syntax.Argument],
) -> @list.List[@syntax.Argument] raise {
  let result : Array[@syntax.Argument] = []
  for arg in args {
    result.push({
      kind: ctx.rewrite_argument_kind(arg.kind),
      value: ctx.rewrite_expr(arg.value),
    })
  }
  List(result)
}

///|
fn MetavarRewriteContext::rewrite_argument_kind(
  ctx : MetavarRewriteContext,
  kind : @syntax.ArgumentKind,
) -> @syntax.ArgumentKind raise {
  match kind {
    Positional => Positional
    Labelled(label) => Labelled(ctx.rewrite_label(label))
    LabelledPun(label) => LabelledPun(ctx.rewrite_label(label))
    LabelledOption(label~, question_loc~) =>
      LabelledOption(label=ctx.rewrite_label(label), question_loc~)
    LabelledOptionPun(label~, question_loc~) =>
      LabelledOptionPun(label=ctx.rewrite_label(label), question_loc~)
  }
}

///|
fn MetavarRewriteContext::rewrite_optional_var(
  ctx : MetavarRewriteContext,
  var_ : @syntax.Var?,
) -> @syntax.Var? raise {
  if var_ is Some(var_) {
    Some(ctx.rewrite_var(var_))
  } else {
    None
  }
}

///|
fn MetavarRewriteContext::rewrite_optional_label(
  ctx : MetavarRewriteContext,
  label : @syntax.Label?,
) -> @syntax.Label? raise {
  if label is Some(label) {
    Some(ctx.rewrite_label(label))
  } else {
    None
  }
}

///|
fn MetavarRewriteContext::rewrite_binder_expr_pairs(
  ctx : MetavarRewriteContext,
  pairs : @list.List[(@syntax.Binder, @syntax.Expr)],
) -> @list.List[(@syntax.Binder, @syntax.Expr)] raise {
  let result : Array[(@syntax.Binder, @syntax.Expr)] = []
  for pair in pairs {
    let (binder, expr) = pair
    result.push((ctx.rewrite_binder(binder), ctx.rewrite_expr(expr)))
  }
  List(result)
}

///|
fn MetavarRewriteContext::rewrite_optional_binders(
  ctx : MetavarRewriteContext,
  binders : @list.List[@syntax.Binder?],
) -> @list.List[@syntax.Binder?] raise {
  let result : Array[@syntax.Binder?] = []
  for binder in binders {
    if binder is Some(binder) {
      result.push(Some(ctx.rewrite_binder(binder)))
    } else {
      result.push(None)
    }
  }
  List(result)
}

///|

///|
fn MetavarRewriteContext::rewrite_accessor(
  ctx : MetavarRewriteContext,
  accessor : @syntax.Accessor,
) -> @syntax.Accessor raise {
  match accessor {
    Label(label) => Label(ctx.rewrite_label(label))
    _ => accessor
  }
}

///|
fn MetavarRewriteContext::rewrite_spreadable_elems(
  ctx : MetavarRewriteContext,
  elems : @list.List[@syntax.SpreadableElem],
) -> @list.List[@syntax.SpreadableElem] raise {
  let result : Array[@syntax.SpreadableElem] = []
  for elem in elems {
    result.push(
      match elem {
        Regular(expr) => Regular(ctx.rewrite_expr(expr))
        Spread(expr~, loc~) => Spread(expr=ctx.rewrite_expr(expr), loc~)
      },
    )
  }
  List(result)
}

///|
fn MetavarRewriteContext::rewrite_func(
  ctx : MetavarRewriteContext,
  func : @syntax.Func,
) -> @syntax.Func raise {
  {
    parameters: ctx.rewrite_parameters(func.parameters),
    params_loc: func.params_loc,
    body: ctx.rewrite_expr(func.body),
    return_type: func.return_type,
    error_type: func.error_type,
    kind: func.kind,
    is_async: func.is_async,
    loc: func.loc,
  }
}

///|
fn MetavarRewriteContext::rewrite_parameters(
  ctx : MetavarRewriteContext,
  parameters : @list.List[@syntax.Parameter],
) -> @list.List[@syntax.Parameter] raise {
  let result : Array[@syntax.Parameter] = []
  for parameter in parameters {
    result.push(
      match parameter {
        Positional(binder~, ty~) =>
          Positional(binder=ctx.rewrite_binder(binder), ty~)
        Labelled(binder~, ty~) =>
          Labelled(binder=ctx.rewrite_binder(binder), ty~)
        QuestionOptional(binder~, ty~) =>
          QuestionOptional(binder=ctx.rewrite_binder(binder), ty~)
        Optional(binder~, default~, ty~) =>
          Optional(
            binder=ctx.rewrite_binder(binder),
            default=ctx.rewrite_expr(default),
            ty~,
          )
        DiscardPositional(..) => parameter
      },
    )
  }
  List(result)
}

///|
fn MetavarRewriteContext::rewrite_let_and_bindings(
  ctx : MetavarRewriteContext,
  bindings : @list.List[(@syntax.Binder, @syntax.Type?, @syntax.Func)],
) -> @list.List[(@syntax.Binder, @syntax.Type?, @syntax.Func)] raise {
  let result : Array[(@syntax.Binder, @syntax.Type?, @syntax.Func)] = []
  for binding in bindings {
    let (binder, ty, func) = binding
    result.push((ctx.rewrite_binder(binder), ty, ctx.rewrite_func(func)))
  }
  List(result)
}

///|
fn MetavarRewriteContext::rewrite_optional_where_clause(
  ctx : MetavarRewriteContext,
  clause : @syntax.WhereClause?,
) -> @syntax.WhereClause? raise {
  if clause is Some(clause) {
    Some({ fields: ctx.rewrite_field_defs(clause.fields), loc: clause.loc })
  } else {
    None
  }
}

///|
fn MetavarRewriteContext::rewrite_field_defs(
  ctx : MetavarRewriteContext,
  fields : @list.List[@syntax.FieldDef],
) -> @list.List[@syntax.FieldDef] raise {
  let result : Array[@syntax.FieldDef] = []
  for field in fields {
    result.push({
      label: ctx.rewrite_label(field.label),
      expr: ctx.rewrite_expr(field.expr),
      is_pun: field.is_pun,
      loc: field.loc,
    })
  }
  List(result)
}

///|
fn MetavarRewriteContext::rewrite_map_expr_elems(
  ctx : MetavarRewriteContext,
  elems : @list.List[@syntax.MapExprElem],
) -> @list.List[@syntax.MapExprElem] raise {
  let result : Array[@syntax.MapExprElem] = []
  for elem in elems {
    result.push({
      key: elem.key,
      key_loc: elem.key_loc,
      expr: ctx.rewrite_expr(elem.expr),
      loc: elem.loc,
    })
  }
  List(result)
}

///|
fn MetavarRewriteContext::rewrite_interp_elems(
  ctx : MetavarRewriteContext,
  elems : @list.List[@syntax.InterpElem],
) -> @list.List[@syntax.InterpElem] raise {
  let result : Array[@syntax.InterpElem] = []
  for elem in elems {
    result.push(
      match elem {
        Expr(expr~, loc~) => Expr(expr=ctx.rewrite_expr(expr), loc~)
        _ => elem
      },
    )
  }
  List(result)
}

///|
fn MetavarRewriteContext::rewrite_multiline_string_elems(
  ctx : MetavarRewriteContext,
  elems : @list.List[@syntax.MultilineStringElem],
) -> @list.List[@syntax.MultilineStringElem] raise {
  let result : Array[@syntax.MultilineStringElem] = []
  for elem in elems {
    result.push(
      match elem {
        Interp(elems) => Interp(ctx.rewrite_interp_elems(elems))
        _ => elem
      },
    )
  }
  List(result)
}
