///|
/// Returns whether `candidate` has the same AST shape as `pattern`.
///
/// This convenience entry point does not enable declared metavars. It still
/// treats parser holes and identifiers made entirely of two or more underscores
/// as ignore placeholders.
pub fn expr_matches(pattern : @syntax.Expr, candidate : @syntax.Expr) -> Bool {
  let compiled : CompiledExprPattern = {
    ast: pattern,
    subtree_metavars: [],
    identifier_metavars: [],
    auto_metavars: [],
    target_metavar: None,
    source_metavar: None,
  }
  match_expr_pattern(compiled, candidate) is Some(_)
}

///|
/// Matches `candidate` against a compiled expression pattern.
///
/// This attempts a single root-level match of `compiled.ast` against
/// `candidate`. It does not traverse candidate descendants; callers that need
/// search should pass each candidate expression subtree separately.
///
/// The returned bindings are fresh for this call. A failed match returns
/// `None` and does not expose partial bindings.
pub fn match_expr_pattern(
  compiled : CompiledExprPattern,
  candidate : @syntax.Expr,
) -> ExprMatch? {
  let bindings : @hashmap.HashMap[String, BoundValue] = @hashmap.HashMap([])
  match_expr_pattern_with_bindings(compiled, candidate, bindings)
}

///|
/// Matches with a caller-supplied binding context.
///
/// This is used by `inside-expr` rules: the outer match establishes bindings,
/// then candidate target expressions are matched with those bindings already in
/// scope. The input map is copied before matching, so failed attempts cannot
/// mutate the caller's context.
pub fn match_expr_pattern_with_bindings(
  compiled : CompiledExprPattern,
  candidate : @syntax.Expr,
  initial_bindings : @hashmap.HashMap[String, BoundValue],
) -> ExprMatch? {
  let bindings = initial_bindings.copy()
  if match_expr(compiled.ast, candidate, compiled, bindings) {
    Some({ root: candidate, bindings })
  } else {
    None
  }
}

