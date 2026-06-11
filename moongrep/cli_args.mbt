///|
pub suberror CliError {
  Usage(message~ : String, exit_code~ : Int)
} derive(Debug)

///|
pub(all) struct CliOptions {
  rules_root : String
  scan_root : String
}

///|
pub fn parse_cli_options(argv : Array[String]) -> CliOptions raise {
  let mut rules_root : String? = None
  let positionals : Array[String] = []
  let mut index = 0
  while index < argv.length() {
    let arg = argv[index]
    if arg == "--rules" {
      if index + 1 >= argv.length() || argv[index + 1].has_prefix("--") {
        raise CliError::Usage(message="missing value for --rules", exit_code=2)
      }
      rules_root = Some(argv[index + 1])
      index = index + 2
    } else if arg.has_prefix("--") {
      raise CliError::Usage(message="unknown option \{arg}", exit_code=2)
    } else {
      positionals.push(arg)
      index = index + 1
    }
  }
  let rules_root = match rules_root {
    Some(path) => path
    None =>
      raise CliError::Usage(message="missing required --rules", exit_code=2)
  }
  if positionals.length() > 1 {
    raise CliError::Usage(message="expected at most one scan root", exit_code=2)
  }
  let scan_root = match positionals {
    [] => "."
    [path] => path
    _ => "."
  }
  { rules_root, scan_root }
}
