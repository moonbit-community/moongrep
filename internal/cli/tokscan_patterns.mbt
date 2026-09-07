///|
fn prepare_tokscan_patterns(sources : Array[String]) -> @tokmatch.Matcher raise {
  if sources.is_empty() {
    raise new_usage_error("tokscan requires at least one --pattern")
  }
  @tokmatch.Matcher::compile(sources) catch {
    @tokmatch.PatternError(index~, reason~) =>
      raise new_tokscan_pattern_error(index, sources[index], reason)
  }
}

///|
fn new_tokscan_pattern_error(
  index : Int,
  source : String,
  reason : String,
) -> CliError {
  Usage(
    diagnostic=new_cli_diagnostic(
      "invalid tokscan pattern \{index + 1}",
      Some("--pattern \{index + 1}"),
      Some(reason),
      None,
      pattern=source,
    ),
  )
}
