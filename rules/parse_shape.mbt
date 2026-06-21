///|
fn parse_shape(
  path : String,
  context : String,
  source : String,
) -> @syntax.Expr raise {
  let tokens = @lexer.tokens_from_string(
      source,
      comment=true,
      metavar_syntax=true,
      name="rule shape",
    ).tokens
  let (expr, reports) = @handrolled_parser.parse_pattern_expr(tokens)
  if reports.length() != 0 {
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{context}.shape is not a valid MoonBit expression",
    )
  }
  expr
}