///|
fn match_expr(
  pattern : @syntax.Expr,
  candidate : @syntax.Expr,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  match match_expr_placeholder(pattern, candidate, compiled, bindings) {
    Some(result) => result
    None =>
      match (pattern, candidate) {
        (Ident(id=pid, ..), Ident(id=cid, ..)) => var_equal(pid, cid)
        (Hole(..), _) => true
        (Constant(c=pc, ..), Constant(c=cc, ..)) => constant_equal(pc, cc)
        (
          ArrayAugmentedSet(op=pop, array=pa, index=pi, value=pv, ..),
          ArrayAugmentedSet(op=cop, array=ca, index=ci, value=cv, ..),
        ) =>
          match_var(pop, cop, compiled, bindings) &&
          match_expr(pa, ca, compiled, bindings) &&
          match_expr(pi, ci, compiled, bindings) &&
          match_expr(pv, cv, compiled, bindings)
        (ArrayGet(array=pa, index=pi, ..), ArrayGet(array=ca, index=ci, ..)) =>
          match_expr(pa, ca, compiled, bindings) &&
          match_expr(pi, ci, compiled, bindings)
        (
          ArrayGetSlice(array=pa, start_index=ps, end_index=pe, ..),
          ArrayGetSlice(array=ca, start_index=cs, end_index=ce, ..),
        ) =>
          match_expr(pa, ca, compiled, bindings) &&
          option_match(ps, cs, (p, c) => match_expr(p, c, compiled, bindings)) &&
          option_match(pe, ce, (p, c) => match_expr(p, c, compiled, bindings))
        (
          ArraySet(array=pa, index=pi, value=pv, ..),
          ArraySet(array=ca, index=ci, value=cv, ..),
        ) =>
          match_expr(pa, ca, compiled, bindings) &&
          match_expr(pi, ci, compiled, bindings) &&
          match_expr(pv, cv, compiled, bindings)
        (ArraySpread(elems=pe, ..), ArraySpread(elems=ce, ..)) =>
          list_match(pe, ce, (p, c) => {
            match_spreadable_elem(p, c, compiled, bindings)
          })
        (As(expr=pe, trait_=pt, ..), As(expr=ce, trait_=ct, ..)) =>
          type_name_equal(pt, ct) && match_expr(pe, ce, compiled, bindings)
        (
          Assign(var_=pv, expr=pe, augmented_by=pa, ..),
          Assign(var_=cv, expr=ce, augmented_by=ca, ..),
        ) =>
          match_var(pv, cv, compiled, bindings) &&
          option_match(pa, ca, (p, c) => match_var(p, c, compiled, bindings)) &&
          match_expr(pe, ce, compiled, bindings)
        (Break(arg=pa, label=pl, ..), Break(arg=ca, label=cl, ..)) =>
          option_match(pa, ca, (p, c) => match_expr(p, c, compiled, bindings)) &&
          option_match(pl, cl, (p, c) => match_label(p, c, compiled, bindings))
        (Constraint(expr=pe, ty=pt, ..), Constraint(expr=ce, ty=ct, ..)) =>
          type_equal(pt, ct) && match_expr(pe, ce, compiled, bindings)
        (Continue(args=pa, label=pl, ..), Continue(args=ca, label=cl, ..)) =>
          list_match(pa, ca, (p, c) => match_expr(p, c, compiled, bindings)) &&
          option_match(pl, cl, (p, c) => match_label(p, c, compiled, bindings))
        (Defer(expr=pe, body=pb, ..), Defer(expr=ce, body=cb, ..)) =>
          match_expr(pe, ce, compiled, bindings) &&
          match_expr(pb, cb, compiled, bindings)
        (Infix(op=pop, lhs=pl, rhs=pr, ..), Infix(op=cop, lhs=cl, rhs=cr, ..)) =>
          match_var(pop, cop, compiled, bindings) &&
          match_expr(pl, cl, compiled, bindings) &&
          match_expr(pr, cr, compiled, bindings)
        (Apply(func=pf, args=pa, ..), Apply(func=cf, args=ca, ..)) =>
          match_expr(pf, cf, compiled, bindings) &&
          list_match(pa, ca, (p, c) => match_argument(p, c, compiled, bindings))
        (
          DotApply(self=ps, method_name=pm, args=pa, return_self=prs, ..),
          DotApply(self=cs, method_name=cm, args=ca, return_self=crs, ..),
        ) =>
          prs == crs &&
          match_expr(ps, cs, compiled, bindings) &&
          match_label(pm, cm, compiled, bindings) &&
          list_match(pa, ca, (p, c) => match_argument(p, c, compiled, bindings))
        (Field(record=pr, accessor=pa, ..), Field(record=cr, accessor=ca, ..)) =>
          match_expr(pr, cr, compiled, bindings) &&
          match_accessor(pa, ca, compiled, bindings)
        (
          ForEach(
            binders=pb,
            expr=pe,
            body=pbody,
            else_block=pelse,
            label=pl,
            ..
          ),
          ForEach(
            binders=cb,
            expr=ce,
            body=cbody,
            else_block=celse,
            label=cl,
            ..
          ),
        ) =>
          list_match(pb, cb, (p, c) => {
            option_match(p, c, (p, c) => match_binder(p, c, compiled, bindings))
          }) &&
          match_expr(pe, ce, compiled, bindings) &&
          match_expr(pbody, cbody, compiled, bindings) &&
          option_match(pelse, celse, (p, c) => {
            match_expr(p, c, compiled, bindings)
          }) &&
          option_match(pl, cl, (p, c) => match_label(p, c, compiled, bindings))
        (Function(func=pf, ..), Function(func=cf, ..)) =>
          match_func(pf, cf, compiled, bindings)
        (
          Guard(cond=pc, otherwise=po, body=pb, ..),
          Guard(cond=cc, otherwise=co, body=cb, ..),
        ) =>
          match_expr(pc, cc, compiled, bindings) &&
          option_match(po, co, (p, c) => match_expr(p, c, compiled, bindings)) &&
          match_expr(pb, cb, compiled, bindings)
        (If(cond=pc, ifso=ps, ifnot=pn, ..), If(cond=cc, ifso=cs, ifnot=cn, ..)) =>
          match_expr(pc, cc, compiled, bindings) &&
          match_expr(ps, cs, compiled, bindings) &&
          option_match(pn, cn, (p, c) => match_expr(p, c, compiled, bindings))
        (Interp(elems=pe, ..), Interp(elems=ce, ..)) =>
          list_match(pe, ce, (p, c) => {
            match_interp_elem(p, c, compiled, bindings)
          })
        (Is(expr=pe, pat=pp, ..), Is(expr=ce, pat=cp, ..)) =>
          match_expr(pe, ce, compiled, bindings) &&
          match_pattern(pp, cp, compiled, bindings)
        (
          Method(type_name=pt, method_name=pm, ..),
          Method(type_name=ct, method_name=cm, ..),
        ) => type_name_equal(pt, ct) && match_label(pm, cm, compiled, bindings)
        (
          Let(pattern=pp, expr=pe, body=pb, ..),
          Let(pattern=cp, expr=ce, body=cb, ..),
        ) =>
          match_pattern(pp, cp, compiled, bindings) &&
          match_expr(pe, ce, compiled, bindings) &&
          match_expr(pb, cb, compiled, bindings)
        (
          LetAnd(bindings=pb, body=pbody, ..),
          LetAnd(bindings=cb, body=cbody, ..),
        ) =>
          list_match(pb, cb, (p, c) => {
            match_let_and_binding(p, c, compiled, bindings)
          }) &&
          match_expr(pbody, cbody, compiled, bindings)
        (
          LetFn(name=pn, func=pf, body=pb, ..),
          LetFn(name=cn, func=cf, body=cb, ..),
        ) =>
          match_binder(pn, cn, compiled, bindings) &&
          match_func(pf, cf, compiled, bindings) &&
          match_expr(pb, cb, compiled, bindings)
        (
          LetMut(binder=pb, ty=pt, expr=pe, body=pbody, ..),
          LetMut(binder=cb, ty=ct, expr=ce, body=cbody, ..),
        ) =>
          match_binder(pb, cb, compiled, bindings) &&
          option_match(pt, ct, type_equal) &&
          match_expr(pe, ce, compiled, bindings) &&
          match_expr(pbody, cbody, compiled, bindings)
        (Map(elems=pe, ..), Map(elems=ce, ..)) =>
          list_match(pe, ce, (p, c) => {
            match_map_expr_elem(p, c, compiled, bindings)
          })
        (Match(expr=pe, cases=pc, ..), Match(expr=ce, cases=cc, ..)) =>
          match_expr(pe, ce, compiled, bindings) &&
          list_match(pc, cc, (p, c) => match_case(p, c, compiled, bindings))
        (Constr(constr=pc, ..), Constr(constr=cc, ..)) =>
          constructor_equal(pc, cc)
        (MultilineString(elems=pe, ..), MultilineString(elems=ce, ..)) =>
          list_match(pe, ce, (p, c) => {
            match_multiline_string_elem(p, c, compiled, bindings)
          })
        (
          Mutate(record=pr, accessor=pa, field=pf, augmented_by=paug, ..),
          Mutate(record=cr, accessor=ca, field=cf, augmented_by=caug, ..),
        ) =>
          match_expr(pr, cr, compiled, bindings) &&
          match_accessor(pa, ca, compiled, bindings) &&
          match_expr(pf, cf, compiled, bindings) &&
          option_match(paug, caug, (p, c) => match_var(p, c, compiled, bindings))
        (Pipe(lhs=pl, rhs=pr, ..), Pipe(lhs=cl, rhs=cr, ..)) =>
          match_expr(pl, cl, compiled, bindings) &&
          match_expr(pr, cr, compiled, bindings)
        (Raise(err_value=pe, ..), Raise(err_value=ce, ..)) =>
          match_expr(pe, ce, compiled, bindings)
        (
          Record(type_name=pt, fields=pf, trailing=ptr, ..),
          Record(type_name=ct, fields=cf, trailing=ctr, ..),
        ) =>
          option_match(pt, ct, type_name_equal) &&
          trailing_mark_equal(ptr, ctr) &&
          list_match(pf, cf, (p, c) => match_field_def(p, c, compiled, bindings))
        (
          RecordUpdate(type_name=pt, record=pr, fields=pf, ..),
          RecordUpdate(type_name=ct, record=cr, fields=cf, ..),
        ) =>
          option_match(pt, ct, type_name_equal) &&
          match_expr(pr, cr, compiled, bindings) &&
          list_match(pf, cf, (p, c) => match_field_def(p, c, compiled, bindings))
        (Return(return_value=pv, ..), Return(return_value=cv, ..)) =>
          option_match(pv, cv, (p, c) => match_expr(p, c, compiled, bindings))
        (Array(exprs=pe, ..), Array(exprs=ce, ..)) =>
          list_match(pe, ce, (p, c) => match_expr(p, c, compiled, bindings))
        (Tuple(exprs=pe, ..), Tuple(exprs=ce, ..)) =>
          list_match(pe, ce, (p, c) => match_expr(p, c, compiled, bindings))
        (Group(expr=pe, group=pg, ..), Group(expr=ce, group=cg, ..)) =>
          group_equal(pg, cg) && match_expr(pe, ce, compiled, bindings)
        (
          Sequence(exprs=pe, last_expr=pl, ..),
          Sequence(exprs=ce, last_expr=cl, ..),
        ) =>
          list_match(pe, ce, (p, c) => match_expr(p, c, compiled, bindings)) &&
          match_expr(pl, cl, compiled, bindings)
        (
          For(
            binders=pb,
            condition=pc,
            continue_block=pcont,
            body=pbody,
            for_else=pelse,
            where_clause=pwhere,
            label=plabel,
            ..
          ),
          For(
            binders=cb,
            condition=cc,
            continue_block=ccont,
            body=cbody,
            for_else=celse,
            where_clause=cwhere,
            label=clabel,
            ..
          ),
        ) =>
          list_match(pb, cb, (p, c) => {
            match_binder_expr_pair(p, c, compiled, bindings)
          }) &&
          option_match(pc, cc, (p, c) => match_expr(p, c, compiled, bindings)) &&
          list_match(pcont, ccont, (p, c) => {
            match_binder_expr_pair(p, c, compiled, bindings)
          }) &&
          match_expr(pbody, cbody, compiled, bindings) &&
          option_match(pelse, celse, (p, c) => {
            match_expr(p, c, compiled, bindings)
          }) &&
          option_match(pwhere, cwhere, (p, c) => {
            match_where_clause(p, c, compiled, bindings)
          }) &&
          option_match(plabel, clabel, (p, c) => {
            match_label(p, c, compiled, bindings)
          })
        (Unit(faked=pf, ..), Unit(faked=cf, ..)) => pf == cf
        (TryOperator(body=pb, kind=pk, ..), TryOperator(body=cb, kind=ck, ..)) =>
          try_operator_kind_equal(pk, ck) &&
          match_expr(pb, cb, compiled, bindings)
        (
          Try(body=pb, catch_=pc, try_else=pelse, has_try=phas, ..),
          Try(body=cb, catch_=cc, try_else=celse, has_try=chas, ..),
        ) =>
          phas == chas &&
          match_expr(pb, cb, compiled, bindings) &&
          list_match(pc, cc, (p, c) => match_case(p, c, compiled, bindings)) &&
          option_match(pelse, celse, (p, c) => {
            list_match(p, c, (p, c) => match_case(p, c, compiled, bindings))
          })
        (Unary(op=po, expr=pe, ..), Unary(op=co, expr=ce, ..)) =>
          match_var(po, co, compiled, bindings) &&
          match_expr(pe, ce, compiled, bindings)
        (
          While(loop_cond=pc, loop_body=pb, while_else=pe, label=pl, ..),
          While(loop_cond=cc, loop_body=cb, while_else=ce, label=cl, ..),
        ) =>
          match_expr(pc, cc, compiled, bindings) &&
          match_expr(pb, cb, compiled, bindings) &&
          option_match(pe, ce, (p, c) => match_expr(p, c, compiled, bindings)) &&
          option_match(pl, cl, (p, c) => match_label(p, c, compiled, bindings))
        _ => false
      }
  }
}

