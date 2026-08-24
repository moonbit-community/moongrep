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
    CliError::Usage(exit_code~, ..) => assert_eq(exit_code, 2)
    err => fail("unexpected error \{err}")
  } noraise {
    _ => fail("expected docs usage error")
  }
}
