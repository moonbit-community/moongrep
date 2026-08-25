///|
#cfg(target="wasm")
fn runtime_exit(code : Int) -> Unit = "wasi_snapshot_preview1" "proc_exit"

///|
#cfg(target="native")
extern "c" fn runtime_exit(code : Int) -> Unit = "exit"

///|
async fn write_cli_output(output : String) -> Unit {
  if output != "" {
    if output.strip_suffix("\n") is Some(_) {
      @stdio.stdout.write(output)
    } else {
      @stdio.stdout.write(output + "\n")
    }
  }
}

///|
async fn main {
  try {
    let command = @cli.parse_cli_command(
      @cli.runtime_cli_args(@env.args()),
      env=@env.get_env_vars(),
    )
    match command {
      ("scan", Some(options), None) => @cli.run_scan_command(options)
      ("lint", Some(options), None) => @cli.run_lint_command(options)
      ("docs-list", None, None) | ("docs-show", None, Some(_)) =>
        write_cli_output(@cli.render_docs_command(command))
      ("dump-impl", None, Some(_)) | ("dump-expr", None, Some(_)) =>
        write_cli_output(@cli.render_dump_command(command))
      _ => fail("invalid CLI command")
    }
  } catch {
    @cli.CliError::Usage(message~, exit_code~) => {
      write_cli_output(message)
      runtime_exit(exit_code)
    }
    err => raise err
  }
}
