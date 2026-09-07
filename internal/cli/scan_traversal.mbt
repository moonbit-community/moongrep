///|
async fn scan_path(
  path : String,
  excludes : Array[String],
  scan_plan : @rule_apply.ScanPlan,
  verbose : Bool,
  receive : async (ScanEvent) -> Unit,
) -> Unit {
  visit_source_files(
    path,
    excludes,
    file => scan_source_file(file, scan_plan, receive),
    trace => emit_scan_trace(verbose, receive, trace),
  )
}

///|
async fn visit_source_files(
  path : String,
  excludes : Array[String],
  process_file : async (String) -> Unit,
  trace : async (ScanTrace) -> Unit,
) -> Unit {
  let visited = @fs_walk.VisitedDirectories::new()
  visit_source_path_once(path, excludes, process_file, trace, visited)
}

///|
async fn visit_source_path_once(
  path : String,
  excludes : Array[String],
  process_file : async (String) -> Unit,
  trace : async (ScanTrace) -> Unit,
  visited : @fs_walk.VisitedDirectories,
) -> Unit {
  let kind = @fs.kind(path) catch {
    @os_error.OSError(_) as err =>
      raise new_scan_input_os_error(path, "access scan path", err)
    err => raise new_scan_input_error(path, "access scan path", "\{err}")
  }
  match kind {
    Directory => {
      let should_enter = visited.should_enter(path) catch {
        @os_error.OSError(_) as err =>
          raise new_scan_input_os_error(path, "resolve scan directory", err)
        err =>
          raise new_scan_input_error(path, "resolve scan directory", "\{err}")
      }
      if !should_enter {
        trace(PathSkipped(path))
        return
      }
      trace(DirectoryEntered(path))
      let entries = @fs.readdir(path, sort=true) catch {
        @os_error.OSError(_) as err =>
          raise new_scan_input_os_error(path, "read scan directory", err)
        err => raise new_scan_input_error(path, "read scan directory", "\{err}")
      }
      for entry in entries {
        let child_path = join_scan_path(path, entry)
        if !should_skip_entry(child_path, entry, excludes) {
          visit_source_path_once(
            child_path, excludes, process_file, trace, visited,
          )
        } else {
          trace(PathSkipped(child_path))
        }
      }
    }
    Regular =>
      if path.has_suffix(".mbt") {
        trace(FileStarted(path))
        process_file(path)
      }
    _ => ()
  }
}

///|
async fn emit_scan_trace(
  verbose : Bool,
  receive : async (ScanEvent) -> Unit,
  trace : ScanTrace,
) -> Unit {
  if verbose {
    receive(Trace(trace))
  }
}

///|
async fn read_text_file(path : String) -> String {
  @fs.read_file(path).text() catch {
    @os_error.OSError(_) as err =>
      raise new_scan_input_os_error(path, "read source file", err)
    err => raise new_scan_input_error(path, "read source file", "\{err}")
  }
}

///|
fn should_skip_entry(
  path : String,
  entry : String,
  excludes : Array[String],
) -> Bool {
  // Skip hidden entries plus dependency and build directories that are noisy
  // and are rarely intended scan targets.
  if entry.has_prefix(".") ||
    scan_path_matches(entry, "_build") ||
    scan_path_matches(entry, "node_modules") ||
    scan_path_matches(entry, "target") {
    return true
  }
  let normalized_path = normalize_scan_exclude(path)
  for exclude in excludes {
    if scan_path_matches(exclude, entry) ||
      scan_path_matches(exclude, normalized_path) {
      return true
    }
  }
  false
}
