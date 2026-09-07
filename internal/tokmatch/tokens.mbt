///|
// The lexer's ordinary token JSON preserves kind and literal representation.
// Interpolations and attributes need recursive normalization instead.
priv enum TokKey {
  Plain(Json)
  Interpolation(@tokens.TokenKind, ReadOnlyArray[TokInterp])
  Attribute(String, String?, ReadOnlyArray[TokKey])
} derive(Eq)

///|
priv enum TokInterp {
  Literal(String)
  Expression(ReadOnlyArray[TokKey])
} derive(Eq)

///|
priv struct TokToken {
  key : TokKey
  loc : @basic.Location
}

///|
/// A lexical failure in a source block, including nested token contents.
pub(all) suberror LexError {
  LexError(String)
}

///|
fn lex_tokscan_tokens(
  source : StringView,
  name? : String = "",
  pattern? : Bool = false,
  is_interpolation? : Bool = false,
) -> Array[TokToken] raise LexError {
  let lexed = @lexer.tokens_from_string(
    source,
    name~,
    comment=false,
    enable_metavar=false,
    is_interpolation~,
  )
  if lexed.errors is [(start, _, error), ..] {
    raise LexError("line \{start.lnum}, column \{start.column()}: \{error}")
  }
  let mut last = lexed.tokens.length() - 1
  while last >= 0 {
    match lexed.tokens[last].0 {
      COMMENT(_) | NEWLINE | EOF => last -= 1
      _ => break
    }
  }
  let normalized : Array[TokToken] = []
  for index, triple in lexed.tokens {
    let (token, start, end) = triple
    match token {
      COMMENT(_) | NEWLINE | EOF => continue
      SEMI(false) if pattern && index == last => continue
      _ => ()
    }
    // These three lexer spans start after the dot. DOT_LPAREN already
    // includes it. Positions from tokens_from_string count Unicode characters.
    let start = match token {
      DOT_LIDENT(_) | DOT_UIDENT(_) | DOT_INT(_) =>
        { ..start, cnum: start.cnum - 1, }
      _ => start
    }
    normalized.push({
      key: normalize_tokscan_token(token),
      loc: { start, end, },
    })
  }
  normalized
}

///|
fn normalize_tokscan_token(token : @tokens.Token) -> TokKey raise LexError {
  match token {
    SEMI(_) => Plain(@tokens.Token::SEMI(false).to_json())
    INTERP(parts)
    | BYTES_INTERP(parts)
    | MULTILINE_INTERP(parts)
    | REGEX_INTERP(parts) => {
      let normalized = ReadOnlyArray::makei(parts.length(), index => {
        match parts[index] {
          InterpLit(repr~, ..) => Literal(repr)
          InterpSource(expr) => {
            let tokens = lex_tokscan_tokens(expr.source, is_interpolation=true) catch {
              LexError(reason) => raise LexError("interpolation: \{reason}")
            }
            Expression(
              ReadOnlyArray::makei(tokens.length(), i => tokens[i].key),
            )
          }
        }
      })
      Interpolation(token.kind(), normalized)
    }
    ATTRIBUTE((name, dot_name, payload)) => {
      let tokens = lex_tokscan_tokens(payload) catch {
        LexError(reason) => raise LexError("attribute #\{name}: \{reason}")
      }
      Attribute(
        name,
        dot_name,
        ReadOnlyArray::makei(tokens.length(), i => tokens[i].key),
      )
    }
    _ => Plain(token.to_json())
  }
}
