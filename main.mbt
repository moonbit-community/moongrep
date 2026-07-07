///|
fn write_cli_output(output : String) -> Unit {
  match output.strip_suffix("\n") {
    Some(trimmed) => println(trimmed.to_owned())
    None => println(output)
  }
}

///|
async fn main {
  try {
    let command = parse_cli_command(
      runtime_cli_args(@env.args()),
      env=@env.get_env_vars(),
    )
    match command {
      ("scan", Some(options), None) => {
        let result = collect_directory_hits(options)
        write_cli_output(
          render_directory_scan_result(result, no_color=options.no_color),
        )
      }
      ("docs-list", None, None) | ("docs-show", None, Some(_)) =>
        write_cli_output(render_docs_command(command))
      ("dump-impl", None, Some(_)) | ("dump-expr", None, Some(_)) =>
        write_cli_output(render_dump_command(command))
      _ => fail("invalid CLI command")
    }
  } catch {
    CliError::Usage(message~, ..) as err => {
      write_cli_output(message)
      raise err
    }
    err => raise err
  }
}
