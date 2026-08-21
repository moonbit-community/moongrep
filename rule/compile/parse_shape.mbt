///|
priv enum ShapeMetavarSyntax {
  Explicit(String, String)
  Bare(String)
  Ellipsis(String, @matching.EllipsisMetavarKind?)
  Ignore
}

///|
priv struct ShapeMetavarOccurrence {
  raw : String
  syntax : ShapeMetavarSyntax
  marker : String
  start : Int
  uppercase_identifier : Bool
}

///|
priv struct PreparedShape {
  source : String
  occurrences : Array[ShapeMetavarOccurrence]
}

///|
fn parse_shape(
  path : String,
  context : String,
  source : String,
) -> (@untyped_cst.CstNode, Array[ShapeMetavarOccurrence]) raise {
  let prepared = prepare_shape(path, context, source)
  let parsed = @untyped_cst.parse_expression(prepared.source, name="rule shape")
  if parsed.diagnostics_view() is [first, ..] {
    let message = restore_metavars_in_diagnostic(
      first.msg.replace_all(old=" in .", new="."),
      prepared.occurrences,
    )
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{shape_context_name(context)} is not a valid MoonBit expression: \{message}",
    )
  }
  if @cst.first_recovery_node(parsed.root()) is Some(_) {
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{shape_context_name(context)} is not a valid MoonBit expression: incomplete recovered CST node",
    )
  }
  (@cst.expression_root(parsed.root()), prepared.occurrences)
}

///|
fn parse_toplevel_shape(
  path : String,
  context : String,
  source : String,
) -> (@untyped_cst.CstNode, Array[ShapeMetavarOccurrence]) raise {
  let prepared = prepare_shape(path, context, source)
  let parsed = @untyped_cst.parse_structure(prepared.source, name="rule shape")
  if !parsed.diagnostics_view().is_empty() ||
    @cst.first_recovery_node(parsed.root()) is Some(_) {
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{shape_context_name(context)} is not a valid MoonBit top-level item",
    )
  }
  match @cst.toplevel_nodes(parsed.root()) {
    [item] => (item, prepared.occurrences)
    _ =>
      raise RuleLoadError::InvalidRule(
        path~,
        info="\{shape_context_name(context)} must contain exactly one MoonBit top-level item",
      )
  }
}

