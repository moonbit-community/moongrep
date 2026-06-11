///|
fn expect_cli_usage(argv : Array[String], exit_code : Int) -> Unit raise {
  try parse_cli_options(argv) catch {
    CliError::Usage(exit_code=found, ..) =>
      inspect(found, content=exit_code.to_string())
    err => fail("unexpected error \{err}")
  } noraise {
    _ => fail("expected CLI usage error")
  }
}

///|
test "cli args require rules option" {
  expect_cli_usage([], 2)
  expect_cli_usage(["src"], 2)
}

///|
test "cli args parse rules root and default scan root" {
  let options = parse_cli_options(["--rules", "custom-rules"])
  inspect(options.rules_root, content="custom-rules")
  inspect(options.scan_root, content=".")
}

///|
test "cli args parse explicit scan root" {
  let options = parse_cli_options(["--rules", "custom-rules", "src"])
  inspect(options.rules_root, content="custom-rules")
  inspect(options.scan_root, content="src")
}

///|
test "cli args reject missing rules value" {
  expect_cli_usage(["--rules"], 2)
}
