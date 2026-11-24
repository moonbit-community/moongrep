///|
/// Solver execution limits, configured independently of rule definitions.
pub(all) struct AnalysisOptions {
  max_scc_rounds : Int32
}

///|
/// Returns the default analysis options (`max_scc_rounds = 64`).
pub fn AnalysisOptions::default() -> AnalysisOptions {
  { max_scc_rounds: 64, }
}

///|
/// Outcome of running taint analysis for one `(PreparedFunction, TaintSpec)`
/// pair.
///
/// - `Complete`: every SCC converged and all findings are final.
/// - `Incomplete`: at least one SCC exceeded `max_scc_rounds`; partial findings
///   are suppressed and diagnostics explain the failure.
pub(all) enum AnalysisResult {
  Complete(Array[SinkFinding])
  Incomplete(Array[@lowering.Diagnostic])
}

///|
pub using @cfg {type InvalidGraph}
