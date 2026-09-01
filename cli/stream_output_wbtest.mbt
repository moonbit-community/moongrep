///|
fn stream_event_scan_options() -> CliOptions {
  {
    rules_root: Some("testdata/skip-structural/rules"),
    rule_file: None,
    patterns: [],
    scan_root: "testdata/stream-events",
    excludes: ["ignored"],
    disabled_rules: [],
    verbose: true,
    no_color: true,
    output_json: false,
  }
}

///|
fn stream_order_scan_options() -> CliOptions {
  {
    rules_root: Some("e2etests/rules/structural"),
    rule_file: None,
    patterns: [],
    scan_root: "testdata/stream-order",
    excludes: [],
    disabled_rules: [],
    verbose: false,
    no_color: true,
    output_json: false,
  }
}

///|
fn no_match_stream_options(output_json : Bool) -> CliOptions {
  {
    rules_root: Some("e2etests/rules/structural"),
    rule_file: None,
    patterns: [],
    scan_root: "testdata/prefilter-irrelevant",
    excludes: [],
    disabled_rules: [],
    verbose: false,
    no_color: true,
    output_json,
  }
}

///|
fn parse_warning_stream_options() -> CliOptions {
  {
    rules_root: Some("e2etests/rules/structural"),
    rule_file: None,
    patterns: [],
    scan_root: "testdata/parse-warning",
    excludes: [],
    disabled_rules: [],
    verbose: true,
    no_color: true,
    output_json: false,
  }
}

///|
fn stream_options_with_format(
  options : CliOptions,
  verbose : Bool,
  output_json : Bool,
) -> CliOptions {
  {
    rules_root: options.rules_root,
    rule_file: options.rule_file,
    patterns: options.patterns,
    scan_root: options.scan_root,
    excludes: options.excludes,
    disabled_rules: options.disabled_rules,
    verbose,
    no_color: true,
    output_json,
  }
}

///|
fn scan_event_summary(event : ScanEvent) -> String {
  match event {
    Trace(trace) => "trace:\{render_scan_trace(trace)}"
    Warning(Parse(warning)) => "warning:\{warning.file}"
    Warning(InvalidMoongrepSkipPayload(file, _)) => "warning:\{file}"
    Hit(hit) =>
      "hit:\{hit.finding.file}:\{hit.finding.rule_id}:\{hit.finding.loc.start.lnum}"
  }
}

///|
fn string_index_containing(items : Array[String], needle : String) -> Int {
  for index, item in items {
    if item.contains(needle) {
      return index
    }
  }
  -1
}

///|
async test "scan events stream before visiting later files" {
  let events : Array[String] = []
  scan_events(Scan, stream_event_scan_options(), event => {
    events.push(scan_event_summary(event))
  })
  assert_eq(events, [
    "trace:moongrep scan: loaded rule taint",
    "trace:moongrep scan: loaded rule structural",
    native_scan_test_path(
      "trace:moongrep scan: entering testdata/stream-events",
    ),
    native_scan_test_path(
      "trace:moongrep scan: file testdata/stream-events/a.mbt",
    ),
    native_scan_test_path("hit:testdata/stream-events/a.mbt:structural:2"),
    native_scan_test_path("hit:testdata/stream-events/a.mbt:taint:4"),
    native_scan_test_path(
      "trace:moongrep scan: entering testdata/stream-events/later",
    ),
    native_scan_test_path(
      "trace:moongrep scan: entering testdata/stream-events/later/nested",
    ),
    native_scan_test_path(
      "trace:moongrep scan: file testdata/stream-events/later/nested/b.mbt",
    ),
    native_scan_test_path(
      "hit:testdata/stream-events/later/nested/b.mbt:structural:2",
    ),
    native_scan_test_path(
      "trace:moongrep scan: skipping testdata/stream-events/ignored",
    ),
    native_scan_test_path(
      "trace:moongrep scan: file testdata/stream-events/broken.mbt",
    ),
    native_scan_test_path("warning:testdata/stream-events/broken.mbt"),
  ])
  let structural = string_index_containing(
    events,
    native_scan_test_path("hit:testdata/stream-events/a.mbt:structural:2"),
  )
  let taint = string_index_containing(
    events,
    native_scan_test_path("hit:testdata/stream-events/a.mbt:taint:4"),
  )
  let later = string_index_containing(
    events,
    native_scan_test_path(
      "trace:moongrep scan: entering testdata/stream-events/later",
    ),
  )
  assert_true(structural >= 0 && structural < taint)
  assert_true(taint < later)
  assert_true(
    string_index_containing(
      events,
      native_scan_test_path(
        "trace:moongrep scan: entering testdata/stream-events/later/nested",
      ),
    ) >=
    0,
  )
  assert_true(
    string_index_containing(
      events,
      native_scan_test_path(
        "trace:moongrep scan: skipping testdata/stream-events/ignored",
      ),
    ) >=
    0,
  )
  assert_true(
    string_index_containing(
      events,
      native_scan_test_path("warning:testdata/stream-events/broken.mbt"),
    ) >=
    0,
  )
  assert_true(
    string_index_containing(
      events,
      native_scan_test_path("hit:testdata/stream-events/ignored"),
    ) <
    0,
  )
}

