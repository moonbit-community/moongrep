///|
fn parse_single_scan_impl(source : String) -> @untyped_cst.CstNode raise {
  let parsed = @untyped_cst.parse_structure(source, name="scan test")
  guard parsed.diagnostics_view().is_empty() else {
    fail("expected source to parse")
  }
  let nodes = @cst.toplevel_nodes(parsed.root())
  guard nodes is [node] else { fail("expected exactly one impl") }
  node
}

///|
fn parsed_impl_moongrep_skip_attributes(
  source : String,
) -> MoongrepSkipAttributes raise {
  impl_moongrep_skip_attributes(parse_single_scan_impl(source))
}

///|
test "bare moongrep skip supports five top-level item kinds" {
  let sources = [
    (
      #|#moongrep.skip
      #|fn skipped { 1 }
    ),
    (
      #|#moongrep.skip
      #|impl Show for Int with output(self, logger) { 1 }
    ),
    (
      #|#moongrep.skip
      #|let skipped = 1
    ),
    (
      #|#moongrep.skip
      #|test "skipped" { 1 }
    ),
    (
      #|#moongrep.skip
      #|enumview ValueView { Value(Int) } for Int with value_view(value) { Value(value) }
    ),
  ]
  for source in sources {
    let skip = parsed_impl_moongrep_skip_attributes(source)
    assert_true(skip.skip_structural)
    assert_true(skip.invalid_payload_locations.is_empty())
  }
}

///|
test "moongrep skip ignores unrelated qualifiers and names" {
  let sources = [
    (
      #|#skip
      #|fn unqualified { 1 }
    ),
    (
      #|#other.skip
      #|fn other_qualified { 1 }
    ),
    (
      #|#moongrep.skipper(
      #|fn adjacent_name { 1 }
    ),
  ]
  for source in sources {
    let skip = parsed_impl_moongrep_skip_attributes(source)
    assert_false(skip.skip_structural)
    assert_true(skip.invalid_payload_locations.is_empty())
  }
}

///|
test "moongrep skip rejects every payload form" {
  let sources = [
    (
      #|#moongrep.skip()
      #|fn empty_payload { 1 }
    ),
    (
      #|#moongrep.skip(true)
      #|fn true_payload { 1 }
    ),
    (
      #|#moongrep.skip(false)
      #|fn false_payload { 1 }
    ),
    (
      #|#moongrep.skip(Debug)
      #|fn arbitrary_payload { 1 }
    ),
    (
      #|#moongrep.skip(
      #|fn malformed_payload { 1 }
    ),
  ]
  for source in sources {
    let skip = parsed_impl_moongrep_skip_attributes(source)
    assert_false(skip.skip_structural)
    assert_eq(skip.invalid_payload_locations.length(), 1)
  }
}

///|
test "bare skip remains effective beside invalid payloads" {
  let skip = parsed_impl_moongrep_skip_attributes(
    (
      #|#moongrep.skip(false)
      #|#other.skip
      #|#moongrep.skip
      #|#moongrep.skip()
      #|fn mixed_attributes { 1 }
    ),
  )
  assert_true(skip.skip_structural)
  assert_eq(skip.invalid_payload_locations.length(), 2)
}

///|
fn skip_scan_options() -> CliOptions {
  {
    rules_root: Some("testdata/skip-structural/rules"),
    rule_file: None,
    patterns: [],
    scan_root: "testdata/skip-structural/src",
    excludes: [],
    disabled_rules: [],
    verbose: false,
    no_color: false,
    output_json: false,
  }
}

///|
fn excluded_entry_scan_options() -> CliOptions {
  let (rules_root, scan_root, excludes) = if scan_uses_windows_paths() {
    (
      ".\\e2etests\\rules/structural\\.",
      ".\\testdata/exclude-dirs\\.",
      ["IGNORED\\", ".\\testdata/exclude-dirs\\GENERATED\\\\", "EXCLUDED.MBT"],
    )
  } else {
    (
      "e2etests/rules/structural",
      "testdata/exclude-dirs",
      [
        "ignored/", "./testdata/exclude-dirs/generated/", "./testdata/exclude-dirs/excluded.mbt",
      ],
    )
  }
  {
    rules_root: Some(rules_root),
    rule_file: None,
    patterns: [],
    scan_root,
    excludes,
    disabled_rules: [],
    verbose: true,
    no_color: false,
    output_json: false,
  }
}

