///|
priv struct InlineMetavarShape {
  ast : @syntax.Expr
  expr_metavars : Array[String]
  identifier_metavars : Array[String]
  constant_metavars : Array[String]
  pattern_metavars : Array[String]
}

///|
fn compile_inline_metavar_shape(
  path : String,
  context : String,
  source : String,
) -> InlineMetavarShape raise {
  let ctx : InlineMetavarRewriteContext = {
    path,
    context,
    expr_metavars: [],
    identifier_metavars: [],
    constant_metavars: [],
  }
  let ast = ctx.rewrite_expr(parse_shape(path, context, source))
  let (
    cleaned_expr_metavars,
    cleaned_identifier_metavars,
    cleaned_constant_metavars,
    pattern_metavars,
  ) = cleanup_temporary_pattern_metavars(
    ctx.expr_metavars,
    ctx.identifier_metavars,
    ctx.constant_metavars,
  )
  {
    ast,
    expr_metavars: cleaned_expr_metavars,
    identifier_metavars: cleaned_identifier_metavars,
    constant_metavars: cleaned_constant_metavars,
    pattern_metavars,
  }
}

///|
fn parse_inline_metavar(
  raw : String,
  path : String,
  context : String,
) -> (String, String)? raise {
  if !raw.has_prefix("$") {
    return None
  }
  if !raw.has_prefix("$(") || !raw.has_suffix(")") {
    let name = if raw.length() > 1 { raw[1:].to_owned() } else { "value" }
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{shape_context_name(context)} uses untyped inline metavar \{raw}; use explicit typed syntax like $(\{name}:exp)",
    )
  }
  let end = raw.length() - 1
  for index in 2..<end {
    if raw[index] == ':' {
      return Some((raw[index + 1:end].to_owned(), raw[2:index].to_owned()))
    }
  }
  raise RuleLoadError::InvalidRule(
    path~,
    info="\{shape_context_name(context)} has invalid inline metavar payload \{raw}; use explicit typed syntax like $(value:exp)",
  )
}

///|
fn inline_metavar_text(kind : String, name : String) -> String {
  "$(" + name + ":" + kind + ")"
}

///|
fn temporary_pattern_metavar_marker(name : String) -> String {
  inline_metavar_text("pat", name)
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
) -> (Array[String], Array[String], Array[String], Array[String]) {
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
