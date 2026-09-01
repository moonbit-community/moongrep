///|
#cfg(target="wasm")
fn runtime_exit(code : Int) -> Unit = "wasi_snapshot_preview1" "proc_exit"

///|
#cfg(target="native")
extern "c" fn runtime_exit(code : Int) -> Unit = "exit"

///|
async fn write_raw_cli_stdout(output : String) -> Unit {
  if output != "" {
    if output.strip_suffix("\n") is Some(_) {
      @stdio.stdout.write(output)
    } else {
      @stdio.stdout.write(output + "\n")
    }
  }
}

///|
async fn write_raw_cli_stderr(output : String) -> Unit {
  if output != "" {
    if output.strip_suffix("\n") is Some(_) {
      @stdio.stderr.write(output)
    } else {
      @stdio.stderr.write(output + "\n")
    }
  }
}

///|
#warnings("-alert_internal")
fn cli_errno_reason(errno : Int) -> String {
  @os_error.errno_to_string(errno)
}

///|
async fn write_cli_stdout(output : String) -> Unit {
  write_raw_cli_stdout(output) catch {
    @os_error.OSError(errno, ..) =>
      raise @cli.CliError::output_error(
        "standard output",
        cli_errno_reason(errno),
      )
    err => raise err
  }
}

///|
async fn exit_with_cli_error(error : @cli.CliError) -> Unit {
  let exit_code = error.exit_code()
  write_raw_cli_stderr("\{error}") catch {
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
    Scan(options) => @cli.run_scan_command(options)
    Lint(options) => @cli.run_lint_command(options)
    DocsList | DocsShow(_) =>
      write_cli_stdout(@cli.render_docs_command(command))
    DumpImpl(..) | DumpExpr(..) =>
      write_cli_stdout(@cli.render_dump_command(command))
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
    err => exit_with_cli_error(@cli.CliError::internal("\{err}"))
  }
}
