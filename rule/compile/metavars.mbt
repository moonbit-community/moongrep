///|
priv struct MetavarShape {
  ast : @untyped_ast.Node
  expr_metavars : Array[String]
  identifier_metavars : Array[String]
  constant_metavars : Array[String]
  arg_metavars : Array[String]
  pattern_metavars : Array[String]
}

///|
priv enum MetavarSyntax {
  Explicit(String, String)
  Bare(String)
}

///|
priv enum BareMetavarPosition {
  BareExpressionPosition
  BareIdentifierPosition
  BarePatternVariablePosition
}

///|
fn compile_metavar_shape(
  path : String,
  context : String,
  source : String,
) -> MetavarShape raise {
  let parsed = parse_shape(path, context, source)
  let collect_ctx : MetavarRewriteContext = {
    path,
    context,
    expr_metavars: [],
    identifier_metavars: [],
    constant_metavars: [],
    arg_metavars: [],
    pattern_metavars: [],
    collecting: true,
    bare_expression_metavars: [],
    bare_identifier_metavars: [],
    bare_pattern_metavars: [],
    resolved_metavars: {},
  }
  ignore(collect_ctx.rewrite_expr(parsed))
  let resolved_metavars = collect_ctx.resolve_metavar_kinds()
  let ctx : MetavarRewriteContext = {
    path,
    context,
    expr_metavars: [],
    identifier_metavars: [],
    constant_metavars: [],
    arg_metavars: [],
    pattern_metavars: [],
    collecting: false,
    bare_expression_metavars: [],
    bare_identifier_metavars: [],
    bare_pattern_metavars: [],
    resolved_metavars,
  }
  let ast = @untyped_ast.from_expr(ctx.rewrite_expr(parsed))
  let (
    cleaned_expr_metavars,
    cleaned_identifier_metavars,
    cleaned_constant_metavars,
    cleaned_arg_metavars,
    pattern_metavars,
  ) = cleanup_temporary_pattern_metavars(
    ctx.expr_metavars,
    ctx.identifier_metavars,
    ctx.constant_metavars,
    ctx.arg_metavars,
  )
  {
    ast,
    expr_metavars: cleaned_expr_metavars,
    identifier_metavars: cleaned_identifier_metavars,
    constant_metavars: cleaned_constant_metavars,
    arg_metavars: cleaned_arg_metavars,
    pattern_metavars,
  }
}

///|
fn compile_toplevel_metavar_shape(
  path : String,
  context : String,
  source : String,
) -> MetavarShape raise {
  let parsed = parse_toplevel_shape(path, context, source)
  let collect_ctx : MetavarRewriteContext = {
    path,
    context,
    expr_metavars: [],
    identifier_metavars: [],
    constant_metavars: [],
    arg_metavars: [],
    pattern_metavars: [],
    collecting: true,
    bare_expression_metavars: [],
    bare_identifier_metavars: [],
    bare_pattern_metavars: [],
    resolved_metavars: {},
  }
  ignore(collect_ctx.rewrite_impl(parsed))
  let resolved_metavars = collect_ctx.resolve_metavar_kinds()
  let ctx : MetavarRewriteContext = {
    path,
    context,
    expr_metavars: [],
    identifier_metavars: [],
    constant_metavars: [],
    arg_metavars: [],
    pattern_metavars: [],
    collecting: false,
    bare_expression_metavars: [],
    bare_identifier_metavars: [],
    bare_pattern_metavars: [],
    resolved_metavars,
  }
  let ast = @untyped_ast.from_impl(ctx.rewrite_impl(parsed))
  let (
    cleaned_expr_metavars,
    cleaned_identifier_metavars,
    cleaned_constant_metavars,
    cleaned_arg_metavars,
    pattern_metavars,
  ) = cleanup_temporary_pattern_metavars(
    ctx.expr_metavars,
    ctx.identifier_metavars,
    ctx.constant_metavars,
    ctx.arg_metavars,
  )
  {
    ast,
    expr_metavars: cleaned_expr_metavars,
    identifier_metavars: cleaned_identifier_metavars,
    constant_metavars: cleaned_constant_metavars,
    arg_metavars: cleaned_arg_metavars,
    pattern_metavars,
  }
}

///|
fn parse_metavar(
  raw : String,
  path : String,
  context : String,
) -> MetavarSyntax? raise {
  if !raw.has_prefix("$") {
    return None
  }
  if !raw.has_prefix("$(") || !raw.has_suffix(")") {
    if raw.length() <= 1 {
      raise RuleLoadError::InvalidRule(
        path~,
        info="\{shape_context_name(context)} has invalid metavar \{raw}; use explicit typed syntax like $(value:exp)",
      )
    }
    return Some(Bare(raw[1:].to_owned()))
  }
  let end = raw.length() - 1
  for index in 2..<end {
    if raw[index] == ':' {
      return Some(
        Explicit(raw[index + 1:end].to_owned(), raw[2:index].to_owned()),
      )
    }
  }
  raise RuleLoadError::InvalidRule(
    path~,
    info="\{shape_context_name(context)} has invalid metavar payload \{raw}; use explicit typed syntax like $(value:exp)",
  )
}

///|
fn metavar_text(kind : String, name : String) -> String {
  "$(" + name + ":" + kind + ")"
}

///|
fn temporary_pattern_metavar_marker(name : String) -> String {
  metavar_text("pat", name)
}

///|
fn parse_temporary_pattern_metavar_marker(raw : String) -> String? {
  if raw.has_prefix("$(") && raw.has_suffix(":pat)") {
    Some(raw[2:raw.length() - ":pat)".length()].to_owned())
  } else {
    None
  }
}

///|
fn cleanup_temporary_pattern_metavars(
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
  constant_metavars : Array[String],
  arg_metavars : Array[String],
) -> (Array[String], Array[String], Array[String], Array[String], Array[String]) {
  let pattern_metavars : Array[String] = []
  let cleaned_identifier_metavars : Array[String] = []
  for name in identifier_metavars {
    if parse_temporary_pattern_metavar_marker(name) is Some(pattern_name) {
      if !array_contains(pattern_metavars, pattern_name) {
        pattern_metavars.push(pattern_name)
      }
    } else {
      cleaned_identifier_metavars.push(name)
    }
  }
  (
    filter_out_temporary_pattern_metavars(expr_metavars, pattern_metavars),
    cleaned_identifier_metavars,
    filter_out_temporary_pattern_metavars(constant_metavars, pattern_metavars),
    filter_out_temporary_pattern_metavars(arg_metavars, pattern_metavars),
    pattern_metavars,
  )
}

///|
fn filter_out_temporary_pattern_metavars(
  items : Array[String],
  pattern_metavars : Array[String],
) -> Array[String] {
  let result : Array[String] = []
  for item in items {
    if !array_contains(pattern_metavars, item) {
      result.push(item)
    }
  }
  result
}
