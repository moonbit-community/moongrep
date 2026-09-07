///|
async test "tokscan excludes names and normalized paths only for discovered entries" {
  for
    case in [
      ("testdata/stream-order", ["a"], ["testdata/stream-order/a.mbt"]),
      ("testdata/stream-order", ["a.mbt"], ["testdata/stream-order/a/hit.mbt"]),
      (
        "testdata/stream-order",
        ["./testdata/stream-order/a/"],
        ["testdata/stream-order/a.mbt"],
      ),
      (
        "testdata/stream-order",
        ["./testdata/stream-order/a.mbt/"],
        ["testdata/stream-order/a/hit.mbt"],
      ),
      ("testdata/stream-order", ["a", "a.mbt"], []),
      (
        "testdata/stream-order/a",
        ["a", "testdata/stream-order/a"],
        ["testdata/stream-order/a/hit.mbt"],
      ),
      (
        "testdata/stream-order/a.mbt",
        ["a.mbt", "testdata/stream-order/a.mbt"],
        ["testdata/stream-order/a.mbt"],
      ),
      (
        "testdata/stream-order",
        ["*.mbt"],
        ["testdata/stream-order/a/hit.mbt", "testdata/stream-order/a.mbt"],
      ),
      (
        "testdata/stream-order",
        ["A"],
        if scan_uses_windows_paths() {
          ["testdata/stream-order/a.mbt"]
        } else {
          ["testdata/stream-order/a/hit.mbt", "testdata/stream-order/a.mbt"]
        },
      ),
    ] {
    let (root, excludes, expected) = case
    let (stdout, stderr) = tokscan_test_output(
      ["target()"],
      root,
      excludes~,
      output_json=true,
    )
    let files = tokscan_json_records(stdout).map(record => {
      guard record is { "file": String(file), .. } else {
        fail("expected file")
      }
      file.replace_all(old="\\", new="/")
    })
    assert_eq(files, expected)
    assert_eq(stderr, [])
  }
}

///|
async test "tokscan exclusions suppress lexical warnings and preserve text no match output" {
  let (stdout, stderr) = tokscan_test_output(
    ["absent"],
    "testdata/tokscan",
    excludes=["warnings.mbt"],
    output_json=true,
  )
  debug_inspect((stdout, stderr), content="([], [])")
  let (stdout, stderr) = tokscan_test_output(
    ["target()"],
    "testdata/stream-order",
    excludes=["a", "a.mbt"],
  )
  debug_inspect(
    (stdout, stderr),
    content=(
      #|(["no match hits\n"], [])
    ),
  )
}
