///|
// Scanner-local result type. The rule model boundary is `rule_model.RuleFinding`;
// scan diagnostics stay here as warnings for the CLI renderer.
priv struct ParseWarning {
  file : String
  block_start_line : Int?
  reason : String
}

///|
priv enum ScanWarning {
  Parse(ParseWarning)
  InvalidMoongrepSkipPayload(String, @basic.Location)
}

///|
priv struct DirectoryScanResult {
  scan_trace : Array[String]
  hits : Array[ScanHit]
  warnings : Array[ScanWarning]
}

///|
priv struct ScanHit {
  finding : @rule_model.RuleFinding
  matched_source : String
  source_context : SourceContext
}

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
priv enum ScanEvent {
  Trace(String)
  Warning(ScanWarning)
  Hit(ScanHit)
}

///|
priv struct BufferedScanHit {
  hit : ScanHit
  ordinal : Int
}

///|
priv struct BufferedScanWarning {
  warning : ScanWarning
  ordinal : Int
}

///|
/// Runs a scan and renders its command-line output into one buffered string.
///
/// This compatibility API retains the historical file sorting and
/// warnings-first layout. The executable uses `run_scan_command` so matches
/// can be written as soon as they are found.
pub async fn render_scan_command(options : CliOptions) -> String {
  let result = collect_directory_hits(options)
  if options.output_json {
    let warnings = render_scan_warnings(result.warnings)
    if warnings != "" {
      @stdio.stderr.write(warnings + "\n")
    }
    render_directory_scan_json(result)
  } else {
    render_directory_scan_result(result, no_color=options.no_color)
  }
}

///|
async fn scan_events(
  options : CliOptions,
  receive : async (ScanEvent) -> Unit,
) -> Unit {
  let compiled_rules = prepare_scan_rules(options)
  let scan_plan = @rule_apply.ScanPlan::from_rules(compiled_rules)
  if options.verbose {
    for rule in compiled_rules {
      receive(Trace("moongrep scan: loaded rule \{rule.rule_id}"))
    }
  }
  let exclude_dirs = normalize_scan_exclude_dirs(options.exclude_dirs)
  scan_path(
    options.scan_root,
    exclude_dirs,
    scan_plan,
    options.verbose,
    receive,
  )
}

///|
async fn prepare_scan_rules(
  options : CliOptions,
) -> Array[@rule_model.CompiledRule] {
  let raw_rules = load_scan_rules(options)
  let enabled_rules = exclude_scan_rules(raw_rules, options.exclude_rules)
  @rule_compile.compile_rules(enabled_rules)
}

///|
async fn collect_directory_hits(options : CliOptions) -> DirectoryScanResult {
  let scan_trace : Array[String] = []
  let buffered_hits : Array[BufferedScanHit] = []
  let buffered_warnings : Array[BufferedScanWarning] = []
  scan_events(options, event => {
    match event {
      Trace(message) => scan_trace.push(message)
      Warning(warning) =>
        buffered_warnings.push({ warning, ordinal: buffered_warnings.length() })
      Hit(hit) => buffered_hits.push({ hit, ordinal: buffered_hits.length() })
    }
  })
  buffered_hits.sort_by(compare_buffered_scan_hits)
  buffered_warnings.sort_by(compare_buffered_scan_warnings)
  let hits : Array[ScanHit] = []
  for buffered in buffered_hits {
    hits.push(buffered.hit)
  }
  let warnings : Array[ScanWarning] = []
  for buffered in buffered_warnings {
    warnings.push(buffered.warning)
  }
  { scan_trace, hits, warnings }
}

///|
fn compare_buffered_scan_hits(
  left : BufferedScanHit,
  right : BufferedScanHit,
) -> Int {
  let file_order = left.hit.finding.file.compare(right.hit.finding.file)
  if file_order == 0 {
    left.ordinal.compare(right.ordinal)
  } else {
    file_order
  }
}

///|
fn ScanWarning::file(self : ScanWarning) -> String {
  match self {
    Parse(warning) => warning.file
    InvalidMoongrepSkipPayload(file, _) => file
  }
}

