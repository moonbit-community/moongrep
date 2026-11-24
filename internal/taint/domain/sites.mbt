///|
/// Where a tainted value or sink value came from.
#derive(Eq, Debug)
pub(all) enum ValueSite {
  /// A concrete storage path such as a parameter, local, field, tuple item, or
  /// array element.
  Path(StoragePath)
  /// The result of a call, with an optional callee name and parser location.
  CallResult(String?, @basic.Location)
  /// An arbitrary expression that could not be represented as a `StoragePath`.
  Expr(@basic.Location, String?)
  /// A caller-supplied synthetic site for model-only origins.
  Synthetic(String)
}

///|
/// A source of taint attached to a value.
#derive(Eq, Debug)
pub(all) struct TaintOrigin {
  rule_id : String
  origin_id : String
  site : ValueSite
  note : String?
}

///|
/// Identifies a sink independently of the taint engine.
///
/// Generic taint models should use `Named`. `PatternIndex` is a zero-based
/// index used by rule lowering when a sink corresponds to an ordered pattern.
#derive(Eq, Debug)
pub(all) enum SinkId {
  Named(String)
  PatternIndex(Int32)
}

///|
/// A reported taint sink hit.
///
/// - Declarative sink effects emit a finding only when at least one tainted
///   origin reaches the sink.
/// - Custom call transfers decide when to emit findings and supply each
///   finding's `sink_loc`; the engine keeps `sink_id` opaque.
/// - Findings store only sink identity and location (taint origins remain in
///   the propagated `TaintValue` trees).
#derive(Eq, Debug)
pub(all) struct SinkFinding {
  sink_id : SinkId
  sink_loc : @basic.Location
}

///|
pub extend ValueSite with Eq::{not_equal, equal}

///|
pub extend ValueSite with Debug::{to_repr}

///|
pub extend TaintOrigin with Eq::{not_equal, equal}

///|
pub extend TaintOrigin with Debug::{to_repr}

///|
pub extend SinkId with Eq::{not_equal, equal}

///|
pub extend SinkId with Debug::{to_repr}

///|
pub extend SinkFinding with Eq::{not_equal, equal}

///|
pub extend SinkFinding with Debug::{to_repr}
