///|
fn MetavarRewriteContext::rewrite_pattern(
  ctx : MetavarRewriteContext,
  pattern : @syntax.Pattern,
) -> @syntax.Pattern raise {
  match pattern {
    Var(binder) => Var(ctx.rewrite_pattern_var_binder(binder))
    Alias(pat~, alias_~, loc~) =>
      Alias(
        pat=ctx.rewrite_pattern(pat),
        alias_=ctx.rewrite_binder(alias_),
        loc~,
      )
    Tuple(pats~, loc~) => Tuple(pats=ctx.rewrite_patterns(pats), loc~)
    Or(pat1~, pat2~, loc~) =>
      Or(pat1=ctx.rewrite_pattern(pat1), pat2=ctx.rewrite_pattern(pat2), loc~)
    Range(lhs~, rhs~, kind~, loc~) =>
      Range(
        lhs=ctx.rewrite_pattern(lhs),
        rhs=ctx.rewrite_pattern(rhs),
        kind~,
        loc~,
      )
    Constraint(pat~, ty~, loc~) =>
      Constraint(pat=ctx.rewrite_pattern(pat), ty=ctx.rewrite_type(ty), loc~)
    Array(pats~, loc~) => Array(pats=ctx.rewrite_array_patterns(pats), loc~)
    Constr(constr~, args~, is_open~, loc~) =>
      Constr(
        constr=ctx.rewrite_constructor(constr),
        args=ctx.rewrite_optional_constr_pat_args(args),
        is_open~,
        loc~,
      )
    Record(fields~, is_closed~, loc~) =>
      Record(fields=ctx.rewrite_field_pats(fields), is_closed~, loc~)
    Map(elems~, is_closed~, loc~) =>
      Map(elems=ctx.rewrite_map_pat_elems(elems), is_closed~, loc~)
    SpecialConstr(binder~, args~, loc~) =>
      SpecialConstr(
        binder=ctx.rewrite_binder(binder),
        args=ctx.rewrite_constr_pat_args(args),
        loc~,
      )
    _ => pattern
  }
}

///|
fn MetavarRewriteContext::rewrite_pattern_var_binder(
  ctx : MetavarRewriteContext,
  binder : @syntax.Binder,
) -> @syntax.Binder raise {
  match parse_metavar(binder.name, ctx.path, ctx.context) {
    None => binder
    Some(syntax) =>
      match
        ctx.collect_or_resolve_metavar(syntax, BarePatternVariablePosition) {
        None => binder
        Some((kind, meta_name)) => {
          if kind == "exp" || kind == "arg" || kind == "type" {
            ctx.reject_metavar_position(kind, meta_name)
          } else if kind == "pat" {
            validate_declared_metavar(ctx.path, ctx.context, meta_name, true)
            let marker = temporary_pattern_metavar_marker(meta_name)
            if !array_contains(ctx.identifier_metavars, marker) {
              ctx.ensure_no_other_metavar_kind(
                meta_name,
                ctx.expr_metavars,
                ctx.identifier_metavars,
              )
              ctx.ensure_no_other_metavar_kind(
                meta_name,
                ctx.constant_metavars,
                [],
              )
              ctx.ensure_no_other_metavar_kind(meta_name, ctx.arg_metavars, [])
              ctx.ensure_no_other_metavar_kind(meta_name, ctx.type_metavars, [])
              ctx.expr_metavars.push(meta_name)
              ctx.identifier_metavars.push(marker)
              ctx.constant_metavars.push(meta_name)
              ctx.pattern_metavars.push(meta_name)
            }
            return { name: metavar_text("pat", meta_name), loc: binder.loc }
          }
          ctx.register_metavar(kind, meta_name)
          { name: meta_name, loc: binder.loc }
        }
      }
  }
}

///|
fn MetavarRewriteContext::rewrite_patterns(
  ctx : MetavarRewriteContext,
  patterns : @list.List[@syntax.Pattern],
) -> @list.List[@syntax.Pattern] raise {
  let result : Array[@syntax.Pattern] = []
  for pattern in patterns {
    result.push(ctx.rewrite_pattern(pattern))
  }
  List(result)
}

///|
fn MetavarRewriteContext::rewrite_array_patterns(
  ctx : MetavarRewriteContext,
  patterns : @syntax.ArrayPatterns,
) -> @syntax.ArrayPatterns raise {
  match patterns {
    Closed(items) => Closed(ctx.rewrite_array_pattern_items(items))
    Open(left, right, binder) =>
      Open(
        ctx.rewrite_array_pattern_items(left),
        ctx.rewrite_array_pattern_items(right),
        ctx.rewrite_dot_dot_binder(binder),
      )
  }
}

///|
fn MetavarRewriteContext::rewrite_array_pattern_items(
  ctx : MetavarRewriteContext,
  items : @list.List[@syntax.ArrayPattern],
) -> @list.List[@syntax.ArrayPattern] raise {
  let result : Array[@syntax.ArrayPattern] = []
  for item in items {
    result.push(
      match item {
        Pattern(pattern) => Pattern(ctx.rewrite_pattern(pattern))
        ConstSpread(binder~, pkg~, loc~) =>
          ConstSpread(binder=ctx.rewrite_binder(binder), pkg~, loc~)
        _ => item
      },
    )
  }
  List(result)
}

