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
        self_ty=ctx.rewrite_optional_type(self_ty),
        trait_~,
        method_name=ctx.rewrite_binder(method_name),
        quantifiers~,
        method_quantifiers~,
        params=ctx.rewrite_parameters(params),
        ret_ty=ctx.rewrite_optional_type(ret_ty),
        err_ty=ctx.rewrite_error_type(err_ty),
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
        ty=ctx.rewrite_optional_type(ty),
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
        source_ty=ctx.rewrite_type(source_ty),
        view_type_name~,
        view_type_loc~,
        view_constrs=ctx.rewrite_constr_decls(view_constrs),
        view_func_name=ctx.rewrite_binder(view_func_name),
        parameters=ctx.rewrite_parameters(parameters),
        params_loc~,
        body=ctx.rewrite_expr(body),
        vis~,
        loc~,
        attrs~,
        doc~,
      )
    TopImplRelation(
      self_ty~,
      trait_~,
      quantifiers~,
      vis~,
      attrs~,
      loc~,
      doc~,
      is_declare~
    ) =>
      TopImplRelation(
        self_ty=ctx.rewrite_type(self_ty),
        trait_~,
        quantifiers~,
        vis~,
        attrs~,
        loc~,
        doc~,
        is_declare~,
      )
    TopTrait(trait_decl) => TopTrait(ctx.rewrite_trait_decl(trait_decl))
    TopTypeDef(type_decl) => TopTypeDef(ctx.rewrite_type_decl(type_decl))
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
    error_type: ctx.rewrite_error_type(fun_decl.error_type),
    is_async: fun_decl.is_async,
    loc: fun_decl.loc,
    name: ctx.rewrite_binder(fun_decl.name),
    params_loc: fun_decl.params_loc,
    quantifiers: fun_decl.quantifiers,
    return_type: ctx.rewrite_optional_type(fun_decl.return_type),
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
fn MetavarRewriteContext::rewrite_type_decl(
  ctx : MetavarRewriteContext,
  decl : @syntax.TypeDecl,
) -> @syntax.TypeDecl raise {
  {
    attrs: decl.attrs,
    components: ctx.rewrite_type_desc(decl.components),
    deriving: decl.deriving,
    doc: decl.doc,
    is_declare: decl.is_declare,
    loc: decl.loc,
    params: decl.params,
    tycon: decl.tycon,
    tycon_loc: decl.tycon_loc,
    type_vis: decl.type_vis,
  }
}

///|
fn MetavarRewriteContext::rewrite_type_desc(
  ctx : MetavarRewriteContext,
  desc : @syntax.TypeDesc,
) -> @syntax.TypeDesc raise {
  match desc {
    Abstract => desc
    Alias(ty) => Alias(ctx.rewrite_type(ty))
    Error(exception_decl) => Error(ctx.rewrite_exception_decl(exception_decl))
    ExtendEnum(target~, constructors~) =>
      ExtendEnum(target~, constructors=ctx.rewrite_constr_decls(constructors))
    ExtensibleEnum(constructors) =>
      ExtensibleEnum(ctx.rewrite_constr_decls(constructors))
    Record(fields~) => Record(fields=ctx.rewrite_field_decls(fields))
    TupleStruct(tys) => TupleStruct(ctx.rewrite_types(tys))
    Variant(constructors) => Variant(ctx.rewrite_constr_decls(constructors))
  }
}

///|
fn MetavarRewriteContext::rewrite_exception_decl(
  ctx : MetavarRewriteContext,
  decl : @syntax.ExceptionDecl,
) -> @syntax.ExceptionDecl raise {
  match decl {
    EnumPayload(constructors) =>
      EnumPayload(ctx.rewrite_constr_decls(constructors))
    NoPayload => decl
  }
}

///|
fn MetavarRewriteContext::rewrite_field_decls(
  ctx : MetavarRewriteContext,
  fields : @list.List[@syntax.FieldDecl],
) -> @list.List[@syntax.FieldDecl] raise {
  let result : Array[@syntax.FieldDecl] = []
  for field in fields {
    result.push(ctx.rewrite_field_decl(field))
  }
  List(result)
}

