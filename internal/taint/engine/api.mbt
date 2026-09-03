///|
/// Analyzes one function or method CST node using one taint specification.
///
/// Raises `TaintAnalysisError::UnsupportedFunctionLike` when `node` is not a
/// supported function-like implementation node. Raises
/// `TaintAnalysisError::FixpointDidNotConverge` when a loop state is still
/// growing after `spec.max_fixpoint_iterations` iterations.
pub fn analyze_function_like(
  node : @untyped_cst.CstNode,
  spec : TaintSpec,
) -> AnalysisResult raise {
  analyze_single_function_like(node, spec)
}