///|
async test "stream order follows DFS traversal" {
  let streamed_files : Array[String] = []
  let options = stream_order_scan_options()
  scan_events(Scan, options, event => {
    if event is Hit(hit) {
      streamed_files.push(hit.finding.file)
    }
  })
  assert_eq(streamed_files, [
    native_scan_test_path("testdata/stream-order/a/hit.mbt"),
    native_scan_test_path("testdata/stream-order/a.mbt"),
  ])
}

///|
async test "human stream writes one complete chunk per hit" {
  let stdout_chunks : Array[String] = []
  let stderr_chunks : Array[String] = []
  run_scan_mode_command_with_writers(
    Scan,
    stream_order_scan_options(),
    output => stdout_chunks.push(output),
    output => stderr_chunks.push(output),
  )
  assert_eq(stdout_chunks.length(), 2)
  assert_true(stdout_chunks[0].has_suffix("\n"))
  assert_false(stdout_chunks[0].has_prefix("\n"))
  assert_true(
    stdout_chunks[0].contains(
      native_scan_test_path("testdata/stream-order/a/hit.mbt"),
    ),
  )
  assert_false(
    stdout_chunks[0].contains(
      native_scan_test_path("testdata/stream-order/a.mbt:2"),
    ),
  )
  assert_true(stdout_chunks[1].has_prefix("\n"))
  assert_true(stdout_chunks[1].has_suffix("\n"))
  assert_true(
    stdout_chunks[1].contains(
      native_scan_test_path("testdata/stream-order/a.mbt"),
    ),
  )
  assert_true(stderr_chunks.is_empty())
}

///|
async test "stream writer is awaited before traversal resumes" {
  let timeline : Array[String] = []
  let options = stream_options_with_format(
    stream_order_scan_options(),
    true,
    false,
  )
  run_scan_mode_command_with_writers(
    Scan,
    options,
    output => {
      let file = if output.contains(native_scan_test_path("a/hit.mbt")) {
        "nested"
      } else {
        "flat"
      }
      timeline.push("stdout-start:\{file}")
      @async.sleep(1)
      timeline.push("stdout-end:\{file}")
    },
    output => timeline.push("stderr:\{output.trim()}"),
  )
  let start = string_index_containing(timeline, "stdout-start:nested")
  let end = string_index_containing(timeline, "stdout-end:nested")
  let next_file = string_index_containing(
    timeline,
    native_scan_test_path(
      "stderr:moongrep scan: file testdata/stream-order/a.mbt",
    ),
  )
  assert_true(start >= 0 && start < end)
  assert_true(end < next_file)
}

///|
async test "JSON stream writes one parseable line per hit" {
  let stdout_chunks : Array[String] = []
  let stderr_chunks : Array[String] = []
  run_scan_mode_command_with_writers(
    Scan,
    stream_options_with_format(stream_order_scan_options(), false, true),
    output => stdout_chunks.push(output),
    output => stderr_chunks.push(output),
  )
  assert_eq(stdout_chunks.length(), 2)
  for output in stdout_chunks {
    guard output.strip_suffix("\n") is Some(record) else {
      fail("expected newline-terminated JSON record")
    }
    assert_false(record.contains("\n"))
    ignore(@json.parse(record))
  }
  assert_true(stderr_chunks.is_empty())
}

///|
async test "stream no-match output depends on format" {
  let human_stdout : Array[String] = []
  let human_stderr : Array[String] = []
  run_scan_mode_command_with_writers(
    Scan,
    no_match_stream_options(false),
    output => human_stdout.push(output),
    output => human_stderr.push(output),
  )
  assert_eq(human_stdout, ["no match hits\n"])
  assert_true(human_stderr.is_empty())
  let json_stdout : Array[String] = []
  let json_stderr : Array[String] = []
  run_scan_mode_command_with_writers(
    Scan,
    no_match_stream_options(true),
    output => json_stdout.push(output),
    output => json_stderr.push(output),
  )
  assert_true(json_stdout.is_empty())
  assert_true(json_stderr.is_empty())
}

