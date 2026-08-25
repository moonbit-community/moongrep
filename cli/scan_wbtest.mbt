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
  {
    rules_root: Some("e2etests/rules/structural"),
    rule_file: None,
    patterns: [],
    scan_root: "testdata/exclude-dirs",
    excludes: [
      "ignored/", "./testdata/exclude-dirs/generated/", "./testdata/exclude-dirs/excluded.mbt",
    ],
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
  let result = collect_directory_hits(Scan, skip_scan_options())
  let summaries : Array[String] = []
  for hit in result.hits {
    summaries.push(scan_hit_line_summary(hit))
  }
  debug_inspect(
    summaries,
    content="[\"structural:9\", \"structural:21\", \"taint:28\"]",
  )
  inspect(
    render_scan_warnings(result.warnings),
    content=(
      #|warning: testdata/skip-structural/src/hit.mbt:7:1-7:22: #moongrep.skip does not accept a payload; use bare #moongrep.skip
      #|warning: testdata/skip-structural/src/hit.mbt:13:1-13:17: #moongrep.skip does not accept a payload; use bare #moongrep.skip
    ),
  )
}

///|
async test "scan and lint render APIs select their rule sources" {
  let options = builtin_api_options()
  inspect(render_scan_command(options), content="no match hits")
  let lint_output = render_lint_command(options)
  assert_true(lint_output.contains("rule: moonbitlang/inspect_number"))
  assert_true(lint_output.contains("rule: moonbitlang/match_option"))
}

///|
async test "scan excludes configured file and directory entries" {
  let result = collect_directory_hits(Scan, excluded_entry_scan_options())
  let summaries : Array[String] = []
  for hit in result.hits {
    summaries.push(hit.finding.file)
  }
  debug_inspect(summaries, content="[\"testdata/exclude-dirs/hit.mbt\"]")
  assert_true(
    string_array_contains(
      result.scan_trace,
      "moongrep scan: skipping testdata/exclude-dirs/ignored",
    ),
  )
  assert_true(
    string_array_contains(
      result.scan_trace,
      "moongrep scan: skipping testdata/exclude-dirs/generated",
    ),
  )
  assert_true(
    string_array_contains(
      result.scan_trace,
      "moongrep scan: skipping testdata/exclude-dirs/excluded.mbt",
    ),
  )
}

///|
async test "scan does not apply excludes to the explicit scan root" {
  let result = collect_directory_hits(Scan, excluded_scan_root_options())
  let files : Array[String] = []
  for hit in result.hits {
    files.push(hit.finding.file)
  }
  debug_inspect(files, content="[\"testdata/exclude-dirs/hit.mbt\"]")
}

///|
async test "scan loads only the configured single rule file" {
  let result = collect_directory_hits(Scan, single_rule_file_scan_options())
  let summaries : Array[String] = []
  for hit in result.hits {
    summaries.push(scan_hit_line_summary(hit))
  }
  debug_inspect(summaries, content="[\"example:4\"]")
}

///|
async test "scan anonymous guarded pattern filters matches" {
  let result = collect_directory_hits(Scan, guarded_cli_pattern_scan_options())
  let summaries : Array[String] = []
  for hit in result.hits {
    summaries.push(scan_hit_line_summary(hit))
  }
  debug_inspect(summaries, content="[\"$(callee:id)($(value:const)):2\"]")
}

///|
async test "scan plan keeps block level prefilter distribution" {
  let result = collect_directory_hits(Scan, block_prefilter_scan_options())
  let summaries : Array[String] = []
  for hit in result.hits {
    summaries.push(scan_hit_line_summary(hit))
  }
  debug_inspect(summaries, content="[\"target:2\", \"other:6\"]")
}

///|
async test "scan does not parse unmatched source blocks" {
  let result = collect_directory_hits(
    Scan,
    irrelevant_broken_block_scan_options(),
  )
  let summaries : Array[String] = []
  for hit in result.hits {
    summaries.push(scan_hit_line_summary(hit))
  }
  debug_inspect(summaries, content="[\"target:6\"]")
  assert_true(result.warnings.is_empty())
}