///|
fn MetavarRewriteContext::rewrite_dot_dot_binder(
  ctx : MetavarRewriteContext,
  binder : @syntax.DotDotBinder,
) -> @syntax.DotDotBinder raise {
  match binder {
    Binder(binder) => Binder(ctx.rewrite_binder(binder))
    BinderAs(binder) => BinderAs(ctx.rewrite_binder(binder))
    _ => binder
  }
}

///|
fn MetavarRewriteContext::rewrite_optional_constr_pat_args(
  ctx : MetavarRewriteContext,
  args : @list.List[@syntax.ConstrPatArg]?,
) -> @list.List[@syntax.ConstrPatArg]? raise {
  if args is Some(args) {
    Some(ctx.rewrite_constr_pat_args(args))
  } else {
    None
  }
}

///|
fn MetavarRewriteContext::rewrite_constr_pat_args(
  ctx : MetavarRewriteContext,
  args : @list.List[@syntax.ConstrPatArg],
) -> @list.List[@syntax.ConstrPatArg] raise {
  let result : Array[@syntax.ConstrPatArg] = []
  for arg in args {
    result.push({
      kind: ctx.rewrite_argument_kind(arg.kind),
      pat: ctx.rewrite_pattern(arg.pat),
    })
  }
  List(result)
}

///|
fn MetavarRewriteContext::rewrite_field_pats(
  ctx : MetavarRewriteContext,
  fields : @list.List[@syntax.FieldPat],
) -> @list.List[@syntax.FieldPat] raise {
  let result : Array[@syntax.FieldPat] = []
  for field in fields {
    result.push({
      label: ctx.rewrite_label(field.label),
      pattern: ctx.rewrite_pattern(field.pattern),
      is_pun: field.is_pun,
      loc: field.loc,
    })
  }
  List(result)
}

///|
fn MetavarRewriteContext::rewrite_map_pat_elems(
  ctx : MetavarRewriteContext,
  elems : @list.List[@syntax.MapPatElem],
) -> @list.List[@syntax.MapPatElem] raise {
  let result : Array[@syntax.MapPatElem] = []
  for elem in elems {
    result.push({
      key: elem.key,
      key_loc: elem.key_loc,
      pat: ctx.rewrite_pattern(elem.pat),
      match_absent: elem.match_absent,
      loc: elem.loc,
    })
  }
  List(result)
}

///|
fn MetavarRewriteContext::rewrite_cases(
  ctx : MetavarRewriteContext,
  cases : @list.List[@syntax.Case],
) -> @list.List[@syntax.Case] raise {
  let result : Array[@syntax.Case] = []
  for case in cases {
    result.push({
      pattern: ctx.rewrite_pattern(case.pattern),
      guard_: ctx.rewrite_optional_expr(case.guard_),
      body: ctx.rewrite_expr(case.body),
    })
  }
  List(result)
}

///|
fn MetavarRewriteContext::rewrite_optional_cases(
  ctx : MetavarRewriteContext,
  cases : @list.List[@syntax.Case]?,
) -> @list.List[@syntax.Case]? raise {
  if cases is Some(cases) {
    Some(ctx.rewrite_cases(cases))
  } else {
    None
  }
}

///|
fn MetavarRewriteContext::rewrite_regex_pattern(
  ctx : MetavarRewriteContext,
  pattern : @syntax.RegexPattern,
) -> @syntax.RegexPattern raise {
  match pattern {
    Alias(pat~, binder~, loc~) =>
      Alias(
        pat=ctx.rewrite_regex_pattern(pat),
        binder=ctx.rewrite_binder(binder),
        loc~,
      )
    Alternation(pat1~, pat2~, loc~) =>
      Alternation(
        pat1=ctx.rewrite_regex_pattern(pat1),
        pat2=ctx.rewrite_regex_pattern(pat2),
        loc~,
      )
    Sequence(pat1~, pat2~, loc~) =>
      Sequence(
        pat1=ctx.rewrite_regex_pattern(pat1),
        pat2=ctx.rewrite_regex_pattern(pat2),
        loc~,
      )
    _ => pattern
  }
}

///|
fn MetavarRewriteContext::rewrite_regex_bindings(
  ctx : MetavarRewriteContext,
  bindings : @list.List[(@syntax.Label, @syntax.Binder?)],
) -> @list.List[(@syntax.Label, @syntax.Binder?)] raise {
  let result : Array[(@syntax.Label, @syntax.Binder?)] = []
  for binding in bindings {
    let (label, binder) = binding
    result.push(
      (ctx.rewrite_label(label), ctx.rewrite_optional_binder_value(binder)),
    )
  }
  List(result)
}

///|
fn MetavarRewriteContext::rewrite_optional_binder_value(
  ctx : MetavarRewriteContext,
  binder : @syntax.Binder?,
) -> @syntax.Binder? raise {
  if binder is Some(binder) {
    Some(ctx.rewrite_binder(binder))
  } else {
    None
  }
}
