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
    let (impls, reports) = @parser.parse_string(source, name=file)
    if reports.length() > 0 {
      // Keep scanning other files even when one file fails to parse. This makes
      // the CLI useful on in-progress worktrees.
      skipped_files.push({
        file,
        reason: "parse failed due to \{compact_reports(reports)}",
      })
    } else {
      let structural_hits = @rules.apply_structural_rules(
        file, impls, compiled_rules,
      )
      for hit in structural_hits {
        hits.push(hit)
      }
      let taint_hits = @rules.apply_taint_rules(file, impls, compiled_rules)
      for hit in taint_hits {
        hits.push(hit)
      }
    }
  }
  { hits, skipped_files }
}

///|
fn collect_source_files(path : String, files : Array[String]) -> Unit raise {
  try {
    if @miniio.is_dir(path) {
      let entries = @miniio.readdir(path)
      entries.sort()
      for entry in entries {
        if !should_skip_entry(entry) {
          collect_source_files("\{path}/\{entry}", files)
        }
      }
    } else if @miniio.is_file(path) && path.has_suffix(".mbt") {
      files.push(path)
    }
  } catch {
    // TODO: miniio currently lacks public symlink/lstat/readlink/walk APIs, so
    // symlinks can only be recognized indirectly through Errno::Loop here.
    // Replace this with explicit symlink handling once miniio exposes enough
    // filesystem metadata.
    @miniio.Errno::Loop => ()
    e => raise e
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
