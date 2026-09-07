///|
fn tokscan_json_records(output : Array[String]) -> Array[Json] raise {
  output.map(line => {
    assert_true(line.has_suffix("\n"))
    assert_eq(line.split("\n").count(), 2)
    assert_false(line.contains("\u001b"))
    @json.parse(line)
  })
}

///|
test "tokscan JSON preserves exact fields pattern spelling and Unicode columns" {
  let source = "before\n// context\n\"😀\".field(\"a\\n\")\n// after\nafter\noutside"
  let pattern = ".field(\n  \"a\\n\"\n)\n"
  let hit = prepare_tokscan_patterns([pattern]).find_matches(source)[0]
  let rendered = render_tokscan_hit_json(
    "example.mbt",
    hit.loc,
    pattern,
    cache_source_lines(source),
  )
  json_inspect(tokscan_json_records([rendered + "\n"])[0], content={
    "type": "finding",
    "file": "example.mbt",
    "pattern": ".field(\n  \"a\\n\"\n)\n",
    "range": {
      "start": { "line": 3, "column": 4 },
      "end": { "line": 3, "column": 17 },
    },
    "matched_source": ".field(\"a\\n\")",
    "source_context": [
      { "line": 1, "text": "before", "is_match": false },
      { "line": 2, "text": "// context", "is_match": false },
      { "line": 3, "text": "\"😀\".field(\"a\\n\")", "is_match": true },
      { "line": 4, "text": "// after", "is_match": false },
      { "line": 5, "text": "after", "is_match": false },
    ],
  })
}

///|
test "tokscan JSON keeps the full multiline match and two surrounding lines" {
  let pattern = "a\nb\nc\nd\ne\nf\ng\nh\ni"
  let source = "outside\n// before 1\n// before 2\n" +
    pattern +
    "\n// after 1\n// after 2\noutside"
  let hit = prepare_tokscan_patterns([pattern]).find_matches(source)[0]
  json_inspect(
    @json.parse(
      render_tokscan_hit_json(
        "multiline.mbt",
        hit.loc,
        pattern,
        cache_source_lines(source),
      ),
    ),
    content={
      "type": "finding",
      "file": "multiline.mbt",
      "pattern": "a\nb\nc\nd\ne\nf\ng\nh\ni",
      "range": {
        "start": { "line": 4, "column": 1 },
        "end": { "line": 12, "column": 2 },
      },
      "matched_source": "a\nb\nc\nd\ne\nf\ng\nh\ni",
      "source_context": [
        { "line": 2, "text": "// before 1", "is_match": false },
        { "line": 3, "text": "// before 2", "is_match": false },
        { "line": 4, "text": "a", "is_match": true },
        { "line": 5, "text": "b", "is_match": true },
        { "line": 6, "text": "c", "is_match": true },
        { "line": 7, "text": "d", "is_match": true },
        { "line": 8, "text": "e", "is_match": true },
        { "line": 9, "text": "f", "is_match": true },
        { "line": 10, "text": "g", "is_match": true },
        { "line": 11, "text": "h", "is_match": true },
        { "line": 12, "text": "i", "is_match": true },
        { "line": 13, "text": "// after 1", "is_match": false },
        { "line": 14, "text": "// after 2", "is_match": false },
      ],
    },
  )
}

///|
async test "tokscan JSON streams overlapping and duplicate patterns without separators" {
  let (stdout, stderr) = tokscan_test_output(
    ["a a", "a a a", "a a"],
    "testdata/tokscan/overlap.mbt",
    output_json=true,
    no_color=false,
  )
  let records = tokscan_json_records(stdout)
  let summary = records.map(record => {
    guard record
      is { "pattern": pattern, "range": range, "matched_source": source, .. } else {
      fail("expected finding")
    }
    (pattern, range, source)
  })
  json_inspect(summary, content=[
    [
      "a a",
      { "start": { "line": 1, "column": 1 }, "end": { "line": 1, "column": 4 } },
      "a a",
    ],
    [
      "a a a",
      { "start": { "line": 1, "column": 1 }, "end": { "line": 1, "column": 6 } },
      "a a a",
    ],
    [
      "a a",
      { "start": { "line": 1, "column": 1 }, "end": { "line": 1, "column": 4 } },
      "a a",
    ],
    [
      "a a",
      { "start": { "line": 1, "column": 3 }, "end": { "line": 1, "column": 6 } },
      "a a",
    ],
    [
      "a a",
      { "start": { "line": 1, "column": 3 }, "end": { "line": 1, "column": 6 } },
      "a a",
    ],
  ])
  debug_inspect(stderr, content="[]")
}

