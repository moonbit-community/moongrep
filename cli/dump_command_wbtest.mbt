///|
test "dump impl renders untyped CST debug output" {
  let output = render_dump_command(DumpImpl("fn answer { 42 }"))
  assert_true(output.contains("Impl_Function"))
  assert_true(output.contains("String(\"answer\")"))
  assert_true(output.contains("Expr_Constant"))
  assert_true(!output.contains("\"kind\""))
}

///|
test "dump impl supports metavariable syntax" {
  let output = render_dump_command(DumpImpl("let $(value:pat) = 1"))
  assert_true(output.contains("Impl_Let"))
  assert_true(output.contains("String(\"$(value:pat)\")"))
}

///|
test "dump expr renders untyped CST debug output" {
  let output = render_dump_command(DumpExpr("x + 1"))
  assert_true(output.contains("Expr_Infix"))
  assert_true(output.contains("Expr_Ident"))
  assert_true(output.contains("Constant_Int"))
  assert_true(!output.contains("\"kind\""))
}

///|
test "dump expr supports metavariable syntax" {
  let output = render_dump_command(DumpExpr("$(value:exp)"))
  assert_true(output.contains("Expr_Ident"))
  assert_true(output.contains("String(\"$(value:exp)\")"))
}

///|
test "dump impl rejects empty source" {
  try render_dump_command(DumpImpl("")) catch {
    CliError::DumpInput(diagnostic~) as err => {
      let message = render_cli_diagnostic(diagnostic)
      assert_eq(err.exit_code(), 3)
      inspect(
        message,
        content=(
          #|error: could not parse dump input
          #|  source: dump --impl
          #|  reason: expected exactly one top-level item
          #|  help: provide exactly one valid MoonBit top-level item
        ),
      )
    }
    err => fail("unexpected error \{err}")
  } noraise {
    _ => fail("expected dump parse error")
  }
}

///|
test "dump expr keeps the compact parser reason" {
  try render_dump_command(DumpExpr("value +")) catch {
    CliError::DumpInput(diagnostic~) as err => {
      let message = render_cli_diagnostic(diagnostic)
      assert_eq(err.exit_code(), 3)
      inspect(
        message,
        content=(
          #|error: could not parse dump input
          #|  source: dump --expr
          #|  reason: Unexpected end of file, missing simple expression here.
          #|  help: provide one valid MoonBit expression
        ),
      )
      assert_false(message.contains("value +"))
    }
    err => fail("unexpected error \{err}")
  } noraise {
    _ => fail("expected dump parse error")
  }
}
