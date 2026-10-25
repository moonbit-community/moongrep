///|
fn strict_taint_options(file : String, strict : Bool) -> CliOptions {
  {
    rules_root: None,
    rule_file: Some("e2etests/testdata/taint-cfg/rules.yaml"),
    patterns: [],
    scan_root: "e2etests/testdata/taint-cfg/" + file,
    excludes: [],
    disabled_rules: [],
    verbose: false,
    no_color: true,
    output_json: true,
    strict_taint: strict,
  }
}

///|
test "strict taint parses for scan and lint and defaults off" {
  guard parse_cli_command(["scan", "--strict-taint"]) is Scan(scan) else {
    fail("expected scan")
  }
  guard parse_cli_command(["lint", "--strict-taint"]) is Lint(lint) else {
    fail("expected lint")
  }
  guard parse_cli_command(["scan"]) is Scan(ordinary) else {
    fail("expected scan")
  }
  debug_inspect(
    (scan.strict_taint, lint.strict_taint, ordinary.strict_taint),
    content="(true, true, false)",
  )
}

///|
async test "taint incomplete warns in JSON and continues with later functions" {
  for file in ["unsupported.mbt", "growth.mbt", "parse.mbt"] {
    let output : Array[String] = []
    let errors : Array[String] = []
    run_scan_mode_command_with_writers(
      Scan,
      strict_taint_options(file, false),
      text => output.push(text),
      text => errors.push(text),
    )
    inspect(output.length(), content="1")
    let records = errors.map(text => @json.parse(text))
    let incomplete = records.filter(record => {
      record is { "category": String("taint_incomplete"), .. }
    })
    inspect(incomplete.length(), content="1")
    guard incomplete[0]
      is {
        "file": String(_),
        "range": Object(_),
        "rule_ids": Array([String("cfg")]),
        "reason": String(_),
        ..
      } else {
      fail("expected complete diagnostic fields")
    }
  }
}

///|
async test "strict taint finishes scanning then exits with code eight" {
  for file in ["unsupported.mbt", "growth.mbt", "parse.mbt"] {
    let output : Array[String] = []
    let errors : Array[String] = []
    try
      run_scan_mode_command_with_writers(
        Scan,
        strict_taint_options(file, true),
        text => output.push(text),
        text => errors.push(text),
      )
    catch {
      CliError::TaintIncomplete(..) as err => {
        assert_eq(err.exit_code(), 8)
        assert_true(err.render_json().contains("taint_incomplete"))
        assert_eq(output.length(), 1)
        assert_true(errors.any(text => text.contains("taint_incomplete")))
      }
      err => fail("unexpected error \{err}")
    } noraise {
      _ => fail("expected strict taint failure")
    }
  }
}
