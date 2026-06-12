///|
fn write_cli_output(output : String) -> Unit raise {
  @miniio.stdout.write_text(output)
  if !output.has_suffix("\n") {
    @miniio.stdout.write_text("\n")
  }
}

///|
fn main {
  try {
    let command = parse_cli_command(runtime_cli_args(@miniio.args_get()))
    match command {
      ("scan", Some(options), None) => {
        let result = collect_directory_hits(options)
        write_cli_output(render_directory_scan_result(result))
      }
      ("docs-list", None, None) | ("docs-show", None, Some(_)) =>
        write_cli_output(render_docs_command(command))
      _ => fail("invalid CLI command")
    }
  } catch {
    CliError::Usage(message~, exit_code~) => {
      println(message)
      @miniio.exit(exit_code)
    }
    err => {
      println("\{to_repr(err)}")
      @miniio.exit(1)
    }
  }
}