///|
fn excluded_scan_root_options() -> CliOptions {
  {
    rules_root: Some("e2etests/rules/structural"),
    rule_file: None,
    patterns: [],
    scan_root: "testdata/exclude-dirs/hit.mbt",
    excludes: ["hit.mbt"],
    disabled_rules: [],
    verbose: false,
    no_color: false,
    output_json: false,
  }
}

///|
fn single_rule_file_scan_options() -> CliOptions {
  {
    rules_root: None,
    rule_file: Some("testdata/recursive-rule-discovery-rules/nested/b.yml"),
    patterns: [],
    scan_root: "testdata/recursive-rule-discovery-src",
    excludes: [],
    disabled_rules: [],
    verbose: false,
    no_color: false,
    output_json: false,
  }
}

///|
fn guarded_cli_pattern_scan_options() -> CliOptions {
  {
    rules_root: None,
    rule_file: None,
    patterns: [
      {
        shape: "$(callee:id)($(value:const))",
        guards: { "$callee": "^@html\\.render$", "$value": "raw" },
        match_mode: Default,
      },
    ],
    scan_root: "testdata/guard",
    excludes: [],
    disabled_rules: [],
    verbose: false,
    no_color: false,
    output_json: false,
  }
}

///|
fn verbose_rules_scan_options() -> CliOptions {
  {
    rules_root: Some("testdata/recursive-rule-discovery-rules"),
    rule_file: None,
    patterns: [],
    scan_root: "testdata/recursive-rule-discovery-src",
    excludes: [],
    disabled_rules: [],
    verbose: true,
    no_color: false,
    output_json: false,
  }
}

///|
fn block_prefilter_scan_options() -> CliOptions {
  {
    rules_root: Some("e2etests/rules/prefilter"),
    rule_file: None,
    patterns: [],
    scan_root: "testdata/prefilter-impl",
    excludes: [],
    disabled_rules: [],
    verbose: false,
    no_color: false,
    output_json: false,
  }
}

///|
fn irrelevant_broken_block_scan_options() -> CliOptions {
  {
    rules_root: Some("e2etests/rules/prefilter"),
    rule_file: None,
    patterns: [],
    scan_root: "testdata/prefilter-block/irrelevant-broken.mbt",
    excludes: [],
    disabled_rules: [],
    verbose: false,
    no_color: false,
    output_json: false,
  }
}

///|
fn matched_broken_block_scan_options() -> CliOptions {
  {
    rules_root: Some("e2etests/rules/prefilter"),
    rule_file: None,
    patterns: [],
    scan_root: "testdata/prefilter-block/matched-broken.mbt",
    excludes: [],
    disabled_rules: [],
    verbose: false,
    no_color: false,
    output_json: false,
  }
}

///|
fn disabled_rule_scan_options() -> CliOptions {
  {
    rules_root: Some("e2etests/rules/prefilter"),
    rule_file: None,
    patterns: [],
    scan_root: "testdata/prefilter-impl",
    excludes: [],
    disabled_rules: ["target"],
    verbose: true,
    no_color: false,
    output_json: false,
  }
}

///|
fn unknown_disabled_rule_scan_options() -> CliOptions {
  {
    rules_root: Some("e2etests/rules/prefilter"),
    rule_file: None,
    patterns: [],
    scan_root: "testdata/prefilter-impl",
    excludes: [],
    disabled_rules: ["missing"],
    verbose: false,
    no_color: false,
    output_json: false,
  }
}

///|
fn builtin_api_options() -> CliOptions {
  {
    rules_root: None,
    rule_file: None,
    patterns: [],
    scan_root: "testdata/builtin-rules",
    excludes: [],
    disabled_rules: [],
    verbose: false,
    no_color: true,
    output_json: false,
  }
}

///|
fn non_bmp_scan_options() -> CliOptions {
  {
    rules_root: None,
    rule_file: None,
    patterns: [
      {
        shape: "let $(name:id) = $(value:exp)",
        guards: Map([]),
        match_mode: Default,
      },
    ],
    scan_root: "testdata/scan-non-bmp/single.mbt",
    excludes: [],
    disabled_rules: [],
    verbose: false,
    no_color: false,
    output_json: false,
  }
}

///|
priv struct CapturedScanEvents {
  traces : Array[String]
  hits : Array[ScanHit]
  warnings : Array[ScanWarning]
}

