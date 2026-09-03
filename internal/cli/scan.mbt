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
priv enum ScanTrace {
  RuleLoaded(String)
  DirectoryEntered(String)
  PathSkipped(String)
  FileStarted(String)
}

///|
priv enum ScanEvent {
  Trace(ScanTrace)
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
      receive(Trace(RuleLoaded(rule.rule_id)))
    }
  }
  let excludes = normalize_scan_excludes(options.excludes)
  let scan_root = normalize_scan_root(options.scan_root)
  scan_path(scan_root, excludes, scan_plan, options.verbose, receive) catch {
    CliError::Output(..) as err => raise err
    CliError::ScanInput(..) as err => raise err
    CliError::Internal(..) as err => raise err
    @os_error.OSError(_) as err =>
      raise new_scan_input_os_error(scan_root, "access scan input", err)
    err => raise new_internal_error("scan failed: \{err}")
  }
}
