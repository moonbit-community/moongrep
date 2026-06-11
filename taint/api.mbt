///|
pub fn analyze_function_like(
  node : @syntax.Impl,
  spec : TaintSpec,
) -> AnalysisResult raise {
  analyze_single_function_like(node, spec)
}

///|
pub fn analyze_function_like_multi(
  node : @syntax.Impl,
  rules : Array[TaintSpec],
) -> Array[AnalysisResult] raise {
  let results : Array[AnalysisResult] = []
  for spec in rules {
    results.push(analyze_single_function_like(node, spec))
  }
  results
}
