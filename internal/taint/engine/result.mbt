///|
/// The SCC budget belongs to analysis, independently of the rule model.
pub(all) struct AnalysisOptions {
  max_scc_rounds : Int32
}

///|
pub fn AnalysisOptions::default() -> AnalysisOptions {
  { max_scc_rounds: 64, }
}

///|
pub(all) enum AnalysisResult {
  Complete(Array[SinkFinding])
  Incomplete(Array[@lowering.Diagnostic])
}

///|
pub using @cfg {type InvalidGraph}
