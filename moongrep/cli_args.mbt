///|
/// CLI argument errors with the process exit code the frontend should use.
pub suberror CliError {
  Usage(message~ : String, exit_code~ : Int)
} derive(Debug)

///|
/// Parsed command-line options for one scan target.
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
/// Parses command-line arguments after the executable name has been removed.
///
/// `scan` is required after the executable name. Within the `scan` subcommand,
/// `--rules <rules-root>`, `--rules=<rules-root>`, or `-r <rules-root>` is
/// required; one optional scan-root positional may appear in the argument list.
/// If the rules option appears multiple times, the last value wins. Missing
/// subcommands, required arguments, unknown options, or more than one scan root
/// raise `CliError::Usage` with exit code 2.
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
