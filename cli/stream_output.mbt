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
  run_scan_command_with_writers(options, write_scan_stdout, write_scan_stderr)
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
async fn run_scan_command_with_writers(
  options : CliOptions,
  stdout_writer : async (String) -> Unit,
  stderr_writer : async (String) -> Unit,
) -> Unit {
  let state : ScanOutputState = { hit_count: 0 }
  scan_events(options, event => {
    write_stream_scan_event(event, options, state, stdout_writer, stderr_writer)
  })
  if state.hit_count == 0 && !options.output_json {
    stdout_writer("no match hits\n")
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
    Trace(message) => stderr_writer(message + "\n")
    Warning(warning) => stderr_writer(render_scan_warning(warning) + "\n")
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
      stdout_writer(separator + rendered + "\n")
      state.hit_count += 1
    }
  }
}
