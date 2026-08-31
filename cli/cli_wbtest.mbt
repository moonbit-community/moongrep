///|
fn expect_cli_usage(argv : Array[String], exit_code : Int) -> Unit raise {
  try parse_cli_command(argv) catch {
    CliError::Usage(..) as err =>
      inspect(err.exit_code(), content=exit_code.to_string())
    err => fail("unexpected error \{err}")
  } noraise {
    _ => fail("expected CLI usage error")
  }
}

///|
test "cli error categories have fixed exit codes" {
  let diagnostic = new_cli_diagnostic("message", None, None, None)
  let errors : Array[CliError] = [
    Internal(diagnostic~),
    Usage(diagnostic~),
    DumpInput(diagnostic~),
    RuleSource(diagnostic~),
    RuleContent(diagnostic~),
    ScanInput(diagnostic~),
    Output(diagnostic~),
  ]
  let exit_codes = errors.map(error => error.exit_code())
  assert_eq(exit_codes, [1, 2, 3, 4, 5, 6, 7])
}

///|
test "cli args describe malformed guard YAML without debug constructors" {
  try
    parse_cli_command(["scan", "--pattern", "target()", "--guard", "{", "src"])
  catch {
    CliError::Usage(diagnostic~) => {
      let message = render_cli_diagnostic(diagnostic)
      inspect(
        message,
        content=(
          #|error: invalid --guard
          #|  source: --guard
          #|  reason: line 2, column 1: while parsing a node, did not find expected node content
          #|  help: pass one YAML mapping from $-prefixed capture names to regex strings
        ),
      )
      assert_false(message.contains("YamlError"))
    }
    err => fail("unexpected error \{err}")
  } noraise {
    _ => fail("expected invalid guard")
  }
}

///|
fn expect_rules_root(options : CliOptions, expected : String) -> Unit raise {
  if options.rules_root is Some(path) {
    inspect(path, content=expected)
  } else {
    fail("expected rules root")
  }
}

///|
fn expect_rule_file(options : CliOptions, expected : String) -> Unit raise {
  if options.rule_file is Some(path) {
    inspect(path, content=expected)
  } else {
    fail("expected rule file")
  }
}

///|
fn expect_no_patterns(options : CliOptions) -> Unit raise {
  assert_eq(options.patterns.length(), 0)
}

///|
fn expect_pattern_shape(
  options : CliOptions,
  index : Int,
  expected : String,
) -> Unit raise {
  inspect(options.patterns[index].shape, content=expected)
}

///|
fn expect_pattern_guard(
  options : CliOptions,
  index : Int,
  key : String,
  expected : String,
) -> Unit raise {
  inspect(options.patterns[index].guards[key], content=expected)
}

///|
test "cli args require command" {
  expect_cli_usage([], 2)
  expect_cli_usage(["src"], 2)
  expect_cli_usage(["--rules", "custom-rules"], 2)
}

///|
test "cli args use default rules root" {
  match parse_cli_command(["scan"]) {
    Scan(options) => {
      expect_rules_root(options, "./.moongrep/rules")
      assert_true(options.rule_file is None)
      expect_no_patterns(options)
      inspect(options.scan_root, content=".")
    }
    _ => fail("unexpected command")
  }
}

///|
test "cli args parse docs list command" {
  match parse_cli_command(["docs", "--list"]) {
    DocsList => inspect("docs-list", content="docs-list")
    _ => fail("unexpected command")
  }
}

///|
test "cli args parse docs named command" {
  match parse_cli_command(["docs", "RuleSpec"]) {
    DocsShow(name) => inspect(name, content="RuleSpec")
    _ => fail("unexpected command")
  }
}

///|
test "cli args reject ambiguous docs command" {
  expect_cli_usage(["docs", "--list", "RuleSpec"], 2)
}

///|
test "cli args parse dump impl command" {
  match parse_cli_command(["dump", "--impl", "fn answer { 42 }"]) {
    DumpImpl(source) => inspect(source, content="fn answer { 42 }")
    _ => fail("unexpected command")
  }
}

