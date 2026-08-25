///|
#cfg(target="wasm")
fn runtime_exit(code : Int) -> Unit = "wasi_snapshot_preview1" "proc_exit"

///|
#cfg(target="native")
extern "c" fn runtime_exit(code : Int) -> Unit = "exit"

///|
async fn write_raw_cli_output(output : String) -> Unit {
  if output != "" {
    if output.strip_suffix("\n") is Some(_) {
      @stdio.stdout.write(output)
    } else {
      @stdio.stdout.write(output + "\n")
    }
  }
}

///|
async fn write_cli_output(output : String) -> Unit {
  write_raw_cli_output(output) catch {
    @os_error.OSError(_) as err => raise @cli.CliError::Output(message="\{err}")
    err => raise err
  }
}

///|
async fn exit_with_cli_error(error : @cli.CliError) -> Unit {
  let exit_code = error.exit_code()
  write_raw_cli_output("\{error}") catch {
    @os_error.OSError(_) => runtime_exit(7)
    err => raise err
  }
  runtime_exit(exit_code)
}

///|
async fn run_cli() -> Unit {
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
    _ => raise @cli.CliError::Internal(message="invalid CLI command")
  }
}

///|
async fn main {
  run_cli() catch {
    @cli.CliError::Internal(..) as err => exit_with_cli_error(err)
    @cli.CliError::Usage(..) as err => exit_with_cli_error(err)
    @cli.CliError::DumpInput(..) as err => exit_with_cli_error(err)
    @cli.CliError::RuleSource(..) as err => exit_with_cli_error(err)
    @cli.CliError::RuleContent(..) as err => exit_with_cli_error(err)
    @cli.CliError::ScanInput(..) as err => exit_with_cli_error(err)
    @cli.CliError::Output(..) as err => exit_with_cli_error(err)
    err => exit_with_cli_error(@cli.CliError::Internal(message="\{err}"))
  }
}
