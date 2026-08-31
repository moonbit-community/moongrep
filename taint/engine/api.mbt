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
