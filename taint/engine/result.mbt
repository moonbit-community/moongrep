///|
/// Errors raised by the taint analyzer.
pub suberror TaintAnalysisError {
  /// The supplied parser `Impl` is not a function or method body that the
  /// analyzer can execute.
  UnsupportedFunctionLike(kind~ : String, loc~ : @basic.Location)
} derive(Debug)

///|
/// Result of analyzing one function-like CST node for one rule.
pub(all) struct AnalysisResult {
  rule_id : String
  function_name : String
  function_loc : @basic.Location
  findings : Array[SinkFinding]
}
