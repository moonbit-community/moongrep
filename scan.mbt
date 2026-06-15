///|
// Scanner-local result type. The public library boundary is `rules.MatchHit`;
// parse failures stay here as warnings for the CLI renderer.
priv struct SkippedFile {
  file : String
  reason : String
}

///|
priv struct DirectoryScanResult {
  hits : Array[@rules.MatchHit]
  skipped_files : Array[SkippedFile]
}

///|
fn collect_directory_hits(options : CliOptions) -> DirectoryScanResult raise {
  let raw_rules = @rules.load_rules(options.rules_root)
  let compiled_rules = @rules.compile_rules(raw_rules)
  let files : Array[String] = []
  collect_source_files(options.scan_root, files)
  files.sort()
  let hits : Array[@rules.MatchHit] = []
  let skipped_files : Array[SkippedFile] = []
  for file in files {
    let source = @miniio.read_text_file(file)
    let file_rules = @rules.prefilter_rules_for_source(compiled_rules, source)
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
          let impl_rules = @rules.prefilter_rules_for_source(
            file_rules, impl_source,
          )
          if !impl_rules.is_empty() {
            let structural_hits = @rules.apply_structural_rules_to_impl(
              file, node, impl_rules,
            )
            for hit in structural_hits {
              hits.push(hit)
            }
            let taint_hits = @rules.apply_taint_rules_to_impl(
              file, node, impl_rules,
            )
            for hit in taint_hits {
              hits.push(hit)
            }
          }
        }
      }
    }
  }
  { hits, skipped_files }
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
fn collect_source_files(path : String, files : Array[String]) -> Unit raise {
  if @miniio.is_dir(path) {
    let entries = @miniio.readdir(path, sort=true, follow_symlink=true)
    for entry in entries {
      if !should_skip_entry(entry) {
        collect_source_files("\{path}/\{entry}", files)
      }
    }
  } else if @miniio.is_file(path) && path.has_suffix(".mbt") {
    files.push(path)
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
