///|
test "dump impl renders parser json" {
  let output = render_dump_impl_json("fn answer { 42 }")
  assert_true(output.contains("\"kind\": \"Impl::TopFuncDef\""))
  assert_true(output.contains("\"name\": \"answer\""))
  assert_true(output.contains("\"value\": \"42\""))
}

///|
test "dump expr renders parser json" {
  let output = render_dump_expr_json("x + 1")
  assert_true(output.contains("\"kind\": \"Expr::Infix\""))
  assert_true(output.contains("\"value\": \"x\""))
  assert_true(output.contains("\"value\": \"1\""))
}

///|
test "dump impl rejects empty source" {
  try render_dump_impl_json("") catch {
    CliError::Usage(exit_code~, ..) => inspect(exit_code, content="1")
    err => fail("unexpected error \{err}")
  } noraise {
    _ => fail("expected dump parse error")
  }
}
