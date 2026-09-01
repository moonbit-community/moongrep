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
async fn exit_with_cli_error(error : @cli.CliError, output_json : Bool) -> Unit {
  let exit_code = error.exit_code()
  let rendered = if output_json { error.render_json() } else { "\{error}" }
  write_raw_cli_stderr(rendered) catch {
    @os_error.OSError(_) => runtime_exit(7)
    err => raise err
  }
  runtime_exit(exit_code)
}

///|
async fn run_cli(argv : Array[String]) -> Unit {
  let command = @cli.parse_cli_command(argv, env=@env.get_env_vars())
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
  let argv = @cli.runtime_cli_args(@env.args())
  let output_json = @cli.output_json_requested(argv)
  run_cli(argv) catch {
    @cli.CliError::Internal(..) as err => exit_with_cli_error(err, output_json)
    @cli.CliError::Usage(..) as err => exit_with_cli_error(err, output_json)
    @cli.CliError::DumpInput(..) as err => exit_with_cli_error(err, output_json)
    @cli.CliError::RuleSource(..) as err =>
      exit_with_cli_error(err, output_json)
    @cli.CliError::RuleContent(..) as err =>
      exit_with_cli_error(err, output_json)
    @cli.CliError::ScanInput(..) as err => exit_with_cli_error(err, output_json)
    @cli.CliError::Output(..) as err => exit_with_cli_error(err, output_json)
    err => exit_with_cli_error(@cli.CliError::internal("\{err}"), output_json)
  }
}
