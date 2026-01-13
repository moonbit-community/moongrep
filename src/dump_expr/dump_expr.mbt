///|
fn dump_expr_json_repr(expr : String) -> Json raise {
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

///|
fn main {
  let args = @sys.get_cli_args()
  let filename = match args {
    [_, filename] => filename
    _ => {
      println("invalid cli arguments: \{args}")
      println("usage: dump_expr <filename>")
      panic()
    }
  }
  let expr = @fs.read_file_to_string(filename) catch {
    err => {
      println("failed to read file \{filename}: \{err}")
      panic()
    }
  }
  let expr = dump_expr_json_repr(expr) catch {
    err => {
      println(err)
      panic()
    }
  }
  println(expr.stringify(indent=2))
}
