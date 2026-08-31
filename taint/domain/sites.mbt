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
/// Returns all unique origins in this taint tree.
///
/// Origins keep their first-occurrence order across relative entries and are
/// deduplicated using full `TaintOrigin` equality.
pub fn taint_tree_origins(tree : TaintTree) -> Array[TaintOrigin] {
  let origins : Array[TaintOrigin] = []
  for entry in tree {
    for origin in entry.origins {
      if !origins.contains(origin) {
        origins.push(origin)
      }
    }
  }
  origins
}

///|
/// Identifies a sink independently of the taint engine.
///
/// Generic taint models should use `Named`. `PatternIndex` is a zero-based
/// index used by rule lowering when a sink corresponds to an ordered pattern.
pub(all) enum SinkId {
  Named(String)
  PatternIndex(Int)
} derive(Eq, Debug)

///|
/// A reported sink.
///
/// Declarative sink effects only produce findings with at least one tainted
/// origin. Findings supplied by `custom_transfer_call` are appended as-is, so
/// custom transfers must preserve invariants such as non-empty origins and a
/// correct sink location/site. The engine treats `sink_id` as opaque.
pub(all) struct SinkFinding {
  rule_id : String
  sink_id : SinkId
  sink_loc : @basic.Location
  sink_site : ValueSite
  origins : Array[TaintOrigin]
} derive(Eq, Debug)
