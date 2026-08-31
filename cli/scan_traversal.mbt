///|
async fn scan_path(
  path : String,
  excludes : Array[String],
  scan_plan : @rule_apply.ScanPlan,
  verbose : Bool,
  receive : async (ScanEvent) -> Unit,
) -> Unit {
  let kind = @fs.kind(path) catch {
    @os_error.OSError(_) as err =>
      raise new_scan_input_os_error(path, "access scan path", err)
    err => raise new_scan_input_error(path, "access scan path", "\{err}")
  }
  match kind {
    Directory => {
      emit_scan_trace(verbose, receive, "moongrep scan: entering \{path}")
      let entries = @fs.readdir(path, sort=true) catch {
        @os_error.OSError(_) as err =>
          raise new_scan_input_os_error(path, "read scan directory", err)
        err => raise new_scan_input_error(path, "read scan directory", "\{err}")
      }
      for entry in entries {
        let child_path = join_scan_path(path, entry)
        if !should_skip_entry(child_path, entry, excludes) {
          scan_path(child_path, excludes, scan_plan, verbose, receive)
        } else {
          emit_scan_trace(
            verbose,
            receive,
            "moongrep scan: skipping \{child_path}",
          )
        }
      }
    }
    Regular =>
      if path.has_suffix(".mbt") {
        emit_scan_trace(verbose, receive, "moongrep scan: file \{path}")
        scan_source_file(path, scan_plan, receive)
      }
    _ => ()
  }
}

///|
async fn emit_scan_trace(
  verbose : Bool,
  receive : async (ScanEvent) -> Unit,
  message : String,
) -> Unit {
  if verbose {
    receive(Trace(message))
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
