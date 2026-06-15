///|
// Renders warnings first and match hits second so parse failures never hide
// successful findings from other files.
fn render_directory_scan_result(result : DirectoryScanResult) -> String {
  let sections : Array[String] = []
  if result.scan_trace.length() > 0 {
    sections.push(result.scan_trace.join("\n"))
  }
  let warnings : Array[String] = []
  for skipped in result.skipped_files {
    warnings.push("warning: skipping \{skipped.file}: \{skipped.reason}")
  }
  if warnings.length() > 0 {
    sections.push(warnings.join("\n"))
  }
  if result.hits.length() == 0 {
    sections.push("no match hits")
  } else {
    let rendered_hits : Array[String] = []
    for hit in result.hits {
      rendered_hits.push(render_match_hit(hit))
    }
    sections.push(rendered_hits.join("\n\n"))
  }
  sections.join("\n\n")
}

///|
// Keep hit output stable and line-oriented for downstream agents. The first
// line is always a location, followed by rule metadata and indented
// description text.
fn render_match_hit(hit : @rules.MatchHit) -> String {
  let lines : Array[String] = [
    format_location(hit.file, hit.loc),
    "rule: \{hit.rule_id}",
  ]
  match hit.outer_loc {
    Some(loc) => lines.push("outer_loc: \{format_location(hit.file, loc)}")
    None => ()
  }
  lines.push("description:")
  let description = trim_trailing_newlines(hit.description)
  if description == "" {
    lines.push("  ")
  } else {
    for line in description.split("\n") {
      lines.push("  \{line}")
    }
  }
  lines.join("\n")
}

///|
fn format_location(file : String, loc : @basic.Location) -> String {
  "\{file}:\{loc.start.lnum}:\{loc.start.column()}-\{loc.end.lnum}:\{loc.end.column()}"
}

///|
fn trim_trailing_newlines(input : String) -> String {
  let mut end = input.length()
  while end > 0 && input[end - 1:end].to_owned() == "\n" {
    end = end - 1
  }
  input[:end].to_owned()
}
