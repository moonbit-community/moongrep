///|
async fn tokscan_test_output(
  patterns : Array[String],
  root : String,
  excludes? : Array[String] = [],
  output_json? : Bool = false,
  no_color? : Bool = true,
) -> (Array[String], Array[String]) {
  let stdout : Array[String] = []
  let stderr : Array[String] = []
  run_tokscan_with_writers(
    patterns,
    root,
    no_color,
    output => stdout.push(output),
    output => stderr.push(output),
    excludes~,
    output_json~,
  )
  (stdout, stderr)
}

///|
async test "tokscan reuses sorted DFS traversal and scan root normalization" {
  let (stdout, stderr) = tokscan_test_output(
    ["target()"],
    "testdata/stream-order",
  )
  debug_inspect(
    stdout.map(output => {
      output
      .trim_start()
      .split("\n")
      .next()
      .unwrap()
      .to_owned()
      .replace_all(old="\\", new="/")
    }),
    content=(
      #|[
      #|  "testdata/stream-order/a/hit.mbt:2:3-2:11",
      #|  "testdata/stream-order/a.mbt:2:3-2:11",
      #|]
    ),
  )
  debug_inspect(stderr, content="[]")
  assert_false(stdout[0].has_prefix("\n"))
  assert_true(stdout[1].has_prefix("\n"))
}

///|
async test "tokscan skips whole invalid blocks and resumes in the same file" {
  let (stdout, stderr) = tokscan_test_output(
    ["target(1)", "let = + )"],
    "testdata/tokscan/warnings.mbt",
  )
  debug_inspect(
    stdout.map(output => {
      output
      .trim_start()
      .split("\n")
      .next()
      .unwrap()
      .to_owned()
      .replace_all(old="\\", new="/")
    }),
    content=(
      #|[
      #|  "testdata/tokscan/warnings.mbt:10:1-10:10",
      #|  "testdata/tokscan/warnings.mbt:11:1-11:13",
      #|]
    ),
  )
  debug_inspect(
    stderr.map(output => output.replace_all(old="\\", new="/")),
    content=(
      #|[
      #|  "warning: skipping testdata/tokscan/warnings.mbt block starting at line 1: lexing failed: line 2, column 1: unrecognized character u32: $\n",
      #|  "warning: skipping testdata/tokscan/warnings.mbt block starting at line 3: lexing failed: attribute #tag: line 1, column 2: unrecognized character u32: $\n",
      #|  "warning: skipping testdata/tokscan/warnings.mbt block starting at line 6: lexing failed: interpolation: line 1, column 1: unrecognized character u32: $\n",
      #|]
    ),
  )
  assert_false(stdout.join("").contains("warning:"))
}

///|
async test "tokscan isolates blocks and treats moongrep skip as ordinary tokens" {
  let (stdout, stderr) = tokscan_test_output(
    ["a;b"],
    "testdata/tokscan/blocks.mbt",
  )
  debug_inspect(stdout, content="[\"no match hits\\n\"]")
  debug_inspect(stderr, content="[]")
  let (stdout, stderr) = tokscan_test_output(
    ["target(1)", "#moongrep.skip", ".field"],
    "testdata/tokscan/blocks.mbt",
  )
  debug_inspect(
    stdout.map(output => {
      output
      .trim_start()
      .split("\n")
      .next()
      .unwrap()
      .to_owned()
      .replace_all(old="\\", new="/")
    }),
    content=(
      #|[
      #|  "testdata/tokscan/blocks.mbt:5:1-5:15",
      #|  "testdata/tokscan/blocks.mbt:6:1-6:10",
      #|  "testdata/tokscan/blocks.mbt:8:4-8:10",
      #|]
    ),
  )
  debug_inspect(stderr, content="[]")
}

///|
async test "tokscan validates every pattern before accessing files or writing" {
  let output : Array[String] = []
  try
    run_tokscan_with_writers(
      ["target()", "$bad", ""],
      "missing-tokscan-root",
      true,
      value => output.push(value),
      value => output.push(value),
    )
  catch {
    CliError::Usage(..) as err => {
      inspect(err.exit_code(), content="2")
      assert_true(render_cli_error(err).contains("invalid tokscan pattern 2"))
    }
    err => fail("unexpected error \{err}")
  } noraise {
    _ => fail("expected pattern error")
  }
  debug_inspect(output, content="[]")
  try tokscan_test_output(["target()"], "missing-tokscan-root") catch {
    CliError::ScanInput(..) as err => inspect(err.exit_code(), content="6")
    err => fail("unexpected error \{err}")
  } noraise {
    _ => fail("expected scan input error")
  }
}

///|
async test "tokscan stdout and stderr failures retain output exit code" {
  for
    case in [
      ("testdata/tokscan/overlap.mbt", ["a"], true, false),
      ("testdata/tokscan/overlap.mbt", ["absent"], true, false),
      ("testdata/tokscan/warnings.mbt", ["target(1)"], false, false),
      ("testdata/tokscan/overlap.mbt", ["a"], true, true),
      ("testdata/tokscan/warnings.mbt", ["target(1)"], false, true),
    ] {
    let (root, patterns, fail_stdout, output_json) = case
    try
      run_tokscan_with_writers(
        patterns,
        root,
        true,
        _ => if fail_stdout { fail("injected stdout failure") },
        _ => if !fail_stdout { fail("injected stderr failure") },
        output_json~,
      )
    catch {
      CliError::Output(..) as err => assert_eq(err.exit_code(), 7)
      err => fail("unexpected error \{err}")
    } noraise {
      _ => fail("expected output error")
    }
  }
}

///|
test "tokscan renders original pattern and shares source highlighting and cropping" {
  let source = "\"😀\".field"
  let lines = cache_source_lines(source)
  let pattern = ".field\n"
  let matcher = prepare_tokscan_patterns([pattern])
  let hit = matcher.find_matches(source)[0]
  inspect(
    render_tokscan_hit("example.mbt", hit.loc, pattern, lines, no_color=true),
    content=(
      #|example.mbt:1:4-1:10
      #|pattern:
      #|  .field
      #|  
      #|source:
      #|1 > "😀".field
    ),
  )
  inspect(
    render_tokscan_hit("example.mbt", hit.loc, pattern, lines, no_color=false),
    content=(
      #|example.mbt:1:4-1:10
      #|pattern:
      #|  .field
      #|  
      #|source:
      #|1 | "😀"[93m.field[39m
    ),
  )
  let source = "a\nb\nc\nd\ne\nf\ng\nh\ni"
  let hit = prepare_tokscan_patterns([source]).find_matches(source)[0]
  inspect(
    render_tokscan_hit(
      "example.mbt",
      hit.loc,
      source,
      cache_source_lines(source),
      no_color=true,
    ),
    content=(
      #|example.mbt:1:1-9:2
      #|pattern:
      #|  a
      #|  b
      #|  c
      #|  d
      #|  e
      #|  f
      #|  g
      #|  h
      #|  i
      #|source:
      #|1 > a
      #|2 > b
      #|3 > c
      #|. > line 4-6: 3 matched lines omitted
      #|7 > g
      #|8 > h
      #|9 > i
    ),
  )
}
