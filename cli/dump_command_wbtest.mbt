///|
test "dump impl renders untyped ast debug output" {
  let output = render_dump_command(
    ("dump-impl", None, Some("fn answer { 42 }")),
  )
  assert_true(output.contains("Impl_TopFuncDef"))
  assert_true(output.contains("PString(\"answer\")"))
  assert_true(output.contains("Constant_Int"))
  assert_true(!output.contains("\"kind\""))
}

///|
test "dump expr renders untyped ast debug output" {
  let output = render_dump_command(("dump-expr", None, Some("x + 1")))
  assert_true(output.contains("Expr_Infix"))
  assert_true(output.contains("Expr_Ident"))
  assert_true(output.contains("Constant_Int"))
  assert_true(!output.contains("\"kind\""))
}

///|
test "dump impl rejects empty source" {
  try render_dump_command(("dump-impl", None, Some(""))) catch {
    CliError::Usage(exit_code~, ..) => assert_eq(exit_code, 1)
    err => fail("unexpected error \{err}")
  } noraise {
    _ => fail("expected dump parse error")
  }
}
