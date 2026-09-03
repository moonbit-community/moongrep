///|
pub fn render_dump_command(command : CliCommand) -> String raise {
  match command {
    DumpImpl(source~, exit_code~, output_json~) =>
      render_dump_impl_debug(source, exit_code, output_json)
    DumpExpr(source~, exit_code~, output_json~) =>
      render_dump_expr_debug(source, exit_code, output_json)
    _ => raise new_internal_error("invalid dump command")
  }
}

///|
fn render_dump_impl_debug(
  source : String,
  exit_code : Bool,
  output_json : Bool,
) -> String raise {
  let node = parse_dump_impl(source)
  render_dump_node(node, "impl", exit_code, output_json)
}

///|
fn render_dump_expr_debug(
  source : String,
  exit_code : Bool,
  output_json : Bool,
) -> String raise {
  let node = parse_dump_expr(source)
  render_dump_node(node, "expr", exit_code, output_json)
}

///|
fn render_dump_node(
  node : @untyped_cst.CstNode,
  kind : String,
  exit_code : Bool,
  output_json : Bool,
) -> String {
  if exit_code {
    ""
  } else {
    let content = "\{Repr(node)}"
    if output_json {
      render_dump_json(kind, content)
    } else {
      content
    }
  }
}

///|
fn parse_dump_impl(source : String) -> @untyped_cst.CstNode raise {
  let parsed = @untyped_cst.parse_structure(
    source,
    name="dump --impl",
    enable_metavar=true,
  )
  let reports = parsed.diagnostics_view().to_owned()
  if !reports.is_empty() {
    raise new_dump_input_error("dump --impl", compact_reports(reports))
  }
  if @cst.first_recovery_node(parsed.root()) is Some(_) {
    raise new_dump_input_error("dump --impl", "incomplete recovered CST node")
  }
  let nodes = @cst.toplevel_nodes(parsed.root())
  if nodes.length() != 1 {
    raise new_dump_input_error(
      "dump --impl", "expected exactly one top-level item",
    )
  }
  nodes[0]
}

///|
fn parse_dump_expr(source : String) -> @untyped_cst.CstNode raise {
  let parsed = @untyped_cst.parse_expression(
    source,
    name="dump --expr",
    enable_metavar=true,
  )
  let reports = parsed.diagnostics_view().to_owned()
  if !reports.is_empty() {
    raise new_dump_input_error("dump --expr", compact_reports(reports))
  }
  if @cst.first_recovery_node(parsed.root()) is Some(_) {
    raise new_dump_input_error("dump --expr", "incomplete recovered CST node")
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