///|
async fn capture_scan_events(
  mode : ScanMode,
  options : CliOptions,
) -> CapturedScanEvents {
  let traces : Array[String] = []
  let hits : Array[ScanHit] = []
  let warnings : Array[ScanWarning] = []
  scan_events(mode, options, event => {
    match event {
      Trace(message) => traces.push(message)
      Warning(warning) => warnings.push(warning)
      Hit(hit) => hits.push(hit)
    }
  })
  { traces, hits, warnings, }
}

///|
fn scan_hit_line_summary(hit : ScanHit) -> String {
  "\{hit.finding.rule_id}:\{hit.finding.loc.start.lnum}"
}

///|
fn string_array_contains(items : Array[String], expected : String) -> Bool {
  for item in items {
    if item == expected {
      return true
    }
  }
  false
}

///|
async test "scan enforces moongrep skip structural and taint contract" {
  let result = capture_scan_events(Scan, skip_scan_options())
  let summaries : Array[String] = []
  for hit in result.hits {
    summaries.push(scan_hit_line_summary(hit))
  }
  assert_eq(summaries, ["structural:9", "structural:21", "taint:28"])
  let rendered_warnings : Array[String] = []
  for warning in result.warnings {
    rendered_warnings.push(render_scan_warning(warning))
  }
  inspect(
    rendered_warnings.join("\n"),
    content=native_scan_test_path(
      (
        #|warning: testdata/skip-structural/src/hit.mbt:7:1-7:22: #moongrep.skip does not accept a payload; use bare #moongrep.skip
        #|warning: testdata/skip-structural/src/hit.mbt:13:1-13:17: #moongrep.skip does not accept a payload; use bare #moongrep.skip
      ),
    ),
  )
}

///|
async test "scan and lint streaming modes select their rule sources" {
  let options = builtin_api_options()
  let scan_stdout : Array[String] = []
  let scan_stderr : Array[String] = []
  run_scan_mode_command_with_writers(
    Scan,
    options,
    output => scan_stdout.push(output),
    output => scan_stderr.push(output),
  )
  inspect(scan_stdout.join(""), content="no match hits\n")
  assert_true(scan_stderr.is_empty())
  let lint_stdout : Array[String] = []
  let lint_stderr : Array[String] = []
  run_scan_mode_command_with_writers(
    Lint,
    options,
    output => lint_stdout.push(output),
    output => lint_stderr.push(output),
  )
  let lint_output = lint_stdout.join("")
  assert_true(lint_output.contains("rule: moonbitlang/inspect_number"))
  assert_true(lint_output.contains("rule: moonbitlang/match_option"))
  assert_true(lint_stderr.is_empty())
}

///|
async test "scan renders non-BMP matches with Unicode code point columns" {
  let result = capture_scan_events(Scan, non_bmp_scan_options())
  guard result.hits is [hit, ..] else { fail("expected a non-BMP scan hit") }
  inspect(
    format_location(hit.finding.file, hit.finding.loc),
    content=native_scan_test_path("testdata/scan-non-bmp/single.mbt:3:3-3:23"),
  )
  inspect(hit.matched_source, content="let str = \"Hello🤣🤣🤣\"")
  assert_true(
    render_scan_hit(hit).contains(
      "3 |   \u{1b}[93mlet str = \"Hello🤣🤣🤣\"\u{1b}[39m",
    ),
  )
  let json_output = render_scan_hit_json(hit)
  ignore(@json.parse(json_output))
  assert_true(
    json_output.contains(
      "\"range\":{\"start\":{\"line\":3,\"column\":3},\"end\":{\"line\":3,\"column\":23}}",
    ),
  )
  assert_true(
    json_output.contains(
      "\"matched_source\":\"let str = \\\"Hello🤣🤣🤣\\\"\"",
    ),
  )
}

///|
async test "scan excludes configured file and directory entries" {
  let result = capture_scan_events(Scan, excluded_entry_scan_options())
  let summaries : Array[String] = []
  for hit in result.hits {
    summaries.push(hit.finding.file)
  }
  assert_eq(summaries, [native_scan_test_path("testdata/exclude-dirs/hit.mbt")])
  assert_true(
    string_array_contains(
      result.traces,
      native_scan_test_path(
        "moongrep scan: skipping testdata/exclude-dirs/ignored",
      ),
    ),
  )
  assert_true(
    string_array_contains(
      result.traces,
      native_scan_test_path(
        "moongrep scan: skipping testdata/exclude-dirs/generated",
      ),
    ),
  )
  assert_true(
    string_array_contains(
      result.traces,
      native_scan_test_path(
        "moongrep scan: skipping testdata/exclude-dirs/excluded.mbt",
      ),
    ),
  )
}

