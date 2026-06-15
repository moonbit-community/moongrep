///|
fn moongrep_tmp_root(prefix : String) -> String raise {
  let base = "_build/moongrep-test-tmp"
  @miniio.mkdir(base) catch {
    Exist => ()
    e => raise e
  }
  let path = "\{base}/\{prefix}"
  @miniio.rmdir(path, recursive=true) catch {
    Noent => ()
    Notdir => @miniio.remove_file(path)
    e => raise e
  }
  @miniio.mkdir(path)
  path
}

///|
fn write_rule_file(dir : String, body : String) -> Unit raise {
  @miniio.write_text_file("\{dir}/example.yaml", body)
}

///|
fn structural_target_rule() -> String {
  let source =
    #|package: example/pkg
    #|description: |
    #|  Target call.
    #|patterns:
    #|  - shape: target()
    #|
  source
}

///|
fn taint_user_rule() -> String {
  let source =
    #|package: example/pkg
    #|description: |
    #|  User input reaches sink.
    #|taint:
    #|  sources:
    #|    - shape: get_user_input()
    #|  sinks:
    #|    - shape: sink(__SOURCE__)
    #|
  source
}

///|
test "scan collects mbt hits and skips dependency, build, and VCS directories" {
  let root = moongrep_tmp_root("moongrep-scan")
  let rules_dir = "\{root}/rules"
  let scan_dir = "\{root}/src"
  @miniio.mkdir(rules_dir)
  @miniio.mkdir(scan_dir)
  @miniio.mkdir("\{scan_dir}/_build")
  @miniio.mkdir("\{scan_dir}/.git")
  @miniio.mkdir("\{scan_dir}/.mooncakes")
  @miniio.mkdir("\{scan_dir}/target")
  write_rule_file(rules_dir, structural_target_rule())
  @miniio.write_text_file("\{scan_dir}/hit.mbt", "fn sample { target() }\n")
  @miniio.write_text_file("\{scan_dir}/ignored.txt", "target()\n")
  @miniio.write_text_file(
    "\{scan_dir}/_build/ignored.mbt",
    "fn sample { target() }\n",
  )
  @miniio.write_text_file(
    "\{scan_dir}/.git/ignored.mbt",
    "fn sample { target() }\n",
  )
  @miniio.write_text_file(
    "\{scan_dir}/.mooncakes/ignored.mbt",
    "fn sample { target() }\n",
  )
  @miniio.write_text_file(
    "\{scan_dir}/target/ignored.mbt",
    "fn sample { target() }\n",
  )
  let result = collect_directory_hits({
    rules_root: Some(rules_dir),
    patterns: [],
    scan_root: scan_dir,
    verbose: false,
  })
  inspect(result.hits.length(), content="1")
  assert_true(result.hits[0].file.has_suffix("hit.mbt"))
}

///|
test "scan follows symlinked directories" {
  let files : Array[String] = []
  collect_source_files("testdata/symlink-fixtures/scan-dir-link", files, None)
  debug_inspect(
    files,
    content="[\"testdata/symlink-fixtures/scan-dir-link/hit.mbt\"]",
  )
}

///|
test "scan records parse failure warning and continues" {
  let root = moongrep_tmp_root("moongrep-parse-warning")
  let rules_dir = "\{root}/rules"
  let scan_dir = "\{root}/src"
  @miniio.mkdir(rules_dir)
  @miniio.mkdir(scan_dir)
  write_rule_file(rules_dir, structural_target_rule())
  @miniio.write_text_file("\{scan_dir}/bad.mbt", "fn sample { target()\n")
  @miniio.write_text_file("\{scan_dir}/hit.mbt", "fn sample { target() }\n")
  let result = collect_directory_hits({
    rules_root: Some(rules_dir),
    patterns: [],
    scan_root: scan_dir,
    verbose: false,
  })
  inspect(result.hits.length(), content="1")
  inspect(result.skipped_files.length(), content="1")
  assert_true(result.skipped_files[0].reason.has_prefix("parse failed due to"))
}

