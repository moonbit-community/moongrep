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
        { line_number: 2, text: "fn sample {", is_match: false },
        { line_number: 3, text: "  target()", is_match: true },
        { line_number: 4, text: "}", is_match: false },
      ],
    },
  }
  let rendered = render_scan_hit_json(hit)
  assert_false(rendered.contains("pattern_index"))
  json_inspect(@json.parse(rendered), content={
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
test "matched source follows multiline UTF-16 locations" {
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
      render_test_location(2, 6, 4, 4),
    ),
    content=(
      #|target(
      #|    "quoted"
      #|  )
    ),
  )
}

///|
test "json directory output contains only one line per finding" {
  inspect(
    render_directory_scan_json({
      scan_trace: ["trace"],
      hits: [],
      warnings: [
        Parse({
          file: "bad.mbt",
          block_start_line: None,
          reason: "parse failed",
        }),
      ],
    }),
    content="",
  )
  let rendered = render_directory_scan_json({
    scan_trace: ["trace"],
    hits: [render_test_hit(3, 3), render_test_hit(8, 8)],
    warnings: [
      Parse({ file: "bad.mbt", block_start_line: None, reason: "parse failed" }),
    ],
  })
  let records = rendered.split("\n").to_array()
  assert_eq(records.length(), 2)
  for record in records {
    ignore(@json.parse(record))
  }
}
