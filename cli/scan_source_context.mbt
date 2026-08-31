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
priv struct SourceLines {
  lines : Array[StringView]
  line_count : Int
}

///|
fn make_scan_hit(
  source_lines : SourceLines,
  finding : @rule_model.RuleFinding,
) -> ScanHit {
  {
    finding,
    matched_source: matched_source_for_location(source_lines, finding.loc),
    source_context: source_context_for_location(source_lines, finding.loc),
  }
}

///|
fn utf16_index_for_unicode_column(line : StringView, column : Int) -> Int {
  if column <= 1 {
    0
  } else if line.offset_of_nth_char(column - 1) is Some(index) {
    index
  } else {
    line.length()
  }
}

///|
fn cache_source_lines(source : String) -> SourceLines {
  let lines : Array[StringView] = source.split("\n").to_array()
  let line_count = if source.has_suffix("\n") && !lines.is_empty() {
    lines.length() - 1
  } else {
    lines.length()
  }
  { lines, line_count, }
}

///|
fn matched_source_for_location(
  source_lines : SourceLines,
  loc : @basic.Location,
) -> String {
  if source_lines.line_count == 0 ||
    loc.start.lnum <= 0 ||
    loc.end.lnum <= 0 ||
    loc.end.lnum < loc.start.lnum ||
    loc.start.lnum > source_lines.line_count ||
    loc.end.lnum > source_lines.line_count {
    return ""
  }
  let start_line = source_lines.lines[loc.start.lnum - 1]
  let end_line = source_lines.lines[loc.end.lnum - 1]
  let start_index = utf16_index_for_unicode_column(
    start_line,
    loc.start.column(),
  )
  let end_index = utf16_index_for_unicode_column(end_line, loc.end.column())
  if loc.start.lnum == loc.end.lnum {
    if end_index < start_index {
      ""
    } else {
      start_line[start_index:end_index].to_owned()
    }
  } else {
    let matched = StringBuilder()
    matched.write_stringview(start_line[start_index:])
    for line_number in (loc.start.lnum + 1)..<loc.end.lnum {
      matched.write_string("\n")
      matched.write_stringview(source_lines.lines[line_number - 1])
    }
    matched.write_string("\n")
    matched.write_stringview(end_line[:end_index])
    matched.to_string()
  }
}

///|
fn source_context_for_location(
  source_lines : SourceLines,
  loc : @basic.Location,
) -> SourceContext {
  if source_lines.line_count == 0 ||
    loc.start.lnum <= 0 ||
    loc.end.lnum <= 0 ||
    loc.end.lnum < loc.start.lnum ||
    loc.start.lnum > source_lines.line_count {
    return { lines: [], }
  }
  let start_line = if loc.start.lnum > 2 { loc.start.lnum - 2 } else { 1 }
  let end_line = if loc.end.lnum + 2 < source_lines.line_count {
    loc.end.lnum + 2
  } else {
    source_lines.line_count
  }
  let lines : Array[SourceContextLine] = []
  for line_number in start_line..<=end_line {
    lines.push({
      line_number,
      text: source_lines.lines[line_number - 1].to_owned(),
      is_match: line_number >= loc.start.lnum && line_number <= loc.end.lnum,
    })
  }
  { lines, }
}
