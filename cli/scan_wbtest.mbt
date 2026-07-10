///|
fn parse_single_scan_impl(source : String) -> @syntax.Impl raise {
  let (impls, reports) = @parser.parse_string(source, name="scan test")
  guard reports is [] else { fail("expected source to parse") }
  let nodes = impls.to_array()
  guard nodes is [node] else { fail("expected exactly one impl") }
  node
}

///|
fn parsed_impl_has_moongrep_skip(source : String) -> Bool raise {
  impl_has_moongrep_skip(parse_single_scan_impl(source))
}

///|
test "scan recognizes only qualified moongrep skip attribute" {
  let qualified =
    #|#moongrep.skip
    #|fn skipped { 1 }
    #|
  let qualified_with_payload =
    #|#moongrep.skip(true)
    #|fn skipped_with_payload { 1 }
    #|
  let unqualified =
    #|#skip
    #|fn unqualified { 1 }
    #|
  let other_qualified =
    #|#other.skip
    #|fn other_qualified { 1 }
    #|
  assert_true(parsed_impl_has_moongrep_skip(qualified))
  assert_true(parsed_impl_has_moongrep_skip(qualified_with_payload))
  assert_false(parsed_impl_has_moongrep_skip(unqualified))
  assert_false(parsed_impl_has_moongrep_skip(other_qualified))
}

///|
fn skip_scan_options() -> CliOptions {
  {
    rules_root: Some("testdata/skip-structural/rules"),
    rule_file: None,
    patterns: [],
    scan_root: "testdata/skip-structural/src",
    exclude_dirs: [],
    exclude_rules: [],
    verbose: false,
    enable_builtin_rules: false,
    no_color: false,
    output_json: false,
  }
}

///|
fn exclude_dir_scan_options() -> CliOptions {
  {
    rules_root: Some("e2etests/rules/structural"),
    rule_file: None,
    patterns: [],
    scan_root: "testdata/exclude-dirs",
    exclude_dirs: ["ignored/", "./testdata/exclude-dirs/generated/"],
    exclude_rules: [],
    verbose: true,
    enable_builtin_rules: false,
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
    exclude_dirs: [],
    exclude_rules: [],
    verbose: false,
    enable_builtin_rules: false,
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
      },
    ],
    scan_root: "testdata/guard",
    exclude_dirs: [],
    exclude_rules: [],
    verbose: false,
    enable_builtin_rules: false,
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
    exclude_dirs: [],
    exclude_rules: [],
    verbose: true,
    enable_builtin_rules: false,
    no_color: false,
    output_json: false,
  }
}

///|
fn impl_prefilter_scan_options() -> CliOptions {
  {
    rules_root: Some("e2etests/rules/prefilter"),
    rule_file: None,
    patterns: [],
    scan_root: "testdata/prefilter-impl",
    exclude_dirs: [],
    exclude_rules: [],
    verbose: false,
    enable_builtin_rules: false,
    no_color: false,
    output_json: false,
  }
}

///|
fn exclude_rule_scan_options() -> CliOptions {
  {
    rules_root: Some("e2etests/rules/prefilter"),
    rule_file: None,
    patterns: [],
    scan_root: "testdata/prefilter-impl",
    exclude_dirs: [],
    exclude_rules: ["target"],
    verbose: true,
    enable_builtin_rules: false,
    no_color: false,
    output_json: false,
  }
}

///|
fn unknown_exclude_rule_scan_options() -> CliOptions {
  {
    rules_root: Some("e2etests/rules/prefilter"),
    rule_file: None,
    patterns: [],
    scan_root: "testdata/prefilter-impl",
    exclude_dirs: [],
    exclude_rules: ["missing"],
    verbose: false,
    enable_builtin_rules: false,
    no_color: false,
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
async test "scan skips structural rules only for moongrep skip attribute" {
  let result = collect_directory_hits(skip_scan_options())
  let summaries : Array[String] = []
  for hit in result.hits {
    summaries.push(scan_hit_line_summary(hit))
  }
  debug_inspect(summaries, content="[\"structural:7\", \"taint:13\"]")
}

///|
async test "scan excludes configured directory names" {
  let result = collect_directory_hits(exclude_dir_scan_options())
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
}

///|
async test "scan loads only the configured single rule file" {
  let result = collect_directory_hits(single_rule_file_scan_options())
  let summaries : Array[String] = []
  for hit in result.hits {
    summaries.push(scan_hit_line_summary(hit))
  }
  debug_inspect(summaries, content="[\"example:4\"]")
}

///|
async test "scan anonymous guarded pattern filters matches" {
  let result = collect_directory_hits(guarded_cli_pattern_scan_options())
  let summaries : Array[String] = []
  for hit in result.hits {
    summaries.push(scan_hit_line_summary(hit))
  }
  debug_inspect(summaries, content="[\"$(callee:id)($(value:const)):2\"]")
}

///|
async test "scan plan keeps impl level prefilter distribution" {
  let result = collect_directory_hits(impl_prefilter_scan_options())
  let summaries : Array[String] = []
  for hit in result.hits {
    summaries.push(scan_hit_line_summary(hit))
  }
  debug_inspect(summaries, content="[\"target:2\", \"other:6\"]")
}

///|
async test "scan excludes configured rule ids before planning" {
  let result = collect_directory_hits(exclude_rule_scan_options())
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
async test "scan rejects unknown exclude rule ids" {
  try collect_directory_hits(unknown_exclude_rule_scan_options()) catch {
    CliError::Usage(message~, exit_code=found) => {
      inspect(found, content="2")
      inspect(message, content="unknown rule id in --exclude-rules: missing")
    }
    err => fail("unexpected error \{err}")
  } noraise {
    _ => fail("expected CLI usage error")
  }
}

///|
async test "scan verbose lists loaded rule ids before traversal" {
  let result = collect_directory_hits(verbose_rules_scan_options())
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
