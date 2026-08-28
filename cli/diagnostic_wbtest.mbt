///|
test "fatal diagnostics cover all seven exit categories" {
  let errors : Array[CliError] = [
    new_internal_error("unexpected state"),
    new_unknown_document_error("MissingDoc"),
    new_dump_input_error("dump --expr", "missing expression"),
    new_empty_rule_directory_error("rules"),
    new_invalid_rule_error("rules/example.yaml", "missing required key id"),
    new_scan_input_error("src", "read scan directory", "permission denied"),
    new_output_error("standard output", "broken pipe"),
  ]
  assert_eq(errors.map(error => error.exit_code()), [1, 2, 3, 4, 5, 6, 7])
  inspect(
    errors.map(error => "\{error}").join("\n---\n"),
    content=(
      #|error: internal error
      #|  reason: unexpected state
      #|  help: report this issue at https://github.com/moonbit-community/moongrep/issues
      #|---
      #|error: unknown document
      #|  source: MissingDoc
      #|  help: run `moongrep docs --list` to list embedded documents
      #|---
      #|error: could not parse dump input
      #|  source: dump --expr
      #|  reason: missing expression
      #|  help: provide one valid MoonBit expression
      #|---
      #|error: no rules found
      #|  source: rules
      #|  reason: the directory contains no YAML rule files
      #|  help: add a .yaml or .yml rule file or choose another --rules directory
      #|---
      #|error: invalid rule
      #|  source: rules/example.yaml
      #|  reason: missing required key id
      #|  help: fix the rule and try again
      #|---
      #|error: could not read scan directory
      #|  source: src
      #|  reason: permission denied
      #|  help: check that the scan path exists and is readable
      #|---
      #|error: could not write output
      #|  source: standard output
      #|  reason: broken pipe
      #|  help: check the output destination or downstream command
    ),
  )
}

///|
test "diagnostic formatter omits empty optional fields and trailing newline" {
  inspect(
    format_cli_diagnostic("summary", None, None, None),
    content="error: summary",
  )
  let rendered = format_cli_diagnostic(
    "summary",
    Some(""),
    Some("reason"),
    Some(""),
  )
  inspect(
    rendered,
    content=(
      #|error: summary
      #|  reason: reason
    ),
  )
  assert_false(rendered.has_suffix("\n"))
  let emitted = rendered + "\n"
  assert_true(emitted.has_suffix("\n"))
  assert_false(emitted.has_suffix("\n\n"))
  inspect(
    format_cli_diagnostic("summary", None, Some("first\nsecond"), None),
    content="error: summary\n  reason: first second",
  )
}

///|
test "plain messages gain an error prefix" {
  inspect(
    "\{CliError::Usage(message="plain message")}",
    content="error: plain message",
  )
}

///|
test "argparse error and usage blocks pass through unchanged" {
  let argparse_message =
    #|error: unexpected argument '--bad' found
    #|
    #|  tip: a similar argument exists: '--help'
    #|
    #|Usage: moongrep <command>
  inspect(
    "\{CliError::Usage(message=argparse_message)}",
    content=(
      #|error: unexpected argument '--bad' found
      #|
      #|  tip: a similar argument exists: '--help'
      #|
      #|Usage: moongrep <command>
    ),
  )
  let usage_message = "Usage: moongrep <command>"
  inspect(
    "\{CliError::Usage(message=usage_message)}",
    content="Usage: moongrep <command>",
  )
}

///|
test "plain internal errors include reporting help" {
  inspect(
    "\{CliError::Internal(message="unreachable state")}",
    content=(
      #|error: internal error
      #|  reason: unreachable state
      #|  help: report this issue at https://github.com/moonbit-community/moongrep/issues
    ),
  )
}

///|
test "plain output errors separate the destination from the OS reason" {
  inspect(
    "\{CliError::Output(message="standard output: Broken pipe")}",
    content=(
      #|error: could not write output
      #|  source: standard output
      #|  reason: Broken pipe
      #|  help: check the output destination or downstream command
    ),
  )
}
