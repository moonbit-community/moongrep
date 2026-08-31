///|
test "docs list renders names and summaries" {
  inspect(
    render_docs_list(),
    content=(
      #|RuleSpec	YAML rule keys, validation, and matcher semantics.
      #|CLISpec	Command-line parsing, scanning, output, diagnostics, and exit behavior.
    ),
  )
}

///|
test "docs show returns CLI specification body" {
  let body = render_doc_body("CLISpec")
  assert_true(body.has_prefix("# Command-Line Interface Specification"))
  assert_true(body.contains("## `scan` and `lint`"))
  assert_true(body.contains("## JSON Lines Output"))
  assert_true(body.contains("## Diagnostics and Exit Status"))
}

///|
test "docs show rejects unknown document name" {
  try render_doc_body("MissingDoc") catch {
    CliError::Usage(..) as err => assert_eq(err.exit_code(), 2)
    err => fail("unexpected error \{err}")
  } noraise {
    _ => fail("expected docs usage error")
  }
}

///|
test "docs rejects unreachable command state as internal" {
  let options : CliOptions = {
    rules_root: None,
    rule_file: None,
    patterns: [],
    scan_root: ".",
    excludes: [],
    disabled_rules: [],
    verbose: false,
    no_color: false,
    output_json: false,
  }
  try render_docs_command(Scan(options)) catch {
    CliError::Internal(..) as err => assert_eq(err.exit_code(), 1)
    err => fail("unexpected error \{err}")
  } noraise {
    _ => fail("expected internal CLI error")
  }
}
