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
  matched_source : String
  source_context : Array[JsonSourceContextLine]
}

///|
fn json_scan_range(loc : @basic.Location) -> JsonScanRange {
  {
    start: { line: loc.start.lnum, column: loc.start.column(), },
    end: { line: loc.end.lnum, column: loc.end.column(), },
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
    matched_source: hit.matched_source,
    source_context: json_source_context(hit.source_context),
  }
}

///|
fn render_scan_hit_json(hit : ScanHit) -> String {
  let finding = json_scan_finding(hit)
  let record : Map[String, Json] = Map([])
  record["type"] = Json::string("finding")
  record["file"] = Json::string(finding.file)
  record["rule_id"] = Json::string(finding.rule_id)
  record["description"] = Json::string(finding.description)
  record["range"] = ToJson::to_json(finding.range)
  record["matched_source"] = Json::string(finding.matched_source)
  record["source_context"] = ToJson::to_json(finding.source_context)
  Json::object(record).stringify()
}