///|
async test "stream writer failures are output errors" {
  try
    run_scan_mode_command_with_writers(
      Scan,
      no_match_stream_options(false),
      _ => fail("injected writer failure"),
      _ => (),
    )
  catch {
    CliError::Output(diagnostic~) as err => {
      let message = render_cli_diagnostic(diagnostic)
      assert_eq(err.exit_code(), 7)
      assert_true(message.contains("injected writer failure"))
    }
    err => fail("unexpected error \{err}")
  } noraise {
    _ => fail("expected output error")
  }
}

///|
async test "stream diagnostics are written only to stderr" {
  let stdout_chunks : Array[String] = []
  let stderr_chunks : Array[String] = []
  run_scan_mode_command_with_writers(
    Scan,
    parse_warning_stream_options(),
    output => stdout_chunks.push(output),
    output => stderr_chunks.push(output),
  )
  assert_eq(stdout_chunks.length(), 1)
  let stdout = stdout_chunks.join("")
  assert_false(stdout.contains("moongrep scan:"))
  assert_false(stdout.contains("warning:"))
  let stderr = stderr_chunks.join("")
  assert_true(stderr.contains("moongrep scan: loaded rule example\n"))
  assert_true(
    stderr.contains(
      native_scan_test_path(
        "warning: skipping testdata/parse-warning/bad.mbt: parse failed",
      ),
    ),
  )
  for output in stderr_chunks {
    assert_true(output.has_suffix("\n"))
  }
}

///|
async test "JSON stderr writes one parseable record per trace and warning" {
  let stdout_chunks : Array[String] = []
  let stderr_chunks : Array[String] = []
  run_scan_mode_command_with_writers(
    Scan,
    stream_options_with_format(parse_warning_stream_options(), true, true),
    output => stdout_chunks.push(output),
    output => stderr_chunks.push(output),
  )
  assert_eq(stdout_chunks.length(), 1)
  assert_true(stderr_chunks.length() > 0)
  let mut saw_trace = false
  let mut saw_warning = false
  for output in stderr_chunks {
    guard output.strip_suffix("\n") is Some(record) else {
      fail("expected newline-terminated JSON record")
    }
    assert_false(record.contains("\n"))
    ignore(@json.parse(record))
    if record.contains("\"type\":\"trace\"") {
      saw_trace = true
    }
    if record.contains("\"type\":\"warning\"") {
      saw_warning = true
    }
  }
  assert_true(saw_trace)
  assert_true(saw_warning)
}

///|
async test "skip payload warnings keep streaming and JSON stdout clean" {
  let human_stdout : Array[String] = []
  let human_stderr : Array[String] = []
  run_scan_mode_command_with_writers(
    Scan,
    stream_options_with_format(skip_scan_options(), false, false),
    output => human_stdout.push(output),
    output => human_stderr.push(output),
  )
  assert_eq(human_stdout.length(), 3)
  assert_false(human_stdout.join("").contains("warning:"))
  assert_eq(human_stderr, [
    native_scan_test_path(
      "warning: testdata/skip-structural/src/hit.mbt:7:1-7:22: #moongrep.skip does not accept a payload; use bare #moongrep.skip\n",
    ),
    native_scan_test_path(
      "warning: testdata/skip-structural/src/hit.mbt:13:1-13:17: #moongrep.skip does not accept a payload; use bare #moongrep.skip\n",
    ),
  ])
  let json_stdout : Array[String] = []
  let json_stderr : Array[String] = []
  run_scan_mode_command_with_writers(
    Scan,
    stream_options_with_format(skip_scan_options(), false, true),
    output => json_stdout.push(output),
    output => json_stderr.push(output),
  )
  assert_eq(json_stdout.length(), 3)
  for output in json_stdout {
    guard output.strip_suffix("\n") is Some(record) else {
      fail("expected newline-terminated JSON record")
    }
    assert_false(record.contains("warning:"))
    ignore(@json.parse(record))
  }
  assert_eq(json_stderr.length(), 2)
  for output in json_stderr {
    guard output.strip_suffix("\n") is Some(record) else {
      fail("expected newline-terminated JSON warning")
    }
    assert_false(record.contains("\n"))
    assert_true(record.contains("\"type\":\"warning\""))
    assert_true(record.contains("\"category\":\"invalid_skip_payload\""))
    ignore(@json.parse(record))
  }
}
