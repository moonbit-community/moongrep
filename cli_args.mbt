///|
/// CLI argument errors with the process exit code the frontend should use.
priv suberror CliError {
  Usage(message~ : String, exit_code~ : Int)
} derive(Debug)

///|
/// Parsed command-line options for one scan target.
priv struct CliOptions {
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
let scan_command : @argparse.Command = @argparse.Command(
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

///|
let docs_command : @argparse.Command = @argparse.Command(
  "docs",
  about="Print embedded moongrep documentation.",
  flags=[
    @argparse.FlagArg(
      "list",
      long="list",
      about="List available embedded documents.",
    ),
  ],
  positionals=[
    @argparse.PositionArg(
      "doc-name",
      about="Document name to print.",
      num_args=@argparse.ValueRange(lower=0, upper=1),
    ),
  ],
)

///|
let moongrep_command : @argparse.Command = @argparse.Command(
  "moongrep",
  about="Scan MoonBit source files with structural and taint rules.",
  subcommands=[scan_command, docs_command],
  subcommand_required=true,
)

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
fn cli_flag_enabled(flags : Map[String, Bool], name : String) -> Bool {
  match flags.get(name) {
    Some(true) => true
    _ => false
  }
}

///|
fn docs_cli_command(
  docs_matches : @argparse.Matches,
) -> (String, CliOptions?, String?) raise {
  let list_requested = cli_flag_enabled(docs_matches.flags, "list")
  let doc_name = last_cli_value(docs_matches.values, "doc-name")
  match (list_requested, doc_name) {
    (true, None) => ("docs-list", None, None)
    (false, Some(name)) => ("docs-show", None, Some(name))
    (true, Some(_)) =>
      raise CliError::Usage(
        message="docs --list cannot be combined with a document name",
        exit_code=2,
      )
    (false, None) =>
      raise CliError::Usage(
        message="missing docs --list or document name",
        exit_code=2,
      )
  }
}

///|
fn scan_cli_options(scan_matches : @argparse.Matches) -> CliOptions raise {
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

///|
/// Parses command-line arguments after the executable name has been removed.
///
/// `scan` is required after the executable name. Within the `scan` subcommand,
/// `--rules <rules-root>`, `--rules=<rules-root>`, or `-r <rules-root>` is
/// required; one optional scan-root positional may appear in the argument list.
/// If the rules option appears multiple times, the last value wins. Missing
/// subcommands, required arguments, unknown options, or more than one scan root
/// raise `CliError::Usage` with exit code 2.
fn parse_cli_command(
  argv : Array[String],
) -> (String, CliOptions?, String?) raise {
  let matches = moongrep_command.parse(argv~, env={}) catch {
    err => {
      let message = "\{err}"
      raise CliError::Usage(message~, exit_code=2)
    }
  }
  match matches.subcommand {
    Some(("scan", scan_matches)) =>
      ("scan", Some(scan_cli_options(scan_matches)), None)
    Some(("docs", docs_matches)) => docs_cli_command(docs_matches)
    _ => raise CliError::Usage(message="missing required command", exit_code=2)
  }
}
