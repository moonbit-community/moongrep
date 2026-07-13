///|
priv struct MetavarRewriteContext {
  path : String
  context : String
  expr_metavars : Array[String]
  identifier_metavars : Array[String]
  constant_metavars : Array[String]
  arg_metavars : Array[String]
  type_metavars : Array[String]
  pattern_metavars : Array[String]
  collecting : Bool
  bare_expression_metavars : Array[String]
  bare_identifier_metavars : Array[String]
  bare_pattern_metavars : Array[String]
  bare_type_metavars : Array[String]
  resolved_metavars : Map[String, String]
}

///|
fn MetavarRewriteContext::register_metavar(
  ctx : MetavarRewriteContext,
  kind : String,
  name : String,
) -> Unit raise {
  if kind == "pat" {
    ctx.reject_metavar_position(kind, name)
  }
  if kind != "exp" &&
    kind != "id" &&
    kind != "const" &&
    kind != "arg" &&
    kind != "type" {
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
    ctx.ensure_no_other_metavar_kind(name, ctx.arg_metavars, ctx.type_metavars)
    if !array_contains(ctx.expr_metavars, name) {
      ctx.expr_metavars.push(name)
    }
  } else if kind == "id" {
    ctx.ensure_no_other_metavar_kind(
      name,
      ctx.expr_metavars,
      ctx.constant_metavars,
    )
    ctx.ensure_no_other_metavar_kind(name, ctx.arg_metavars, ctx.type_metavars)
    if !array_contains(ctx.identifier_metavars, name) {
      ctx.identifier_metavars.push(name)
    }
  } else if kind == "const" {
    ctx.ensure_no_other_metavar_kind(
      name,
      ctx.expr_metavars,
      ctx.identifier_metavars,
    )
    ctx.ensure_no_other_metavar_kind(name, ctx.arg_metavars, ctx.type_metavars)
    if !array_contains(ctx.constant_metavars, name) {
      ctx.constant_metavars.push(name)
    }
  } else if kind == "arg" {
    ctx.ensure_no_other_metavar_kind(
      name,
      ctx.expr_metavars,
      ctx.identifier_metavars,
    )
    ctx.ensure_no_other_metavar_kind(
      name,
      ctx.constant_metavars,
      ctx.pattern_metavars,
    )
    ctx.ensure_no_other_metavar_kind(name, ctx.type_metavars, [])
    if !array_contains(ctx.arg_metavars, name) {
      ctx.arg_metavars.push(name)
    }
  } else {
    ctx.ensure_no_other_metavar_kind(
      name,
      ctx.expr_metavars,
      ctx.identifier_metavars,
    )
    ctx.ensure_no_other_metavar_kind(
      name,
      ctx.constant_metavars,
      ctx.arg_metavars,
    )
    ctx.ensure_no_other_metavar_kind(name, ctx.pattern_metavars, [])
    if !array_contains(ctx.type_metavars, name) {
      ctx.type_metavars.push(name)
    }
  }
}

///|
fn MetavarRewriteContext::collect_or_resolve_metavar(
  ctx : MetavarRewriteContext,
  syntax : MetavarSyntax,
  position : BareMetavarPosition,
) -> (String, String)? raise {
  match syntax {
    Explicit(kind, name) => Some((kind, name))
    Bare(name) =>
      if ctx.collecting {
        ctx.record_bare_metavar(name, position)
        None
      } else {
        Some((ctx.resolved_metavar_kind(name), name))
      }
  }
}

///|
fn MetavarRewriteContext::record_bare_metavar(
  ctx : MetavarRewriteContext,
  name : String,
  position : BareMetavarPosition,
) -> Unit raise {
  validate_declared_metavar(ctx.path, ctx.context, name, true)
  match position {
    BareExpressionPosition =>
      push_unique_string(ctx.bare_expression_metavars, name)
    BareIdentifierPosition =>
      push_unique_string(ctx.bare_identifier_metavars, name)
    BarePatternVariablePosition =>
      push_unique_string(ctx.bare_pattern_metavars, name)
    BareTypePosition => push_unique_string(ctx.bare_type_metavars, name)
  }
}

