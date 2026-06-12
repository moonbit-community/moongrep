///|
fn main {
  try {
    let options = parse_cli_options(runtime_cli_args(@miniio.args_get()))
    let result = collect_directory_hits(options)
    println(render_directory_scan_result(result))
  } catch {
    CliError::Usage(message~, exit_code~) => {
      println(message)
      @miniio.exit(exit_code)
    }
    err => {
      println("\{err}")
      @miniio.exit(1)
    }
  }
}
