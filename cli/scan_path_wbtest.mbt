///|
fn native_scan_test_path(path : String) -> String {
  if scan_uses_windows_paths() {
    path.replace_all(old="/", new="\\")
  } else {
    path
  }
}

///|
test "scan path helpers follow the host path flavor" {
  if scan_uses_windows_paths() {
    inspect(
      normalize_scan_root(".\\src/./generated\\..\\target"),
      content="src\\target",
    )
    inspect(
      join_scan_path("src\\nested", "file.mbt"),
      content="src\\nested\\file.mbt",
    )
    inspect(
      normalize_scan_exclude(".\\src//generated\\..\\vendor\\\\"),
      content="src\\vendor",
    )
    inspect(normalize_scan_exclude("C:\\\\"), content="C:\\")
    inspect(
      normalize_scan_exclude("\\\\server\\share\\\\"),
      content="\\\\server\\share\\",
    )
    inspect(normalize_scan_exclude(""), content="")
    inspect(normalize_scan_exclude(".\\src\\*.mbt\\"), content="src\\*.mbt")
    assert_true(scan_path_matches("VENDOR\\ÜBER", "vendor\\über"))
    assert_true(should_skip_entry("root\\.GIT", ".GIT", []))
    assert_false(
      should_skip_entry("relative\\file.mbt", "file.mbt", [
        "C:\\relative\\file.mbt",
      ]),
    )
  } else {
    inspect(normalize_scan_root("./src/../target"), content="./src/../target")
    inspect(join_scan_path("./src", "file.mbt"), content="./src/file.mbt")
    inspect(
      normalize_scan_exclude("./src/../vendor///"),
      content="src/../vendor",
    )
    inspect(normalize_scan_exclude("/"), content="/")
    inspect(normalize_scan_exclude(".\\vendor\\"), content=".\\vendor\\")
    inspect(normalize_scan_exclude(""), content="")
    inspect(normalize_scan_exclude("./src/*.mbt/"), content="src/*.mbt")
    assert_false(scan_path_matches("VENDOR/ÜBER", "vendor/über"))
    assert_false(should_skip_entry("root/.GIT", ".GIT", []))
    assert_false(
      should_skip_entry("relative/file.mbt", "file.mbt", ["/relative/file.mbt"]),
    )
  }
}
