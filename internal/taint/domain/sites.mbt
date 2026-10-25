///|
/// Where a tainted value or sink value came from.
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
} derive(Eq, Debug)

///|
/// A source of taint attached to a value.
pub(all) struct TaintOrigin {
  rule_id : String
  origin_id : String
  site : ValueSite
  note : String?
} derive(Eq, Debug)

///|
/// Identifies a sink independently of the taint engine.
///
/// Generic taint models should use `Named`. `PatternIndex` is a zero-based
/// index used by rule lowering when a sink corresponds to an ordered pattern.
pub(all) enum SinkId {
  Named(String)
  PatternIndex(Int32)
} derive(Eq, Debug)

///|
/// A reported sink.
///
/// Declarative sink effects only produce findings with at least one tainted
/// origin. Findings supplied by a custom call transfer are appended as-is, so
/// custom transfers decide when to report a sink and supply its location.
/// Findings retain only the sink identity and location; origins stay in the
/// propagated taint trees. The engine treats `sink_id` as opaque.
pub(all) struct SinkFinding {
  sink_id : SinkId
  sink_loc : @basic.Location
} derive(Eq, Debug)

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