///|
async test "scan does not apply excludes to the explicit scan root" {
  let result = capture_scan_events(Scan, excluded_scan_root_options())
  let files : Array[String] = []
  for hit in result.hits {
    files.push(hit.finding.file)
  }
  assert_eq(files, [native_scan_test_path("testdata/exclude-dirs/hit.mbt")])
}

///|
async test "scan loads only the configured single rule file" {
  let result = capture_scan_events(Scan, single_rule_file_scan_options())
  let summaries : Array[String] = []
  for hit in result.hits {
    summaries.push(scan_hit_line_summary(hit))
  }
  assert_eq(summaries, ["example:4"])
}

///|
async test "scan anonymous guarded pattern filters matches" {
  let result = capture_scan_events(Scan, guarded_cli_pattern_scan_options())
  let summaries : Array[String] = []
  for hit in result.hits {
    summaries.push(scan_hit_line_summary(hit))
  }
  assert_eq(summaries, ["$(callee:id)($(value:const)):2"])
}

///|
async test "scan plan keeps block level prefilter distribution" {
  let result = capture_scan_events(Scan, block_prefilter_scan_options())
  let summaries : Array[String] = []
  for hit in result.hits {
    summaries.push(scan_hit_line_summary(hit))
  }
  assert_eq(summaries, ["target:2", "other:6"])
}

///|
async test "scan does not parse unmatched source blocks" {
  let result = capture_scan_events(Scan, irrelevant_broken_block_scan_options())
  let summaries : Array[String] = []
  for hit in result.hits {
    summaries.push(scan_hit_line_summary(hit))
  }
  assert_eq(summaries, ["target:6"])
  assert_true(result.warnings.is_empty())
}

///|
async test "scan isolates matching source block parse failures" {
  let result = capture_scan_events(Scan, matched_broken_block_scan_options())
  let summaries : Array[String] = []
  for hit in result.hits {
    summaries.push(scan_hit_line_summary(hit))
  }
  assert_eq(summaries, ["other:3", "target:10"])
  guard result.warnings is [Parse(skipped)] else {
    fail("expected one skipped source block")
  }
  assert_true(skipped.block_start_line == Some(5))
  assert_true(
    render_scan_warning(Parse(skipped)).has_prefix(
      native_scan_test_path(
        "warning: skipping testdata/prefilter-block/matched-broken.mbt block starting at line 5: parse failed due to ",
      ),
    ),
  )
}

///|
async test "scan disables configured rule ids before planning" {
  let result = capture_scan_events(Scan, disabled_rule_scan_options())
  let summaries : Array[String] = []
  for hit in result.hits {
    summaries.push(scan_hit_line_summary(hit))
  }
  assert_eq(summaries, ["other:6"])
  assert_eq(result.traces, [
    "moongrep scan: loaded rule other",
    native_scan_test_path("moongrep scan: entering testdata/prefilter-impl"),
    native_scan_test_path(
      "moongrep scan: file testdata/prefilter-impl/hits.mbt",
    ),
  ])
}

///|
async test "scan rejects unknown disabled rule ids" {
  try capture_scan_events(Scan, unknown_disabled_rule_scan_options()) catch {
    CliError::Usage(message~) as err => {
      assert_eq(err.exit_code(), 2)
      inspect(
        message,
        content=(
          #|error: unknown rule id in --disable
          #|  source: missing
          #|  help: use the exact id of a loaded rule
        ),
      )
    }
    err => fail("unexpected error \{err}")
  } noraise {
    _ => fail("expected CLI usage error")
  }
}

///|
async test "scan keeps rule disabling case sensitive on every host" {
  let rules = load_rule_directory("e2etests/rules/prefilter")
  try disable_scan_rules(rules, ["TARGET"]) catch {
    CliError::Usage(message~) =>
      inspect(
        message,
        content=(
          #|error: unknown rule id in --disable
          #|  source: TARGET
          #|  help: use the exact id of a loaded rule
        ),
      )
    err => fail("unexpected error \{err}")
  } noraise {
    _ => fail("expected case-mismatched rule id rejection")
  }
}

