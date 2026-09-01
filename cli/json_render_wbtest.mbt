///|
test "json scan finding uses the agent record schema" {
  let hit : ScanHit = {
    finding: {
      file: "src/sample.mbt",
      rule_id: "example",
      description: "Line \"one\".\n\n",
      pattern_index: 7,
      loc: render_test_location(3, 3, 3, 11),
    },
    matched_source: "target()",
    source_context: {
      lines: [
        { line_number: 2, text: "fn sample {", is_match: false, },
        { line_number: 3, text: "  target()", is_match: true, },
        { line_number: 4, text: "}", is_match: false, },
      ],
    },
  }
  let rendered = render_scan_hit_json(hit)
  assert_false(rendered.contains("pattern_index"))
  json_inspect(@json.parse(rendered), content={
    "type": "finding",
    "file": "src/sample.mbt",
    "rule_id": "example",
    "description": "Line \"one\".",
    "range": {
      "start": { "line": 3, "column": 3 },
      "end": { "line": 3, "column": 11 },
    },
    "matched_source": "target()",
    "source_context": [
      { "line": 2, "text": "fn sample {", "is_match": false },
      { "line": 3, "text": "  target()", "is_match": true },
      { "line": 4, "text": "}", "is_match": false },
    ],
  })
}

///|
test "json scan finding uses the compact range schema" {
  let rendered = render_scan_hit_json(render_test_hit(3, 3))
  json_inspect(@json.parse(rendered), content={
    "type": "finding",
    "file": "test.mbt",
    "rule_id": "test-rule",
    "description": "Test finding.",
    "range": {
      "start": { "line": 3, "column": 1 },
      "end": { "line": 3, "column": 9 },
    },
    "matched_source": "line 3",
    "source_context": [
      { "line": 2, "text": "  line 2", "is_match": false },
      { "line": 3, "text": "  line 3", "is_match": true },
      { "line": 4, "text": "  line 4", "is_match": false },
    ],
  })
}

///|
test "json scan warnings use stable schemas" {
  inspect(
    render_scan_warning_json(
      Parse({
        file: "src/bad.mbt",
        block_start_line: Some(8),
        reason: "parse failed due to unexpected token",
      }),
    ),
    content="{\"type\":\"warning\",\"category\":\"parse\",\"message\":\"skipping src/bad.mbt block starting at line 8: parse failed due to unexpected token\",\"file\":\"src/bad.mbt\",\"reason\":\"parse failed due to unexpected token\",\"block_start_line\":8}",
  )
  inspect(
    render_scan_warning_json(
      Parse({
        file: "src/single.mbt",
        block_start_line: None,
        reason: "parse failed due to missing expression",
      }),
    ),
    content="{\"type\":\"warning\",\"category\":\"parse\",\"message\":\"skipping src/single.mbt: parse failed due to missing expression\",\"file\":\"src/single.mbt\",\"reason\":\"parse failed due to missing expression\"}",
  )
  inspect(
    render_scan_warning_json(
      InvalidMoongrepSkipPayload(
        "src/hit.mbt",
        render_test_location(7, 1, 7, 22),
      ),
    ),
    content="{\"type\":\"warning\",\"category\":\"invalid_skip_payload\",\"message\":\"src/hit.mbt:7:1-7:22: #moongrep.skip does not accept a payload; use bare #moongrep.skip\",\"file\":\"src/hit.mbt\",\"range\":{\"start\":{\"line\":7,\"column\":1},\"end\":{\"line\":7,\"column\":22}}}",
  )
}

///|
test "json scan traces use typed events" {
  assert_eq(
    [
      render_scan_trace_json(RuleLoaded("example")),
      render_scan_trace_json(DirectoryEntered("src")),
      render_scan_trace_json(PathSkipped("src/vendor")),
      render_scan_trace_json(FileStarted("src/main.mbt")),
    ],
    [
      "{\"type\":\"trace\",\"event\":\"rule_loaded\",\"rule_id\":\"example\"}", "{\"type\":\"trace\",\"event\":\"directory_entered\",\"path\":\"src\"}",
      "{\"type\":\"trace\",\"event\":\"path_skipped\",\"path\":\"src/vendor\"}",
      "{\"type\":\"trace\",\"event\":\"file_started\",\"path\":\"src/main.mbt\"}",
    ],
  )
}

///|
test "matched source follows multiline Unicode code point locations" {
  let source =
    #|fn sample {
    #|  😀 target(
    #|    "quoted"
    #|  )
    #|}
    #|
  inspect(
    matched_source_for_location(
      cache_source_lines(source),
      render_test_location(2, 5, 4, 4),
    ),
    content=(
      #|target(
      #|    "quoted"
      #|  )
    ),
  )
}
