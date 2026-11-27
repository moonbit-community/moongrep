///|
async test "source open and read failures keep scan input diagnostics" {
  // A missing file fails while opening; a directory can fail while reading,
  // after core/async wraps the OS error in ReaderError::TransportError.
  for
    path in [
      "e2etests/testdata/missing-source.mbt", "e2etests/testdata/custom-rules",
    ] {
    let path = native_scan_test_path(path)
    try read_text_file(path) catch {
      CliError::ScanInput(diagnostic~) as err => {
        assert_eq(err.exit_code(), 6)
        guard diagnostic is Fields(summary~, source~, reason~, ..) else {
          fail("expected structured diagnostic")
        }
        assert_eq(summary, "could not read source file")
        assert_eq(source, Some(path))
        assert_true(reason is Some(text) && !text.is_empty())
        let message = render_cli_diagnostic(diagnostic)
        assert_false(message.contains("TransportError"))
        assert_false(message.contains("OsError"))
        assert_false(message.contains("@fs."))
      }
      err => fail("unexpected source read error \{err}")
    } noraise {
      _ => fail("expected source read error for \{path}")
    }
  }
}

///|
test "OS error reasons omit library context including embedded colons" {
  let error = @os_error.from_errno(2, context="@fs.open(): C:\\rules.yaml")
  let reason = os_error_reason(error)
  assert_false(reason.is_empty())
  assert_false(reason.contains("@fs."))
  assert_false(reason.contains("C:"))
  assert_eq(reason, os_error_reason(error.wrap_context(_ => "")))
  assert_eq(reason, os_error_reason(error.wrap_context(_ => "read: source")))
}
