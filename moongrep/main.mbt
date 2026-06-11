///|
fn main {
  try {
    let options = parse_cli_options(@sys.get_cli_args())
    let result = collect_directory_hits(options)
    println(render_directory_scan_result(result))
  } catch {
    CliError::Usage(message~, exit_code~) => {
      println(message)
      @sys.exit(exit_code)
    }
    err => {
      println("\{err}")
      @sys.exit(1)
    }
  }
}
