///|
fn moongrep_tmp_root(prefix : String) -> String raise {
  let base = match @sys.get_env_var("TMPDIR") {
    Some(path) => path
    None => "/tmp"
  }
  for index in 0..<1000 {
    let path = "\{base}/\{prefix}-\{index}"
    if !@fs.path_exists(path) {
      @fs.create_dir(path)
      return path
    }
  }
  fail("could not create temporary directory")
}

///|
fn write_rule_file(dir : String, body : String) -> Unit raise {
  @fs.write_string_to_file("\{dir}/example.yaml", body)
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
test "scan collects mbt hits and skips build directories" {
  let root = moongrep_tmp_root("moongrep-scan")
  let rules_dir = "\{root}/rules"
  let scan_dir = "\{root}/src"
  @fs.create_dir(rules_dir)
  @fs.create_dir(scan_dir)
  @fs.create_dir("\{scan_dir}/_build")
  @fs.create_dir("\{scan_dir}/.git")
  @fs.create_dir("\{scan_dir}/.mooncakes")
  @fs.create_dir("\{scan_dir}/target")
  write_rule_file(rules_dir, structural_target_rule())
  @fs.write_string_to_file("\{scan_dir}/hit.mbt", "fn sample { target() }\n")
  @fs.write_string_to_file("\{scan_dir}/ignored.txt", "target()\n")
  @fs.write_string_to_file(
    "\{scan_dir}/_build/ignored.mbt",
    "fn sample { target() }\n",
  )
  @fs.write_string_to_file(
    "\{scan_dir}/.git/ignored.mbt",
    "fn sample { target() }\n",
  )
  @fs.write_string_to_file(
    "\{scan_dir}/.mooncakes/ignored.mbt",
    "fn sample { target() }\n",
  )
  @fs.write_string_to_file(
    "\{scan_dir}/target/ignored.mbt",
    "fn sample { target() }\n",
  )
  let result = collect_directory_hits({
    rules_root: rules_dir,
    scan_root: scan_dir,
  })
  inspect(result.hits.length(), content="1")
  inspect(result.hits[0].file.has_suffix("hit.mbt"), content="true")
}

///|
test "scan records parse failure warning and continues" {
  let root = moongrep_tmp_root("moongrep-parse-warning")
  let rules_dir = "\{root}/rules"
  let scan_dir = "\{root}/src"
  @fs.create_dir(rules_dir)
  @fs.create_dir(scan_dir)
  write_rule_file(rules_dir, structural_target_rule())
  @fs.write_string_to_file("\{scan_dir}/bad.mbt", "fn sample {\n")
  @fs.write_string_to_file("\{scan_dir}/hit.mbt", "fn sample { target() }\n")
  let result = collect_directory_hits({
    rules_root: rules_dir,
    scan_root: scan_dir,
  })
  inspect(result.hits.length(), content="1")
  inspect(result.skipped_files.length(), content="1")
  inspect(
    result.skipped_files[0].reason.has_prefix("parse failed due to"),
    content="true",
  )
}

///|
test "render prints warnings before no hits" {
  let output = render_directory_scan_result({
    hits: [],
    skipped_files: [{ file: "bad.mbt", reason: "parse failed due to nope" }],
  })
  inspect(
    output,
    content="warning: skipping bad.mbt: parse failed due to nope\n\nno match hits",
  )
}

///|
test "render prints structural hit location and description" {
  let root = moongrep_tmp_root("moongrep-render-hit")
  let rules_dir = "\{root}/rules"
  let scan_dir = "\{root}/src"
  @fs.create_dir(rules_dir)
  @fs.create_dir(scan_dir)
  write_rule_file(rules_dir, structural_target_rule())
  @fs.write_string_to_file("\{scan_dir}/hit.mbt", "fn sample { target() }\n")
  let result = collect_directory_hits({
    rules_root: rules_dir,
    scan_root: scan_dir,
  })
  let output = render_directory_scan_result(result)
  inspect(output.contains("rule: example"), content="true")
  inspect(output.contains("description:\n  Target call."), content="true")
}

///|
test "scan reports taint hits" {
  let root = moongrep_tmp_root("moongrep-taint-hit")
  let rules_dir = "\{root}/rules"
  let scan_dir = "\{root}/src"
  @fs.create_dir(rules_dir)
  @fs.create_dir(scan_dir)
  write_rule_file(rules_dir, taint_user_rule())
  @fs.write_string_to_file(
    "\{scan_dir}/hit.mbt",
    "fn sample { let x = get_user_input(); sink(x) }\n",
  )
  let result = collect_directory_hits({
    rules_root: rules_dir,
    scan_root: scan_dir,
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
  @fs.create_dir(left_rules)
  @fs.create_dir(right_rules)
  @fs.create_dir(scan_dir)
  write_rule_file(left_rules, structural_target_rule())
  let right_rule =
    #|package: example/pkg
    #|description: |
    #|  Other call.
    #|patterns:
    #|  - shape: other()
    #|
  write_rule_file(right_rules, right_rule)
  @fs.write_string_to_file("\{scan_dir}/hit.mbt", "fn sample { target() }\n")
  let left = collect_directory_hits({
    rules_root: left_rules,
    scan_root: scan_dir,
  })
  let right = collect_directory_hits({
    rules_root: right_rules,
    scan_root: scan_dir,
  })
  inspect(left.hits.length(), content="1")
  inspect(right.hits.length(), content="0")
}
