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
  start : Int
  end : Int
  uppercase_identifier : Bool
}

///|
fn parse_shape(
  path : String,
  context : String,
  source : String,
) -> (@untyped_cst.CstNode, Array[ShapeMetavarOccurrence]) raise {
  let parsed = @untyped_cst.parse_expression(
    source,
    name="rule shape",
    enable_metavar=true,
  )
  let root = parsed.root()
  let occurrences = collect_shape_metavars(path, context, source, root)
  if parsed.diagnostics_view() is [first, ..] {
    let message = first.msg.replace_all(old=" in .", new=".")
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{shape_context_name(context)} is not a valid MoonBit expression: \{message}",
    )
  }
  if @cst.first_recovery_node(root) is Some(_) {
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{shape_context_name(context)} is not a valid MoonBit expression: incomplete recovered CST node",
    )
  }
  (@cst.expression_root(root), occurrences)
}

///|
fn parse_toplevel_shape(
  path : String,
  context : String,
  source : String,
) -> (@untyped_cst.CstNode, Array[ShapeMetavarOccurrence]) raise {
  let parsed = @untyped_cst.parse_structure(
    source,
    name="rule shape",
    enable_metavar=true,
  )
  let root = parsed.root()
  let occurrences = collect_shape_metavars(path, context, source, root)
  if !parsed.diagnostics_view().is_empty() ||
    @cst.first_recovery_node(root) is Some(_) {
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{shape_context_name(context)} is not a valid MoonBit top-level item",
    )
  }
  match @cst.toplevel_nodes(root) {
    [item] => (item, occurrences)
    _ =>
      raise RuleLoadError::InvalidRule(
        path~,
        info="\{shape_context_name(context)} must contain exactly one MoonBit top-level item",
      )
  }
}

///|
fn collect_shape_metavars(
  path : String,
  context : String,
  source : String,
  root : @untyped_cst.CstNode,
) -> Array[ShapeMetavarOccurrence] raise {
  let lex_result = @lexer.tokens_from_string_with_utf16_location(
    source,
    comment=true,
    name="rule shape",
    enable_metavar=true,
  )
  reject_shape_lex_errors(path, context, lex_result.errors)
  let occurrences : Array[ShapeMetavarOccurrence] = []
  collect_shape_metavar_tokens(path, context, lex_result.tokens, occurrences)
  collect_interpolation_metavars(path, context, root, occurrences)
  occurrences
}

///|
fn reject_shape_lex_errors(
  path : String,
  context : String,
  errors : Array[(@basic.Position, @basic.Position, @lexer.LexicalError)],
) -> Unit raise {
  if errors.is_empty() {
    return
  }
  for error_entry in errors {
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

///|
fn collect_shape_metavar_tokens(
  path : String,
  context : String,
  tokens : Array[(@tokens.Token, @basic.Position, @basic.Position)],
  occurrences : Array[ShapeMetavarOccurrence],
) -> Unit raise {
  for entry in tokens {
    let (token, start, end) = entry
    if metavar_token_payload(token) is Some(raw) {
      insert_shape_metavar_occurrence(occurrences, {
        raw,
        syntax: parse_shape_metavar_syntax(path, context, raw),
        start: start.cnum,
        end: end.cnum,
        uppercase_identifier: metavar_name_starts_uppercase(raw),
      })
    }
  }
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
fn insert_shape_metavar_occurrence(
  occurrences : Array[ShapeMetavarOccurrence],
  occurrence : ShapeMetavarOccurrence,
) -> Unit {
  for index in 0..<occurrences.length() {
    if occurrence.start < occurrences[index].start {
      occurrences.insert(index, occurrence)
      return
    }
  }
  occurrences.push(occurrence)
}

///|
fn collect_interpolation_metavars(
  path : String,
  context : String,
  node : @untyped_cst.CstNode,
  occurrences : Array[ShapeMetavarOccurrence],
) -> Unit raise {
  if node.kind is @untyped_cst.InterpSegment_Source &&
    @cst.string_payload(node) is Some(interpolation_source) {
    let lex_result = @lexer.tokens_from_string_with_utf16_location(
      interpolation_source,
      start_pos=node.loc.start,
      is_interpolation=true,
      comment=true,
      name="rule interpolation shape",
      enable_metavar=true,
    )
    reject_shape_lex_errors(path, context, lex_result.errors)
    collect_shape_metavar_tokens(path, context, lex_result.tokens, occurrences)
  }
  for entry in node.children {
    collect_interpolation_metavars(path, context, entry.1, occurrences)
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
