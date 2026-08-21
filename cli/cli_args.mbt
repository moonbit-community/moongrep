///|
/// CLI argument errors with the process exit code the frontend should use.
pub(all) suberror CliError {
  Usage(message~ : String, exit_code~ : Int)
} derive(Debug)

///|
/// Parsed command-line options for one scan target.
pub(all) struct CliOptions {
  rules_root : String?
  rule_file : String?
  patterns : Array[@rule_model.RulePatternSpec]
  scan_root : String
  exclude_dirs : Array[String]
  exclude_rules : Array[String]
  verbose : Bool
  enable_builtin_rules : Bool
  no_color : Bool
  output_json : Bool
}

///|
pub fn runtime_cli_args(argv : Array[String]) -> Array[String] {
  let args : Array[String] = []
  for index in 1..<argv.length() {
    args.push(argv[index])
  }
  args
}

///|
let default_rules_root : String = "./.moongrep/rules"

///|
fn scan_like_command(
  name : StringView,
  about : StringView,
  include_enable_builtin_rules : Bool,
  default_rules_root_enabled : Bool,
  arg_required_else_help : Bool,
) -> @argparse.Command {
  let flags : Array[@argparse.FlagArg] = [
    FlagArg(
      "verbose",
      long="verbose",
      about="Write loaded rule ids and traversal progress to stderr.",
    ),
  ]
  if include_enable_builtin_rules {
    flags.push(
      FlagArg(
        "enable-builtin-rules",
        long="enable-builtin-rules",
        about="Enable embedded builtin rules.",
      ),
    )
  }
  flags.push(
    FlagArg(
      "output-json",
      long="output-json",
      about="Write each match as one JSON record to stdout.",
    ),
  )
  Command(
    name,
    about~,
    arg_required_else_help~,
    flags~,
    options=[
      OptionArg(
        "rules",
        short='r',
        action=Append,
        default_values=if default_rules_root_enabled {
          [default_rules_root]
        } else {
          []
        },
        about="Directory containing YAML rules.",
      ),
      OptionArg("rule", action=Append, about="Single YAML rule file."),
      OptionArg(
        "pattern",
        action=Append,
        about="Anonymous structural pattern to match.",
      ),
      OptionArg(
        "guard",
        action=Append,
        about="YAML guard map for the preceding anonymous pattern.",
      ),
      OptionArg(
        "exclude-dir",
        action=Append,
        about="Directory name or path to skip while recursively scanning. May be repeated.",
      ),
      OptionArg(
        "exclude-rule",
        action=Append,
        about="Rule id to disable after loading rules. May be repeated.",
      ),
    ],
    positionals=[PositionArg("scan-root", about="Directory to scan.")],
  )
}

///|
let scan_command : @argparse.Command = scan_like_command(
  "scan", "Scan MoonBit source files.", true, true, false,
)

///|
let lint_command : @argparse.Command = scan_like_command(
  "lint", "Scan MoonBit source files with embedded builtin rules.", false, false,
  false,
)

///|
let docs_command : @argparse.Command = Command(
  "docs",
  about="Print embedded moongrep documentation.",
  arg_required_else_help=true,
  flags=[
    FlagArg("list", long="list", about="List available embedded documents."),
  ],
  positionals=[
    PositionArg(
      "doc-name",
      about="Document name to print.",
      num_args=ValueRange(lower=0, upper=1),
    ),
  ],
)

///|
let dump_command : @argparse.Command = Command(
  "dump",
  about="Parse a MoonBit impl or expression and print untyped CST debug output.",
  arg_required_else_help=true,
  options=[
    OptionArg(
      "impl",
      action=Set,
      about="MoonBit top-level implementation item to parse.",
    ),
    OptionArg("expr", action=Set, about="MoonBit expression to parse."),
  ],
)