///|
async test "scan classifies rule source, rule content, and scan input failures" {
  try load_rule_directory("testdata/missing-rule-root") catch {
    CliError::RuleSource(message~) as err => {
      assert_eq(err.exit_code(), 4)
      assert_true(message.contains("error: could not read rule directory"))
      assert_true(message.contains("testdata/missing-rule-root"))
      assert_false(message.contains("OSError"))
      assert_false(message.contains("@fs."))
    }
    err => fail("unexpected missing rule source error \{err}")
  } noraise {
    _ => fail("expected missing rule source error")
  }
  try load_rule_directory("testdata/empty-rule-root") catch {
    CliError::RuleSource(message~) as err => {
      assert_eq(err.exit_code(), 4)
      inspect(
        message,
        content=native_scan_test_path(
          (
            #|error: no rules found
            #|  source: testdata/empty-rule-root
            #|  reason: the directory contains no YAML rule files
            #|  help: add a .yaml or .yml rule file or choose another --rules directory
          ),
        ),
      )
    }
    err => fail("unexpected rule source error \{err}")
  } noraise {
    _ => fail("expected rule source error")
  }
  let invalid_pattern_options : CliOptions = {
    rules_root: None,
    rule_file: None,
    patterns: [{ shape: "target(", guards: Map([]), match_mode: Default, }],
    scan_root: "testdata/custom-rules",
    excludes: [],
    disabled_rules: [],
    verbose: false,
    no_color: true,
    output_json: false,
  }
  try capture_scan_events(Scan, invalid_pattern_options) catch {
    CliError::RuleContent(message~) as err => {
      assert_eq(err.exit_code(), 5)
      inspect(
        message,
        content=(
          #|error: invalid anonymous pattern
          #|  source: --pattern
          #|  pattern:
          #|    target(
          #|  reason: the pattern is not a valid MoonBit expression: Unexpected end of file, missing simple expression here.
          #|  help: fix the pattern passed to --pattern and try again
        ),
      )
      assert_false(message.contains("RuleLoadError"))
    }
    err => fail("unexpected rule content error \{err}")
  } noraise {
    _ => fail("expected rule content error")
  }
  try load_rule_file("testdata/exit-codes/invalid.yaml") catch {
    CliError::RuleContent(message~) as err => {
      assert_eq(err.exit_code(), 5)
      inspect(
        message,
        content=native_scan_test_path(
          (
            #|error: invalid rule
            #|  source: testdata/exit-codes/invalid.yaml
            #|  reason: line 2, column 1: while parsing a node, did not find expected node content
            #|  help: fix the rule and try again
          ),
        ),
      )
      assert_false(message.contains("YamlError"))
    }
    err => fail("unexpected YAML rule content error \{err}")
  } noraise {
    _ => fail("expected YAML rule content error")
  }
  let missing_scan_root_options : CliOptions = {
    rules_root: Some("e2etests/rules/structural"),
    rule_file: None,
    patterns: [],
    scan_root: "testdata/does-not-exist",
    excludes: [],
    disabled_rules: [],
    verbose: false,
    no_color: true,
    output_json: false,
  }
  try capture_scan_events(Scan, missing_scan_root_options) catch {
    CliError::ScanInput(message~) as err => {
      assert_eq(err.exit_code(), 6)
      assert_true(message.contains("error: could not access scan path"))
      assert_true(
        message.contains(native_scan_test_path("testdata/does-not-exist")),
      )
      assert_false(message.contains("OSError"))
      assert_false(message.contains("@fs."))
    }
    err => fail("unexpected scan input error \{err}")
  } noraise {
    _ => fail("expected scan input error")
  }
}

///|
async test "scan verbose lists loaded rule ids before traversal" {
  let result = capture_scan_events(Scan, verbose_rules_scan_options())
  assert_eq(result.traces, [
    "moongrep scan: loaded rule example",
    "moongrep scan: loaded rule nested/example",
    native_scan_test_path(
      "moongrep scan: entering testdata/recursive-rule-discovery-src",
    ),
    native_scan_test_path(
      "moongrep scan: file testdata/recursive-rule-discovery-src/hits.mbt",
    ),
  ])
}
