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
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{context}.shape has lexical errors",
    )
  }
  let (expr, reports) = @handrolled_parser.parse_expr(lex_result.tokens)
  if reports.length() != 0 {
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{context}.shape is not a valid MoonBit expression",
    )
  }
  expr
}
