///|
priv struct ScanOutputState {
  mut hit_count : Int
}

///|
/// Scans source files and writes results as they are found.
///
/// Match records are written to standard output. Verbose traversal messages
/// and scan warnings are written to standard error.
pub async fn run_scan_command(options : CliOptions) -> Unit {
  run_scan_mode_command_with_writers(
    Scan,
    options,
    write_scan_stdout,
    write_scan_stderr,
  )
}

///|
/// Lints source files with builtin rules and writes results as they are found.
///
/// Match records are written to standard output. Verbose traversal messages
/// and scan warnings are written to standard error.
pub async fn run_lint_command(options : CliOptions) -> Unit {
  run_scan_mode_command_with_writers(
    Lint,
    options,
    write_scan_stdout,
    write_scan_stderr,
  )
}

///|
async fn write_scan_stdout(output : String) -> Unit {
  @stdio.stdout.write(output)
}

///|
async fn write_scan_stderr(output : String) -> Unit {
  @stdio.stderr.write(output)
}

///|
async fn invoke_scan_writer(
  writer : async (String) -> Unit,
  output : String,
) -> Unit {
  writer(output) catch {
    CliError::Output(..) as err => raise err
    err => raise CliError::Output(message="\{err}")
  }
}

///|
async fn run_scan_mode_command_with_writers(
  mode : ScanMode,
  options : CliOptions,
  stdout_writer : async (String) -> Unit,
  stderr_writer : async (String) -> Unit,
) -> Unit {
  let state : ScanOutputState = { hit_count: 0, }
  scan_events(mode, options, event => {
    write_stream_scan_event(event, options, state, stdout_writer, stderr_writer)
  })
  if state.hit_count == 0 && !options.output_json {
    invoke_scan_writer(stdout_writer, "no match hits\n")
  }
}

///|
async fn write_stream_scan_event(
  event : ScanEvent,
  options : CliOptions,
  state : ScanOutputState,
  stdout_writer : async (String) -> Unit,
  stderr_writer : async (String) -> Unit,
) -> Unit {
  match event {
    Trace(message) => invoke_scan_writer(stderr_writer, message + "\n")
    Warning(warning) =>
      invoke_scan_writer(stderr_writer, render_scan_warning(warning) + "\n")
    Hit(hit) => {
      let rendered = if options.output_json {
        render_scan_hit_json(hit)
      } else {
        render_scan_hit(hit, no_color=options.no_color)
      }
      let separator = if !options.output_json && state.hit_count > 0 {
        "\n"
      } else {
        ""
      }
      invoke_scan_writer(stdout_writer, separator + rendered + "\n")
      state.hit_count += 1
    }
  }
}
