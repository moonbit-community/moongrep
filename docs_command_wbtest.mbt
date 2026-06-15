///|
test "docs list renders names and summaries" {
  inspect(
    render_docs_list(),
    content=(
      #|RuleSpec	Authoritative YAML rule specification for accepted keys, validation, and matcher semantics.
      #|WritingRules	Practical guide for writing and refining moongrep YAML rules.
    ),
  )
}

///|
test "docs show returns matching document body" {
  let body = render_doc_body("RuleSpec")
  assert_true(body.has_prefix("# Rule Specification"))
  assert_true(body.contains("## YAML Schema"))
}

///|
test "docs show rejects unknown document name" {
  try render_doc_body("MissingDoc") catch {
    CliError::Usage(exit_code~, ..) => inspect(exit_code, content="2")
    err => fail("unexpected error \{err}")
  } noraise {
    _ => fail("expected docs usage error")
  }
}
