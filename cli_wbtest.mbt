///|
fn expect_cli_usage(argv : Array[String], exit_code : Int) -> Unit raise {
  try parse_cli_command(argv) catch {
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
test "cli args parse docs list command" {
  match parse_cli_command(["docs", "--list"]) {
    ("docs-list", None, None) => inspect("docs-list", content="docs-list")
    _ => fail("unexpected command")
  }
}

///|
test "cli args parse docs named command" {
  match parse_cli_command(["docs", "RuleSpec"]) {
    ("docs-show", None, Some(name)) => inspect(name, content="RuleSpec")
    _ => fail("unexpected command")
  }
}

///|
test "cli args reject ambiguous docs command" {
  expect_cli_usage(["docs"], 2)
  expect_cli_usage(["docs", "--list", "RuleSpec"], 2)
}

///|
test "cli args parse rules root and default scan root" {
  match parse_cli_command(["scan", "--rules", "custom-rules"]) {
    ("scan", Some(options), None) => {
      inspect(options.rules_root, content="custom-rules")
      inspect(options.scan_root, content=".")
      assert_false(options.verbose)
    }
    _ => fail("unexpected command")
  }
}

///|
test "cli args parse explicit scan root" {
  match parse_cli_command(["scan", "--rules", "custom-rules", "src"]) {
    ("scan", Some(options), None) => {
      inspect(options.rules_root, content="custom-rules")
      inspect(options.scan_root, content="src")
      assert_false(options.verbose)
    }
    _ => fail("unexpected command")
  }
}

///|
test "cli args parse scan verbose flag" {
  match
    parse_cli_command(["scan", "--rules", "custom-rules", "--verbose", "src"]) {
    ("scan", Some(options), None) => {
      inspect(options.rules_root, content="custom-rules")
      inspect(options.scan_root, content="src")
      assert_true(options.verbose)
    }
    _ => fail("unexpected command")
  }
}

///|
test "cli args parse argparse option input forms" {
  match parse_cli_command(["scan", "--rules=inline-rules"]) {
    ("scan", Some(options), None) => {
      inspect(options.rules_root, content="inline-rules")
      inspect(options.scan_root, content=".")
      assert_false(options.verbose)
    }
    _ => fail("unexpected inline command")
  }
  match parse_cli_command(["scan", "-r", "short-rules", "src"]) {
    ("scan", Some(options), None) => {
      inspect(options.rules_root, content="short-rules")
      inspect(options.scan_root, content="src")
      assert_false(options.verbose)
    }
    _ => fail("unexpected short command")
  }
}

///|
test "cli args keep the last rules option" {
  match
    parse_cli_command([
      "scan", "--rules", "old-rules", "--rules=new-rules", "src",
    ]) {
    ("scan", Some(options), None) => {
      inspect(options.rules_root, content="new-rules")
      inspect(options.scan_root, content="src")
      assert_false(options.verbose)
    }
    _ => fail("unexpected command")
  }
}

///|
test "cli args reject missing rules value" {
  expect_cli_usage(["scan", "--rules"], 2)
}

///|
test "cli args render argparse help" {
  let help = moongrep_command.render_help()
  assert_true(help.has_prefix("Usage: moongrep <command>"))
  assert_true(help.contains("scan"))
  assert_true(help.contains("docs"))
}

///|
test "cli args from runtime drop executable name" {
  match
    parse_cli_command(
      runtime_cli_args(["moongrep", "scan", "--rules", "custom-rules", "src"]),
    ) {
    ("scan", Some(options), None) => {
      inspect(options.rules_root, content="custom-rules")
      inspect(options.scan_root, content="src")
      assert_false(options.verbose)
    }
    _ => fail("unexpected command")
  }
}