///|
fn prepare_shape(
  path : String,
  context : String,
  source : String,
) -> PreparedShape raise {
  let lex_result = @lexer.tokens_from_string_with_utf16_location(
    source,
    comment=true,
    name="rule shape",
    enable_metavar=true,
  )
  if lex_result.errors.length() != 0 {
    for error_entry in lex_result.errors {
      match error_entry.2 {
        InvalidMetavarSyntax(raw) =>
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
  let replacements : Array[
    (@basic.Position, @basic.Position, String, ShapeMetavarSyntax, String),
  ] = []
  for entry in lex_result.tokens {
    let (token, start, end) = entry
    if metavar_token_payload(token) is Some(raw) {
      let syntax = parse_shape_metavar_syntax(path, context, raw)
      let marker = shape_metavar_marker(syntax, raw, token)
      let replacement = match token {
        @tokens.POST_LABEL(_) => marker + "~"
        @tokens.POST_LABEL_TRANSPARENT(_) => marker + "~~"
        _ => marker
      }
      replacements.push((start, end, raw, syntax, replacement))
    }
  }
  let output = StringBuilder::new()
  let occurrences : Array[ShapeMetavarOccurrence] = []
  let mut source_offset = 0
  let mut output_offset = 0
  for replacement in replacements {
    let start = replacement.0.cnum
    let end = replacement.1.cnum
    if start > source_offset {
      let unchanged = source[source_offset:start]
      output.write_string(unchanged.to_owned())
      output_offset += unchanged.length()
    }
    let new_start = output_offset
    output.write_string(replacement.4)
    output_offset += replacement.4.length()
    occurrences.push({
      raw: replacement.2,
      syntax: replacement.3,
      marker: shape_marker_without_label_suffix(replacement.4),
      start: new_start,
      uppercase_identifier: metavar_name_starts_uppercase(replacement.2),
    })
    source_offset = end
  }
  if source_offset < source.length() {
    output.write_string(source[source_offset:].to_owned())
  }
  { source: output.to_string(), occurrences }
}

///|
fn metavar_name_starts_uppercase(raw : String) -> Bool {
  let offset = if raw.has_prefix("$(") { 2 } else { 1 }
  if offset >= raw.length() {
    false
  } else {
    raw[offset] >= 'A' && raw[offset] <= 'Z'
  }
}

///|
fn restore_metavars_in_diagnostic(
  message : String,
  occurrences : Array[ShapeMetavarOccurrence],
) -> String {
  let mut result = message
  for occurrence in occurrences {
    result = result.replace_all(old=occurrence.marker, new=occurrence.raw)
  }
  result
}

///|
fn shape_marker_without_label_suffix(marker : String) -> String {
  if marker.has_suffix("~~") {
    marker[:marker.length() - 2].to_owned()
  } else if marker.has_suffix("~") {
    marker[:marker.length() - 1].to_owned()
  } else {
    marker
  }
}

///|
fn metavar_token_payload(token : @tokens.Token) -> String? {
  match token {
    @tokens.LIDENT(raw)
    | @tokens.UIDENT(raw)
    | @tokens.DOT_LIDENT(raw)
    | @tokens.DOT_UIDENT(raw)
    | @tokens.POST_LABEL(raw)
    | @tokens.POST_LABEL_TRANSPARENT(raw) =>
      if raw.has_prefix("$") {
        Some(raw)
      } else {
        None
      }
    _ => None
  }
}

///|
fn parse_shape_metavar_syntax(
  path : String,
  context : String,
  raw : String,
) -> ShapeMetavarSyntax raise {
  if raw == "$_" {
    return Ignore
  }
  if raw.has_prefix("$$$") {
    guard parse_ellipsis_syntax(path, context, raw) is Some(parsed) else {
      raise RuleLoadError::InvalidRule(
        path~,
        info="\{shape_context_name(context)} contains invalid ellipsis metavar \{raw}",
      )
    }
    return Ellipsis(parsed.0, parsed.1)
  }
  guard parse_metavar(raw, path, context) is Some(syntax) else {
    raise RuleLoadError::InvalidRule(
      path~,
      info=invalid_metavar_syntax_message(context, raw),
    )
  }
  match syntax {
    Explicit(kind, name) => Explicit(kind, name)
    Bare(name) => Bare(name)
  }
}

///|
fn shape_metavar_marker(
  syntax : ShapeMetavarSyntax,
  raw : String,
  _token : @tokens.Token,
) -> String {
  match syntax {
    Ignore => "__moongrep_ignore"
    Bare(name) =>
      if metavar_name_starts_uppercase(raw) {
        "MoongrepBare_\{name}"
      } else {
        "__moongrep_bare_\{name}"
      }
    Explicit("pat", name) => "__moongrep_pat_\{name}"
    Explicit("exp", name) => "__moongrep_exp_\{name}"
    Explicit("const", name) => "__moongrep_const_\{name}"
    Explicit("arg", name) => "__moongrep_arg_\{name}"
    Explicit("type", name) => "MoongrepType_\{name}"
    Explicit("id", name) =>
      if metavar_name_starts_uppercase(raw) {
        "MoongrepId_\{name}"
      } else {
        "__moongrep_id_\{name}"
      }
    Explicit(_, name) => "__moongrep_id_\{name}"
    Ellipsis(name, Some(TypeItem)) => "MoongrepEllipsis_type_\{name}"
    Ellipsis(name, kind) =>
      "__moongrep_ellipsis_\{ellipsis_marker_kind(kind)}_\{name}"
  }
}

///|
fn ellipsis_marker_kind(kind : @matching.EllipsisMetavarKind?) -> String {
  match kind {
    None | Some(AnyItem) => "any"
    Some(ExpItem) => "exp"
    Some(IdItem) => "id"
    Some(ConstItem) => "const"
    Some(ArgItem) => "arg"
    Some(PatItem) => "pat"
    Some(TypeItem) => "type"
  }
}

///|
fn shape_context_name(context : String) -> String {
  if context == "inside-expr" || context == "inside-toplevel" {
    context
  } else {
    "\{context}.shape"
  }
}

///|
fn invalid_metavar_syntax_message(context : String, raw : String) -> String {
  match legacy_metavar_replacement(raw) {
    Some((old, replacement)) =>
      "\{shape_context_name(context)} uses legacy metavar syntax \{old}; use \{replacement}"
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
      let suffix = if has_post_label { "~" } else { "" }
      return Some(
        (raw, "\{prefix}$(\{name.to_owned()}:\{kind.to_owned()})\{suffix}"),
      )
    }
  }
  None
}
