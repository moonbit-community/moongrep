///|
priv struct InlineMetavarRewriteContext {
  path : String
  context : String
  expr_metavars : Array[String]
  identifier_metavars : Array[String]
  constant_metavars : Array[String]
}

///|
fn InlineMetavarRewriteContext::register_inline_metavar(
  ctx : InlineMetavarRewriteContext,
  kind : String,
  name : String,
) -> Unit raise {
  if kind == "pat" {
    ctx.reject_inline_metavar_position(kind, name)
  }
  if kind != "exp" && kind != "id" && kind != "const" {
    raise RuleLoadError::InvalidRule(
      path=ctx.path,
      info="\{shape_context_name(ctx.context)} contains unsupported metavar kind \{kind}",
    )
  }
  validate_declared_metavar(ctx.path, ctx.context, name, true)
  if kind == "exp" {
    ctx.ensure_no_other_metavar_kind(
      name,
      ctx.identifier_metavars,
      ctx.constant_metavars,
    )
    if !array_contains(ctx.expr_metavars, name) {
      ctx.expr_metavars.push(name)
    }
  } else if kind == "id" {
    ctx.ensure_no_other_metavar_kind(
      name,
      ctx.expr_metavars,
      ctx.constant_metavars,
    )
    if !array_contains(ctx.identifier_metavars, name) {
      ctx.identifier_metavars.push(name)
    }
  } else {
    ctx.ensure_no_other_metavar_kind(
      name,
      ctx.expr_metavars,
      ctx.identifier_metavars,
    )
    if !array_contains(ctx.constant_metavars, name) {
      ctx.constant_metavars.push(name)
    }
  }
}

///|
fn InlineMetavarRewriteContext::ensure_no_other_metavar_kind(
  ctx : InlineMetavarRewriteContext,
  name : String,
  left : Array[String],
  right : Array[String],
) -> Unit raise {
  if array_contains(left, name) || array_contains(right, name) {
    raise RuleLoadError::InvalidRule(
      path=ctx.path,
      info="\{shape_context_name(ctx.context)} declares metavar \{name} as multiple inline metavar kinds",
    )
  }
}

///|
fn InlineMetavarRewriteContext::reject_inline_metavar_position(
  ctx : InlineMetavarRewriteContext,
  kind : String,
  name : String,
) -> Unit raise {
  if kind == "exp" {
    raise RuleLoadError::InvalidRule(
      path=ctx.path,
      info="\{shape_context_name(ctx.context)} uses \{inline_metavar_text(kind, name)} outside a bare expression position",
    )
  } else if kind == "pat" {
    raise RuleLoadError::InvalidRule(
      path=ctx.path,
      info="\{shape_context_name(ctx.context)} uses \{inline_metavar_text(kind, name)} outside a bare pattern position",
    )
  } else {
    raise RuleLoadError::InvalidRule(
      path=ctx.path,
      info="\{shape_context_name(ctx.context)} uses \{inline_metavar_text(kind, name)} outside a constant expression or pattern position",
    )
  }
}

///|
fn InlineMetavarRewriteContext::reject_qualified_inline_metavar(
  ctx : InlineMetavarRewriteContext,
  id : String,
) -> Unit raise {
  match parse_inline_metavar(id, ctx.path, ctx.context) {
    Some((kind, name)) =>
      if kind == "exp" {
        raise RuleLoadError::InvalidRule(
          path=ctx.path,
          info="\{shape_context_name(ctx.context)} uses \{inline_metavar_text(kind, name)} outside a bare expression position",
        )
      } else {
        raise RuleLoadError::InvalidRule(
          path=ctx.path,
          info="\{shape_context_name(ctx.context)} uses \{inline_metavar_text(kind, name)} in an unsupported qualified identifier position",
        )
      }
    None => ()
  }
}
