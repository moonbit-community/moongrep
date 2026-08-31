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
test "diagnostic formatter preserves multiline pattern layout" {
  let rendered = format_cli_diagnostic(
    "invalid rule",
    Some("rules/example.yaml"),
    Some("the pattern is not valid"),
    Some("fix the rule and try again"),
    pattern="first\r\n  second\r\rthird\r\n",
  )
  inspect(
    rendered,
    content="error: invalid rule\n  source: rules/example.yaml\n  pattern:\n    first\n      second\n    \n    third\n  reason: the pattern is not valid\n  help: fix the rule and try again",
  )
  assert_false(rendered.contains("\r"))
  assert_false(rendered.contains("third\n    \n  reason"))
  inspect(
    format_cli_diagnostic("summary", None, None, None, pattern=""),
    content="error: summary\n  pattern:",
  )
  inspect(
    format_cli_diagnostic(
      "summary",
      None,
      Some("reason"),
      None,
      pattern="first\n\n",
    ),
    content="error: summary\n  pattern:\n    first\n    \n  reason: reason",
  )
}

///|
test "rule pattern diagnostics keep source and shape separate" {
  let file_error = new_rule_load_error(
    @rule_model.InvalidPattern(
      path="rules/example.yaml",
      shape="wrap($$$items + 1)",
      info="the pattern uses ellipsis metavar $$$items outside a complete ordered CST list item",
    ),
  )
  assert_eq(file_error.exit_code(), 5)
  inspect(
    "\{file_error}",
    content=(
      #|error: invalid rule
      #|  source: rules/example.yaml
      #|  pattern:
      #|    wrap($$$items + 1)
      #|  reason: the pattern uses ellipsis metavar $$$items outside a complete ordered CST list item
      #|  help: fix the rule and try again
    ),
  )
  let shape = "$(name:id)()"
  let anonymous_error = new_compiled_rule_error(
    @rule_model.InvalidRule(
      path=shape,
      info="patterns[0].guard.$name has invalid regex",
    ),
    [{ shape, guards: Map([]), match_mode: Default, }],
  )
  inspect(
    "\{anonymous_error}",
    content=(
      #|error: invalid anonymous pattern
      #|  source: --pattern
      #|  pattern:
      #|    $(name:id)()
      #|  reason: patterns[0].guard.$name has invalid regex
      #|  help: fix the pattern passed to --pattern and try again
    ),
  )
}

///|
test "usage errors retain structured diagnostic fields" {
  match new_unknown_document_error("MissingDoc") {
    Usage(diagnostic~) =>
      match diagnostic {
        Fields(summary~, source~, reason~, help~, pattern~) => {
          inspect(summary, content="unknown document")
          assert_eq(source, Some("MissingDoc"))
          assert_true(reason is None)
          assert_eq(
            help,
            Some("run `moongrep docs --list` to list embedded documents"),
          )
          assert_true(pattern is None)
        }
        ParserMessage(..) => fail("expected structured usage diagnostic")
      }
    _ => fail("expected usage error")
  }
}

///|
test "plain messages gain an error prefix" {
  inspect("\{new_usage_error("plain message")}", content="error: plain message")
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
    "\{new_parser_usage_error(argparse_message)}",
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
    "\{new_parser_usage_error(usage_message)}",
    content="Usage: moongrep <command>",
  )
}

///|
test "plain internal errors include reporting help" {
  inspect(
    "\{CliError::internal("unreachable state")}",
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
    "\{CliError::output_error("standard output", "Broken pipe")}",
    content=(
      #|error: could not write output
      #|  source: standard output
      #|  reason: Broken pipe
      #|  help: check the output destination or downstream command
    ),
  )
}
