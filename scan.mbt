///|
// Scanner-local result type. The rule model boundary is `rule_model.RuleFinding`;
// parse failures stay here as warnings for the CLI renderer.
priv struct SkippedFile {
  file : String
  reason : String
}

///|
priv struct DirectoryScanResult {
  scan_trace : Array[String]
  hits : Array[ScanHit]
  skipped_files : Array[SkippedFile]
}

///|
priv struct ScanHit {
  finding : @rule_model.RuleFinding
  source_context : SourceContext
}

///|
priv struct SourceContext {
  lines : Array[SourceContextLine]
}

///|
priv struct SourceContextLine {
  line_number : Int
  text : String
  is_match : Bool
}

///|
fn collect_directory_hits(options : CliOptions) -> DirectoryScanResult raise {
  let raw_rules = load_scan_rules(options)
  let compiled_rules = @rule_compile.compile_rules(raw_rules)
  let files : Array[String] = []
  let scan_trace : Array[String] = []
  collect_source_files(
    options.scan_root,
    files,
    if options.verbose {
      Some(scan_trace)
    } else {
      None
    },
  )
  files.sort()
  let hits : Array[ScanHit] = []
  let skipped_files : Array[SkippedFile] = []
  for file in files {
    let source = @miniio.read_text_file(file)
    let file_rules = @rule_prefilter.prefilter_rules_for_source(
      compiled_rules, source,
    )
    if !file_rules.is_empty() {
      let (impls, reports) = @parser.parse_string(source, name=file)
      if reports.length() > 0 {
        // Keep scanning other files even when one file fails to parse. This makes
        // the CLI useful on in-progress worktrees.
        skipped_files.push({
          file,
          reason: "parse failed due to \{compact_reports(reports)}",
        })
      } else {
        for node in impls {
          let impl_source = source_text_for_impl(source, node)
          let impl_rules = @rule_prefilter.prefilter_rules_for_source(
            file_rules, impl_source,
          )
          if !impl_rules.is_empty() {
            let structural_hits = @rule_apply.apply_structural_rules_to_impl_with_backend(
              file,
              node,
              impl_rules,
              options.matcher,
            )
            for hit in structural_hits {
              hits.push(make_scan_hit(source, hit))
            }
            let taint_hits = @rule_apply.apply_taint_rules_to_impl_with_backend(
              file,
              node,
              impl_rules,
              options.matcher,
            )
            for hit in taint_hits {
              hits.push(make_scan_hit(source, hit))
            }
          }
        }
      }
    }
  }
  { scan_trace, hits, skipped_files }
}

///|
fn make_scan_hit(source : String, finding : @rule_model.RuleFinding) -> ScanHit {
  { finding, source_context: source_context_for_location(source, finding.loc) }
}

///|
fn source_context_for_location(
  source : String,
  loc : @basic.Location,
) -> SourceContext {
  let split_lines = source.split("\n").to_array()
  let line_count = source_context_line_count(source, split_lines.length())
  if line_count == 0 ||
    loc.start.lnum <= 0 ||
    loc.end.lnum <= 0 ||
    loc.end.lnum < loc.start.lnum {
    return { lines: [] }
  }
  let start_line = if loc.start.lnum > 2 { loc.start.lnum - 2 } else { 1 }
  let end_line = if loc.end.lnum + 2 < line_count {
    loc.end.lnum + 2
  } else {
    line_count
  }
  let lines : Array[SourceContextLine] = []
  for line_number in start_line..<=end_line {
    lines.push({
      line_number,
      text: split_lines[line_number - 1].to_owned(),
      is_match: line_number >= loc.start.lnum && line_number <= loc.end.lnum,
    })
  }
  { lines, }
}

///|
fn source_context_line_count(source : String, split_line_count : Int) -> Int {
  if source.has_suffix("\n") && split_line_count > 0 {
    split_line_count - 1
  } else {
    split_line_count
  }
}

///|
fn load_scan_rules(
  options : CliOptions,
) -> Array[@rule_model.RawRuleSpec] raise {
  let raw_rules : Array[@rule_model.RawRuleSpec] = []
  if options.enable_builtin_rules {
    raw_rules.append(@rule_builtin.load_rules())
  }
  if options.rules_root is Some(rules_root) {
    raw_rules.append(@rule_load.load_rules(rules_root))
  }
  for index in 0..<options.patterns.length() {
    raw_rules.push(anonymous_pattern_rule(options.patterns[index], index))
  }
  raw_rules
}

///|
fn anonymous_pattern_rule(
  pattern : String,
  _index : Int,
) -> @rule_model.RawRuleSpec {
  {
    path: pattern,
    rule_id: pattern,
    description: "Anonymous CLI pattern.",
    definition: Structural({
      inside_expr: None,
      patterns: [{ shape: pattern, guards: {} }],
    }),
  }
}

///|
fn source_text_for_impl(source : String, node : @syntax.Impl) -> String {
  source_text_for_location(source, node.loc())
}

///|
fn source_text_for_location(source : String, loc : @basic.Location) -> String {
  let lines = source.split("\n").to_array()
  let start_line = loc.start.lnum
  let end_line = loc.end.lnum
  if start_line <= 0 || end_line <= 0 || end_line < start_line {
    return source
  }
  let start_index = start_line - 1
  let end_index = end_line
  if start_index >= lines.length() || end_index > lines.length() {
    return source
  }
  let block_lines = []
  for line in lines[start_index:end_index] {
    block_lines.push(line)
  }
  let block = block_lines.join("\n")
  if block.length() == 0 {
    source
  } else {
    block
  }
}

///|
fn collect_source_files(
  path : String,
  files : Array[String],
  scan_trace : Array[String]?,
) -> Unit raise {
  if @miniio.is_dir(path) {
    push_scan_trace(scan_trace, "moongrep scan: entering \{path}")
    let entries = @miniio.readdir(path, sort=true, follow_symlink=true)
    for entry in entries {
      if !should_skip_entry(entry) {
        collect_source_files("\{path}/\{entry}", files, scan_trace)
      } else {
        push_scan_trace(scan_trace, "moongrep scan: skipping \{path}/\{entry}")
      }
    }
  } else if @miniio.is_file(path) && path.has_suffix(".mbt") {
    files.push(path)
    push_scan_trace(scan_trace, "moongrep scan: file \{path}")
  }
}

///|
fn push_scan_trace(scan_trace : Array[String]?, message : String) -> Unit {
  if scan_trace is Some(lines) {
    lines.push(message)
  }
}

///|
fn should_skip_entry(entry : String) -> Bool {
  // Skip dependency, build, and VCS directories that are noisy and are rarely
  // intended scan targets.
  entry == ".git" ||
  entry == "_build" ||
  entry == ".mooncakes" ||
  entry == "target"
}

///|
fn compact_reports(reports : Array[@basic.Report]) -> String {
  let messages : Array[String] = []
  for report in reports {
    messages.push(report.msg.replace_all(old="\n", new=" "))
  }
  messages.join(" ")
}
