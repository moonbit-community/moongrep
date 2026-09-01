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

///|
fn render_scan_warning_json(warning : ScanWarning) -> String {
  let record : Map[String, Json] = Map([])
  record["type"] = Json::string("warning")
  match warning {
    Parse(parse_warning) => {
      record["category"] = Json::string("parse")
      record["message"] = Json::string(scan_warning_message(warning))
      record["file"] = Json::string(parse_warning.file)
      record["reason"] = Json::string(parse_warning.reason)
      match parse_warning.block_start_line {
        Some(line) => record["block_start_line"] = ToJson::to_json(line)
        None => ()
      }
    }
    InvalidMoongrepSkipPayload(file, loc) => {
      record["category"] = Json::string("invalid_skip_payload")
      record["message"] = Json::string(scan_warning_message(warning))
      record["file"] = Json::string(file)
      record["range"] = ToJson::to_json(json_scan_range(loc))
    }
  }
  Json::object(record).stringify()
}

///|
fn render_scan_trace_json(trace : ScanTrace) -> String {
  let record : Map[String, Json] = Map([])
  record["type"] = Json::string("trace")
  match trace {
    RuleLoaded(rule_id) => {
      record["event"] = Json::string("rule_loaded")
      record["rule_id"] = Json::string(rule_id)
    }
    DirectoryEntered(path) => {
      record["event"] = Json::string("directory_entered")
      record["path"] = Json::string(path)
    }
    PathSkipped(path) => {
      record["event"] = Json::string("path_skipped")
      record["path"] = Json::string(path)
    }
    FileStarted(path) => {
      record["event"] = Json::string("file_started")
      record["path"] = Json::string(path)
    }
  }
  Json::object(record).stringify()
}