///|
test "cli args parse dump expr command" {
  match parse_cli_command(["dump", "--expr", "x + 1"]) {
    DumpExpr(source) => inspect(source, content="x + 1")
    _ => fail("unexpected command")
  }
}

///|
test "cli args reject ambiguous dump command" {
  expect_cli_usage(["dump", "--impl", "fn answer { 42 }", "--expr", "x + 1"], 2)
}

///|
test "cli args parse rules root and default scan root" {
  match parse_cli_command(["scan", "--rules", "custom-rules"]) {
    Scan(options) => {
      expect_rules_root(options, "custom-rules")
      assert_true(options.rule_file is None)
      expect_no_patterns(options)
      inspect(options.scan_root, content=".")
      assert_false(options.verbose)
      assert_false(options.no_color)
      assert_false(options.output_json)
    }
    _ => fail("unexpected command")
  }
}

///|
test "cli args enable no color only when NO_COLOR is 1" {
  match parse_cli_command(["scan", "--rules", "custom-rules"]) {
    Scan(options) => assert_false(options.no_color)
    _ => fail("unexpected command")
  }
  match
    parse_cli_command(["scan", "--rules", "custom-rules"], env={
      "NO_COLOR": "",
    }) {
    Scan(options) => assert_false(options.no_color)
    _ => fail("unexpected command")
  }
  match
    parse_cli_command(["scan", "--rules", "custom-rules"], env={
      "NO_COLOR": "true",
    }) {
    Scan(options) => assert_false(options.no_color)
    _ => fail("unexpected command")
  }
  match
    parse_cli_command(["scan", "--rules", "custom-rules"], env={
      "NO_COLOR": "1",
    }) {
    Scan(options) => assert_true(options.no_color)
    _ => fail("unexpected command")
  }
}

///|
test "cli args parse single rule file and default scan root" {
  match parse_cli_command(["scan", "--rule", "custom-rules/example.yaml"]) {
    Scan(options) => {
      assert_true(options.rules_root is None)
      expect_rule_file(options, "custom-rules/example.yaml")
      expect_no_patterns(options)
      inspect(options.scan_root, content=".")
      assert_false(options.verbose)
    }
    _ => fail("unexpected command")
  }
}