///|
// Handles rule-pattern placeholders, including special identifiers and parser
// holes, before the structural matcher falls back to literal AST comparison.
fn match_expr_placeholder(
  pattern : @syntax.Expr,
  candidate : @syntax.Expr,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool? {
  match pattern {
    Ident(id~, ..) =>
      match @ident.normalize_identifier_name_from_var(id) {
        Some(name) =>
          if is_ignore_placeholder(name) {
            Some(true)
          } else if is_special_expr_metavar(compiled, name) ||
            contains_name(compiled.subtree_metavars, name) {
            Some(bind_value(bindings, name, Expr(candidate)))
          } else if contains_name(compiled.identifier_metavars, name) {
            match @ident.normalize_identifier_name_from_expr(candidate) {
              Some(candidate_name) =>
                Some(bind_value(bindings, name, Identifier(candidate_name)))
              None => Some(false)
            }
          } else if contains_name(compiled.auto_metavars, name) {
            Some(
              bind_auto_value(
                bindings,
                name,
                @ident.normalize_identifier_name_from_expr(candidate),
                Expr(candidate),
              ),
            )
          } else {
            None
          }
        None => None
      }
    Hole(..) => Some(true)
    _ => None
  }
}

///|
fn match_argument(
  pattern : @syntax.Argument,
  candidate : @syntax.Argument,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  match_argument_kind(pattern.kind, candidate.kind, compiled, bindings) &&
  match_expr(pattern.value, candidate.value, compiled, bindings)
}

///|
fn match_argument_kind(
  pattern : @syntax.ArgumentKind,
  candidate : @syntax.ArgumentKind,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  match (pattern, candidate) {
    (Positional, Positional) => true
    (Labelled(pl), Labelled(cl)) => match_label(pl, cl, compiled, bindings)
    (LabelledPun(pl), LabelledPun(cl)) =>
      match_label(pl, cl, compiled, bindings)
    (LabelledOption(label=pl, ..), LabelledOption(label=cl, ..)) =>
      match_label(pl, cl, compiled, bindings)
    (LabelledOptionPun(label=pl, ..), LabelledOptionPun(label=cl, ..)) =>
      match_label(pl, cl, compiled, bindings)
    _ => false
  }
}

///|
fn match_accessor(
  pattern : @syntax.Accessor,
  candidate : @syntax.Accessor,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  match (pattern, candidate) {
    (Label(pl), Label(cl)) => match_label(pl, cl, compiled, bindings)
    (Index(tuple_index=pi, ..), Index(tuple_index=ci, ..)) => pi == ci
    (Newtype(..), Newtype(..)) => true
    _ => false
  }
}

///|
fn match_binder_expr_pair(
  pattern : (@syntax.Binder, @syntax.Expr),
  candidate : (@syntax.Binder, @syntax.Expr),
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  let (pb, pe) = pattern
  let (cb, ce) = candidate
  match_binder(pb, cb, compiled, bindings) &&
  match_expr(pe, ce, compiled, bindings)
}

///|
fn match_let_and_binding(
  pattern : (@syntax.Binder, @syntax.Type?, @syntax.Func),
  candidate : (@syntax.Binder, @syntax.Type?, @syntax.Func),
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  let (pb, pt, pf) = pattern
  let (cb, ct, cf) = candidate
  match_binder(pb, cb, compiled, bindings) &&
  option_match(pt, ct, type_equal) &&
  match_func(pf, cf, compiled, bindings)
}

///|
fn match_func(
  pattern : @syntax.Func,
  candidate : @syntax.Func,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  fn_kind_equal(pattern.kind, candidate.kind) &&
  error_type_equal(pattern.error_type, candidate.error_type) &&
  option_location_presence_equal(pattern.is_async, candidate.is_async) &&
  option_match(pattern.return_type, candidate.return_type, type_equal) &&
  list_match(pattern.parameters, candidate.parameters, (p, c) => {
    match_parameter(p, c, compiled, bindings)
  }) &&
  match_expr(pattern.body, candidate.body, compiled, bindings)
}

///|
fn match_parameter(
  pattern : @syntax.Parameter,
  candidate : @syntax.Parameter,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  match (pattern, candidate) {
    (DiscardPositional(ty=pt, ..), DiscardPositional(ty=ct, ..)) =>
      option_match(pt, ct, type_equal)
    (Labelled(binder=pb, ty=pt), Labelled(binder=cb, ty=ct)) =>
      match_binder(pb, cb, compiled, bindings) &&
      option_match(pt, ct, type_equal)
    (
      Optional(binder=pb, default=pd, ty=pt),
      Optional(binder=cb, default=cd, ty=ct),
    ) =>
      match_binder(pb, cb, compiled, bindings) &&
      option_match(pt, ct, type_equal) &&
      match_expr(pd, cd, compiled, bindings)
    (Positional(binder=pb, ty=pt), Positional(binder=cb, ty=ct)) =>
      match_binder(pb, cb, compiled, bindings) &&
      option_match(pt, ct, type_equal)
    (QuestionOptional(binder=pb, ty=pt), QuestionOptional(binder=cb, ty=ct)) =>
      match_binder(pb, cb, compiled, bindings) &&
      option_match(pt, ct, type_equal)
    _ => false
  }
}

///|
fn match_pattern(
  pattern : @syntax.Pattern,
  candidate : @syntax.Pattern,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  match pattern {
    Var(binder) => {
      let name = binder.name
      if is_ignore_placeholder(name) {
        true
      } else if contains_name(compiled.subtree_metavars, name) {
        bind_value(bindings, name, Pattern(candidate))
      } else if contains_name(compiled.identifier_metavars, name) {
        match @ident.normalize_identifier_name_from_pattern(candidate) {
          Some(candidate_name) =>
            bind_value(bindings, name, Identifier(candidate_name))
          None => false
        }
      } else if contains_name(compiled.auto_metavars, name) {
        bind_auto_value(
          bindings,
          name,
          @ident.normalize_identifier_name_from_pattern(candidate),
          Pattern(candidate),
        )
      } else {
        match candidate {
          Var(candidate_binder) => binder_equal(binder, candidate_binder)
          _ => false
        }
      }
    }
    Any(..) =>
      match candidate {
        Any(..) => true
        _ => false
      }
    Alias(pat=pp, alias_=pa, ..) =>
      match candidate {
        Alias(pat=cp, alias_=ca, ..) =>
          match_pattern(pp, cp, compiled, bindings) &&
          match_binder(pa, ca, compiled, bindings)
        _ => false
      }
    Array(pats=pp, ..) =>
      match candidate {
        Array(pats=cp, ..) => match_array_patterns(pp, cp, compiled, bindings)
        _ => false
      }
    Constant(c=pc, ..) =>
      match candidate {
        Constant(c=cc, ..) => constant_equal(pc, cc)
        _ => false
      }
    Constr(constr=pc, args=pa, is_open=po, ..) =>
      match candidate {
        Constr(constr=cc, args=ca, is_open=co, ..) =>
          po == co &&
          constructor_equal(pc, cc) &&
          option_match(pa, ca, (p, c) => {
            list_match(p, c, (p, c) => {
              match_constr_pat_arg(p, c, compiled, bindings)
            })
          })
        _ => false
      }
    Constraint(pat=pp, ty=pt, ..) =>
      match candidate {
        Constraint(pat=cp, ty=ct, ..) =>
          type_equal(pt, ct) && match_pattern(pp, cp, compiled, bindings)
        _ => false
      }
    Map(elems=pe, is_closed=pc, ..) =>
      match candidate {
        Map(elems=ce, is_closed=cc, ..) =>
          pc == cc &&
          list_match(pe, ce, (p, c) => {
            match_map_pat_elem(p, c, compiled, bindings)
          })
        _ => false
      }
    Or(pat1=pl, pat2=pr, ..) =>
      match candidate {
        Or(pat1=cl, pat2=cr, ..) =>
          match_pattern(pl, cl, compiled, bindings) &&
          match_pattern(pr, cr, compiled, bindings)
        _ => false
      }
    Range(lhs=pl, rhs=pr, kind=pk, ..) =>
      match candidate {
        Range(lhs=cl, rhs=cr, kind=ck, ..) =>
          range_kind_equal(pk, ck) &&
          match_pattern(pl, cl, compiled, bindings) &&
          match_pattern(pr, cr, compiled, bindings)
        _ => false
      }
    Record(fields=pf, is_closed=pc, ..) =>
      match candidate {
        Record(fields=cf, is_closed=cc, ..) =>
          pc == cc &&
          list_match(pf, cf, (p, c) => match_field_pat(p, c, compiled, bindings))
        _ => false
      }
    SpecialConstr(binder=pb, args=pa, ..) =>
      match candidate {
        SpecialConstr(binder=cb, args=ca, ..) =>
          match_binder(pb, cb, compiled, bindings) &&
          list_match(pa, ca, (p, c) => {
            match_constr_pat_arg(p, c, compiled, bindings)
          })
        _ => false
      }
    Tuple(pats=pp, ..) =>
      match candidate {
        Tuple(pats=cp, ..) =>
          list_match(pp, cp, (p, c) => match_pattern(p, c, compiled, bindings))
        _ => false
      }
  }
}

///|
fn match_array_patterns(
  pattern : @syntax.ArrayPatterns,
  candidate : @syntax.ArrayPatterns,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  match (pattern, candidate) {
    (Closed(patterns), Closed(candidates)) =>
      list_match(patterns, candidates, (p, c) => {
        match_array_pattern(p, c, compiled, bindings)
      })
    (Open(pl, pr, pb), Open(cl, cr, cb)) =>
      dot_dot_binder_equal(pb, cb) &&
      list_match(pl, cl, (p, c) => match_array_pattern(p, c, compiled, bindings)) &&
      list_match(pr, cr, (p, c) => match_array_pattern(p, c, compiled, bindings))
    _ => false
  }
}

///|
fn match_array_pattern(
  pattern : @syntax.ArrayPattern,
  candidate : @syntax.ArrayPattern,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  match (pattern, candidate) {
    (BytesSpread(bytes=left, ..), BytesSpread(bytes=right, ..)) => left == right
    (ConstSpread(binder=pb, pkg=pp, ..), ConstSpread(binder=cb, pkg=cp, ..)) =>
      pp == cp && match_binder(pb, cb, compiled, bindings)
    (Pattern(pattern), Pattern(candidate)) =>
      match_pattern(pattern, candidate, compiled, bindings)
    (StringSpread(str=left, ..), StringSpread(str=right, ..)) => left == right
    _ => false
  }
}

///|
fn match_constr_pat_arg(
  pattern : @syntax.ConstrPatArg,
  candidate : @syntax.ConstrPatArg,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  match_argument_kind(pattern.kind, candidate.kind, compiled, bindings) &&
  match_pattern(pattern.pat, candidate.pat, compiled, bindings)
}

///|
fn match_map_pat_elem(
  pattern : @syntax.MapPatElem,
  candidate : @syntax.MapPatElem,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  pattern.match_absent == candidate.match_absent &&
  constant_equal(pattern.key, candidate.key) &&
  match_pattern(pattern.pat, candidate.pat, compiled, bindings)
}

///|
fn match_field_pat(
  pattern : @syntax.FieldPat,
  candidate : @syntax.FieldPat,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  pattern.is_pun == candidate.is_pun &&
  match_label(pattern.label, candidate.label, compiled, bindings) &&
  match_pattern(pattern.pattern, candidate.pattern, compiled, bindings)
}

///|
fn match_spreadable_elem(
  pattern : @syntax.SpreadableElem,
  candidate : @syntax.SpreadableElem,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  match (pattern, candidate) {
    (Regular(pattern), Regular(candidate)) =>
      match_expr(pattern, candidate, compiled, bindings)
    (Spread(expr=pattern, ..), Spread(expr=candidate, ..)) =>
      match_expr(pattern, candidate, compiled, bindings)
    _ => false
  }
}

///|
fn match_interp_elem(
  pattern : @syntax.InterpElem,
  candidate : @syntax.InterpElem,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  match (pattern, candidate) {
    (Expr(expr=pattern, ..), Expr(expr=candidate, ..)) =>
      match_expr(pattern, candidate, compiled, bindings)
    (Literal(repr=left, ..), Literal(repr=right, ..)) => left == right
    // Parser token internals are not compared here; non-expression
    // interpolation sources currently match by node kind only.
    (Source(_), Source(_)) => true
    _ => false
  }
}

///|
fn match_multiline_string_elem(
  pattern : @syntax.MultilineStringElem,
  candidate : @syntax.MultilineStringElem,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  match (pattern, candidate) {
    (String(left), String(right)) => left == right
    (Interp(left), Interp(right)) =>
      list_match(left, right, (p, c) => {
        match_interp_elem(p, c, compiled, bindings)
      })
    _ => false
  }
}

///|
fn match_map_expr_elem(
  pattern : @syntax.MapExprElem,
  candidate : @syntax.MapExprElem,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  constant_equal(pattern.key, candidate.key) &&
  match_expr(pattern.expr, candidate.expr, compiled, bindings)
}

///|
fn match_case(
  pattern : @syntax.Case,
  candidate : @syntax.Case,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  match_pattern(pattern.pattern, candidate.pattern, compiled, bindings) &&
  option_match(pattern.guard_, candidate.guard_, (p, c) => {
    match_expr(p, c, compiled, bindings)
  }) &&
  match_expr(pattern.body, candidate.body, compiled, bindings)
}

///|
fn match_field_def(
  pattern : @syntax.FieldDef,
  candidate : @syntax.FieldDef,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  pattern.is_pun == candidate.is_pun &&
  match_label(pattern.label, candidate.label, compiled, bindings) &&
  match_expr(pattern.expr, candidate.expr, compiled, bindings)
}

///|
fn match_where_clause(
  pattern : @syntax.WhereClause,
  candidate : @syntax.WhereClause,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  list_match(pattern.fields, candidate.fields, (p, c) => {
    match_field_def(p, c, compiled, bindings)
  })
}

///|
fn match_var(
  pattern : @syntax.Var,
  candidate : @syntax.Var,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  match @ident.normalize_identifier_name_from_var(pattern) {
    Some(name) =>
      if is_ignore_placeholder(name) {
        true
      } else if contains_name(compiled.subtree_metavars, name) {
        bind_value(bindings, name, Var(candidate))
      } else if contains_name(compiled.identifier_metavars, name) {
        match @ident.normalize_identifier_name_from_var(candidate) {
          Some(candidate_name) =>
            bind_value(bindings, name, Identifier(candidate_name))
          None => false
        }
      } else if contains_name(compiled.auto_metavars, name) {
        bind_auto_value(
          bindings,
          name,
          @ident.normalize_identifier_name_from_var(candidate),
          Var(candidate),
        )
      } else {
        var_equal(pattern, candidate)
      }
    None => var_equal(pattern, candidate)
  }
}

///|
fn match_binder(
  pattern : @syntax.Binder,
  candidate : @syntax.Binder,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  let name = pattern.name
  if is_ignore_placeholder(name) {
    true
  } else if contains_name(compiled.subtree_metavars, name) {
    bind_value(bindings, name, Binder(candidate))
  } else if contains_name(compiled.identifier_metavars, name) {
    bind_value(bindings, name, Identifier(candidate.name))
  } else if contains_name(compiled.auto_metavars, name) {
    bind_auto_value(
      bindings,
      name,
      @ident.normalize_identifier_name_from_binder(candidate),
      Binder(candidate),
    )
  } else {
    binder_equal(pattern, candidate)
  }
}

///|
fn match_label(
  pattern : @syntax.Label,
  candidate : @syntax.Label,
  compiled : CompiledExprPattern,
  bindings : @hashmap.HashMap[String, BoundValue],
) -> Bool {
  let name = pattern.name
  if is_ignore_placeholder(name) {
    true
  } else if contains_name(compiled.subtree_metavars, name) {
    bind_value(bindings, name, Label(candidate))
  } else if contains_name(compiled.identifier_metavars, name) {
    bind_value(bindings, name, Identifier(candidate.name))
  } else if contains_name(compiled.auto_metavars, name) {
    bind_auto_value(
      bindings,
      name,
      @ident.normalize_identifier_name_from_label(candidate),
      Label(candidate),
    )
  } else {
    label_equal(pattern, candidate)
  }
}

///|
fn bind_auto_value(
  bindings : @hashmap.HashMap[String, BoundValue],
  name : String,
  normalized_identifier : String?,
  structural_value : BoundValue,
) -> Bool {
  match bindings.get(name) {
    Some(Identifier(existing)) =>
      match normalized_identifier {
        Some(candidate) => existing == candidate
        None => false
      }
    Some(existing) => bound_value_equal(existing, structural_value)
    None =>
      match normalized_identifier {
        Some(candidate) => {
          bindings[name] = Identifier(candidate)
          true
        }
        None => {
          bindings[name] = structural_value
          true
        }
      }
  }
}

///|
fn bind_value(
  bindings : @hashmap.HashMap[String, BoundValue],
  name : String,
  value : BoundValue,
) -> Bool {
  match bindings.get(name) {
    Some(existing) => bound_value_equal(existing, value)
    None => {
      bindings[name] = value
      true
    }
  }
}

///|
fn bound_value_equal(left : BoundValue, right : BoundValue) -> Bool {
  match (left, right) {
    (Expr(left), Expr(right)) => expr_equal_ignoring_loc(left, right)
    (Var(left), Var(right)) => var_equal(left, right)
    (Binder(left), Binder(right)) => binder_equal(left, right)
    (Pattern(left), Pattern(right)) => pattern_equal(left, right)
    (Label(left), Label(right)) => label_equal(left, right)
    (Identifier(left), Identifier(right)) => left == right
    _ => false
  }
}

///|
fn expr_equal_ignoring_loc(left : @syntax.Expr, right : @syntax.Expr) -> Bool {
  match (left, right) {
    (Ident(id=left, ..), Ident(id=right, ..)) => var_equal(left, right)
    (Hole(kind=left, ..), Hole(kind=right, ..)) => hole_equal(left, right)
    (Constant(c=left, ..), Constant(c=right, ..)) => constant_equal(left, right)
    (Infix(op=lop, lhs=ll, rhs=lr, ..), Infix(op=rop, lhs=rl, rhs=rr, ..)) =>
      var_equal(lop, rop) &&
      expr_equal_ignoring_loc(ll, rl) &&
      expr_equal_ignoring_loc(lr, rr)
    (Apply(func=lf, args=la, ..), Apply(func=rf, args=ra, ..)) =>
      expr_equal_ignoring_loc(lf, rf) &&
      list_match(la, ra, (l, r) => argument_equal(l, r))
    (
      DotApply(self=ls, method_name=lm, args=la, return_self=lrs, ..),
      DotApply(self=rs, method_name=rm, args=ra, return_self=rrs, ..),
    ) =>
      lrs == rrs &&
      expr_equal_ignoring_loc(ls, rs) &&
      label_equal(lm, rm) &&
      list_match(la, ra, (l, r) => argument_equal(l, r))
    (Field(record=lr, accessor=la, ..), Field(record=rr, accessor=ra, ..)) =>
      expr_equal_ignoring_loc(lr, rr) && accessor_equal(la, ra)
    (
      Method(type_name=lt, method_name=lm, ..),
      Method(type_name=rt, method_name=rm, ..),
    ) => type_name_equal(lt, rt) && label_equal(lm, rm)
    (Constr(constr=left, ..), Constr(constr=right, ..)) =>
      constructor_equal(left, right)
    (Array(exprs=left, ..), Array(exprs=right, ..)) =>
      list_match(left, right, (l, r) => expr_equal_ignoring_loc(l, r))
    (Tuple(exprs=left, ..), Tuple(exprs=right, ..)) =>
      list_match(left, right, (l, r) => expr_equal_ignoring_loc(l, r))
    (Group(expr=le, group=lg, ..), Group(expr=re, group=rg, ..)) =>
      group_equal(lg, rg) && expr_equal_ignoring_loc(le, re)
    (Sequence(exprs=le, last_expr=ll, ..), Sequence(exprs=re, last_expr=rl, ..)) =>
      list_match(le, re, (l, r) => expr_equal_ignoring_loc(l, r)) &&
      expr_equal_ignoring_loc(ll, rl)
    (
      For(
        binders=lb,
        condition=lc,
        continue_block=lcont,
        body=lbody,
        for_else=lelse,
        ..
      ),
      For(
        binders=rb,
        condition=rc,
        continue_block=rcont,
        body=rbody,
        for_else=relse,
        ..
      ),
    ) =>
      list_match(lb, rb, binder_expr_pair_equal) &&
      option_match(lc, rc, expr_equal_ignoring_loc) &&
      list_match(lcont, rcont, binder_expr_pair_equal) &&
      expr_equal_ignoring_loc(lbody, rbody) &&
      option_match(lelse, relse, expr_equal_ignoring_loc)
    (Unit(faked=left, ..), Unit(faked=right, ..)) => left == right
    _ => false
  }
}

///|
fn argument_equal(left : @syntax.Argument, right : @syntax.Argument) -> Bool {
  argument_kind_equal(left.kind, right.kind) &&
  expr_equal_ignoring_loc(left.value, right.value)
}

///|
fn argument_kind_equal(
  left : @syntax.ArgumentKind,
  right : @syntax.ArgumentKind,
) -> Bool {
  match (left, right) {
    (Positional, Positional) => true
    (Labelled(left), Labelled(right)) => label_equal(left, right)
    (LabelledPun(left), LabelledPun(right)) => label_equal(left, right)
    (LabelledOption(label=left, ..), LabelledOption(label=right, ..)) =>
      label_equal(left, right)
    (LabelledOptionPun(label=left, ..), LabelledOptionPun(label=right, ..)) =>
      label_equal(left, right)
    _ => false
  }
}

///|
fn accessor_equal(left : @syntax.Accessor, right : @syntax.Accessor) -> Bool {
  match (left, right) {
    (Label(left), Label(right)) => label_equal(left, right)
    (Index(tuple_index=left, ..), Index(tuple_index=right, ..)) => left == right
    (Newtype(..), Newtype(..)) => true
    _ => false
  }
}

///|
fn binder_expr_pair_equal(
  left : (@syntax.Binder, @syntax.Expr),
  right : (@syntax.Binder, @syntax.Expr),
) -> Bool {
  let (left_binder, left_expr) = left
  let (right_binder, right_expr) = right
  binder_equal(left_binder, right_binder) &&
  expr_equal_ignoring_loc(left_expr, right_expr)
}

///|
fn pattern_equal(left : @syntax.Pattern, right : @syntax.Pattern) -> Bool {
  match (left, right) {
    (Var(left), Var(right)) => binder_equal(left, right)
    (Any(..), Any(..)) => true
    (Constant(c=left, ..), Constant(c=right, ..)) => constant_equal(left, right)
    (Tuple(pats=left, ..), Tuple(pats=right, ..)) =>
      list_match(left, right, pattern_equal)
    (Or(pat1=ll, pat2=lr, ..), Or(pat1=rl, pat2=rr, ..)) =>
      pattern_equal(ll, rl) && pattern_equal(lr, rr)
    _ => false
  }
}

///|
fn var_equal(left : @syntax.Var, right : @syntax.Var) -> Bool {
  long_ident_equal(left.name, right.name)
}

///|
fn binder_equal(left : @syntax.Binder, right : @syntax.Binder) -> Bool {
  left.name == right.name
}

///|
fn label_equal(left : @syntax.Label, right : @syntax.Label) -> Bool {
  left.name == right.name
}

///|
fn long_ident_equal(
  left : @syntax.LongIdent,
  right : @syntax.LongIdent,
) -> Bool {
  match (left, right) {
    (Ident(name=left), Ident(name=right)) => left == right
    (Dot(pkg=left_pkg, id=left_id), Dot(pkg=right_pkg, id=right_id)) =>
      left_pkg == right_pkg && left_id == right_id
    _ => false
  }
}

///|
fn type_name_equal(left : @syntax.TypeName, right : @syntax.TypeName) -> Bool {
  left.is_object == right.is_object && long_ident_equal(left.name, right.name)
}

///|
fn constructor_equal(
  left : @syntax.Constructor,
  right : @syntax.Constructor,
) -> Bool {
  constr_name_equal(left.name, right.name) &&
  constructor_extra_info_equal(left.extra_info, right.extra_info)
}

///|
fn constr_name_equal(
  left : @syntax.ConstrName,
  right : @syntax.ConstrName,
) -> Bool {
  left.name == right.name
}

///|
fn constructor_extra_info_equal(
  left : @syntax.ConstructorExtraInfo,
  right : @syntax.ConstructorExtraInfo,
) -> Bool {
  match (left, right) {
    (NoExtraInfo, NoExtraInfo) => true
    (Package(left), Package(right)) => left == right
    (TypeName(left), TypeName(right)) => type_name_equal(left, right)
    (
      TypeNameWithConstrPackage(type_name=left_type, pkg=left_pkg),
      TypeNameWithConstrPackage(type_name=right_type, pkg=right_pkg),
    ) => left_pkg == right_pkg && type_name_equal(left_type, right_type)
    _ => false
  }
}

///|
fn type_equal(left : @syntax.Type, right : @syntax.Type) -> Bool {
  match (left, right) {
    (Any(..), Any(..)) => true
    (
      Arrow(args=left_args, res=left_res, err=left_err, is_async=left_async, ..),
      Arrow(
        args=right_args,
        res=right_res,
        err=right_err,
        is_async=right_async,
        ..
      ),
    ) =>
      option_location_presence_equal(left_async, right_async) &&
      error_type_equal(left_err, right_err) &&
      list_match(left_args, right_args, type_equal) &&
      type_equal(left_res, right_res)
    (
      Name(constr_id=left_id, tys=left_tys, ..),
      Name(constr_id=right_id, tys=right_tys, ..),
    ) =>
      constr_id_equal(left_id, right_id) &&
      list_match(left_tys, right_tys, type_equal)
    (Object(left), Object(right)) => constr_id_equal(left, right)
    (Option(ty=left, ..), Option(ty=right, ..)) => type_equal(left, right)
    (Tuple(tys=left, ..), Tuple(tys=right, ..)) =>
      list_match(left, right, type_equal)
    _ => false
  }
}

///|
fn constr_id_equal(left : @syntax.ConstrId, right : @syntax.ConstrId) -> Bool {
  long_ident_equal(left.id, right.id)
}

///|
fn error_type_equal(
  left : @syntax.ErrorType,
  right : @syntax.ErrorType,
) -> Bool {
  match (left, right) {
    (DefaultErrorType(..), DefaultErrorType(..)) => true
    (ErrorType(ty=left), ErrorType(ty=right)) => type_equal(left, right)
    (MaybeError(ty=left), MaybeError(ty=right)) => type_equal(left, right)
    (NoErrorType, NoErrorType) => true
    (Noraise(..), Noraise(..)) => true
    _ => false
  }
}

///|
fn fn_kind_equal(left : @syntax.FnKind, right : @syntax.FnKind) -> Bool {
  match (left, right) {
    (Arrow, Arrow) => true
    (Lambda, Lambda) => true
    _ => false
  }
}

///|
fn range_kind_equal(
  left : @syntax.RangeKind,
  right : @syntax.RangeKind,
) -> Bool {
  match (left, right) {
    (Exclusive, Exclusive) => true
    (Inclusive, Inclusive) => true
    (InclusiveMissingEqual, InclusiveMissingEqual) => true
    _ => false
  }
}

///|
fn dot_dot_binder_equal(
  left : @syntax.DotDotBinder,
  right : @syntax.DotDotBinder,
) -> Bool {
  match (left, right) {
    (Binder(left), Binder(right)) => binder_equal(left, right)
    (BinderAs(left), BinderAs(right)) => binder_equal(left, right)
    (NoBinder, NoBinder) => true
    (Underscore, Underscore) => true
    _ => false
  }
}

///|
fn trailing_mark_equal(
  left : @syntax.TrailingMark,
  right : @syntax.TrailingMark,
) -> Bool {
  match (left, right) {
    (Comma, Comma) => true
    (None, None) => true
    (Semi, Semi) => true
    _ => false
  }
}

///|
fn try_operator_kind_equal(
  left : @syntax.TryOperatorKind,
  right : @syntax.TryOperatorKind,
) -> Bool {
  match (left, right) {
    (Exclamation, Exclamation) => true
    (Question, Question) => true
    _ => false
  }
}

///|
fn option_location_presence_equal(
  left : @basic.Location?,
  right : @basic.Location?,
) -> Bool {
  match (left, right) {
    (None, None) => true
    (Some(_), Some(_)) => true
    _ => false
  }
}

///|
fn constant_equal(left : @syntax.Constant, right : @syntax.Constant) -> Bool {
  match (left, right) {
    (BigInt(left), BigInt(right)) => left == right
    (Bool(left), Bool(right)) => left == right
    (Byte(left), Byte(right)) => left == right
    (Bytes(left), Bytes(right)) => left == right
    (Char(left), Char(right)) => left == right
    (Double(left), Double(right)) => left == right
    (Float(left), Float(right)) => left == right
    (Int(left), Int(right)) => left == right
    (Int64(left), Int64(right)) => left == right
    (Regex(left), Regex(right)) => left == right
    (String(left), String(right)) => left == right
    (UInt(left), UInt(right)) => left == right
    (UInt64(left), UInt64(right)) => left == right
    _ => false
  }
}

///|
fn group_equal(left : @syntax.Group, right : @syntax.Group) -> Bool {
  match (left, right) {
    (Brace, Brace) => true
    (Paren, Paren) => true
    _ => false
  }
}

///|
fn hole_equal(left : @syntax.Hole, right : @syntax.Hole) -> Bool {
  match (left, right) {
    (Incomplete, Incomplete) => true
    (Synthesized, Synthesized) => true
    (Todo, Todo) => true
    _ => false
  }
}

///|
fn[A] option_match(left : A?, right : A?, equal : (A, A) -> Bool) -> Bool {
  match (left, right) {
    (None, None) => true
    (Some(left), Some(right)) => equal(left, right)
    _ => false
  }
}

///|
fn[A] list_match(
  left : @list.List[A],
  right : @list.List[A],
  equal : (A, A) -> Bool,
) -> Bool {
  let left_array = left.to_array()
  let right_array = right.to_array()
  if left_array.length() != right_array.length() {
    return false
  }
  for index in 0..<left_array.length() {
    if !equal(left_array[index], right_array[index]) {
      return false
    }
  }
  true
}

///|
fn contains_name(names : Array[String], name : String) -> Bool {
  for item in names {
    if item == name {
      return true
    }
  }
  false
}

///|
fn is_special_expr_metavar(
  compiled : CompiledExprPattern,
  name : String,
) -> Bool {
  compiled.target_metavar == Some(name) || compiled.source_metavar == Some(name)
}

///|
fn is_ignore_placeholder(name : String) -> Bool {
  if name.length() < 2 {
    return false
  }
  for char in name {
    if char != '_' {
      return false
    }
  }
  true
}
