///|
fn MetavarRewriteContext::rewrite_type(
  ctx : MetavarRewriteContext,
  ty : @syntax.Type,
) -> @syntax.Type raise {
  if ctx.rewrite_type_metavar(ty) is Some(rewritten) {
    return rewritten
  }
  match ty {
    Any(_) => ty
    Arrow(args~, res~, err~, is_async~, loc~) =>
      Arrow(
        args=ctx.rewrite_types(args),
        res=ctx.rewrite_type(res),
        err=ctx.rewrite_error_type(err),
        is_async~,
        loc~,
      )
    Tuple(tys~, loc~) => Tuple(tys=ctx.rewrite_types(tys), loc~)
    Name(constr_id~, tys~, loc~) =>
      Name(constr_id~, tys=ctx.rewrite_types(tys), loc~)
    Option(ty=inner, loc~, question_loc~) =>
      Option(ty=ctx.rewrite_type(inner), loc~, question_loc~)
    Object(_) => ty
  }
}

///|
fn MetavarRewriteContext::rewrite_type_metavar(
  ctx : MetavarRewriteContext,
  ty : @syntax.Type,
) -> @syntax.Type? raise {
  guard ty is Name(constr_id~, tys~, loc~) else { return None }
  if !tys.is_empty() {
    return None
  }
  guard constr_id.id is Ident(name~) else { return None }
  match parse_metavar(name, ctx.path, ctx.context) {
    None => None
    Some(syntax) =>
      match ctx.collect_or_resolve_metavar(syntax, BareTypePosition) {
        None => None
        Some((kind, meta_name)) => {
          if kind != "type" {
            ctx.reject_metavar_position(kind, meta_name)
          }
          ctx.register_metavar(kind, meta_name)
          Some(type_metavar_marker(meta_name, loc))
        }
      }
  }
}

///|
fn type_metavar_marker(name : String, loc : @basic.Location) -> @syntax.Type {
  Name(constr_id={ id: Ident(name~), loc }, tys=List([]), loc~)
}

///|
fn MetavarRewriteContext::rewrite_optional_type(
  ctx : MetavarRewriteContext,
  ty : @syntax.Type?,
) -> @syntax.Type? raise {
  match ty {
    None => None
    Some(ty) => Some(ctx.rewrite_type(ty))
  }
}

///|
fn MetavarRewriteContext::rewrite_types(
  ctx : MetavarRewriteContext,
  tys : @list.List[@syntax.Type],
) -> @list.List[@syntax.Type] raise {
  let result : Array[@syntax.Type] = []
  for ty in tys {
    result.push(ctx.rewrite_type(ty))
  }
  List(result)
}

///|
fn MetavarRewriteContext::rewrite_error_type(
  ctx : MetavarRewriteContext,
  ty : @syntax.ErrorType,
) -> @syntax.ErrorType raise {
  match ty {
    ErrorType(ty~) => ErrorType(ty=ctx.rewrite_type(ty))
    MaybeError(ty~) => MaybeError(ty=ctx.rewrite_type(ty))
    DefaultErrorType(_) | NoErrorType | Noraise(_) => ty
  }
}
