///|
pub fn render_dump_command(
  command : (String, CliOptions?, String?),
) -> String raise {
  match command {
    ("dump-impl", None, Some(source)) => render_dump_impl_debug(source)
    ("dump-expr", None, Some(source)) => render_dump_expr_debug(source)
    _ => raise CliError::Internal(message="invalid dump command")
  }
}

///|
fn render_dump_impl_debug(source : String) -> String raise {
  "\{Repr(parse_dump_impl(source))}"
}

///|
fn render_dump_expr_debug(source : String) -> String raise {
  "\{Repr(parse_dump_expr(source))}"
}

///|
fn parse_dump_impl(source : String) -> @untyped_cst.CstNode raise {
  let parsed = @untyped_cst.parse_structure(source, name="dump --impl")
  let reports = parsed.diagnostics_view().to_owned()
  if !reports.is_empty() {
    raise CliError::DumpInput(
      message="dump --impl parse failed: \{compact_reports(reports)}",
    )
  }
  if @cst.first_recovery_node(parsed.root()) is Some(_) {
    raise CliError::DumpInput(
      message="dump --impl parse failed: incomplete recovered CST node",
    )
  }
  let nodes = @cst.toplevel_nodes(parsed.root())
  if nodes.length() != 1 {
    raise CliError::DumpInput(
      message="dump --impl expects exactly one top-level item",
    )
  }
  nodes[0]
}

///|
fn parse_dump_expr(source : String) -> @untyped_cst.CstNode raise {
  let parsed = @untyped_cst.parse_expression(source, name="dump --expr")
  let reports = parsed.diagnostics_view().to_owned()
  if !reports.is_empty() {
    raise CliError::DumpInput(
      message="dump --expr parse failed: \{compact_reports(reports)}",
    )
  }
  if @cst.first_recovery_node(parsed.root()) is Some(_) {
    raise CliError::DumpInput(
      message="dump --expr parse failed: incomplete recovered CST node",
    )
  }
  @cst.expression_root(parsed.root())
}

///|
fn compact_reports(reports : Array[@basic.Report]) -> String {
  let messages : Array[String] = []
  for report in reports {
    messages.push(report.msg.replace_all(old="\n", new=" "))
  }
  messages.join(" ")
}
