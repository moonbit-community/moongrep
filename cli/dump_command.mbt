///|
pub fn render_dump_command(
  command : (String, CliOptions?, String?),
) -> String raise {
  match command {
    ("dump-impl", None, Some(source)) => render_dump_impl_debug(source)
    ("dump-expr", None, Some(source)) => render_dump_expr_debug(source)
    _ => fail("invalid dump command")
  }
}

///|
fn render_dump_impl_debug(source : String) -> String raise {
  "\{Repr(@untyped_ast.from_impl(parse_dump_impl(source)))}"
}

///|
fn render_dump_expr_debug(source : String) -> String raise {
  "\{Repr(@untyped_ast.from_expr(parse_dump_expr(source)))}"
}

///|
fn parse_dump_impl(source : String) -> @syntax.Impl raise {
  let (impls, reports) = @parser.parse_string(source, name="dump --impl")
  if reports.length() != 0 {
    raise CliError::Usage(
      message="dump --impl parse failed: \{compact_reports(reports)}",
      exit_code=1,
    )
  }
  let nodes = impls.to_array()
  if nodes.length() != 1 {
    raise CliError::Usage(
      message="dump --impl expects exactly one top-level item",
      exit_code=1,
    )
  }
  nodes[0]
}

///|
fn parse_dump_expr(source : String) -> @syntax.Expr raise {
  let lex_result = @lexer.tokens_from_string(
    source,
    comment=true,
    name="dump --expr",
  )
  if lex_result.errors.length() != 0 {
    raise CliError::Usage(message="dump --expr has lexical errors", exit_code=1)
  }
  let (expr, reports) = @handrolled_parser.parse_expr(lex_result.tokens)
  if reports.length() != 0 {
    raise CliError::Usage(
      message="dump --expr parse failed: \{compact_reports(reports)}",
      exit_code=1,
    )
  }
  expr
}

///|
fn compact_reports(reports : Array[@basic.Report]) -> String {
  let messages : Array[String] = []
  for report in reports {
    messages.push(report.msg.replace_all(old="\n", new=" "))
  }
  messages.join(" ")
}