///|
async test "tokscan JSON warnings use stderr and recover at subsequent blocks" {
  let (stdout, stderr) = tokscan_test_output(
    ["target(1)", "let = + )"],
    "testdata/tokscan/warnings.mbt",
    output_json=true,
  )
  let findings = tokscan_json_records(stdout)
  json_inspect(
    findings.map(record => {
      guard record
        is { "type": "finding", "range": range, "matched_source": source, .. } else {
        fail("expected finding on stdout")
      }
      (range, source)
    }),
    content=[
      [
        {
          "start": { "line": 10, "column": 1 },
          "end": { "line": 10, "column": 10 },
        },
        "let = + )",
      ],
      [
        {
          "start": { "line": 11, "column": 1 },
          "end": { "line": 11, "column": 13 },
        },
        "target ( 1 )",
      ],
    ],
  )
  // Normalize decoded paths so JSON backslash escaping remains intact.
  let warnings = tokscan_json_records(stderr).map(record => {
    guard record is Object(fields) else { fail("expected warning object") }
    for key in ["file", "message"] {
      guard fields.get(key) is Some(String(value)) else {
        fail("expected string")
      }
      fields[key] = Json::string(value.replace_all(old="\\", new="/"))
    }
    record
  })
  json_inspect(warnings, content=[
    {
      "type": "warning",
      "category": "lexical",
      "message": "skipping testdata/tokscan/warnings.mbt block starting at line 1: lexing failed: line 2, column 1: unrecognized character u32: $",
      "file": "testdata/tokscan/warnings.mbt",
      "reason": "lexing failed: line 2, column 1: unrecognized character u32: $",
      "block_start_line": 1,
    },
    {
      "type": "warning",
      "category": "lexical",
      "message": "skipping testdata/tokscan/warnings.mbt block starting at line 3: lexing failed: attribute #tag: line 1, column 2: unrecognized character u32: $",
      "file": "testdata/tokscan/warnings.mbt",
      "reason": "lexing failed: attribute #tag: line 1, column 2: unrecognized character u32: $",
      "block_start_line": 3,
    },
    {
      "type": "warning",
      "category": "lexical",
      "message": "skipping testdata/tokscan/warnings.mbt block starting at line 6: lexing failed: interpolation: line 1, column 1: unrecognized character u32: $",
      "file": "testdata/tokscan/warnings.mbt",
      "reason": "lexing failed: interpolation: line 1, column 1: unrecognized character u32: $",
      "block_start_line": 6,
    },
  ])
}

///|
test "tokscan single block JSON warnings omit block start" {
  json_inspect(
    @json.parse(
      render_source_warning_json(
        {
          file: "bad.mbt",
          block_start_line: None,
          reason: "lexing failed: bad token",
        },
        category="lexical",
      ),
    ),
    content={
      "type": "warning",
      "category": "lexical",
      "message": "skipping bad.mbt: lexing failed: bad token",
      "file": "bad.mbt",
      "reason": "lexing failed: bad token",
    },
  )
}

///|
async test "tokscan JSON no matches write no stdout including warning only scans" {
  for root in ["testdata/tokscan/overlap.mbt", "testdata/tokscan/warnings.mbt"] {
    let (stdout, stderr) = tokscan_test_output(
      ["absent"],
      root,
      output_json=true,
    )
    assert_eq(stdout, [])
    let warnings = tokscan_json_records(stderr)
    assert_eq(
      warnings.length(),
      if root.has_suffix("warnings.mbt") {
        3
      } else {
        0
      },
    )
  }
}
