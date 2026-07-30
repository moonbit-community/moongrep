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
  let warnings = render_skipped_file_warnings(result.skipped_files)
  if warnings != "" {
    sections.push(warnings)
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
fn render_skipped_file_warnings(skipped_files : Array[SkippedFile]) -> String {
  let warnings : Array[String] = []
  for skipped in skipped_files {
    warnings.push(render_skipped_file_warning(skipped))
  }
  warnings.join("\n")
}

///|
fn render_skipped_file_warning(skipped : SkippedFile) -> String {
  if skipped.block_start_line is Some(line) {
    "warning: skipping \{skipped.file} block starting at line \{line}: \{skipped.reason}"
  } else {
    "warning: skipping \{skipped.file}: \{skipped.reason}"
  }
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
  let mut line_number_width = 1
  for context_line in hit.source_context.lines {
    let width = context_line.line_number.to_string().length()
    if width > line_number_width {
      line_number_width = width
    }
  }
  let collapse_match = finding.loc.end.lnum - finding.loc.start.lnum + 1 > 6
  let first_omitted_line = finding.loc.start.lnum + 3
  let last_omitted_line = finding.loc.end.lnum - 3
  let mut rendered_omission = false
  let mut previous_line_indent = ""
  for context_line in hit.source_context.lines {
    if collapse_match &&
      context_line.is_match &&
      context_line.line_number >= first_omitted_line &&
      context_line.line_number <= last_omitted_line {
      if !rendered_omission {
        lines.push(
          render_omitted_source_lines(
            first_omitted_line,
            last_omitted_line,
            line_number_width,
            previous_line_indent,
            no_color~,
          ),
        )
        rendered_omission = true
      }
    } else {
      lines.push(
        render_source_context_line(
          context_line,
          finding.loc,
          line_number_width,
          no_color~,
        ),
      )
      previous_line_indent = leading_whitespace(context_line.text)
    }
  }
  lines.join("\n")
}

///|
fn render_source_context_line(
  line : SourceContextLine,
  match_loc : @basic.Location,
  line_number_width : Int,
  no_color? : Bool = false,
) -> String {
  let separator = if no_color && line.is_match { " > " } else { " | " }
  let line_number = line.line_number
    .to_string()
    .pad_start(line_number_width, ' ')
  let prefix = "\{line_number}\{separator}"
  if line.is_match {
    if no_color {
      prefix + line.text
    } else {
      prefix + render_highlighted_match_text(line, match_loc)
    }
  } else if no_color {
    prefix + line.text
  } else {
    render_gray(prefix + line.text)
  }
}

///|
fn leading_whitespace(text : String) -> String {
  let mut end = 0
  while end < text.length() && (text[end] == ' ' || text[end] == '\t') {
    end += 1
  }
  text[:end].to_owned()
}

///|
fn render_highlighted_match_text(
  line : SourceContextLine,
  match_loc : @basic.Location,
) -> String {
  let raw_start = if line.line_number == match_loc.start.lnum {
    match_loc.start.column() - 1
  } else {
    0
  }
  let raw_end = if line.line_number == match_loc.end.lnum {
    match_loc.end.column() - 1
  } else {
    line.text.length()
  }
  let start = if raw_start < 0 {
    0
  } else if raw_start > line.text.length() {
    line.text.length()
  } else {
    raw_start
  }
  let end = if raw_end < start {
    start
  } else if raw_end > line.text.length() {
    line.text.length()
  } else {
    raw_end
  }
  if start == end {
    line.text
  } else {
    line.text[:start].to_owned() +
    render_yellow(line.text[start:end].to_owned()) +
    line.text[end:].to_owned()
  }
}

///|
fn render_omitted_source_lines(
  first_line : Int,
  last_line : Int,
  line_number_width : Int,
  indent : String,
  no_color? : Bool = false,
) -> String {
  let count = last_line - first_line + 1
  let line_range = if first_line == last_line {
    first_line.to_string()
  } else {
    "\{first_line}-\{last_line}"
  }
  let omission_width = (first_line - 1).to_string().length()
  let omission_marker = "."
    .repeat(omission_width)
    .pad_start(line_number_width, ' ')
  let separator = if no_color { " > " } else { " | " }
  let noun = if count == 1 { "line" } else { "lines" }
  let rendered = "\{omission_marker}\{separator}\{indent}line \{line_range}: \{count} matched \{noun} omitted"
  if no_color {
    rendered
  } else {
    render_gray(rendered)
  }
}

///|
fn render_gray(text : String) -> String {
  @chalk.chalk().color(BlackBright).render(text)
}

///|
fn render_yellow(text : String) -> String {
  @chalk.chalk().color(YellowBright).render(text)
}

///|
fn format_location(file : String, loc : @basic.Location) -> String {
  "\{file}:\{loc.start.lnum}:\{loc.start.column()}-\{loc.end.lnum}:\{loc.end.column()}"
}

///|
fn trim_trailing_newlines(input : String) -> String {
  let mut end = input.length()
  while end > 0 && input[end - 1:end].to_owned() == "\n" {
    end -= 1
  }
  input[:end].to_owned()
}
