///|
// Renders warnings first and match hits second so parse failures never hide
// successful findings from other files.
fn render_directory_scan_result(
  result : DirectoryScanResult,
  no_color? : Bool = false,
) -> String {
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
      rendered_hits.push(render_scan_hit(hit, no_color~))
    }
    sections.push(rendered_hits.join("\n\n"))
  }
  sections.join("\n\n")
}

///|
// Keep hit output stable and line-oriented for downstream agents. The first
// line is always a location, followed by rule metadata and indented
// description text.
fn render_scan_hit(hit : ScanHit, no_color? : Bool = false) -> String {
  let finding = hit.finding
  let lines : Array[String] = [
    format_location(finding.file, finding.loc),
    "rule: \{finding.rule_id}",
  ]
  if finding.outer_loc is Some(loc) {
    lines.push("outer_loc: \{format_location(finding.file, loc)}")
  }
  lines.push("description:")
  let description = trim_trailing_newlines(finding.description)
  if description == "" {
    lines.push("  ")
  } else {
    for line in description.split("\n") {
      lines.push("  \{line}")
    }
  }
  lines.push("source:")
  for context_line in hit.source_context.lines {
    lines.push(render_source_context_line(context_line, no_color~))
  }
  lines.join("\n")
}

///|
fn render_source_context_line(
  line : SourceContextLine,
  no_color? : Bool = false,
) -> String {
  let separator = if no_color && line.is_match { " > " } else { " | " }
  let prefix = "\{line.line_number}\{separator}"
  if line.is_match {
    prefix + line.text
  } else if no_color {
    prefix + line.text
  } else {
    render_gray(prefix + line.text)
  }
}

///|
fn render_gray(text : String) -> String {
  @chalk.chalk().color(@chalk.Colors::BlackBright).render(text)
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
