///|
pub fn dump_expr_json_repr(expr : String) -> Json raise {
  let (expr, reports) = @lexer.tokens_from_string(
      expr,
      comment=true,
      name="pattern",
    ).tokens
    |> @handrolled_parser.parse_expr
  if reports.is_empty() {
    expr.json_repr()
  } else {
    fail(reports.to_json().stringify(indent=2))
  }
}
