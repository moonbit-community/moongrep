///|
fn MetavarRewriteContext::rewrite_impl(
  ctx : MetavarRewriteContext,
  item : @syntax.Impl,
) -> @syntax.Impl raise {
  match item {
    TopExpr(expr~, is_main~, is_async~, loc~) =>
      TopExpr(expr=ctx.rewrite_expr(expr), is_main~, is_async~, loc~)
    TopFuncDef(fun_decl~, decl_body~, where_clause~, loc~) =>
      TopFuncDef(
        fun_decl=ctx.rewrite_fun_decl(fun_decl),
        decl_body=ctx.rewrite_decl_body(decl_body),
        where_clause=ctx.rewrite_optional_where_clause(where_clause),
        loc~,
      )
    TopImpl(
      self_ty~,
      trait_~,
      method_name~,
      quantifiers~,
      method_quantifiers~,
      params~,
      ret_ty~,
      err_ty~,
      body~,
      vis~,
      loc~,
      attrs~,
      doc~
    ) =>
      TopImpl(
        self_ty~,
        trait_~,
        method_name=ctx.rewrite_binder(method_name),
        quantifiers~,
        method_quantifiers~,
        params=ctx.rewrite_parameters(params),
        ret_ty~,
        err_ty~,
        body=ctx.rewrite_decl_body(body),
        vis~,
        loc~,
        attrs~,
        doc~,
      )
    TopLetDef(
      binder~,
      ty~,
      expr~,
      vis~,
      is_constant~,
      loc~,
      attrs~,
      doc~,
      is_declare~
    ) =>
      TopLetDef(
        binder=ctx.rewrite_binder(binder),
        ty~,
        expr=ctx.rewrite_expr(expr),
        vis~,
        is_constant~,
        loc~,
        attrs~,
        doc~,
        is_declare~,
      )
    TopTest(expr~, name~, params~, is_async~, loc~, attrs~, doc~) =>
      TopTest(
        expr=ctx.rewrite_expr(expr),
        name~,
        params=ctx.rewrite_optional_parameters(params),
        is_async~,
        loc~,
        attrs~,
        doc~,
      )
    TopUsing(pkg~, names~, vis~, attrs~, loc~, doc~) =>
      TopUsing(pkg=ctx.rewrite_label(pkg), names~, vis~, attrs~, loc~, doc~)
    TopView(
      quantifiers~,
      source_ty~,
      view_type_name~,
      view_type_loc~,
      view_constrs~,
      view_func_name~,
      parameters~,
      params_loc~,
      body~,
      vis~,
      loc~,
      attrs~,
      doc~
    ) =>
      TopView(
        quantifiers~,
        source_ty~,
        view_type_name~,
        view_type_loc~,
        view_constrs~,
        view_func_name=ctx.rewrite_binder(view_func_name),
        parameters=ctx.rewrite_parameters(parameters),
        params_loc~,
        body=ctx.rewrite_expr(body),
        vis~,
        loc~,
        attrs~,
        doc~,
      )
    TopTrait(_) | TopTypeDef(_) | TopImplRelation(..) => item
  }
}

///|
fn MetavarRewriteContext::rewrite_fun_decl(
  ctx : MetavarRewriteContext,
  fun_decl : @syntax.FunDecl,
) -> @syntax.FunDecl raise {
  {
    attrs: fun_decl.attrs,
    decl_params: ctx.rewrite_optional_parameters(fun_decl.decl_params),
    doc: fun_decl.doc,
    error_type: fun_decl.error_type,
    is_async: fun_decl.is_async,
    loc: fun_decl.loc,
    name: ctx.rewrite_binder(fun_decl.name),
    params_loc: fun_decl.params_loc,
    quantifiers: fun_decl.quantifiers,
    return_type: fun_decl.return_type,
    type_name: fun_decl.type_name,
    vis: fun_decl.vis,
  }
}

///|
fn MetavarRewriteContext::rewrite_decl_body(
  ctx : MetavarRewriteContext,
  body : @syntax.DeclBody,
) -> @syntax.DeclBody raise {
  match body {
    DeclBody(expr~) => DeclBody(expr=ctx.rewrite_expr(expr))
    DeclNone | DeclStubs(_) => body
  }
}

///|
fn MetavarRewriteContext::rewrite_optional_parameters(
  ctx : MetavarRewriteContext,
  parameters : @list.List[@syntax.Parameter]?,
) -> @list.List[@syntax.Parameter]? raise {
  match parameters {
    None => None
    Some(parameters) => Some(ctx.rewrite_parameters(parameters))
  }
}
