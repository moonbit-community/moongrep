///|
test "tokscan CLI preserves repeated patterns and defaults" {
  debug_inspect(
    tokscan_test_cli(["tokscan", "--pattern", "a", "--pattern=a"]),
    content=(
      #|(["a", "a"], ".", [], false, false)
    ),
  )
  debug_inspect(
    tokscan_test_cli(["tokscan", "src", "--pattern", "a"], env={
      "NO_COLOR": "1",
    }),
    content=(
      #|(["a"], "src", [], true, false)
    ),
  )
  debug_inspect(
    tokscan_test_cli(["tokscan", "--pattern=a", "--", "--pattern=b"], env={
      "NO_COLOR": "true",
    }),
    content=(
      #|(["a"], "--pattern=b", [], false, false)
    ),
  )
  for
    argv in [
      ["tokscan", "src"],
      ["tokscan", "--pattern"],
      ["tokscan", "--pattern=a", "src", "extra"],
      ["tokscan", "--json"],
      ["tokscan", "--exclude"],
      ["tokscan", "--guard=x", "--pattern=a"],
      ["tokscan", "--verbose", "--pattern=a"],
      ["tokscan", "--rule=x", "--pattern=a"],
      ["tokscan", "--rules=x", "--pattern=a"],
      ["tokscan", "--disable=x", "--pattern=a"],
    ] {
    expect_cli_usage(argv, 2)
  }
}

///|
test "tokscan CLI appends exclusions among patterns flags and root" {
  debug_inspect(
    tokscan_test_cli([
      "tokscan", "--exclude", "./vendor/", "--pattern=a", "src", "--json", "--exclude=./generated/",
      "--pattern", "b", "--exclude", "vendor",
    ]),
    content=(
      #|(["a", "b"], "src", ["vendor", "generated", "vendor"], false, true)
    ),
  )
  if scan_uses_windows_paths() {
    let (_, _, excludes, _, _) = tokscan_test_cli([
      "tokscan", "--pattern=a", "--exclude=.\\src//ignored\\..\\VENDOR\\",
    ])
    debug_inspect(
      excludes,
      content=(
        #|["src\\VENDOR"]
      ),
    )
    assert_true(should_skip_entry("src\\vendor", "vendor", excludes))
  }
}

///|
test "tokscan JSON detection precedes parsing and respects the terminator" {
  for
    argv in [
      ["tokscan", "--json"],
      ["tokscan", "--unknown", "--json"],
      ["tokscan", "--json", "--pattern"],
      ["tokscan", "--json", "--help"],
      ["tokscan", "--json", "--", "--json"],
    ] {
    assert_true(output_json_requested(argv))
  }
  for
    argv in [
      ["tokscan"],
      ["tokscan", "--json=true"],
      ["tokscan", "--pattern=--json"],
      ["tokscan", "--", "--json"],
      ["help", "tokscan", "--json"],
    ] {
    assert_false(output_json_requested(argv))
  }
  debug_inspect(
    tokscan_test_cli(["tokscan", "--pattern=a", "--", "--json"]),
    content=(
      #|(["a"], "--json", [], false, false)
    ),
  )
  try parse_cli_command(["tokscan", "--json"]) catch {
    CliError::Usage(..) as err =>
      json_inspect(@json.parse(err.render_json()), content={
        "type": "error",
        "category": "usage",
        "exit_code": 2,
        "message": "tokscan requires at least one --pattern",
      })
    err => fail("unexpected error \{err}")
  } noraise {
    _ => fail("expected missing-pattern usage error")
  }
}

///|
test "tokscan rejects empty and recursively invalid patterns in input order" {
  for
    source in [
      "", " \n// comment\n", "$x", "$(x:exp)", "\"unterminated", "#tag($x)", "#outer #inner($x)",
      "\"\\{$x}\"", "#tag(\"\\{$x}\")", "\"\\{\"\\{$x}\"}\"",
    ] {
    try prepare_tokscan_patterns(["valid", source, "$later"]) catch {
      CliError::Usage(..) as err => {
        assert_eq(err.exit_code(), 2)
        let diagnostic = render_cli_error(err)
        assert_true(diagnostic.contains("invalid tokscan pattern 2"))
        assert_true(diagnostic.contains("pattern:"))
        assert_false(diagnostic.contains("$later"))
      }
      err => fail("unexpected error \{err}")
    } noraise {
      _ => fail("expected invalid pattern: \{source}")
    }
  }
  try prepare_tokscan_patterns(["ok", "#tag($x)"]) catch {
    CliError::Usage(..) as err =>
      inspect(
        render_cli_error(err),
        content=(
          #|error: invalid tokscan pattern 2
          #|  source: --pattern 2
          #|  pattern:
          #|    #tag($x)
          #|  reason: attribute #tag: line 1, column 2: unrecognized character u32: $
        ),
      )
    err => fail("unexpected error \{err}")
  } noraise {
    _ => fail("expected lexical error")
  }
}

///|
fn tokscan_test_cli(
  argv : Array[String],
  env? : Map[String, String] = {},
) -> (Array[String], String, Array[String], Bool, Bool) raise {
  match parse_cli_command(argv, env~) {
    TokScan(patterns~, scan_root~, excludes~, no_color~, output_json~) =>
      (patterns, scan_root, excludes, no_color, output_json)
    _ => fail("expected tokscan command")
  }
}
