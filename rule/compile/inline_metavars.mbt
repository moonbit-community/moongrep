///|
priv struct InlineMetavarShape {
  ast : @syntax.Expr
  expr_metavars : Array[String]
  identifier_metavars : Array[String]
}

///|
fn compile_inline_metavar_shape(
  path : String,
  context : String,
  source : String,
) -> InlineMetavarShape raise {
  let expr_metavars : Array[String] = []
  let identifier_metavars : Array[String] = []
  let ast = rewrite_expr(
    parse_shape(path, context, source),
    path,
    context,
    expr_metavars,
    identifier_metavars,
  )
  { ast, expr_metavars, identifier_metavars }
}

///|
fn parse_inline_metavar(raw : String) -> (String, String)? {
  if !raw.has_prefix("$") {
    return None
  }
  for index in 1..<raw.length() {
    if raw[index] == ':' {
      return Some((raw[1:index].to_owned(), raw[index + 1:].to_owned()))
    }
  }
  None
}

///|
fn rewrite_expr(
  expr : @syntax.Expr,
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @syntax.Expr raise {
  match expr {
    Ident(id~, loc~) =>
      @syntax.Expr::Ident(
        id=rewrite_expr_var(
          id, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    Apply(func~, args~, loc~) =>
      @syntax.Expr::Apply(
        func=rewrite_expr(
          func, path, context, expr_metavars, identifier_metavars,
        ),
        args=rewrite_arguments(
          args, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    DotApply(self~, method_name~, args~, return_self~, loc~) =>
      @syntax.Expr::DotApply(
        self=rewrite_expr(
          self, path, context, expr_metavars, identifier_metavars,
        ),
        method_name=rewrite_label(
          method_name, path, context, expr_metavars, identifier_metavars,
        ),
        args=rewrite_arguments(
          args, path, context, expr_metavars, identifier_metavars,
        ),
        return_self~,
        loc~,
      )
    Infix(op~, lhs~, rhs~, loc~) =>
      @syntax.Expr::Infix(
        op=rewrite_var(op, path, context, expr_metavars, identifier_metavars),
        lhs=rewrite_expr(lhs, path, context, expr_metavars, identifier_metavars),
        rhs=rewrite_expr(rhs, path, context, expr_metavars, identifier_metavars),
        loc~,
      )
    Unary(op~, expr=inner, loc~) =>
      @syntax.Expr::Unary(
        op=rewrite_var(op, path, context, expr_metavars, identifier_metavars),
        expr=rewrite_expr(
          inner, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    Assign(var_~, expr=inner, augmented_by~, loc~) =>
      @syntax.Expr::Assign(
        var_=rewrite_var(
          var_, path, context, expr_metavars, identifier_metavars,
        ),
        expr=rewrite_expr(
          inner, path, context, expr_metavars, identifier_metavars,
        ),
        augmented_by=rewrite_optional_var(
          augmented_by, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    ArrayAugmentedSet(op~, array~, index~, value~, loc~) =>
      @syntax.Expr::ArrayAugmentedSet(
        op=rewrite_var(op, path, context, expr_metavars, identifier_metavars),
        array=rewrite_expr(
          array, path, context, expr_metavars, identifier_metavars,
        ),
        index=rewrite_expr(
          index, path, context, expr_metavars, identifier_metavars,
        ),
        value=rewrite_expr(
          value, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    ArrayGet(array~, index~, loc~) =>
      @syntax.Expr::ArrayGet(
        array=rewrite_expr(
          array, path, context, expr_metavars, identifier_metavars,
        ),
        index=rewrite_expr(
          index, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    ArraySet(array~, index~, value~, loc~) =>
      @syntax.Expr::ArraySet(
        array=rewrite_expr(
          array, path, context, expr_metavars, identifier_metavars,
        ),
        index=rewrite_expr(
          index, path, context, expr_metavars, identifier_metavars,
        ),
        value=rewrite_expr(
          value, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    ArrayGetSlice(array~, start_index~, end_index~, index_loc~, loc~) =>
      @syntax.Expr::ArrayGetSlice(
        array=rewrite_expr(
          array, path, context, expr_metavars, identifier_metavars,
        ),
        start_index=rewrite_optional_expr(
          start_index, path, context, expr_metavars, identifier_metavars,
        ),
        end_index=rewrite_optional_expr(
          end_index, path, context, expr_metavars, identifier_metavars,
        ),
        index_loc~,
        loc~,
      )
    Array(exprs~, loc~) =>
      @syntax.Expr::Array(
        exprs=rewrite_expr_list(
          exprs, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    Tuple(exprs~, loc~) =>
      @syntax.Expr::Tuple(
        exprs=rewrite_expr_list(
          exprs, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    ArraySpread(elems~, loc~) =>
      @syntax.Expr::ArraySpread(
        elems=rewrite_spreadable_elems(
          elems, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    Group(expr=inner, group~, loc~) =>
      @syntax.Expr::Group(
        expr=rewrite_expr(
          inner, path, context, expr_metavars, identifier_metavars,
        ),
        group~,
        loc~,
      )
    Constraint(expr=inner, ty~, loc~) =>
      @syntax.Expr::Constraint(
        expr=rewrite_expr(
          inner, path, context, expr_metavars, identifier_metavars,
        ),
        ty~,
        loc~,
      )
    As(expr=inner, trait_~, loc~) =>
      @syntax.Expr::As(
        expr=rewrite_expr(
          inner, path, context, expr_metavars, identifier_metavars,
        ),
        trait_~,
        loc~,
      )
    Sequence(exprs~, last_expr~, loc~) =>
      @syntax.Expr::Sequence(
        exprs=rewrite_expr_list(
          exprs, path, context, expr_metavars, identifier_metavars,
        ),
        last_expr=rewrite_expr(
          last_expr, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    Break(arg~, label~, loc~) =>
      @syntax.Expr::Break(
        arg=rewrite_optional_expr(
          arg, path, context, expr_metavars, identifier_metavars,
        ),
        label=rewrite_optional_label(
          label, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    Continue(args~, label~, loc~) =>
      @syntax.Expr::Continue(
        args=rewrite_expr_list(
          args, path, context, expr_metavars, identifier_metavars,
        ),
        label=rewrite_optional_label(
          label, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    Defer(expr=inner, body~, loc~) =>
      @syntax.Expr::Defer(
        expr=rewrite_expr(
          inner, path, context, expr_metavars, identifier_metavars,
        ),
        body=rewrite_expr(
          body, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    Return(return_value~, loc~) =>
      @syntax.Expr::Return(
        return_value=rewrite_optional_expr(
          return_value, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    If(cond~, ifso~, ifnot~, loc~) =>
      @syntax.Expr::If(
        cond=rewrite_expr(
          cond, path, context, expr_metavars, identifier_metavars,
        ),
        ifso=rewrite_expr(
          ifso, path, context, expr_metavars, identifier_metavars,
        ),
        ifnot=rewrite_optional_expr(
          ifnot, path, context, expr_metavars, identifier_metavars,
        ),
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
      @syntax.Expr::For(
        binders=rewrite_binder_expr_pairs(
          binders, path, context, expr_metavars, identifier_metavars,
        ),
        condition=rewrite_optional_expr(
          condition, path, context, expr_metavars, identifier_metavars,
        ),
        continue_block=rewrite_binder_expr_pairs(
          continue_block, path, context, expr_metavars, identifier_metavars,
        ),
        body=rewrite_expr(
          body, path, context, expr_metavars, identifier_metavars,
        ),
        for_else=rewrite_optional_expr(
          for_else, path, context, expr_metavars, identifier_metavars,
        ),
        where_clause=rewrite_optional_where_clause(
          where_clause, path, context, expr_metavars, identifier_metavars,
        ),
        label=rewrite_optional_label(
          label, path, context, expr_metavars, identifier_metavars,
        ),
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
      @syntax.Expr::ForEach(
        binders=rewrite_optional_binders(
          binders, path, context, expr_metavars, identifier_metavars,
        ),
        expr=rewrite_expr(
          iter, path, context, expr_metavars, identifier_metavars,
        ),
        init=rewrite_binder_expr_pairs(
          init, path, context, expr_metavars, identifier_metavars,
        ),
        continue_block=rewrite_binder_expr_pairs(
          continue_block, path, context, expr_metavars, identifier_metavars,
        ),
        body=rewrite_expr(
          body, path, context, expr_metavars, identifier_metavars,
        ),
        else_block=rewrite_optional_expr(
          else_block, path, context, expr_metavars, identifier_metavars,
        ),
        where_clause=rewrite_optional_where_clause(
          where_clause, path, context, expr_metavars, identifier_metavars,
        ),
        label=rewrite_optional_label(
          label, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    Function(func~, loc~) =>
      @syntax.Expr::Function(
        func=rewrite_func(
          func, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    Guard(cond~, otherwise~, body~, loc~) =>
      @syntax.Expr::Guard(
        cond=rewrite_expr(
          cond, path, context, expr_metavars, identifier_metavars,
        ),
        otherwise=rewrite_optional_expr(
          otherwise, path, context, expr_metavars, identifier_metavars,
        ),
        body=rewrite_expr(
          body, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    Interp(elems~, loc~) =>
      @syntax.Expr::Interp(
        elems=rewrite_interp_elems(
          elems, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    Is(expr=inner, pat~, loc~) =>
      @syntax.Expr::Is(
        expr=rewrite_expr(
          inner, path, context, expr_metavars, identifier_metavars,
        ),
        pat=rewrite_pattern(
          pat, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    Let(pattern~, expr=bound_expr, body~, loc~) =>
      @syntax.Expr::Let(
        pattern=rewrite_pattern(
          pattern, path, context, expr_metavars, identifier_metavars,
        ),
        expr=rewrite_expr(
          bound_expr, path, context, expr_metavars, identifier_metavars,
        ),
        body=rewrite_expr(
          body, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    LetMut(binder~, ty~, expr=bound_expr, body~, loc~) =>
      @syntax.Expr::LetMut(
        binder=rewrite_binder(
          binder, path, context, expr_metavars, identifier_metavars,
        ),
        ty~,
        expr=rewrite_expr(
          bound_expr, path, context, expr_metavars, identifier_metavars,
        ),
        body=rewrite_expr(
          body, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    LetFn(name~, func~, body~, loc~) =>
      @syntax.Expr::LetFn(
        name=rewrite_binder(
          name, path, context, expr_metavars, identifier_metavars,
        ),
        func=rewrite_func(
          func, path, context, expr_metavars, identifier_metavars,
        ),
        body=rewrite_expr(
          body, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    LetAnd(bindings~, body~, loc~) =>
      @syntax.Expr::LetAnd(
        bindings=rewrite_let_and_bindings(
          bindings, path, context, expr_metavars, identifier_metavars,
        ),
        body=rewrite_expr(
          body, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    Map(elems~, loc~) =>
      @syntax.Expr::Map(
        elems=rewrite_map_expr_elems(
          elems, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    Match(expr=matched, cases~, match_loc~, loc~) =>
      @syntax.Expr::Match(
        expr=rewrite_expr(
          matched, path, context, expr_metavars, identifier_metavars,
        ),
        cases=rewrite_cases(
          cases, path, context, expr_metavars, identifier_metavars,
        ),
        match_loc~,
        loc~,
      )
    Method(type_name~, method_name~, loc~) =>
      @syntax.Expr::Method(
        type_name~,
        method_name=rewrite_label(
          method_name, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    MultilineString(elems~, loc~) =>
      @syntax.Expr::MultilineString(
        elems=rewrite_multiline_string_elems(
          elems, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    Mutate(record~, accessor~, field~, augmented_by~, loc~) =>
      @syntax.Expr::Mutate(
        record=rewrite_expr(
          record, path, context, expr_metavars, identifier_metavars,
        ),
        accessor=rewrite_accessor(
          accessor, path, context, expr_metavars, identifier_metavars,
        ),
        field=rewrite_expr(
          field, path, context, expr_metavars, identifier_metavars,
        ),
        augmented_by=rewrite_optional_var(
          augmented_by, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    Pipe(lhs~, rhs~, loc~) =>
      @syntax.Expr::Pipe(
        lhs=rewrite_expr(lhs, path, context, expr_metavars, identifier_metavars),
        rhs=rewrite_expr(rhs, path, context, expr_metavars, identifier_metavars),
        loc~,
      )
    RevPipe(lhs~, rhs~, loc~) =>
      @syntax.Expr::RevPipe(
        lhs=rewrite_expr(lhs, path, context, expr_metavars, identifier_metavars),
        rhs=rewrite_expr(rhs, path, context, expr_metavars, identifier_metavars),
        loc~,
      )
    Implies(lhs~, rhs~, loc~) =>
      @syntax.Expr::Implies(
        lhs=rewrite_expr(lhs, path, context, expr_metavars, identifier_metavars),
        rhs=rewrite_expr(rhs, path, context, expr_metavars, identifier_metavars),
        loc~,
      )
    Record(type_name~, fields~, trailing~, loc~) =>
      @syntax.Expr::Record(
        type_name~,
        fields=rewrite_field_defs(
          fields, path, context, expr_metavars, identifier_metavars,
        ),
        trailing~,
        loc~,
      )
    RecordUpdate(type_name~, record~, fields~, loc~) =>
      @syntax.Expr::RecordUpdate(
        type_name~,
        record=rewrite_expr(
          record, path, context, expr_metavars, identifier_metavars,
        ),
        fields=rewrite_field_defs(
          fields, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    RegexMatch(expr=inner, pat~, bindings~, loc~) =>
      @syntax.Expr::RegexMatch(
        expr=rewrite_expr(
          inner, path, context, expr_metavars, identifier_metavars,
        ),
        pat=rewrite_regex_pattern(
          pat, path, context, expr_metavars, identifier_metavars,
        ),
        bindings=rewrite_regex_bindings(
          bindings, path, context, expr_metavars, identifier_metavars,
        ),
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
      @syntax.Expr::Try(
        body=rewrite_expr(
          body, path, context, expr_metavars, identifier_metavars,
        ),
        catch_=rewrite_cases(
          catch_, path, context, expr_metavars, identifier_metavars,
        ),
        try_else=rewrite_optional_cases(
          try_else, path, context, expr_metavars, identifier_metavars,
        ),
        has_try~,
        try_loc~,
        catch_loc~,
        else_loc~,
        loc~,
      )
    TryOperator(body~, kind~, try_loc~, loc~) =>
      @syntax.Expr::TryOperator(
        body=rewrite_expr(
          body, path, context, expr_metavars, identifier_metavars,
        ),
        kind~,
        try_loc~,
        loc~,
      )
    While(loop_cond~, loop_body~, while_else~, label~, loc~) =>
      @syntax.Expr::While(
        loop_cond=rewrite_expr(
          loop_cond, path, context, expr_metavars, identifier_metavars,
        ),
        loop_body=rewrite_expr(
          loop_body, path, context, expr_metavars, identifier_metavars,
        ),
        while_else=rewrite_optional_expr(
          while_else, path, context, expr_metavars, identifier_metavars,
        ),
        label=rewrite_optional_label(
          label, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    ListComprehension(kind~, guard_~, body~, loc~) =>
      @syntax.Expr::ListComprehension(
        kind~,
        guard_=rewrite_optional_expr(
          guard_, path, context, expr_metavars, identifier_metavars,
        ),
        body=rewrite_expr(
          body, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    ProofLet(binder~, expr=inner, loc~) =>
      @syntax.Expr::ProofLet(
        binder=rewrite_binder(
          binder, path, context, expr_metavars, identifier_metavars,
        ),
        expr=rewrite_expr(
          inner, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    ProofAssert(expr=inner, loc~) =>
      @syntax.Expr::ProofAssert(
        expr=rewrite_expr(
          inner, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    Raise(err_value~, loc~) =>
      @syntax.Expr::Raise(
        err_value=rewrite_expr(
          err_value, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    TemplateWriting(expr=inner, template~, loc~) =>
      @syntax.Expr::TemplateWriting(
        expr=rewrite_expr(
          inner, path, context, expr_metavars, identifier_metavars,
        ),
        template=rewrite_expr(
          template, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    StaticAssert(asserts~, body~) =>
      @syntax.Expr::StaticAssert(
        asserts~,
        body=rewrite_expr(
          body, path, context, expr_metavars, identifier_metavars,
        ),
      )
    _ => expr
  }
}

///|
fn rewrite_expr_var(
  var_ : @syntax.Var,
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @syntax.Var raise {
  match var_.name {
    Ident(name~) =>
      match parse_inline_metavar(name) {
        None => var_
        Some((kind, meta_name)) => {
          register_inline_metavar(
            path, context, kind, meta_name, expr_metavars, identifier_metavars,
          )
          { name: @syntax.LongIdent::Ident(name=meta_name), loc: var_.loc }
        }
      }
    Dot(id~, ..) => {
      reject_qualified_inline_metavar(path, context, id)
      var_
    }
  }
}

///|
fn rewrite_var(
  var_ : @syntax.Var,
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @syntax.Var raise {
  match var_.name {
    Ident(name~) =>
      match parse_inline_metavar(name) {
        None => var_
        Some((kind, meta_name)) => {
          if kind == "exp" {
            raise RuleLoadError::InvalidRule(
              path~,
              info="\{context}.shape uses $exp:\{meta_name} outside a bare expression position",
            )
          }
          register_inline_metavar(
            path, context, kind, meta_name, expr_metavars, identifier_metavars,
          )
          { name: @syntax.LongIdent::Ident(name=meta_name), loc: var_.loc }
        }
      }
    Dot(id~, ..) => {
      reject_qualified_inline_metavar(path, context, id)
      var_
    }
  }
}

///|
fn rewrite_binder(
  binder : @syntax.Binder,
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @syntax.Binder raise {
  match parse_inline_metavar(binder.name) {
    None => binder
    Some((kind, meta_name)) => {
      if kind == "exp" {
        raise RuleLoadError::InvalidRule(
          path~,
          info="\{context}.shape uses $exp:\{meta_name} outside a bare expression position",
        )
      }
      register_inline_metavar(
        path, context, kind, meta_name, expr_metavars, identifier_metavars,
      )
      { name: meta_name, loc: binder.loc }
    }
  }
}

///|
fn rewrite_label(
  label : @syntax.Label,
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @syntax.Label raise {
  match parse_inline_metavar(label.name) {
    None => label
    Some((kind, meta_name)) => {
      if kind == "exp" {
        raise RuleLoadError::InvalidRule(
          path~,
          info="\{context}.shape uses $exp:\{meta_name} outside a bare expression position",
        )
      }
      register_inline_metavar(
        path, context, kind, meta_name, expr_metavars, identifier_metavars,
      )
      { name: meta_name, loc: label.loc }
    }
  }
}

///|
fn register_inline_metavar(
  path : String,
  context : String,
  kind : String,
  name : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> Unit raise {
  if kind != "exp" && kind != "id" {
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{context}.shape contains unsupported metavar kind \{kind}",
    )
  }
  validate_declared_metavar(path, context, name, true)
  if kind == "exp" {
    if array_contains(identifier_metavars, name) {
      raise RuleLoadError::InvalidRule(
        path~,
        info="\{context}.shape declares metavar \{name} as both exp and id",
      )
    }
    if !array_contains(expr_metavars, name) {
      expr_metavars.push(name)
    }
  } else {
    if array_contains(expr_metavars, name) {
      raise RuleLoadError::InvalidRule(
        path~,
        info="\{context}.shape declares metavar \{name} as both exp and id",
      )
    }
    if !array_contains(identifier_metavars, name) {
      identifier_metavars.push(name)
    }
  }
}

///|
fn reject_qualified_inline_metavar(
  path : String,
  context : String,
  id : String,
) -> Unit raise {
  match parse_inline_metavar(id) {
    Some((kind, name)) =>
      if kind == "exp" {
        raise RuleLoadError::InvalidRule(
          path~,
          info="\{context}.shape uses $exp:\{name} outside a bare expression position",
        )
      } else {
        raise RuleLoadError::InvalidRule(
          path~,
          info="\{context}.shape uses $\{kind}:\{name} in an unsupported qualified identifier position",
        )
      }
    None => ()
  }
}

///|
fn rewrite_optional_expr(
  expr : @syntax.Expr?,
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @syntax.Expr? raise {
  match expr {
    None => None
    Some(expr) =>
      Some(
        rewrite_expr(expr, path, context, expr_metavars, identifier_metavars),
      )
  }
}

///|
fn rewrite_expr_list(
  exprs : @list.List[@syntax.Expr],
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @list.List[@syntax.Expr] raise {
  let result : Array[@syntax.Expr] = []
  for expr in exprs {
    result.push(
      rewrite_expr(expr, path, context, expr_metavars, identifier_metavars),
    )
  }
  @list.from_array(result)
}

///|
fn rewrite_arguments(
  args : @list.List[@syntax.Argument],
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @list.List[@syntax.Argument] raise {
  let result : Array[@syntax.Argument] = []
  for arg in args {
    result.push({
      kind: rewrite_argument_kind(
        arg.kind,
        path,
        context,
        expr_metavars,
        identifier_metavars,
      ),
      value: rewrite_expr(
        arg.value,
        path,
        context,
        expr_metavars,
        identifier_metavars,
      ),
    })
  }
  @list.from_array(result)
}

///|
fn rewrite_argument_kind(
  kind : @syntax.ArgumentKind,
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @syntax.ArgumentKind raise {
  match kind {
    Positional => Positional
    Labelled(label) =>
      Labelled(
        rewrite_label(label, path, context, expr_metavars, identifier_metavars),
      )
    LabelledPun(label) =>
      LabelledPun(
        rewrite_label(label, path, context, expr_metavars, identifier_metavars),
      )
    LabelledOption(label~, question_loc~) =>
      LabelledOption(
        label=rewrite_label(
          label, path, context, expr_metavars, identifier_metavars,
        ),
        question_loc~,
      )
    LabelledOptionPun(label~, question_loc~) =>
      LabelledOptionPun(
        label=rewrite_label(
          label, path, context, expr_metavars, identifier_metavars,
        ),
        question_loc~,
      )
  }
}

///|
fn rewrite_optional_var(
  var_ : @syntax.Var?,
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @syntax.Var? raise {
  match var_ {
    None => None
    Some(var_) =>
      Some(rewrite_var(var_, path, context, expr_metavars, identifier_metavars))
  }
}

///|
fn rewrite_optional_label(
  label : @syntax.Label?,
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @syntax.Label? raise {
  match label {
    None => None
    Some(label) =>
      Some(
        rewrite_label(label, path, context, expr_metavars, identifier_metavars),
      )
  }
}

///|
fn rewrite_binder_expr_pairs(
  pairs : @list.List[(@syntax.Binder, @syntax.Expr)],
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @list.List[(@syntax.Binder, @syntax.Expr)] raise {
  let result : Array[(@syntax.Binder, @syntax.Expr)] = []
  for pair in pairs {
    let (binder, expr) = pair
    result.push(
      (
        rewrite_binder(
          binder, path, context, expr_metavars, identifier_metavars,
        ),
        rewrite_expr(expr, path, context, expr_metavars, identifier_metavars),
      ),
    )
  }
  @list.from_array(result)
}

///|
fn rewrite_optional_binders(
  binders : @list.List[@syntax.Binder?],
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @list.List[@syntax.Binder?] raise {
  let result : Array[@syntax.Binder?] = []
  for binder in binders {
    match binder {
      None => result.push(None)
      Some(binder) =>
        result.push(
          Some(
            rewrite_binder(
              binder, path, context, expr_metavars, identifier_metavars,
            ),
          ),
        )
    }
  }
  @list.from_array(result)
}

///|
fn rewrite_pattern(
  pattern : @syntax.Pattern,
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @syntax.Pattern raise {
  match pattern {
    Var(binder) =>
      @syntax.Pattern::Var(
        rewrite_binder(
          binder, path, context, expr_metavars, identifier_metavars,
        ),
      )
    Alias(pat~, alias_~, loc~) =>
      @syntax.Pattern::Alias(
        pat=rewrite_pattern(
          pat, path, context, expr_metavars, identifier_metavars,
        ),
        alias_=rewrite_binder(
          alias_, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    Tuple(pats~, loc~) =>
      @syntax.Pattern::Tuple(
        pats=rewrite_patterns(
          pats, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    Or(pat1~, pat2~, loc~) =>
      @syntax.Pattern::Or(
        pat1=rewrite_pattern(
          pat1, path, context, expr_metavars, identifier_metavars,
        ),
        pat2=rewrite_pattern(
          pat2, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    Range(lhs~, rhs~, kind~, loc~) =>
      @syntax.Pattern::Range(
        lhs=rewrite_pattern(
          lhs, path, context, expr_metavars, identifier_metavars,
        ),
        rhs=rewrite_pattern(
          rhs, path, context, expr_metavars, identifier_metavars,
        ),
        kind~,
        loc~,
      )
    Constraint(pat~, ty~, loc~) =>
      @syntax.Pattern::Constraint(
        pat=rewrite_pattern(
          pat, path, context, expr_metavars, identifier_metavars,
        ),
        ty~,
        loc~,
      )
    Array(pats~, loc~) =>
      @syntax.Pattern::Array(
        pats=rewrite_array_patterns(
          pats, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    Constr(constr~, args~, is_open~, loc~) =>
      @syntax.Pattern::Constr(
        constr~,
        args=rewrite_optional_constr_pat_args(
          args, path, context, expr_metavars, identifier_metavars,
        ),
        is_open~,
        loc~,
      )
    Record(fields~, is_closed~, loc~) =>
      @syntax.Pattern::Record(
        fields=rewrite_field_pats(
          fields, path, context, expr_metavars, identifier_metavars,
        ),
        is_closed~,
        loc~,
      )
    Map(elems~, is_closed~, loc~) =>
      @syntax.Pattern::Map(
        elems=rewrite_map_pat_elems(
          elems, path, context, expr_metavars, identifier_metavars,
        ),
        is_closed~,
        loc~,
      )
    SpecialConstr(binder~, args~, loc~) =>
      @syntax.Pattern::SpecialConstr(
        binder=rewrite_binder(
          binder, path, context, expr_metavars, identifier_metavars,
        ),
        args=rewrite_constr_pat_args(
          args, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    _ => pattern
  }
}

///|
fn rewrite_patterns(
  patterns : @list.List[@syntax.Pattern],
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @list.List[@syntax.Pattern] raise {
  let result : Array[@syntax.Pattern] = []
  for pattern in patterns {
    result.push(
      rewrite_pattern(
        pattern, path, context, expr_metavars, identifier_metavars,
      ),
    )
  }
  @list.from_array(result)
}

///|
fn rewrite_array_patterns(
  patterns : @syntax.ArrayPatterns,
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @syntax.ArrayPatterns raise {
  match patterns {
    Closed(items) =>
      Closed(
        rewrite_array_pattern_items(
          items, path, context, expr_metavars, identifier_metavars,
        ),
      )
    Open(left, right, binder) =>
      Open(
        rewrite_array_pattern_items(
          left, path, context, expr_metavars, identifier_metavars,
        ),
        rewrite_array_pattern_items(
          right, path, context, expr_metavars, identifier_metavars,
        ),
        rewrite_dot_dot_binder(
          binder, path, context, expr_metavars, identifier_metavars,
        ),
      )
  }
}

///|
fn rewrite_array_pattern_items(
  items : @list.List[@syntax.ArrayPattern],
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @list.List[@syntax.ArrayPattern] raise {
  let result : Array[@syntax.ArrayPattern] = []
  for item in items {
    result.push(
      match item {
        Pattern(pattern) =>
          Pattern(
            rewrite_pattern(
              pattern, path, context, expr_metavars, identifier_metavars,
            ),
          )
        ConstSpread(binder~, pkg~, loc~) =>
          ConstSpread(
            binder=rewrite_binder(
              binder, path, context, expr_metavars, identifier_metavars,
            ),
            pkg~,
            loc~,
          )
        _ => item
      },
    )
  }
  @list.from_array(result)
}

///|
fn rewrite_dot_dot_binder(
  binder : @syntax.DotDotBinder,
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @syntax.DotDotBinder raise {
  match binder {
    Binder(binder) =>
      Binder(
        rewrite_binder(
          binder, path, context, expr_metavars, identifier_metavars,
        ),
      )
    BinderAs(binder) =>
      BinderAs(
        rewrite_binder(
          binder, path, context, expr_metavars, identifier_metavars,
        ),
      )
    _ => binder
  }
}

///|
fn rewrite_optional_constr_pat_args(
  args : @list.List[@syntax.ConstrPatArg]?,
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @list.List[@syntax.ConstrPatArg]? raise {
  match args {
    None => None
    Some(args) =>
      Some(
        rewrite_constr_pat_args(
          args, path, context, expr_metavars, identifier_metavars,
        ),
      )
  }
}

///|
fn rewrite_constr_pat_args(
  args : @list.List[@syntax.ConstrPatArg],
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @list.List[@syntax.ConstrPatArg] raise {
  let result : Array[@syntax.ConstrPatArg] = []
  for arg in args {
    result.push({
      kind: rewrite_argument_kind(
        arg.kind,
        path,
        context,
        expr_metavars,
        identifier_metavars,
      ),
      pat: rewrite_pattern(
        arg.pat,
        path,
        context,
        expr_metavars,
        identifier_metavars,
      ),
    })
  }
  @list.from_array(result)
}

///|
fn rewrite_field_pats(
  fields : @list.List[@syntax.FieldPat],
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @list.List[@syntax.FieldPat] raise {
  let result : Array[@syntax.FieldPat] = []
  for field in fields {
    result.push({
      label: rewrite_label(
        field.label,
        path,
        context,
        expr_metavars,
        identifier_metavars,
      ),
      pattern: rewrite_pattern(
        field.pattern,
        path,
        context,
        expr_metavars,
        identifier_metavars,
      ),
      is_pun: field.is_pun,
      loc: field.loc,
    })
  }
  @list.from_array(result)
}

///|
fn rewrite_map_pat_elems(
  elems : @list.List[@syntax.MapPatElem],
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @list.List[@syntax.MapPatElem] raise {
  let result : Array[@syntax.MapPatElem] = []
  for elem in elems {
    result.push({
      key: elem.key,
      key_loc: elem.key_loc,
      pat: rewrite_pattern(
        elem.pat,
        path,
        context,
        expr_metavars,
        identifier_metavars,
      ),
      match_absent: elem.match_absent,
      loc: elem.loc,
    })
  }
  @list.from_array(result)
}

///|
fn rewrite_accessor(
  accessor : @syntax.Accessor,
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @syntax.Accessor raise {
  match accessor {
    Label(label) =>
      Label(
        rewrite_label(label, path, context, expr_metavars, identifier_metavars),
      )
    _ => accessor
  }
}

///|
fn rewrite_spreadable_elems(
  elems : @list.List[@syntax.SpreadableElem],
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @list.List[@syntax.SpreadableElem] raise {
  let result : Array[@syntax.SpreadableElem] = []
  for elem in elems {
    result.push(
      match elem {
        Regular(expr) =>
          Regular(
            rewrite_expr(
              expr, path, context, expr_metavars, identifier_metavars,
            ),
          )
        Spread(expr~, loc~) =>
          Spread(
            expr=rewrite_expr(
              expr, path, context, expr_metavars, identifier_metavars,
            ),
            loc~,
          )
      },
    )
  }
  @list.from_array(result)
}

///|
fn rewrite_cases(
  cases : @list.List[@syntax.Case],
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @list.List[@syntax.Case] raise {
  let result : Array[@syntax.Case] = []
  for case in cases {
    result.push({
      pattern: rewrite_pattern(
        case.pattern,
        path,
        context,
        expr_metavars,
        identifier_metavars,
      ),
      guard_: rewrite_optional_expr(
        case.guard_,
        path,
        context,
        expr_metavars,
        identifier_metavars,
      ),
      body: rewrite_expr(
        case.body,
        path,
        context,
        expr_metavars,
        identifier_metavars,
      ),
    })
  }
  @list.from_array(result)
}

///|
fn rewrite_optional_cases(
  cases : @list.List[@syntax.Case]?,
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @list.List[@syntax.Case]? raise {
  match cases {
    None => None
    Some(cases) =>
      Some(
        rewrite_cases(cases, path, context, expr_metavars, identifier_metavars),
      )
  }
}

///|
fn rewrite_func(
  func : @syntax.Func,
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @syntax.Func raise {
  {
    parameters: rewrite_parameters(
      func.parameters,
      path,
      context,
      expr_metavars,
      identifier_metavars,
    ),
    params_loc: func.params_loc,
    body: rewrite_expr(
      func.body,
      path,
      context,
      expr_metavars,
      identifier_metavars,
    ),
    return_type: func.return_type,
    error_type: func.error_type,
    kind: func.kind,
    is_async: func.is_async,
    loc: func.loc,
  }
}

///|
fn rewrite_parameters(
  parameters : @list.List[@syntax.Parameter],
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @list.List[@syntax.Parameter] raise {
  let result : Array[@syntax.Parameter] = []
  for parameter in parameters {
    result.push(
      match parameter {
        Positional(binder~, ty~) =>
          Positional(
            binder=rewrite_binder(
              binder, path, context, expr_metavars, identifier_metavars,
            ),
            ty~,
          )
        Labelled(binder~, ty~) =>
          Labelled(
            binder=rewrite_binder(
              binder, path, context, expr_metavars, identifier_metavars,
            ),
            ty~,
          )
        QuestionOptional(binder~, ty~) =>
          QuestionOptional(
            binder=rewrite_binder(
              binder, path, context, expr_metavars, identifier_metavars,
            ),
            ty~,
          )
        Optional(binder~, default~, ty~) =>
          Optional(
            binder=rewrite_binder(
              binder, path, context, expr_metavars, identifier_metavars,
            ),
            default=rewrite_expr(
              default, path, context, expr_metavars, identifier_metavars,
            ),
            ty~,
          )
        DiscardPositional(..) => parameter
      },
    )
  }
  @list.from_array(result)
}

///|
fn rewrite_let_and_bindings(
  bindings : @list.List[(@syntax.Binder, @syntax.Type?, @syntax.Func)],
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @list.List[(@syntax.Binder, @syntax.Type?, @syntax.Func)] raise {
  let result : Array[(@syntax.Binder, @syntax.Type?, @syntax.Func)] = []
  for binding in bindings {
    let (binder, ty, func) = binding
    result.push(
      (
        rewrite_binder(
          binder, path, context, expr_metavars, identifier_metavars,
        ),
        ty,
        rewrite_func(func, path, context, expr_metavars, identifier_metavars),
      ),
    )
  }
  @list.from_array(result)
}

///|
fn rewrite_optional_where_clause(
  clause : @syntax.WhereClause?,
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @syntax.WhereClause? raise {
  match clause {
    None => None
    Some(clause) =>
      Some({
        fields: rewrite_field_defs(
          clause.fields,
          path,
          context,
          expr_metavars,
          identifier_metavars,
        ),
        loc: clause.loc,
      })
  }
}

///|
fn rewrite_field_defs(
  fields : @list.List[@syntax.FieldDef],
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @list.List[@syntax.FieldDef] raise {
  let result : Array[@syntax.FieldDef] = []
  for field in fields {
    result.push({
      label: rewrite_label(
        field.label,
        path,
        context,
        expr_metavars,
        identifier_metavars,
      ),
      expr: rewrite_expr(
        field.expr,
        path,
        context,
        expr_metavars,
        identifier_metavars,
      ),
      is_pun: field.is_pun,
      loc: field.loc,
    })
  }
  @list.from_array(result)
}

///|
fn rewrite_map_expr_elems(
  elems : @list.List[@syntax.MapExprElem],
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @list.List[@syntax.MapExprElem] raise {
  let result : Array[@syntax.MapExprElem] = []
  for elem in elems {
    result.push({
      key: elem.key,
      key_loc: elem.key_loc,
      expr: rewrite_expr(
        elem.expr,
        path,
        context,
        expr_metavars,
        identifier_metavars,
      ),
      loc: elem.loc,
    })
  }
  @list.from_array(result)
}

///|
fn rewrite_interp_elems(
  elems : @list.List[@syntax.InterpElem],
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @list.List[@syntax.InterpElem] raise {
  let result : Array[@syntax.InterpElem] = []
  for elem in elems {
    result.push(
      match elem {
        Expr(expr~, loc~) =>
          Expr(
            expr=rewrite_expr(
              expr, path, context, expr_metavars, identifier_metavars,
            ),
            loc~,
          )
        _ => elem
      },
    )
  }
  @list.from_array(result)
}

///|
fn rewrite_multiline_string_elems(
  elems : @list.List[@syntax.MultilineStringElem],
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @list.List[@syntax.MultilineStringElem] raise {
  let result : Array[@syntax.MultilineStringElem] = []
  for elem in elems {
    result.push(
      match elem {
        Interp(elems) =>
          Interp(
            rewrite_interp_elems(
              elems, path, context, expr_metavars, identifier_metavars,
            ),
          )
        _ => elem
      },
    )
  }
  @list.from_array(result)
}

///|
fn rewrite_regex_pattern(
  pattern : @syntax.RegexPattern,
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @syntax.RegexPattern raise {
  match pattern {
    Alias(pat~, binder~, loc~) =>
      Alias(
        pat=rewrite_regex_pattern(
          pat, path, context, expr_metavars, identifier_metavars,
        ),
        binder=rewrite_binder(
          binder, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    Alternation(pat1~, pat2~, loc~) =>
      Alternation(
        pat1=rewrite_regex_pattern(
          pat1, path, context, expr_metavars, identifier_metavars,
        ),
        pat2=rewrite_regex_pattern(
          pat2, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    Sequence(pat1~, pat2~, loc~) =>
      Sequence(
        pat1=rewrite_regex_pattern(
          pat1, path, context, expr_metavars, identifier_metavars,
        ),
        pat2=rewrite_regex_pattern(
          pat2, path, context, expr_metavars, identifier_metavars,
        ),
        loc~,
      )
    _ => pattern
  }
}

///|
fn rewrite_regex_bindings(
  bindings : @list.List[(@syntax.Label, @syntax.Binder?)],
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @list.List[(@syntax.Label, @syntax.Binder?)] raise {
  let result : Array[(@syntax.Label, @syntax.Binder?)] = []
  for binding in bindings {
    let (label, binder) = binding
    result.push(
      (
        rewrite_label(label, path, context, expr_metavars, identifier_metavars),
        rewrite_optional_binder_value(
          binder, path, context, expr_metavars, identifier_metavars,
        ),
      ),
    )
  }
  @list.from_array(result)
}

///|
fn rewrite_optional_binder_value(
  binder : @syntax.Binder?,
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
) -> @syntax.Binder? raise {
  match binder {
    None => None
    Some(binder) =>
      Some(
        rewrite_binder(
          binder, path, context, expr_metavars, identifier_metavars,
        ),
      )
  }
}
