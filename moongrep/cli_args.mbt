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
fn runtime_cli_args(argv : Array[String]) -> Array[String] {
  let args : Array[String] = []
  for index in 1..<argv.length() {
    args.push(argv[index])
  }
  args
}

///|
fn scan_command() -> @argparse.Command {
  @argparse.Command(
    "scan",
    about="Scan MoonBit source files with structural and taint rules.",
    options=[
      @argparse.OptionArg(
        "rules",
        short='r',
        action=@argparse.OptionAction::Append,
        about="Directory containing YAML rules.",
        required=true,
      ),
    ],
    positionals=[@argparse.PositionArg("scan-root", about="Directory to scan.")],
  )
}

///|
fn moongrep_command() -> @argparse.Command {
  @argparse.Command(
    "moongrep",
    about="Scan MoonBit source files with structural and taint rules.",
    subcommands=[scan_command()],
    subcommand_required=true,
  )
}

///|
fn last_cli_value(
  values : Map[String, Array[String]],
  name : String,
) -> String? {
  match values.get(name) {
    Some(items) if items.length() > 0 => Some(items[items.length() - 1])
    _ => None
  }
}

///|
pub fn parse_cli_options(argv : Array[String]) -> CliOptions raise {
  let matches = moongrep_command().parse(argv~, env={}) catch {
    err => {
      let message = "\{err}"
      raise CliError::Usage(message~, exit_code=2)
    }
  }
  let scan_matches = match matches.subcommand {
    Some(("scan", scan_matches)) => scan_matches
    _ =>
      raise CliError::Usage(
        message="missing required scan command",
        exit_code=2,
      )
  }
  let rules_root = match last_cli_value(scan_matches.values, "rules") {
    Some(path) => path
    None =>
      raise CliError::Usage(message="missing required --rules", exit_code=2)
  }
  let scan_root = match last_cli_value(scan_matches.values, "scan-root") {
    Some(path) => path
    None => "."
  }
  { rules_root, scan_root }
}
