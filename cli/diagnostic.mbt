///|
fn format_cli_diagnostic(
  summary : String,
  source : String?,
  reason : String?,
  help : String?,
  pattern? : String,
) -> String {
  let output = StringBuilder()
  output.write_string("error: ")
  output.write_string(summary)
  append_cli_diagnostic_field(output, "source", source)
  append_cli_diagnostic_pattern(output, pattern)
  append_cli_diagnostic_field(output, "reason", reason)
  append_cli_diagnostic_field(output, "help", help)
  output.to_string()
}

///|
fn append_cli_diagnostic_pattern(
  output : StringBuilder,
  value : String?,
) -> Unit {
  match value {
    Some(text) => {
      let normalized = normalize_cli_diagnostic_pattern(text)
      output.write_string("\n  pattern:")
      if normalized != "" {
        for line in normalized.split("\n") {
          output.write_string("\n    ")
          output.write_string(line.to_owned())
        }
      }
    }
    _ => ()
  }
}

///|
fn normalize_cli_diagnostic_pattern(value : String) -> String {
  let normalized = value
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
  if normalized.has_suffix("\n") {
    normalized[:normalized.length() - 1].to_owned()
  } else {
    normalized
  }
}

///|
fn append_cli_diagnostic_field(
  output : StringBuilder,
  label : String,
  value : String?,
) -> Unit {
  match value {
    Some(text) if text != "" => {
      output.write_string("\n  ")
      output.write_string(label)
      output.write_string(": ")
      output.write_string(compact_cli_diagnostic_value(text))
    }
    _ => ()
  }
}

///|
fn compact_cli_diagnostic_value(value : String) -> String {
  value
  .replace_all(old="\r\n", new=" ")
  .replace_all(old="\n", new=" ")
  .replace_all(old="\r", new=" ")
}

///|
fn cli_message_is_display_ready(message : String) -> Bool {
  message.has_prefix("error:") || message.has_prefix("Usage:")
}

///|
fn render_cli_error(error : CliError) -> String {
  let message = match error {
    Internal(message~) => message
    Usage(message~) => message
    DumpInput(message~) => message
    RuleSource(message~) => message
    RuleContent(message~) => message
    ScanInput(message~) => message
    Output(message~) => message
  }
  if cli_message_is_display_ready(message) {
    message
  } else {
    match error {
      Internal(_) =>
        format_cli_diagnostic(
          "internal error",
          None,
          Some(message),
          Some(
            "report this issue at https://github.com/moonbit-community/moongrep/issues",
          ),
        )
      Output(_) => render_plain_output_error(message)
      _ => "error: \{message}"
    }
  }
}

///|
fn render_plain_output_error(message : String) -> String {
  let stdout_prefix = "standard output: "
  let stderr_prefix = "standard error: "
  let (source, reason) = if message.has_prefix(stdout_prefix) {
    (Some("standard output"), message[stdout_prefix.length():].to_owned())
  } else if message.has_prefix(stderr_prefix) {
    (Some("standard error"), message[stderr_prefix.length():].to_owned())
  } else {
    (None, message)
  }
  format_cli_diagnostic(
    "could not write output",
    source,
    Some(reason),
    Some("check the output destination or downstream command"),
  )
}

///|
fn yaml_location_reason(mark : @yaml.Marker, info : String) -> String {
  "line \{mark.line}, column \{mark.col + 1}: \{info}"
}

///|
#warnings("-alert_internal")
fn os_error_reason(error : @os_error.OSError) -> String {
  let @os_error.OSError(errno, ..) = error
  @os_error.errno_to_string(errno)
}

///|
fn new_internal_error(reason : String) -> CliError {
  Internal(
    message=format_cli_diagnostic(
      "internal error",
      None,
      Some(reason),
      Some(
        "report this issue at https://github.com/moonbit-community/moongrep/issues",
      ),
    ),
  )
}

///|
fn new_guard_error(source : String, reason : String) -> CliError {
  Usage(
    message=format_cli_diagnostic(
      "invalid --guard",
      Some(source),
      Some(reason),
      Some(
        "pass one YAML mapping from $-prefixed capture names to regex strings",
      ),
    ),
  )
}

///|
fn new_yaml_guard_error(error : @yaml.YamlError) -> CliError {
  let @yaml.YamlError::YamlError(mark~, info~) = error
  new_guard_error("--guard", yaml_location_reason(mark, info))
}

///|
fn new_guard_placement_error(reason : String) -> CliError {
  Usage(
    message=format_cli_diagnostic(
      "invalid --guard placement",
      Some("--guard"),
      Some(reason),
      Some("place one --guard after the anonymous --pattern it applies to"),
    ),
  )
}

