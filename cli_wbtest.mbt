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
  expect_cli_usage(["--rules", "custom-rules"], 2)
}

///|
test "cli args parse rules root and default scan root" {
  let options = parse_cli_options(["scan", "--rules", "custom-rules"])
  inspect(options.rules_root, content="custom-rules")
  inspect(options.scan_root, content=".")
}

///|
test "cli args parse explicit scan root" {
  let options = parse_cli_options(["scan", "--rules", "custom-rules", "src"])
  inspect(options.rules_root, content="custom-rules")
  inspect(options.scan_root, content="src")
}

///|
test "cli args parse argparse option input forms" {
  let inline = parse_cli_options(["scan", "--rules=inline-rules"])
  inspect(inline.rules_root, content="inline-rules")
  inspect(inline.scan_root, content=".")
  let short = parse_cli_options(["scan", "-r", "short-rules", "src"])
  inspect(short.rules_root, content="short-rules")
  inspect(short.scan_root, content="src")
}

///|
test "cli args keep the last rules option" {
  let options = parse_cli_options([
    "scan", "--rules", "old-rules", "--rules=new-rules", "src",
  ])
  inspect(options.rules_root, content="new-rules")
  inspect(options.scan_root, content="src")
}

///|
test "cli args reject missing rules value" {
  expect_cli_usage(["scan", "--rules"], 2)
}

///|
test "cli args render argparse help" {
  let help = moongrep_command().render_help()
  inspect(help.has_prefix("Usage: moongrep <command>"), content="true")
  inspect(help.contains("scan"), content="true")
}

///|
test "cli args from runtime drop executable name" {
  let options = parse_cli_options(
    runtime_cli_args(["moongrep", "scan", "--rules", "custom-rules", "src"]),
  )
  inspect(options.rules_root, content="custom-rules")
  inspect(options.scan_root, content="src")
}
