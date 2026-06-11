///|
fn write_integration_source(
  dir : String,
  name : String,
  source : String,
) -> Unit raise {
  @fs.write_string_to_file("\{dir}/\{name}.mbt", source)
}

///|
test "integration applies compatible async structural rule" {
  let root = moongrep_tmp_root("moongrep-integration-structural")
  let rules_dir = "\{root}/rules"
  let scan_dir = "\{root}/src"
  @fs.create_dir(rules_dir)
  @fs.create_dir(scan_dir)
  let rule_source =
    #|package: moonbitlang/async/fs
    #|description: |
    #|  `@fs.read_file(...)` reads the full target into memory.
    #|patterns:
    #|  - shape: |
    #|      @fs.read_file(__)
    #|
  write_rule_file(rules_dir, rule_source)
  write_integration_source(
    scan_dir, "hit", "fn sample { @fs.read_file(path) }\n",
  )
  let result = collect_directory_hits({
    rules_root: rules_dir,
    scan_root: scan_dir,
  })
  inspect(result.hits.length(), content="1")
  inspect(result.hits[0].rule_id, content="example")
}

///|
test "integration applies inside expr target traversal" {
  let root = moongrep_tmp_root("moongrep-integration-inside")
  let rules_dir = "\{root}/rules"
  let scan_dir = "\{root}/src"
  @fs.create_dir(rules_dir)
  @fs.create_dir(scan_dir)
  let rule_source =
    #|package: moonbitlang/core
    #|description: |
    #|  Local println shadows the builtin.
    #|inside-expr:
    #|  shape: |
    #|    let println = ___
    #|    __TARGET__
    #|patterns:
    #|  - shape: |
    #|      println(___)
    #|
  write_rule_file(rules_dir, rule_source)
  let source =
    #|fn sample {
    #|  let println = custom;
    #|  println("x")
    #|}
    #|
  write_integration_source(scan_dir, "hit", source)
  let result = collect_directory_hits({
    rules_root: rules_dir,
    scan_root: scan_dir,
  })
  inspect(result.skipped_files.length(), content="0")
  inspect(result.hits.length(), content="1")
  inspect(result.hits[0].outer_loc is Some(_), content="true")
}

///|
test "integration applies taint rule and sanitizer" {
  let root = moongrep_tmp_root("moongrep-integration-taint")
  let rules_dir = "\{root}/rules"
  let scan_dir = "\{root}/src"
  @fs.create_dir(rules_dir)
  @fs.create_dir(scan_dir)
  let rule_source =
    #|package: moonbit-community/rabbita/html
    #|description: |
    #|  Attrs built with `inner_html(...)` carry raw DOM content.
    #|taint:
    #|  sources:
    #|    - shape: |
    #|        @html.Attrs::build().inner_html(__)
    #|  sinks:
    #|    - shape: |
    #|        @html.div(class=__, attrs=__SOURCE__, __)
    #|  sanitizers:
    #|    - shape: sanitize(__SOURCE__)
    #|
  write_rule_file(rules_dir, rule_source)
  let hit_source =
    #|fn hit(raw, child) {
    #|  let attrs = @html.Attrs::build().inner_html(raw);
    #|  @html.div(class="x", attrs=attrs, child)
    #|}
    #|
  write_integration_source(scan_dir, "hit", hit_source)
  let safe_source =
    #|fn safe(raw, child) {
    #|  let attrs = sanitize(@html.Attrs::build().inner_html(raw));
    #|  @html.div(class="x", attrs=attrs, child)
    #|}
    #|
  write_integration_source(scan_dir, "safe", safe_source)
  let result = collect_directory_hits({
    rules_root: rules_dir,
    scan_root: scan_dir,
  })
  inspect(result.skipped_files.length(), content="0")
  inspect(result.hits.length(), content="1")
}