///|
test "scan prefilter skips parse failures for irrelevant files" {
  let root = moongrep_tmp_root("moongrep-prefilter-skip")
  let rules_dir = "\{root}/rules"
  let scan_dir = "\{root}/src"
  @miniio.mkdir(rules_dir)
  @miniio.mkdir(scan_dir)
  write_rule_file(rules_dir, structural_target_rule())
  @miniio.write_text_file("\{scan_dir}/bad.mbt", "fn sample {\n")
  let result = collect_directory_hits({
    rules_root: Some(rules_dir),
    patterns: [],
    scan_root: scan_dir,
    verbose: false,
  })
  inspect(result.hits.length(), content="0")
  inspect(result.skipped_files.length(), content="0")
}

///|
test "scan prefilter keeps unfilterable rules relevant" {
  let root = moongrep_tmp_root("moongrep-prefilter-general")
  let rules_dir = "\{root}/rules"
  let scan_dir = "\{root}/src"
  @miniio.mkdir(rules_dir)
  @miniio.mkdir(scan_dir)
  let general_rule =
    #|package: example/pkg
    #|description: |
    #|  Any expression.
    #|patterns:
    #|  - shape: _expr
    #|    metavars:
    #|      subtree: [_expr]
    #|
  write_rule_file(rules_dir, general_rule)
  @miniio.write_text_file("\{scan_dir}/bad.mbt", "fn sample {\n")
  let result = collect_directory_hits({
    rules_root: Some(rules_dir),
    patterns: [],
    scan_root: scan_dir,
    verbose: false,
  })
  inspect(result.hits.length(), content="0")
  inspect(result.skipped_files.length(), content="1")
}

///|
fn rule_ids(rules : Array[@rules.CompiledRule]) -> Array[String] {
  let ids : Array[String] = []
  for rule in rules {
    ids.push(rule.rule_id)
  }
  ids
}

///|
test "scan prefilter narrows rules by impl source text" {
  let root = moongrep_tmp_root("moongrep-prefilter-impl")
  let rules_dir = "\{root}/rules"
  @miniio.mkdir(rules_dir)
  @miniio.write_text_file("\{rules_dir}/target.yaml", structural_target_rule())
  let other_rule =
    #|package: example/pkg
    #|description: |
    #|  Other call.
    #|patterns:
    #|  - shape: other()
    #|
  @miniio.write_text_file("\{rules_dir}/other.yaml", other_rule)
  let compiled_rules = @rules.compile_rules(@rules.load_rules(rules_dir))
  let source =
    #|fn first {
    #|  target()
    #|}
    #|
    #|fn second {
    #|  other()
    #|}
    #|
  let (impls, reports) = @parser.parse_string(source, name="impl-filter.mbt")
  inspect(reports.length(), content="0")
  let nodes = impls.to_array()
  guard nodes is [first, second] else { fail("expected two impls") }
  let first_rules = @rules.prefilter_rules_for_source(
    compiled_rules,
    source_text_for_impl(source, first),
  )
  let second_rules = @rules.prefilter_rules_for_source(
    compiled_rules,
    source_text_for_impl(source, second),
  )
  debug_inspect(rule_ids(first_rules), content="[\"target\"]")
  debug_inspect(rule_ids(second_rules), content="[\"other\"]")
}

///|
test "render prints warnings before no hits" {
  let output = render_directory_scan_result({
    scan_trace: [],
    hits: [],
    skipped_files: [{ file: "bad.mbt", reason: "parse failed due to nope" }],
  })
  inspect(
    output,
    content="warning: skipping bad.mbt: parse failed due to nope\n\nno match hits",
  )
}

