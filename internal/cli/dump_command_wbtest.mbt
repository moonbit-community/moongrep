///|
test "dump impl renders untyped CST debug output" {
  let output = render_dump_command(
    DumpImpl(source="fn answer { 42 }", exit_code=false, output_json=false),
  )
  assert_true(output.contains("Impl_Function"))
  assert_true(output.contains("String(\"answer\")"))
  assert_true(output.contains("Expr_Constant"))
  assert_true(!output.contains("\"kind\""))
}

///|
test "dump impl supports metavariable syntax" {
  let output = render_dump_command(
    DumpImpl(source="let $(value:pat) = 1", exit_code=false, output_json=false),
  )
  assert_true(output.contains("Impl_Let"))
  assert_true(output.contains("String(\"$(value:pat)\")"))
}

///|
test "dump expr renders untyped CST debug output" {
  let output = render_dump_command(
    DumpExpr(source="x + 1", exit_code=false, output_json=false),
  )
  assert_true(output.contains("Expr_Infix"))
  assert_true(output.contains("Expr_Ident"))
  assert_true(output.contains("Constant_Int"))
  assert_true(!output.contains("\"kind\""))
}

///|
test "dump expr supports metavariable syntax" {
  let output = render_dump_command(
    DumpExpr(source="$(value:exp)", exit_code=false, output_json=false),
  )
  assert_true(output.contains("Expr_Ident"))
  assert_true(output.contains("String(\"$(value:exp)\")"))
}

///|
fn expect_json_dump(
  text_command : CliCommand,
  json_command : CliCommand,
  expected_kind : String,
) -> Unit raise {
  let text_output = render_dump_command(text_command)
  let json_output = render_dump_command(json_command)
  assert_false(json_output.contains("\n"))
  assert_true(
    json_output.has_prefix(
      "{\"type\":\"dump\",\"kind\":\"\{expected_kind}\",\"content\":",
    ),
  )
  assert_eq(
    json_output,
    "{\"type\":\"dump\",\"kind\":\"\{expected_kind}\",\"content\":\{Json::string(text_output).stringify()}}",
  )
  match @json.parse(json_output) {
    {
      "type": String(record_type),
      "kind": String(kind),
      "content": String(content),
      ..
    } => {
      inspect(record_type, content="dump")
      inspect(kind, content=expected_kind)
      assert_eq(content, text_output)
    }
    _ => fail("unexpected JSON dump record")
  }
}

///|
test "dump JSON output preserves impl and expr Repr content" {
  expect_json_dump(
    DumpImpl(source="fn answer { 42 }", exit_code=false, output_json=false),
    DumpImpl(source="fn answer { 42 }", exit_code=false, output_json=true),
    "impl",
  )
  expect_json_dump(
    DumpExpr(source="x + 1", exit_code=false, output_json=false),
    DumpExpr(source="x + 1", exit_code=false, output_json=true),
    "expr",
  )
}

///|
test "dump exit code mode suppresses successful CST output" {
  inspect(
    render_dump_command(
      DumpImpl(source="fn answer { 42 }", exit_code=true, output_json=false),
    ),
    content="",
  )
  inspect(
    render_dump_command(
      DumpExpr(source="x + 1", exit_code=true, output_json=true),
    ),
    content="",
  )
}

///|
test "dump impl rejects empty source" {
  try
    render_dump_command(DumpImpl(source="", exit_code=false, output_json=true))
  catch {
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
  try
    render_dump_command(
      DumpExpr(source="value +", exit_code=true, output_json=true),
    )
  catch {
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