///|
fn MetavarRewriteContext::rewrite_field_decl(
  ctx : MetavarRewriteContext,
  field : @syntax.FieldDecl,
) -> @syntax.FieldDecl raise {
  {
    attrs: field.attrs,
    doc: field.doc,
    loc: field.loc,
    mut_: field.mut_,
    name: field.name,
    ty: ctx.rewrite_type(field.ty),
    vis: field.vis,
  }
}

///|
fn MetavarRewriteContext::rewrite_constr_decls(
  ctx : MetavarRewriteContext,
  constructors : @list.List[@syntax.ConstrDecl],
) -> @list.List[@syntax.ConstrDecl] raise {
  let result : Array[@syntax.ConstrDecl] = []
  for ctor in constructors {
    result.push(ctx.rewrite_constr_decl(ctor))
  }
  List(result)
}

///|
fn MetavarRewriteContext::rewrite_constr_decl(
  ctx : MetavarRewriteContext,
  ctor : @syntax.ConstrDecl,
) -> @syntax.ConstrDecl raise {
  {
    args: ctx.rewrite_optional_constr_params(ctor.args),
    attrs: ctor.attrs,
    doc: ctor.doc,
    loc: ctor.loc,
    name: ctx.rewrite_constr_name(ctor.name),
    tag: ctor.tag,
  }
}

///|
fn MetavarRewriteContext::rewrite_optional_constr_params(
  ctx : MetavarRewriteContext,
  params : @list.List[@syntax.ConstrParam]?,
) -> @list.List[@syntax.ConstrParam]? raise {
  match params {
    None => None
    Some(params) => Some(ctx.rewrite_constr_params(params))
  }
}

///|
fn MetavarRewriteContext::rewrite_constr_params(
  ctx : MetavarRewriteContext,
  params : @list.List[@syntax.ConstrParam],
) -> @list.List[@syntax.ConstrParam] raise {
  let result : Array[@syntax.ConstrParam] = []
  for param in params {
    result.push(ctx.rewrite_constr_param(param))
  }
  List(result)
}

///|
fn MetavarRewriteContext::rewrite_constr_param(
  ctx : MetavarRewriteContext,
  param : @syntax.ConstrParam,
) -> @syntax.ConstrParam raise {
  { label: param.label, mut_: param.mut_, ty: ctx.rewrite_type(param.ty) }
}

///|
fn MetavarRewriteContext::rewrite_trait_decl(
  ctx : MetavarRewriteContext,
  decl : @syntax.TraitDecl,
) -> @syntax.TraitDecl raise {
  {
    attrs: decl.attrs,
    doc: decl.doc,
    is_declare: decl.is_declare,
    loc: decl.loc,
    methods: ctx.rewrite_trait_method_decls(decl.methods),
    name: ctx.rewrite_binder(decl.name),
    supers: decl.supers,
    vis: decl.vis,
  }
}

///|
fn MetavarRewriteContext::rewrite_trait_method_decls(
  ctx : MetavarRewriteContext,
  methods : @list.List[@syntax.TraitMethodDecl],
) -> @list.List[@syntax.TraitMethodDecl] raise {
  let result : Array[@syntax.TraitMethodDecl] = []
  for method_decl in methods {
    result.push(ctx.rewrite_trait_method_decl(method_decl))
  }
  List(result)
}

///|
fn MetavarRewriteContext::rewrite_trait_method_decl(
  ctx : MetavarRewriteContext,
  method_decl : @syntax.TraitMethodDecl,
) -> @syntax.TraitMethodDecl raise {
  {
    attrs: method_decl.attrs,
    error_type: ctx.rewrite_error_type(method_decl.error_type),
    has_default: method_decl.has_default,
    is_async: method_decl.is_async,
    loc: method_decl.loc,
    name: ctx.rewrite_binder(method_decl.name),
    params: ctx.rewrite_parameters(method_decl.params),
    quantifiers: method_decl.quantifiers,
    return_type: ctx.rewrite_optional_type(method_decl.return_type),
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
