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
/// Taint carried by a relative path below the current value.
///
/// An empty `path` means the value itself is tainted. Non-empty paths describe
/// tainted subvalues, for example a field inside a record value.
pub(all) struct RelativeTaint {
  path : Array[PathSegment]
  origins : Array[TaintOrigin]
} derive(Eq, Debug)

///|
/// A set of relative taint entries for a single evaluated expression.
pub type TaintTree = Array[RelativeTaint]

///|
/// A reported sink.
///
/// Declarative sink effects only produce findings with at least one tainted
/// origin. Findings supplied by `custom_transfer_call` are appended as-is, so
/// custom transfers must preserve invariants such as non-empty origins and a
/// correct sink location/site.
pub(all) struct SinkFinding {
  rule_id : String
  sink_id : String
  sink_loc : @basic.Location
  sink_site : ValueSite
  origins : Array[TaintOrigin]
} derive(Eq, Debug)
