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
priv enum ScanMode {
  Scan
  Lint
}

///|
async fn scan_events(
  mode : ScanMode,
  options : CliOptions,
  receive : async (ScanEvent) -> Unit,
) -> Unit {
  let compiled_rules = prepare_scan_rules(mode, options)
  let scan_plan = @rule_apply.ScanPlan::from_rules(compiled_rules)
  if options.verbose {
    for rule in compiled_rules {
      receive(Trace("moongrep scan: loaded rule \{rule.rule_id}"))
    }
  }
  let excludes = normalize_scan_excludes(options.excludes)
  let scan_root = normalize_scan_root(options.scan_root)
  scan_path(scan_root, excludes, scan_plan, options.verbose, receive) catch {
    CliError::Output(..) as err => raise err
    err => raise CliError::ScanInput(message="\{err}")
  }
}

///|
async fn prepare_scan_rules(
  mode : ScanMode,
  options : CliOptions,
) -> Array[@rule_model.CompiledRule] {
  let builtin_rules = load_builtin_scan_rules(mode)
  let raw_rules = builtin_rules.copy()
  raw_rules.append(load_scan_rules(options))
  let enabled_rules = disable_scan_rules(raw_rules, options.disabled_rules)
  @rule_compile.compile_rules(enabled_rules) catch {
    @rule_model.RuleLoadError::InvalidRule(..) as err =>
      raise CliError::RuleContent(message="\{err}")
    @rule_model.RuleLoadError::NoRuleFiles(..) as err =>
      raise CliError::RuleSource(message="\{err}")
    err => raise err
  }
}

///|
fn load_builtin_scan_rules(
  mode : ScanMode,
) -> Array[@rule_model.RawRuleSpec] raise {
  if mode is Scan {
    return []
  }
  let rules = @rule_builtin.load_rules() catch {
    err => raise CliError::Internal(message="\{err}")
  }
  ignore(
    @rule_compile.compile_rules(rules) catch {
      err => raise CliError::Internal(message="\{err}")
    },
  )
  rules
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
  if options.rules_root is Some(rules_root) {
    raw_rules.append(load_rule_directory(rules_root))
  }
  if options.rule_file is Some(rule_file) {
    raw_rules.push(load_rule_file(rule_file))
  }
  for index in 0..<options.patterns.length() {
    raw_rules.push(anonymous_pattern_rule(options.patterns[index], index))
  }
  raw_rules
}

///|
async fn load_rule_directory(
  rules_root : String,
) -> Array[@rule_model.RawRuleSpec] {
  @rule_load.load_rules(rules_root) catch {
    @rule_model.RuleLoadError::NoRuleFiles(..) as err =>
      raise CliError::RuleSource(message="\{err}")
    @rule_model.RuleLoadError::InvalidRule(..) as err =>
      raise CliError::RuleContent(message="\{err}")
    err => raise CliError::RuleSource(message="\{err}")
  }
}

///|
async fn load_rule_file(rule_file : String) -> @rule_model.RawRuleSpec {
  @rule_load.load_rule(rule_file) catch {
    @rule_model.RuleLoadError::NoRuleFiles(..) as err =>
      raise CliError::RuleSource(message="\{err}")
    @rule_model.RuleLoadError::InvalidRule(..) as err =>
      raise CliError::RuleContent(message="\{err}")
    err => raise CliError::RuleSource(message="\{err}")
  }
}

///|
fn disable_scan_rules(
  raw_rules : Array[@rule_model.RawRuleSpec],
  disabled_rules : Array[String],
) -> Array[@rule_model.RawRuleSpec] raise {
  if disabled_rules.is_empty() {
    return raw_rules
  }
  ensure_disabled_rule_ids_exist(raw_rules, disabled_rules)
  let disabled : Map[String, Bool] = Map([])
  for rule_id in disabled_rules {
    disabled[rule_id] = true
  }
  let enabled : Array[@rule_model.RawRuleSpec] = []
  for raw in raw_rules {
    if !disabled.contains(raw.rule_id) {
      enabled.push(raw)
    }
  }
  enabled
}

///|
fn ensure_disabled_rule_ids_exist(
  raw_rules : Array[@rule_model.RawRuleSpec],
  disabled_rules : Array[String],
) -> Unit raise {
  let loaded : Map[String, Bool] = Map([])
  for raw in raw_rules {
    loaded[raw.rule_id] = true
  }
  for rule_id in disabled_rules {
    if !loaded.contains(rule_id) {
      raise CliError::Usage(message="unknown rule id in --disable: \{rule_id}")
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
fn impl_moongrep_skip_attributes(
  node : @untyped_cst.CstNode,
) -> MoongrepSkipAttributes {
  let mut skip_structural = false
  let invalid_payload_locations : Array[@basic.Location] = []
  for attr in @cst.attributes(node) {
    if attr.qualifier == Some("moongrep") && attr.name == "skip" {
      if attr.raw_payload == "" {
        skip_structural = true
      } else {
        invalid_payload_locations.push(attr.node.loc)
      }
    }
  }
  { skip_structural, invalid_payload_locations }
}

///|
async fn scan_path(
  path : String,
  excludes : Array[String],
  scan_plan : @rule_apply.ScanPlan,
  verbose : Bool,
  receive : async (ScanEvent) -> Unit,
) -> Unit {
  match @fs.kind(path) {
    Directory => {
      emit_scan_trace(verbose, receive, "moongrep scan: entering \{path}")
      let entries = @fs.readdir(path, sort=true)
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
      let skip = impl_moongrep_skip_attributes(node)
      for loc in skip.invalid_payload_locations {
        receive(
          Warning(InvalidMoongrepSkipPayload(file, block.rebase_location(loc))),
        )
      }
      if !skip.skip_structural {
        let structural_hits = @rule_apply.apply_structural_scan_plan_to_node(
          file, node, block_plan,
        )
        for finding in structural_hits {
          receive(
            Hit(make_scan_hit(source_lines, block.rebase_finding(finding))),
          )
        }
      }
      let taint_hits = @rule_apply.apply_taint_scan_plan_to_node(
        file, node, block_plan,
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
  excludes : Array[String],
) -> Bool {
  // Skip dependency, build, and VCS directories that are noisy and are rarely
  // intended scan targets.
  if scan_path_matches(entry, ".git") ||
    scan_path_matches(entry, "_build") ||
    scan_path_matches(entry, ".mooncakes") ||
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

///|
fn compact_scan_reports(reports : Array[@basic.Report]) -> String {
  let messages : Array[String] = []
  for report in reports {
    messages.push(report.msg.replace_all(old="\n", new=" "))
  }
  messages.join(" ")
}