///|
test "render prints verbose scan traversal before hits" {
  let root = moongrep_tmp_root("moongrep-verbose")
  let rules_dir = "\{root}/rules"
  let scan_dir = "\{root}/src"
  let nested_dir = "\{scan_dir}/nested"
  @miniio.mkdir(rules_dir)
  @miniio.mkdir(scan_dir)
  @miniio.mkdir("\{scan_dir}/_build")
  @miniio.mkdir(nested_dir)
  write_rule_file(rules_dir, structural_target_rule())
  @miniio.write_text_file("\{nested_dir}/hit.mbt", "fn sample { target() }\n")
  @miniio.write_text_file(
    "\{scan_dir}/_build/ignored.mbt",
    "fn sample { target() }\n",
  )
  let output = render_directory_scan_result(
    collect_directory_hits({
      rules_root: Some(rules_dir),
      patterns: [],
      scan_root: scan_dir,
      verbose: true,
    }),
  )
  let expected_prefix = [
      "moongrep scan: entering \{scan_dir}",
      "moongrep scan: skipping \{scan_dir}/_build",
      "moongrep scan: entering \{nested_dir}",
      "moongrep scan: file \{nested_dir}/hit.mbt",
    ].join("\n") +
    "\n\n"
  assert_true(output.has_prefix(expected_prefix))
  assert_true(output.contains("rule: example"))
}

///|
test "render prints structural hit location and description" {
  let root = moongrep_tmp_root("moongrep-render-hit")
  let rules_dir = "\{root}/rules"
  let scan_dir = "\{root}/src"
  @miniio.mkdir(rules_dir)
  @miniio.mkdir(scan_dir)
  write_rule_file(rules_dir, structural_target_rule())
  @miniio.write_text_file("\{scan_dir}/hit.mbt", "fn sample { target() }\n")
  let result = collect_directory_hits({
    rules_root: Some(rules_dir),
    patterns: [],
    scan_root: scan_dir,
    verbose: false,
  })
  let output = render_directory_scan_result(result)
  assert_true(output.contains("rule: example"))
  assert_true(output.contains("description:\n  Target call."))
}

///|
test "scan reports taint hits" {
  let root = moongrep_tmp_root("moongrep-taint-hit")
  let rules_dir = "\{root}/rules"
  let scan_dir = "\{root}/src"
  @miniio.mkdir(rules_dir)
  @miniio.mkdir(scan_dir)
  write_rule_file(rules_dir, taint_user_rule())
  @miniio.write_text_file(
    "\{scan_dir}/hit.mbt",
    "fn sample { let x = get_user_input(); sink(x) }\n",
  )
  let result = collect_directory_hits({
    rules_root: Some(rules_dir),
    patterns: [],
    scan_root: scan_dir,
    verbose: false,
  })
  inspect(result.hits.length(), content="1")
  inspect(result.hits[0].rule_id, content="example")
}

///|
test "scan uses selected rules directory" {
  let root = moongrep_tmp_root("moongrep-custom-rules")
  let left_rules = "\{root}/left-rules"
  let right_rules = "\{root}/right-rules"
  let scan_dir = "\{root}/src"
  @miniio.mkdir(left_rules)
  @miniio.mkdir(right_rules)
  @miniio.mkdir(scan_dir)
  write_rule_file(left_rules, structural_target_rule())
  let right_rule =
    #|package: example/pkg
    #|description: |
    #|  Other call.
    #|patterns:
    #|  - shape: other()
    #|
  write_rule_file(right_rules, right_rule)
  @miniio.write_text_file("\{scan_dir}/hit.mbt", "fn sample { target() }\n")
  let left = collect_directory_hits({
    rules_root: Some(left_rules),
    patterns: [],
    scan_root: scan_dir,
    verbose: false,
  })
  let right = collect_directory_hits({
    rules_root: Some(right_rules),
    patterns: [],
    scan_root: scan_dir,
    verbose: false,
  })
  inspect(left.hits.length(), content="1")
  inspect(right.hits.length(), content="0")
}

///|
test "scan applies anonymous cli pattern without rules directory" {
  let root = moongrep_tmp_root("moongrep-cli-pattern")
  let scan_dir = "\{root}/src"
  @miniio.mkdir(scan_dir)
  @miniio.write_text_file("\{scan_dir}/hit.mbt", "fn sample { target() }\n")
  match parse_cli_command(["scan", "--pattern", "target()", scan_dir]) {
    ("scan", Some(options), None) => {
      let result = collect_directory_hits(options)
      inspect(result.hits.length(), content="1")
      inspect(result.hits[0].rule_id, content="<pattern>")
      inspect(result.hits[0].package_name, content="<unknown>")
    }
    _ => fail("unexpected command")
  }
}
