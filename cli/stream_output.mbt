///|
priv struct ScanOutputState {
  mut hit_count : Int
}

///|
priv struct BufferedStdout {
  mut contents : StringBuilder
  mut length : Int
}

///|
/// Scans source files and writes results as they are found.
///
/// Match records are written to standard output. Verbose traversal messages
/// and parse warnings are written to standard error.
pub async fn run_scan_command(options : CliOptions) -> Unit {
  let stdout : BufferedStdout = { contents: StringBuilder(), length: 0 }
  run_scan_command_with_writers(
    options,
    output => write_buffered_scan_stdout(stdout, output),
    write_scan_stderr,
  )
  flush_buffered_scan_stdout(stdout)
}

///|
async fn write_buffered_scan_stdout(
  stdout : BufferedStdout,
  output : String,
) -> Unit {
  stdout.contents.write_string(output)
  stdout.length += output.length()
  if stdout.length >= 65536 {
    flush_buffered_scan_stdout(stdout)
  }
}

///|
async fn flush_buffered_scan_stdout(stdout : BufferedStdout) -> Unit {
  if stdout.length == 0 {
    return
  }
  @stdio.stdout.write(stdout.contents.to_string())
  stdout.contents = StringBuilder()
  stdout.length = 0
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
    Warning(skipped_file) =>
      stderr_writer(render_skipped_file_warning(skipped_file) + "\n")
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
