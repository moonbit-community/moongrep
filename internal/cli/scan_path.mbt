///|
fn scan_uses_windows_paths() -> Bool {
  @path.sep == '\\'
}

///|
fn normalize_scan_root(path : String) -> String {
  if scan_uses_windows_paths() {
    @path.Path::normalize(path).to_string()
  } else {
    path
  }
}

///|
fn join_scan_path(directory : String, entry : String) -> String {
  if scan_uses_windows_paths() {
    @path.Path::join(directory, entry).to_string()
  } else {
    "\{directory}/\{entry}"
  }
}

///|
fn trim_windows_scan_trailing_separators(path : String) -> String {
  if (!path.has_suffix("\\") && !path.has_suffix("/")) ||
    @path.Path::dirname(path).to_string() == path {
    return path
  }
  let mut end = path.length()
  while end > 0 && (path[end - 1] == '\\' || path[end - 1] == '/') {
    end -= 1
  }
  path[:end].to_owned()
}

///|
fn normalize_scan_exclude(path : String) -> String {
  if scan_uses_windows_paths() {
    if path == "" {
      return ""
    }
    trim_windows_scan_trailing_separators(
      @path.Path::normalize(path).to_string(),
    )
  } else {
    let mut normalized = path
    while normalized.length() > 1 && normalized.has_suffix("/") {
      normalized = normalized[0:normalized.length() - 1].to_owned()
    }
    while normalized.has_prefix("./") {
      normalized = normalized[2:].to_owned()
    }
    normalized
  }
}

///|
fn normalize_scan_excludes(paths : Array[String]) -> Array[String] {
  let normalized : Array[String] = []
  for path in paths {
    normalized.push(normalize_scan_exclude(path))
  }
  normalized
}

///|
fn scan_path_match_key(path : String) -> String {
  if !scan_uses_windows_paths() {
    return path
  }
  let folded = StringBuilder()
  for ch in path {
    folded.write_char(@unicode.to_lowercase(ch))
  }
  folded.to_string()
}

///|
fn scan_path_matches(left : String, right : String) -> Bool {
  scan_path_match_key(left) == scan_path_match_key(right)
}
