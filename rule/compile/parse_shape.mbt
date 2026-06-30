///|
fn parse_shape(
  path : String,
  context : String,
  source : String,
) -> @syntax.Expr raise {
  let lex_result = @lexer.tokens_from_string(
    source,
    comment=true,
    name="rule shape",
    enable_metavar=true,
  )
  if lex_result.errors.length() != 0 {
    for error_entry in lex_result.errors {
      match error_entry {
        (_, _, @lexer.LexicalError::InvalidMetavarSyntax(raw)) =>
          raise RuleLoadError::InvalidRule(
            path~,
            info=invalid_metavar_syntax_message(context, raw),
          )
        _ => ()
      }
    }
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{shape_context_name(context)} has lexical errors",
    )
  }
  let (expr, reports) = @handrolled_parser.parse_expr(lex_result.tokens)
  if reports.length() != 0 {
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{shape_context_name(context)} is not a valid MoonBit expression",
    )
  }
  expr
}

///|
fn shape_context_name(context : String) -> String {
  if context == "inside-expr" {
    context
  } else {
    "\{context}.shape"
  }
}

///|
fn invalid_metavar_syntax_message(context : String, raw : String) -> String {
  match legacy_metavar_replacement(raw) {
    Some((old, replacement)) =>
      "\{shape_context_name(context)} uses legacy inline metavar syntax \{old}; use \{replacement}"
    None =>
      "\{shape_context_name(context)} has invalid metavar syntax \{raw}; use explicit typed syntax like $(value:exp)"
  }
}

///|
fn legacy_metavar_replacement(raw : String) -> (String, String)? {
  let (prefix, start) = if raw.has_prefix(".$") {
    (".", 2)
  } else if raw.has_prefix("$") {
    ("", 1)
  } else {
    return None
  }
  let has_post_label = raw.has_suffix("~")
  let end = if has_post_label { raw.length() - 1 } else { raw.length() }
  if end <= start {
    return None
  }
  for index in start..<end {
    if raw[index] == ':' {
      let kind = raw[start:index]
      let name = raw[index + 1:end]
      if kind.length() == 0 || name.length() == 0 {
        return None
      }
      let kind_text = kind.to_owned()
      let name_text = name.to_owned()
      let suffix = if has_post_label { "~" } else { "" }
      return Some((raw, "\{prefix}$(\{name_text}:\{kind_text})\{suffix}"))
    }
  }
  None
}