///|
async test "scan isolates matching source block parse failures" {
  let result = collect_directory_hits(Scan, matched_broken_block_scan_options())
  let summaries : Array[String] = []
  for hit in result.hits {
    summaries.push(scan_hit_line_summary(hit))
  }
  debug_inspect(summaries, content="[\"other:3\", \"target:10\"]")
  guard result.warnings is [Parse(skipped)] else {
    fail("expected one skipped source block")
  }
  assert_true(skipped.block_start_line == Some(5))
  assert_true(
    render_scan_warning(Parse(skipped)).has_prefix(
      "warning: skipping testdata/prefilter-block/matched-broken.mbt block starting at line 5: parse failed due to ",
    ),
  )
}

///|
async test "scan disables configured rule ids before planning" {
  let result = collect_directory_hits(Scan, disabled_rule_scan_options())
  let summaries : Array[String] = []
  for hit in result.hits {
    summaries.push(scan_hit_line_summary(hit))
  }
  debug_inspect(summaries, content="[\"other:6\"]")
  debug_inspect(
    result.scan_trace,
    content=(
      #|[
      #|  "moongrep scan: loaded rule other",
      #|  "moongrep scan: entering testdata/prefilter-impl",
      #|  "moongrep scan: file testdata/prefilter-impl/hits.mbt",
      #|]
    ),
  )
}

///|
async test "scan rejects unknown disabled rule ids" {
  try collect_directory_hits(Scan, unknown_disabled_rule_scan_options()) catch {
    CliError::Usage(message~) as err => {
      assert_eq(err.exit_code(), 2)
      inspect(message, content="unknown rule id in --disable: missing")
    }
    err => fail("unexpected error \{err}")
  } noraise {
    _ => fail("expected CLI usage error")
  }
}

///|
async test "scan classifies rule source, rule content, and scan input failures" {
  try load_rule_directory("testdata/empty-rule-root") catch {
    CliError::RuleSource(..) as err => assert_eq(err.exit_code(), 4)
    err => fail("unexpected rule source error \{err}")
  } noraise {
    _ => fail("expected rule source error")
  }
  let invalid_pattern_options : CliOptions = {
    rules_root: None,
    rule_file: None,
    patterns: [{ shape: "target(", guards: Map([]), match_mode: Default }],
    scan_root: "testdata/custom-rules",
    excludes: [],
    disabled_rules: [],
    verbose: false,
    no_color: true,
    output_json: false,
  }
  try collect_directory_hits(Scan, invalid_pattern_options) catch {
    CliError::RuleContent(..) as err => assert_eq(err.exit_code(), 5)
    err => fail("unexpected rule content error \{err}")
  } noraise {
    _ => fail("expected rule content error")
  }
  try load_rule_file("testdata/exit-codes/invalid.yaml") catch {
    CliError::RuleContent(message~) as err => {
      assert_eq(err.exit_code(), 5)
      assert_true(message.has_prefix("testdata/exit-codes/invalid.yaml: "))
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
  try collect_directory_hits(Scan, missing_scan_root_options) catch {
    CliError::ScanInput(..) as err => assert_eq(err.exit_code(), 6)
    err => fail("unexpected scan input error \{err}")
  } noraise {
    _ => fail("expected scan input error")
  }
}

///|
async test "scan verbose lists loaded rule ids before traversal" {
  let result = collect_directory_hits(Scan, verbose_rules_scan_options())
  debug_inspect(
    result.scan_trace,
    content=(
      #|[
      #|  "moongrep scan: loaded rule example",
      #|  "moongrep scan: loaded rule nested/example",
      #|  "moongrep scan: entering testdata/recursive-rule-discovery-src",
      #|  "moongrep scan: file testdata/recursive-rule-discovery-src/hits.mbt",
      #|]
    ),
  )
}
