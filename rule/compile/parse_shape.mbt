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
        (_, _, InvalidMetavarSyntax(raw)) =>
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
    let message = reports[0].msg.replace_all(old=" in .", new=".")
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{shape_context_name(context)} is not a valid MoonBit expression: \{message}",
    )
  }
  expr
}

///|
fn parse_toplevel_shape(
  path : String,
  context : String,
  source : String,
) -> @syntax.Impl raise {
  let lex_result = @lexer.tokens_from_string(
    source,
    comment=true,
    name="rule shape",
    enable_metavar=true,
  )
  if lex_result.errors.length() != 0 {
    for error_entry in lex_result.errors {
      match error_entry {
        (_, _, InvalidMetavarSyntax(raw)) =>
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
  let (impls, reports) = @handrolled_parser.parse(lex_result.tokens)
  if reports.length() != 0 {
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{shape_context_name(context)} is not a valid MoonBit top-level item",
    )
  }
  if impls.length() != 1 {
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{shape_context_name(context)} must contain exactly one MoonBit top-level item",
    )
  }
  let items = impls.to_array()
  attach_toplevel_shape_docstring(lex_result.docstrings, items[0])
  items[0]
}

///|
fn attach_toplevel_shape_docstring(
  docstrings : Array[@list.List[(@basic.Location, @tokens.Comment)]],
  item : @syntax.Impl,
) -> Unit {
  let item_loc = item.loc()
  let mut selected : @list.List[(@basic.Location, @tokens.Comment)]? = None
  // Lexer docstring groups are stored in reverse source order. Iterating from
  // the end toward the beginning leaves the nearest group before this single
  // top-level shape selected.
  let mut index = docstrings.length()
  while index > 0 {
    index -= 1
    let comments = docstrings[index]
    if comments.head() is Some((loc, _)) &&
      loc.start.lnum <= item_loc.start.lnum {
      selected = Some(comments)
    }
  }
  let doc = if selected is Some(comments) {
    shape_docstring_from_comments(comments)
  } else {
    @syntax.DocString::empty()
  }
  match item {
    TopFuncDef(fun_decl~, ..) => fun_decl.doc = doc
    TopLetDef(..) as let_def => let_def.doc = doc
    TopImpl(..) as impl_def => impl_def.doc = doc
    TopImplRelation(..) as relation => relation.doc = doc
    TopTest(..) as test_def => test_def.doc = doc
    TopTrait(trait_decl) => trait_decl.doc = doc
    TopTypeDef(type_decl) => type_decl.doc = doc
    TopUsing(..) as using_def => using_def.doc = doc
    TopView(..) as view_def => view_def.doc = doc
    TopExpr(..) => ()
  }
}

///|
fn shape_docstring_from_comments(
  comments : @list.List[(@basic.Location, @tokens.Comment)],
) -> @syntax.DocString {
  let first_loc = comments.head().unwrap().0
  let last_loc = comments.last().unwrap().0
  {
    content: comments.map(fn(entry) {
      let content = entry.1.content
      match content {
        [.. "///|", .. remain] =>
          if remain.is_blank() {
            ""
          } else {
            remain.to_owned()
          }
        [.. "///", .. remain] => remain.to_owned()
        _ => ""
      }
    }),
    loc: { start: first_loc.start, end: last_loc.end },
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
      let kind_text = kind.to_owned()
      let name_text = name.to_owned()
      let suffix = if has_post_label { "~" } else { "" }
      return Some((raw, "\{prefix}$(\{name_text}:\{kind_text})\{suffix}"))
    }
  }
  None
}
