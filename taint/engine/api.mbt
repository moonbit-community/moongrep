///|
/// Analyzes one function or method CST node using one taint specification.
///
/// Raises `TaintAnalysisError::UnsupportedFunctionLike` when `node` is not a
/// supported function-like implementation node.
pub fn analyze_function_like(
  node : @untyped_cst.CstNode,
  spec : TaintSpec,
) -> AnalysisResult raise {
  analyze_single_function_like(node, spec)
}

///|
/// Runs several taint specifications against the same function-like CST node.
///
/// Results are returned in the same order as `rules`.
pub fn analyze_function_like_multi(
  node : @untyped_cst.CstNode,
  rules : Array[TaintSpec],
) -> Array[AnalysisResult] raise {
  let results : Array[AnalysisResult] = []
  for spec in rules {
    results.push(analyze_single_function_like(node, spec))
  }
  results
}
