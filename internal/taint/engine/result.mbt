///|
/// Errors raised by the taint analyzer.
pub suberror TaintAnalysisError {
  /// The supplied parser `Impl` is not a function or method body that the
  /// analyzer can execute.
  UnsupportedFunctionLike(kind~ : String, loc~ : @basic.Location)
  /// A loop's abstract state was still growing when its safety budget was
  /// exhausted, so no partial analysis result was produced.
  FixpointDidNotConverge(
    rule_id~ : String,
    loop_kind~ : String,
    loc~ : @basic.Location,
    budget~ : Int
  )
} derive(Debug)

///|
/// Result of analyzing one function-like CST node for one rule.
pub(all) struct AnalysisResult {
  rule_id : String
  function_name : String
  function_loc : @basic.Location
  findings : Array[SinkFinding]
}
