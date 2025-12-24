///|
test "build infix expr pattern" {
  let pattern = "1 + 3 * ___"
  let tokens = @lexer.tokens_from_string(pattern, comment=true).tokens
  let (pattern, _) = @handrolled_parser.parse_expr(tokens)
  current_convert_mode.val = Pattern
  @json.inspect(LabelledTree::from_expr(pattern), content=[
    "Expr::Infix",
    [
      "Constant::Int(1)",
      "Op(+)",
      ["Expr::Infix", ["Constant::Int(3)", "Op(*)", "$_"]],
    ],
  ])
}
