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
    patterns: [],
    scan_root: "testdata/skip-structural/src",
    verbose: false,
    enable_builtin_rules: false,
    matcher: @rule_model.MatcherBackend::AstMatcher,
  }
}

///|
fn scan_hit_line_summary(hit : ScanHit) -> String {
  "\{hit.finding.rule_id}:\{hit.finding.loc.start.lnum}"
}

///|
test "scan skips structural rules only for moongrep skip attribute" {
  let result = collect_directory_hits(skip_scan_options())
  let summaries : Array[String] = []
  for hit in result.hits {
    summaries.push(scan_hit_line_summary(hit))
  }
  debug_inspect(summaries, content="[\"structural:7\", \"taint:13\"]")
}