///|
fn new_unknown_document_error(name : String) -> CliError {
  Usage(
    message=format_cli_diagnostic(
      "unknown document",
      Some(name),
      None,
      Some("run `moongrep docs --list` to list embedded documents"),
    ),
  )
}

///|
fn new_unknown_disabled_rule_error(rule_id : String) -> CliError {
  Usage(
    message=format_cli_diagnostic(
      "unknown rule id in --disable",
      Some(rule_id),
      None,
      Some("use the exact id of a loaded rule"),
    ),
  )
}

///|
fn dump_input_help(source : String) -> String {
  if source == "dump --impl" {
    "provide exactly one valid MoonBit top-level item"
  } else {
    "provide one valid MoonBit expression"
  }
}

///|
fn new_dump_input_error(source : String, reason : String) -> CliError {
  DumpInput(
    message=format_cli_diagnostic(
      "could not parse dump input",
      Some(source),
      Some(reason),
      Some(dump_input_help(source)),
    ),
  )
}

///|
fn new_empty_rule_directory_error(path : String) -> CliError {
  RuleSource(
    message=format_cli_diagnostic(
      "no rules found",
      Some(path),
      Some("the directory contains no YAML rule files"),
      Some("add a .yaml or .yml rule file or choose another --rules directory"),
    ),
  )
}

///|
fn new_invalid_rule_error(path : String, reason : String) -> CliError {
  RuleContent(
    message=format_cli_diagnostic(
      "invalid rule",
      Some(path),
      Some(reason),
      Some("fix the rule and try again"),
    ),
  )
}

///|
fn new_invalid_pattern_error(
  path : String,
  shape : String,
  reason : String,
) -> CliError {
  RuleContent(
    message=format_cli_diagnostic(
      "invalid rule",
      Some(path),
      Some(reason),
      Some("fix the rule and try again"),
      pattern=shape,
    ),
  )
}

///|
fn new_invalid_anonymous_pattern_error(
  shape : String,
  reason : String,
) -> CliError {
  RuleContent(
    message=format_cli_diagnostic(
      "invalid anonymous pattern",
      Some("--pattern"),
      Some(reason),
      Some("fix the pattern passed to --pattern and try again"),
      pattern=shape,
    ),
  )
}

///|
fn new_rule_load_error(error : @rule_model.RuleLoadError) -> CliError {
  match error {
    NoRuleFiles(path~) => new_empty_rule_directory_error(path)
    InvalidPattern(path~, shape~, info~) =>
      new_invalid_pattern_error(path, shape, info)
    InvalidRule(path~, info~) => new_invalid_rule_error(path, info)
  }
}

///|
fn is_anonymous_pattern_source(
  path : String,
  patterns : Array[@rule_model.RulePatternSpec],
) -> Bool {
  for pattern in patterns {
    if pattern.shape == path {
      return true
    }
  }
  false
}

///|
fn new_compiled_rule_error(
  error : @rule_model.RuleLoadError,
  patterns : Array[@rule_model.RulePatternSpec],
) -> CliError {
  match error {
    NoRuleFiles(path~) => new_empty_rule_directory_error(path)
    InvalidPattern(path~, shape~, info~) =>
      if is_anonymous_pattern_source(path, patterns) {
        new_invalid_anonymous_pattern_error(shape, info)
      } else {
        new_invalid_pattern_error(path, shape, info)
      }
    InvalidRule(path~, info~) =>
      if is_anonymous_pattern_source(path, patterns) {
        new_invalid_anonymous_pattern_error(path, info)
      } else {
        new_invalid_rule_error(path, info)
      }
  }
}

///|
fn new_rule_source_os_error(
  path : String,
  operation : String,
  error : @os_error.OSError,
) -> CliError {
  RuleSource(
    message=format_cli_diagnostic(
      "could not \{operation}",
      Some(path),
      Some(os_error_reason(error)),
      Some("check that the rule path exists and is readable"),
    ),
  )
}

///|
fn new_scan_input_error(
  path : String,
  operation : String,
  reason : String,
) -> CliError {
  ScanInput(
    message=format_cli_diagnostic(
      "could not \{operation}",
      Some(path),
      Some(reason),
      Some("check that the scan path exists and is readable"),
    ),
  )
}

///|
fn new_scan_input_os_error(
  path : String,
  operation : String,
  error : @os_error.OSError,
) -> CliError {
  new_scan_input_error(path, operation, os_error_reason(error))
}

///|
fn new_output_error(destination : String, reason : String) -> CliError {
  Output(
    message=format_cli_diagnostic(
      "could not write output",
      Some(destination),
      Some(reason),
      Some("check the output destination or downstream command"),
    ),
  )
}

///|
fn new_output_os_error(
  destination : String,
  error : @os_error.OSError,
) -> CliError {
  new_output_error(destination, os_error_reason(error))
}