///|
fn compare_buffered_scan_warnings(
  left : BufferedScanWarning,
  right : BufferedScanWarning,
) -> Int {
  let file_order = left.warning.file().compare(right.warning.file())
  if file_order == 0 {
    left.ordinal.compare(right.ordinal)
  } else {
    file_order
  }
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
fn clamp_source_index(index : Int, length : Int) -> Int {
  if index < 0 {
    0
  } else if index > length {
    length
  } else {
    index
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
  { lines, line_count }
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
  let start_index = clamp_source_index(
    loc.start.column() - 1,
    start_line.length(),
  )
  let end_index = clamp_source_index(loc.end.column() - 1, end_line.length())
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
    return { lines: [] }
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

///|
async fn load_scan_rules(
  options : CliOptions,
) -> Array[@rule_model.RawRuleSpec] {
  let raw_rules : Array[@rule_model.RawRuleSpec] = []
  if options.enable_builtin_rules {
    raw_rules.append(@rule_builtin.load_rules())
  }
  if options.rules_root is Some(rules_root) {
    raw_rules.append(@rule_load.load_rules(rules_root))
  }
  if options.rule_file is Some(rule_file) {
    raw_rules.push(@rule_load.load_rule(rule_file))
  }
  for index in 0..<options.patterns.length() {
    raw_rules.push(anonymous_pattern_rule(options.patterns[index], index))
  }
  raw_rules
}

///|
fn exclude_scan_rules(
  raw_rules : Array[@rule_model.RawRuleSpec],
  exclude_rules : Array[String],
) -> Array[@rule_model.RawRuleSpec] raise {
  if exclude_rules.is_empty() {
    return raw_rules
  }
  ensure_exclude_rule_ids_exist(raw_rules, exclude_rules)
  let excluded : Map[String, Bool] = Map([])
  for rule_id in exclude_rules {
    excluded[rule_id] = true
  }
  let enabled : Array[@rule_model.RawRuleSpec] = []
  for raw in raw_rules {
    if !excluded.contains(raw.rule_id) {
      enabled.push(raw)
    }
  }
  enabled
}

///|
fn ensure_exclude_rule_ids_exist(
  raw_rules : Array[@rule_model.RawRuleSpec],
  exclude_rules : Array[String],
) -> Unit raise {
  let loaded : Map[String, Bool] = Map([])
  for raw in raw_rules {
    loaded[raw.rule_id] = true
  }
  for rule_id in exclude_rules {
    if !loaded.contains(rule_id) {
      raise CliError::Usage(
        message="unknown rule id in --exclude-rule: \{rule_id}",
        exit_code=2,
      )
    }
  }
}

///|
fn anonymous_pattern_rule(
  pattern : @rule_model.RulePatternSpec,
  _index : Int,
) -> @rule_model.RawRuleSpec {
  {
    path: pattern.shape,
    rule_id: pattern.shape,
    description: "Anonymous CLI pattern.",
    definition: Structural({
      inside_expr: [],
      inside_toplevel: [],
      patterns: [pattern],
      patterns_not: [],
      patterns_not_mode: PruneOnNegative,
    }),
  }
}

///|
priv struct MoongrepSkipAttributes {
  skip_structural : Bool
  invalid_payload_locations : Array[@basic.Location]
}

///|
fn impl_moongrep_skip_attributes(node : @syntax.Impl) -> MoongrepSkipAttributes {
  let attrs = match node {
    TopFuncDef(fun_decl~, ..) => fun_decl.attrs
    TopImpl(attrs~, ..) => attrs
    TopLetDef(attrs~, ..) => attrs
    TopTest(attrs~, ..) => attrs
    TopView(attrs~, ..) => attrs
    _ => return { skip_structural: false, invalid_payload_locations: [] }
  }
  analyze_moongrep_skip_attributes(attrs)
}

///|
fn analyze_moongrep_skip_attributes(
  attrs : @list.List[@attribute.Attribute],
) -> MoongrepSkipAttributes {
  let mut skip_structural = false
  let invalid_payload_locations : Array[@basic.Location] = []
  for attr in attrs {
    match attr.parsed {
      Some(Ident(id)) if attribute_id_is_moongrep_skip(id) =>
        if raw_moongrep_skip_is_bare(attr.raw) {
          skip_structural = true
        } else {
          invalid_payload_locations.push(attr.loc)
        }
      Some(Apply(id, _)) if attribute_id_is_moongrep_skip(id) =>
        invalid_payload_locations.push(attr.loc)
      None if unparsed_attribute_targets_moongrep_skip(attr.raw) =>
        invalid_payload_locations.push(attr.loc)
      _ => ()
    }
  }
  { skip_structural, invalid_payload_locations }
}

///|
fn attribute_id_is_moongrep_skip(id : @attribute.Id) -> Bool {
  id.qual == Some("moongrep") && id.name == "skip"
}

///|
fn raw_moongrep_skip_is_bare(raw : String) -> Bool {
  let prefix = "#moongrep.skip"
  raw.has_prefix(prefix) && raw[prefix.length():].is_blank()
}

///|
fn unparsed_attribute_targets_moongrep_skip(raw : String) -> Bool {
  let prefix = "#moongrep.skip"
  if !raw.has_prefix(prefix) {
    return false
  }
  if raw.length() == prefix.length() {
    return true
  }
  let next = raw[prefix.length()]
  !(next is ('a'..='z' | 'A'..='Z' | '0'..='9' | '_'))
}

///|
async fn scan_path(
  path : String,
  exclude_dirs : Array[String],
  scan_plan : @rule_apply.ScanPlan,
  verbose : Bool,
  receive : async (ScanEvent) -> Unit,
) -> Unit {
  match @fs.kind(path) {
    Directory => {
      emit_scan_trace(verbose, receive, "moongrep scan: entering \{path}")
      let entries = @fs.readdir(path, sort=true)
      for entry in entries {
        let child_path = "\{path}/\{entry}"
        if !should_skip_entry(child_path, entry, exclude_dirs) {
          scan_path(child_path, exclude_dirs, scan_plan, verbose, receive)
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
async fn scan_source_file(
  file : String,
  scan_plan : @rule_apply.ScanPlan,
  receive : async (ScanEvent) -> Unit,
) -> Unit {
  let source = read_text_file(file)
  let file_plan = scan_plan.filter_source(source)
  if file_plan.is_empty() {
    return
  }
  let source_lines = cache_source_lines(source)
  let blocks = split_source_blocks(source)
  let has_multiple_blocks = blocks.length() > 1
  for block in blocks {
    let block_plan = file_plan.filter_source(block.source)
    if block_plan.is_empty() {
      continue
    }
    let (impls, reports) = parse_source_block(block.source, file)
    if reports.length() > 0 {
      // A malformed matching block does not prevent other matching blocks in
      // the same file from being scanned.
      receive(
        Warning(
          Parse({
            file,
            block_start_line: if has_multiple_blocks {
              Some(block.start_line)
            } else {
              None
            },
            reason: "parse failed due to \{compact_scan_reports(reports)}",
          }),
        ),
      )
      continue
    }
    for node in impls {
      let untyped_node = @untyped_ast.from_impl(node)
      let skip = impl_moongrep_skip_attributes(node)
      for loc in skip.invalid_payload_locations {
        receive(
          Warning(InvalidMoongrepSkipPayload(file, block.rebase_location(loc))),
        )
      }
      if !skip.skip_structural {
        let structural_hits = @rule_apply.apply_structural_scan_plan_to_node(
          file, untyped_node, block_plan,
        )
        for finding in structural_hits {
          receive(
            Hit(make_scan_hit(source_lines, block.rebase_finding(finding))),
          )
        }
      }
      let taint_hits = @rule_apply.apply_taint_scan_plan_to_node(
        file, untyped_node, block_plan,
      )
      for finding in taint_hits {
        receive(Hit(make_scan_hit(source_lines, block.rebase_finding(finding))))
      }
    }
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
  @fs.read_file(path).text()
}

///|
fn should_skip_entry(
  path : String,
  entry : String,
  exclude_dirs : Array[String],
) -> Bool {
  // Skip dependency, build, and VCS directories that are noisy and are rarely
  // intended scan targets.
  entry == ".git" ||
  entry == "_build" ||
  entry == ".mooncakes" ||
  entry == "target" ||
  exclude_dirs.contains(entry) ||
  exclude_dirs.contains(normalize_scan_exclude_dir(path))
}

///|
fn compact_scan_reports(reports : Array[@basic.Report]) -> String {
  let messages : Array[String] = []
  for report in reports {
    messages.push(report.msg.replace_all(old="\n", new=" "))
  }
  messages.join(" ")
}
