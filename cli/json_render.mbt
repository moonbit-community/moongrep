///|
priv struct JsonScanPosition {
  line : Int
  column : Int
} derive(ToJson)

///|
priv struct JsonScanRange {
  start : JsonScanPosition
  end : JsonScanPosition
} derive(ToJson)

///|
priv struct JsonSourceContextLine {
  line : Int
  text : String
  is_match : Bool
} derive(ToJson)

///|
priv struct JsonScanFinding {
  file : String
  rule_id : String
  description : String
  range : JsonScanRange
  outer_range : Json
  matched_source : String
  source_context : Array[JsonSourceContextLine]
} derive(ToJson)

///|
fn json_scan_range(loc : @basic.Location) -> JsonScanRange {
  {
    start: { line: loc.start.lnum, column: loc.start.column() },
    end: { line: loc.end.lnum, column: loc.end.column() },
  }
}

///|
fn json_source_context(context : SourceContext) -> Array[JsonSourceContextLine] {
  let lines : Array[JsonSourceContextLine] = []
  for line in context.lines {
    lines.push({
      line: line.line_number,
      text: line.text,
      is_match: line.is_match,
    })
  }
  lines
}

///|
fn json_scan_finding(hit : ScanHit) -> JsonScanFinding {
  let finding = hit.finding
  {
    file: finding.file,
    rule_id: finding.rule_id,
    description: trim_trailing_newlines(finding.description),
    range: json_scan_range(finding.loc),
    outer_range: match finding.outer_loc {
      Some(loc) => json_scan_range(loc).to_json()
      None => Json::null()
    },
    matched_source: hit.matched_source,
    source_context: json_source_context(hit.source_context),
  }
}

///|
fn render_scan_hit_json(hit : ScanHit) -> String {
  json_scan_finding(hit).to_json().stringify()
}

///|
// JSON stdout is finding-only: scan trace, parse warnings, and the human
// no-match summary are omitted so every non-empty line is a machine-readable
// finding record. Parse warnings are written separately to stderr.
fn render_directory_scan_json(result : DirectoryScanResult) -> String {
  let records : Array[String] = []
  for hit in result.hits {
    records.push(render_scan_hit_json(hit))
  }
  records.join("\n")
}
