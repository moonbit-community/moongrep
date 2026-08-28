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
  context : PatternCompileContext,
) -> (@untyped_cst.CstNode, Array[ShapeMetavarOccurrence]) raise {
  let parsed = @untyped_cst.parse_expression(
    context.shape,
    name="rule shape",
    enable_metavar=true,
  )
  let root = parsed.root()
  let occurrences = collect_shape_metavars(context, root)
  if parsed.diagnostics_view() is [first, ..] {
    let message = first.msg.replace_all(old=" in .", new=".")
    raise context.invalid_pattern(
      "the pattern is not a valid MoonBit expression: \{message}",
    )
  }
  if @cst.first_recovery_node(root) is Some(_) {
    raise context.invalid_pattern(
      "the pattern is not a valid MoonBit expression: incomplete recovered CST node",
    )
  }
  (@cst.expression_root(root), occurrences)
}

///|
fn parse_toplevel_shape(
  context : PatternCompileContext,
) -> (@untyped_cst.CstNode, Array[ShapeMetavarOccurrence]) raise {
  let parsed = @untyped_cst.parse_structure(
    context.shape,
    name="rule shape",
    enable_metavar=true,
  )
  let root = parsed.root()
  let occurrences = collect_shape_metavars(context, root)
  if !parsed.diagnostics_view().is_empty() ||
    @cst.first_recovery_node(root) is Some(_) {
    raise context.invalid_pattern(
      "the pattern is not a valid MoonBit top-level item",
    )
  }
  match @cst.toplevel_nodes(root) {
    [item] => (item, occurrences)
    _ =>
      raise context.invalid_pattern(
        "the pattern must contain exactly one MoonBit top-level item",
      )
  }
}

///|
fn collect_shape_metavars(
  context : PatternCompileContext,
  root : @untyped_cst.CstNode,
) -> Array[ShapeMetavarOccurrence] raise {
  let lex_result = @lexer.tokens_from_string_with_utf16_location(
    context.shape,
    comment=true,
    name="rule shape",
    enable_metavar=true,
  )
  reject_shape_lex_errors(context, lex_result.errors)
  let occurrences : Array[ShapeMetavarOccurrence] = []
  collect_shape_metavar_tokens(context, lex_result.tokens, occurrences)
  collect_interpolation_metavars(context, root, occurrences)
  occurrences
}

///|
fn reject_shape_lex_errors(
  context : PatternCompileContext,
  errors : Array[(@basic.Position, @basic.Position, @lexer.LexicalError)],
) -> Unit raise {
  if errors.is_empty() {
    return
  }
  for error_entry in errors {
    match error_entry.2 {
      InvalidMetavarSyntax(raw) =>
        raise context.invalid_pattern(invalid_metavar_syntax_message(raw))
      _ => ()
    }
  }
  raise context.invalid_pattern("the pattern has lexical errors")
}

///|
fn collect_shape_metavar_tokens(
  context : PatternCompileContext,
  tokens : Array[(@tokens.Token, @basic.Position, @basic.Position)],
  occurrences : Array[ShapeMetavarOccurrence],
) -> Unit raise {
  for entry in tokens {
    let (token, start, end) = entry
    if metavar_token_payload(token) is Some(raw) {
      insert_shape_metavar_occurrence(occurrences, {
        raw,
        syntax: parse_shape_metavar_syntax(context, raw),
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
  context : PatternCompileContext,
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
    reject_shape_lex_errors(context, lex_result.errors)
    collect_shape_metavar_tokens(context, lex_result.tokens, occurrences)
  }
  for entry in node.children {
    collect_interpolation_metavars(context, entry.1, occurrences)
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
  context : PatternCompileContext,
  raw : String,
) -> ShapeMetavarSyntax raise {
  if raw == "$_" {
    return Ignore
  }
  if raw.has_prefix("$$$") {
    guard parse_ellipsis_syntax(context, raw) is Some(parsed) else {
      raise context.invalid_pattern(
        "the pattern contains invalid ellipsis metavar \{raw}",
      )
    }
    return Ellipsis(parsed.0, parsed.1)
  }
  guard parse_metavar(raw, context) is Some(syntax) else {
    raise context.invalid_pattern(invalid_metavar_syntax_message(raw))
  }
  match syntax {
    Explicit(kind, name) => Explicit(kind, name)
    Bare(name) => Bare(name)
  }
}

///|
fn invalid_metavar_syntax_message(raw : String) -> String {
  match legacy_metavar_replacement(raw) {
    Some((old, replacement)) =>
      "the pattern uses legacy metavar syntax \{old}; use \{replacement}"
    None =>
      "the pattern has invalid metavar syntax \{raw}; use explicit typed syntax like $(value:exp)"
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