///|
fn MetavarRewriteContext::resolve_metavar_kinds(
  ctx : MetavarRewriteContext,
) -> Map[String, String] raise {
  let resolved : Map[String, String] = Map([])
  for name in ctx.pattern_metavars {
    resolved[name] = "pat"
  }
  for name in ctx.expr_metavars {
    if !array_contains(ctx.pattern_metavars, name) {
      resolved[name] = "exp"
    }
  }
  for name in ctx.identifier_metavars {
    if parse_temporary_pattern_metavar_marker(name) is None {
      resolved[name] = "id"
    }
  }
  for name in ctx.constant_metavars {
    if !array_contains(ctx.pattern_metavars, name) {
      resolved[name] = "const"
    }
  }
  for name in ctx.arg_metavars {
    if !array_contains(ctx.pattern_metavars, name) {
      resolved[name] = "arg"
    }
  }
  for name in ctx.type_metavars {
    if !array_contains(ctx.pattern_metavars, name) {
      resolved[name] = "type"
    }
  }
  for name in ctx.bare_identifier_metavars {
    if !resolved.contains(name) {
      resolved[name] = "id"
    }
  }
  for name in ctx.bare_pattern_metavars {
    if !resolved.contains(name) {
      raise RuleLoadError::InvalidRule(
        path=ctx.path,
        info="\{shape_context_name(ctx.context)} cannot infer kind for bare metavar $\{name} in a pattern variable position; use explicit typed syntax like $(\{name}:id), $(\{name}:const), or $(\{name}:pat)",
      )
    }
  }
  for name in ctx.bare_type_metavars {
    if resolved.contains(name) && resolved[name] != "type" {
      raise RuleLoadError::InvalidRule(
        path=ctx.path,
        info="\{shape_context_name(ctx.context)} declares metavar \{name} as multiple metavar kinds",
      )
    }
    if !resolved.contains(name) {
      resolved[name] = "type"
    }
  }
  for name in ctx.bare_expression_metavars {
    if !resolved.contains(name) {
      resolved[name] = "exp"
    }
  }
  resolved
}

///|
fn MetavarRewriteContext::resolved_metavar_kind(
  ctx : MetavarRewriteContext,
  name : String,
) -> String raise {
  if ctx.resolved_metavars.contains(name) {
    ctx.resolved_metavars[name]
  } else {
    raise RuleLoadError::InvalidRule(
      path=ctx.path,
      info="\{shape_context_name(ctx.context)} cannot infer kind for bare metavar $\{name}; use explicit typed syntax like $(\{name}:exp)",
    )
  }
}

///|
fn push_unique_string(items : Array[String], item : String) -> Unit {
  if !array_contains(items, item) {
    items.push(item)
  }
}

///|
fn MetavarRewriteContext::ensure_no_other_metavar_kind(
  ctx : MetavarRewriteContext,
  name : String,
  left : Array[String],
  right : Array[String],
) -> Unit raise {
  if array_contains(left, name) || array_contains(right, name) {
    raise RuleLoadError::InvalidRule(
      path=ctx.path,
      info="\{shape_context_name(ctx.context)} declares metavar \{name} as multiple metavar kinds",
    )
  }
}

///|
fn MetavarRewriteContext::reject_metavar_position(
  ctx : MetavarRewriteContext,
  kind : String,
  name : String,
) -> Unit raise {
  if kind == "exp" {
    raise RuleLoadError::InvalidRule(
      path=ctx.path,
      info="\{shape_context_name(ctx.context)} uses \{metavar_text(kind, name)} outside a bare expression position",
    )
  } else if kind == "pat" {
    raise RuleLoadError::InvalidRule(
      path=ctx.path,
      info="\{shape_context_name(ctx.context)} uses \{metavar_text(kind, name)} outside a bare pattern position",
    )
  } else if kind == "arg" {
    raise RuleLoadError::InvalidRule(
      path=ctx.path,
      info="\{shape_context_name(ctx.context)} uses \{metavar_text(kind, name)} outside a bare argument position",
    )
  } else if kind == "type" {
    raise RuleLoadError::InvalidRule(
      path=ctx.path,
      info="\{shape_context_name(ctx.context)} uses \{metavar_text(kind, name)} outside a whole type position",
    )
  } else if kind == "id" {
    raise RuleLoadError::InvalidRule(
      path=ctx.path,
      info="\{shape_context_name(ctx.context)} uses \{metavar_text(kind, name)} outside an identifier position",
    )
  } else {
    raise RuleLoadError::InvalidRule(
      path=ctx.path,
      info="\{shape_context_name(ctx.context)} uses \{metavar_text(kind, name)} outside a constant expression or pattern position",
    )
  }
}

///|
fn MetavarRewriteContext::reject_qualified_metavar(
  ctx : MetavarRewriteContext,
  kind : String,
  name : String,
) -> Unit raise {
  if kind == "exp" {
    raise RuleLoadError::InvalidRule(
      path=ctx.path,
      info="\{shape_context_name(ctx.context)} uses \{metavar_text(kind, name)} outside a bare expression position",
    )
  } else if kind == "arg" {
    raise RuleLoadError::InvalidRule(
      path=ctx.path,
      info="\{shape_context_name(ctx.context)} uses \{metavar_text(kind, name)} outside a bare argument position",
    )
  } else if kind == "type" {
    raise RuleLoadError::InvalidRule(
      path=ctx.path,
      info="\{shape_context_name(ctx.context)} uses \{metavar_text(kind, name)} outside a whole type position",
    )
  } else {
    raise RuleLoadError::InvalidRule(
      path=ctx.path,
      info="\{shape_context_name(ctx.context)} uses \{metavar_text(kind, name)} in an unsupported qualified identifier position",
    )
  }
}