///|
let moongrep_command : @argparse.Command = Command(
  "moongrep",
  about="Scan MoonBit source files with structural and taint rules.",
  subcommands=[scan_command, lint_command, docs_command, dump_command],
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
fn all_cli_values(
  values : Map[String, Array[String]],
  name : String,
) -> Array[String] {
  if values.get(name) is Some(items) {
    items
  } else {
    []
  }
}

///|
fn normalize_scan_exclude_dir(path : String) -> String {
  let mut normalized = path
  while normalized.length() > 1 && normalized.has_suffix("/") {
    normalized = normalized[0:normalized.length() - 1].to_owned()
  }
  while normalized.has_prefix("./") {
    normalized = normalized[2:].to_owned()
  }
  normalized
}

///|
fn normalize_scan_exclude_dirs(paths : Array[String]) -> Array[String] {
  let normalized : Array[String] = []
  for path in paths {
    normalized.push(normalize_scan_exclude_dir(path))
  }
  normalized
}

///|
fn cli_flag_enabled(flags : Map[String, Bool], name : String) -> Bool {
  match flags.get(name) {
    Some(true) => true
    _ => false
  }
}

///|
fn no_color_enabled(env : Map[String, String]) -> Bool {
  match env.get("NO_COLOR") {
    Some(value) if value == "1" => true
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
fn dump_cli_command(
  dump_matches : @argparse.Matches,
) -> (String, CliOptions?, String?) raise {
  let impl_source = last_cli_value(dump_matches.values, "impl")
  let expr_source = last_cli_value(dump_matches.values, "expr")
  match (impl_source, expr_source) {
    (Some(source), None) => ("dump-impl", None, Some(source))
    (None, Some(source)) => ("dump-expr", None, Some(source))
    (Some(_), Some(_)) =>
      raise CliError::Usage(
        message="dump --impl cannot be combined with --expr",
        exit_code=2,
      )
    (None, None) =>
      raise CliError::Usage(
        message="missing dump --impl or --expr",
        exit_code=2,
      )
  }
}

///|
fn scan_cli_options(
  scan_matches : @argparse.Matches,
  env : Map[String, String],
  argv : Array[String],
  enable_builtin_rules_by_default~ : Bool,
) -> CliOptions raise {
  let verbose = cli_flag_enabled(scan_matches.flags, "verbose")
  let enable_builtin_rules = enable_builtin_rules_by_default ||
    cli_flag_enabled(scan_matches.flags, "enable-builtin-rules")
  let output_json = cli_flag_enabled(scan_matches.flags, "output-json")
  let no_color = no_color_enabled(env)
  let parsed_rules_root = last_cli_value(scan_matches.values, "rules")
  let rule_file = last_cli_value(scan_matches.values, "rule")
  let patterns = parse_scan_pattern_specs(argv)
  let rules_root = if scan_matches.sources.get("rules") is Some(Default) &&
    (rule_file is Some(_) || !patterns.is_empty() || enable_builtin_rules) {
    None
  } else {
    parsed_rules_root
  }
  let exclude_dirs = normalize_scan_exclude_dirs(
    all_cli_values(scan_matches.values, "exclude-dir"),
  )
  let exclude_rules = all_cli_values(scan_matches.values, "exclude-rule")
  if rules_root is None &&
    rule_file is None &&
    patterns.is_empty() &&
    !enable_builtin_rules {
    raise CliError::Usage(
      message="missing required --rules, --rule, --pattern, or --enable-builtin-rules",
      exit_code=2,
    )
  }
  let scan_root = if last_cli_value(scan_matches.values, "scan-root")
    is Some(path) {
    path
  } else {
    "."
  }
  {
    rules_root,
    rule_file,
    patterns,
    scan_root,
    exclude_dirs,
    exclude_rules,
    verbose,
    enable_builtin_rules,
    no_color,
    output_json,
  }
}

///|
fn parse_scan_pattern_specs(
  argv : Array[String],
) -> Array[@rule_model.RulePatternSpec] raise {
  let patterns : Array[@rule_model.RulePatternSpec] = []
  let has_guard : Array[Bool] = []
  let mut index = 1
  while index < argv.length() {
    let arg = argv[index]
    if arg == "--pattern" {
      if index + 1 >= argv.length() {
        raise CliError::Usage(
          message="missing value for --pattern",
          exit_code=2,
        )
      }
      patterns.push({
        shape: argv[index + 1],
        guards: Map([]),
        match_mode: Default,
      })
      has_guard.push(false)
      index += 2
    } else if arg.has_prefix("--pattern=") {
      patterns.push({
        shape: arg["--pattern=".length():].to_owned(),
        guards: Map([]),
        match_mode: Default,
      })
      has_guard.push(false)
      index += 1
    } else if arg == "--guard" {
      if index + 1 >= argv.length() {
        raise CliError::Usage(message="missing value for --guard", exit_code=2)
      }
      attach_scan_guard(
        patterns,
        has_guard,
        parse_cli_guard_map(argv[index + 1]),
      )
      index += 2
    } else if arg.has_prefix("--guard=") {
      attach_scan_guard(
        patterns,
        has_guard,
        parse_cli_guard_map(arg["--guard=".length():].to_owned()),
      )
      index += 1
    } else {
      index += 1
    }
  }
  patterns
}

///|
fn attach_scan_guard(
  patterns : Array[@rule_model.RulePatternSpec],
  has_guard : Array[Bool],
  guards : Map[String, String],
) -> Unit raise {
  let mut index = patterns.length()
  while index > 0 {
    index -= 1
    if !has_guard[index] {
      let shape = patterns[index].shape
      patterns[index] = { shape, guards, match_mode: Default }
      has_guard[index] = true
      return
    }
  }
  let message = if patterns.is_empty() {
    "--guard requires a preceding --pattern"
  } else {
    "duplicate --guard for anonymous --pattern"
  }
  raise CliError::Usage(message~, exit_code=2)
}

///|
fn parse_cli_guard_map(source : String) -> Map[String, String] raise {
  let docs = @yaml.Yaml::load_from_string(source) catch {
    err =>
      raise CliError::Usage(
        message="invalid --guard YAML: \{Repr(err)}",
        exit_code=2,
      )
  }
  if docs.length() != 1 {
    raise CliError::Usage(
      message="--guard must contain exactly one YAML document",
      exit_code=2,
    )
  }
  guard docs[0] is Map(map) else {
    raise CliError::Usage(message="--guard must be a YAML mapping", exit_code=2)
  }
  let guards : Map[String, String] = Map([])
  for key, value in map {
    if !key.has_prefix("$") || key.length() <= 1 {
      raise CliError::Usage(
        message="guard key \{key} must be a $-prefixed metavar name",
        exit_code=2,
      )
    }
    match value {
      String(regex_source) => guards[key] = regex_source
      _ =>
        raise CliError::Usage(
          message="--guard.\{key} must be a string",
          exit_code=2,
        )
    }
  }
  guards
}

///|
/// Parses command-line arguments after the executable name has been removed.
///
/// A supported subcommand is required after the executable name. Within `scan`,
/// `--rules <rules-root>`, `--rules=<rules-root>`, and `-r <rules-root>` select
/// a rules directory. When no rule source is given, the rules directory
/// defaults to `./.moongrep/rules`. An explicit `--rule <rule-file>`, at least
/// one `--pattern <pattern>`, or `--enable-builtin-rules` suppresses that
/// default. `--verbose` and `--output-json` are optional.
/// `lint` accepts the other scan options, enables builtin rules automatically,
/// and defaults to scanning the current directory when no arguments are given.
/// Each `--exclude-dir <dir>` skips one matching child directory name or path
/// during recursive source scanning. Each `--exclude-rule <rule-id>` disables
/// one loaded rule by exact rule id before matching. Both options may be
/// repeated.
/// One optional scan-root positional may appear in the argument list. If the
/// rules option or single rule option appears multiple times, the last value
/// wins. Repeated patterns, exclude directories, and excluded rules are
/// appended in order.
/// Invoking `docs` or `dump` without any arguments prints that subcommand's
/// help and exits successfully. Missing subcommands, other missing required
/// arguments, unknown options, or more than one scan root raise
/// `CliError::Usage` with exit code 2.
pub fn parse_cli_command(
  argv : Array[String],
  env? : Map[String, String] = Map([]),
) -> (String, CliOptions?, String?) raise {
  let matches = moongrep_command.parse(argv~, env~) catch {
    err => {
      let message = "\{err}"
      raise CliError::Usage(message~, exit_code=2)
    }
  }
  match matches.subcommand {
    Some(("scan", scan_matches)) =>
      (
        "scan",
        Some(
          scan_cli_options(
            scan_matches,
            env,
            argv,
            enable_builtin_rules_by_default=false,
          ),
        ),
        None,
      )
    Some(("lint", lint_matches)) =>
      (
        "scan",
        Some(
          scan_cli_options(
            lint_matches,
            env,
            argv,
            enable_builtin_rules_by_default=true,
          ),
        ),
        None,
      )
    Some(("docs", docs_matches)) => docs_cli_command(docs_matches)
    Some(("dump", dump_matches)) => dump_cli_command(dump_matches)
    _ => raise CliError::Usage(message="missing required command", exit_code=2)
  }
}