///|
test "cli args parse explicit scan root" {
  match parse_cli_command(["scan", "--rules", "custom-rules", "src"]) {
    Scan(options) => {
      expect_rules_root(options, "custom-rules")
      expect_no_patterns(options)
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
    Scan(options) => {
      expect_rules_root(options, "custom-rules")
      expect_no_patterns(options)
      inspect(options.scan_root, content="src")
      assert_true(options.verbose)
    }
    _ => fail("unexpected command")
  }
}

///|
test "cli args parse scan output json flag" {
  match
    parse_cli_command([
      "scan", "--rules", "custom-rules", "--output-json", "src",
    ]) {
    Scan(options) => {
      inspect(options.scan_root, content="src")
      assert_true(options.output_json)
      assert_false(options.verbose)
    }
    _ => fail("unexpected command")
  }
}

///|
test "cli args parse repeated scan excludes before scan root" {
  match
    parse_cli_command([
      "scan", "--rules", "custom-rules", "--exclude", "./vendor/", "--exclude=generated.mbt",
      "src",
    ]) {
    Scan(options) => {
      expect_rules_root(options, "custom-rules")
      inspect(options.scan_root, content="src")
      assert_eq(options.excludes, ["vendor", "generated.mbt"])
      assert_false(options.verbose)
    }
    _ => fail("unexpected command")
  }
}

///|
test "cli args parse repeated scan disabled rules before scan root" {
  match
    parse_cli_command([
      "scan", "--rules", "custom-rules", "--disable", "target", "--disable=other",
      "--disable", "third", "--disable", "last", "src",
    ]) {
    Scan(options) => {
      expect_rules_root(options, "custom-rules")
      inspect(options.scan_root, content="src")
      assert_eq(options.disabled_rules, ["target", "other", "third", "last"])
      assert_false(options.verbose)
    }
    _ => fail("unexpected command")
  }
}

///|
test "cli args reject json matcher flag" {
  expect_cli_usage(
    ["scan", "--rules", "custom-rules", "--json-matcher", "src"],
    2,
  )
}

///|
test "cli args parse argparse option input forms" {
  match parse_cli_command(["scan", "--rules=inline-rules"]) {
    Scan(options) => {
      expect_rules_root(options, "inline-rules")
      expect_no_patterns(options)
      inspect(options.scan_root, content=".")
      assert_false(options.verbose)
    }
    _ => fail("unexpected inline command")
  }
  match parse_cli_command(["scan", "-r", "short-rules", "src"]) {
    Scan(options) => {
      expect_rules_root(options, "short-rules")
      expect_no_patterns(options)
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
    Scan(options) => {
      expect_rules_root(options, "new-rules")
      expect_no_patterns(options)
      inspect(options.scan_root, content="src")
      assert_false(options.verbose)
    }
    _ => fail("unexpected command")
  }
}

///|
test "cli args parse anonymous patterns without rules root" {
  match
    parse_cli_command([
      "scan", "--pattern", "target()", "--pattern", "other()", "src",
    ]) {
    Scan(options) => {
      assert_true(options.rules_root is None)
      assert_eq(options.patterns.length(), 2)
      expect_pattern_shape(options, 0, "target()")
      expect_pattern_shape(options, 1, "other()")
      assert_eq(options.patterns[0].guards.length(), 0)
      assert_eq(options.patterns[1].guards.length(), 0)
      inspect(options.scan_root, content="src")
      assert_false(options.verbose)
    }
    _ => fail("unexpected command")
  }
}

///|
test "cli args parse anonymous pattern guard" {
  match
    parse_cli_command([
      "scan", "--pattern", "$(callee:id)()", "--guard", "{$callee: \"^safe_\"}",
      "src",
    ]) {
    Scan(options) => {
      assert_true(options.rules_root is None)
      assert_eq(options.patterns.length(), 1)
      expect_pattern_shape(options, 0, "$(callee:id)()")
      expect_pattern_guard(options, 0, "$callee", "^safe_")
      inspect(options.scan_root, content="src")
    }
    _ => fail("unexpected command")
  }
}

///|
test "cli args parse multiple anonymous pattern guard pairs in order" {
  match
    parse_cli_command([
      "scan", "--pattern", "$(callee:id)()", "--guard", "{$callee: \"^safe_\"}",
      "--pattern", "sink($(value:const))", "--guard", "{$value: \"^ok$\"}", "src",
    ]) {
    Scan(options) => {
      assert_eq(options.patterns.length(), 2)
      expect_pattern_shape(options, 0, "$(callee:id)()")
      expect_pattern_shape(options, 1, "sink($(value:const))")
      expect_pattern_guard(options, 0, "$callee", "^safe_")
      expect_pattern_guard(options, 1, "$value", "^ok$")
      inspect(options.scan_root, content="src")
    }
    _ => fail("unexpected command")
  }
}

///|
test "cli args reject guard without pattern and duplicate pattern guard" {
  expect_cli_usage(
    ["scan", "--rules", "custom-rules", "--guard", "{$callee: \"^safe_\"}"],
    2,
  )
  expect_cli_usage(
    [
      "scan", "--pattern", "$(callee:id)()", "--guard", "{$callee: \"^safe_\"}",
      "--guard", "{$callee: \"^other\"}", "src",
    ],
    2,
  )
}

///|
test "cli args reject malformed guard yaml" {
  expect_cli_usage(
    ["scan", "--pattern", "$(callee:id)()", "--guard", "{", "src"],
    2,
  )
  expect_cli_usage(
    ["scan", "--pattern", "$(callee:id)()", "--guard", "[]", "src"],
    2,
  )
  expect_cli_usage(
    ["scan", "--pattern", "$(callee:id)()", "--guard", "{$callee: 1}", "src"],
    2,
  )
}

///|
test "cli args reject missing rules value" {
  expect_cli_usage(["scan", "--rules"], 2)
}

///|
test "cli args reject missing exclusion option values" {
  expect_cli_usage(["scan", "--rules", "custom-rules", "--exclude"], 2)
  expect_cli_usage(["scan", "--rules", "custom-rules", "--disable"], 2)
}

///|
test "cli args reject legacy exclusion options" {
  expect_cli_usage(
    ["scan", "--rules", "custom-rules", "--exclude-dir", "vendor"],
    2,
  )
  expect_cli_usage(
    ["scan", "--rules", "custom-rules", "--exclude-rule", "target"],
    2,
  )
  expect_cli_usage(
    ["scan", "--rules", "custom-rules", "--exclude-rules", "target"],
    2,
  )
}

///|
test "cli args reject multiple values after one exclusion option" {
  expect_cli_usage(
    [
      "scan", "--rules", "custom-rules", "src", "--exclude", "vendor", "generated",
    ],
    2,
  )
  expect_cli_usage(
    ["scan", "--rules", "custom-rules", "src", "--disable", "target", "other"],
    2,
  )
}

///|
test "cli args reject scan builtin rules flag" {
  expect_cli_usage(["scan", "--enable-builtin-rules", "src"], 2)
}

///|
test "cli args parse lint with builtin rules and default scan root" {
  match parse_cli_command(["lint"]) {
    Lint(options) => {
      assert_true(options.rules_root is None)
      assert_true(options.rule_file is None)
      expect_no_patterns(options)
      inspect(options.scan_root, content=".")
      assert_true(options.excludes.is_empty())
      assert_true(options.disabled_rules.is_empty())
      assert_false(options.verbose)
      assert_false(options.no_color)
      assert_false(options.output_json)
    }
    _ => fail("unexpected command")
  }
}

///|
test "cli args parse lint scan options in addition to builtin rules" {
  match
    parse_cli_command(
      [
        "lint", "--rules", "custom-rules", "--rule", "custom-rules/example.yaml",
        "--pattern", "$(callee:id)()", "--guard", "{$callee: \"^safe_\"}", "--exclude",
        "./vendor/", "--disable", "moonbitlang/match_option", "--verbose", "--output-json",
        "src",
      ],
      env={ "NO_COLOR": "1" },
    ) {
    Lint(options) => {
      expect_rules_root(options, "custom-rules")
      expect_rule_file(options, "custom-rules/example.yaml")
      assert_eq(options.patterns.length(), 1)
      expect_pattern_shape(options, 0, "$(callee:id)()")
      expect_pattern_guard(options, 0, "$callee", "^safe_")
      inspect(options.scan_root, content="src")
      assert_eq(options.excludes, ["vendor"])
      assert_eq(options.disabled_rules, ["moonbitlang/match_option"])
      assert_true(options.verbose)
      assert_true(options.no_color)
      assert_true(options.output_json)
    }
    _ => fail("unexpected command")
  }
}

///|
test "cli args reject redundant lint builtin rules flag" {
  expect_cli_usage(["lint", "--enable-builtin-rules"], 2)
}

///|
test "cli args render argparse help" {
  let help = moongrep_command.render_help()
  assert_true(help.has_prefix("Usage: moongrep <command>"))
  assert_true(help.contains("scan"))
  assert_true(help.contains("lint"))
  assert_true(help.contains("docs"))
  let lint_help = lint_command.render_help()
  assert_true(lint_help.contains("embedded builtin rules"))
  assert_false(lint_help.contains("--enable-builtin-rules"))
  assert_false(lint_help.contains("[default: ./.moongrep/rules]"))
  assert_true(lint_help.contains("Directory or .mbt file to scan."))
  let scan_help = scan_command.render_help()
  assert_false(scan_help.contains("--enable-builtin-rules"))
  assert_true(scan_help.contains("[default: ./.moongrep/rules]"))
  assert_true(scan_help.contains("Directory or .mbt file to scan."))
}

///|
test "cli args from runtime drop executable name" {
  match
    parse_cli_command(
      runtime_cli_args(["moongrep", "scan", "--rules", "custom-rules", "src"]),
    ) {
    Scan(options) => {
      expect_rules_root(options, "custom-rules")
      expect_no_patterns(options)
      inspect(options.scan_root, content="src")
      assert_false(options.verbose)
    }
    _ => fail("unexpected command")
  }
}
