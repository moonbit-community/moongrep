///|
/// One possible call completion, including its own storage effects.
pub(all) struct CallOutcome {
  value : TaintValue
  writes : Array[StorageWrite]
} derive(Eq, Debug)

///|
pub(all) enum StorageWrite {
  Set(StoragePath, TaintValue)
  Sanitize(StoragePath)
} derive(Eq, Debug)

///|
/// None means that completion is impossible. Unknown calls never raise.
pub(all) struct CallTransfer {
  normal : CallOutcome?
  exceptional : CallOutcome?
  findings : Array[SinkFinding]
} derive(Eq, Debug)

///|
pub fn CallTransfer::normal(
  value : TaintValue,
  killed_paths~ : Array[StoragePath] = [],
  findings~ : Array[SinkFinding] = [],
) -> CallTransfer {
  {
    normal: Some({ value, writes: killed_paths.map(path => Sanitize(path)), }),
    exceptional: None,
    findings,
  }
}

///|
/// Fallback behavior for calls that do not match any source or call model.
///
/// `NoEffect` treats unknown calls as returning untainted values.
/// `PropagateArgumentsToReturn` returns the union of receiver and argument
/// taint.
pub(all) enum UnknownCallPolicy {
  NoEffect
  PropagateArgumentsToReturn
} derive(Eq, Debug)

///|
/// A rule-level source of taint.
///
/// `EntryPath` marks a parameter or modeled subpath as tainted when the root is
/// a named function parameter. Path segments are not validated against type or
/// field declarations.
/// `CallReturn` marks matching call results as fresh sources. Its path is
/// relative to the call return value; `[]` taints the return value itself.
pub(all) enum SourceModel {
  EntryPath(ParameterPath, String, String?)
  CallReturn(CallMatcher, String, String?, Array[PathSegment])
} derive(Eq, Debug)

///|
/// Selects calls for source and transfer models.
///
/// `CalleeName` matches any normalized `callee_name`, including direct calls,
/// method calls, pipes, and reverse-pipes when a callee name is available.
/// `MethodName` matches method calls and pipe calls whose normalized
/// `callee_name` matches; it does not match reverse-pipe calls.
/// `AnyCall` matches every call.
pub(all) enum CallMatcher {
  CalleeName(String)
  /// Select a resolved local or parameter call target, including shadowing.
  CalleeBinding(BindingId)
  MethodName(String)
  AnyCall
} derive(Eq, Debug)

///|
/// A declarative model for calls outside the current function body.
///
/// All matching call models are applied in array order; matching is not
/// first-match.
pub(all) struct CallModel {
  matcher : CallMatcher
  effects : Array[CallEffect]
} derive(Eq, Debug)

///|
/// Transfer effects applied when a call model matches.
///
/// Effects can introduce fresh return taint, propagate argument or receiver
/// taint to the return value, kill storage paths, or report sink findings.
/// `ReturnFreshSource` paths are relative to the call return value; `[]` taints
/// the return value itself. `PropagateArgSubpathToReturn` projects the selected
/// argument subpath and returns it with that prefix stripped. `KillArg` and
/// `KillReceiver` remove taint only from post-call storage when the selected
/// value has a storage path; they do not rewrite already evaluated
/// argument/receiver taint used by other effects on the same call.
/// Sink identifiers are passed through unchanged. Generic models should use
/// `SinkId::Named`; `SinkId::PatternIndex` is reserved for ordered rule
/// patterns.
pub(all) enum CallEffect {
  ReturnFreshSource(String, String?, Array[PathSegment])
  PropagateArgToReturn(Int32)
  PropagateReceiverToReturn
  PropagateArgSubpathToReturn(Int32, Array[PathSegment])
  KillArg(Int32)
  KillReceiver
  ReportSinkArg(SinkId, Int32)
  ReportSinkReceiver(SinkId)
  /// Add an exceptional completion with taint propagated from this argument.
  RaiseArg(Int32)
  /// Make the normal completion impossible.
  NoReturn
} derive(Eq, Debug)

///|
/// Complete taint-analysis configuration for one rule.
///
/// `bind_call` runs once on static metadata and returns a pure transfer.
/// The transfer has first chance to model each call. When it returns
/// `Some`, declared sources, call models, and `unknown_call_policy` are skipped
/// for that call. Otherwise all matching `CallReturn` sources and `CallModel`s
/// are applied in array order and their effects are merged. `unknown_call_policy`
/// only applies after custom transfer, sources, and call models do not match.
/// Static metadata has clean taint; actual values are transfer snapshots.
pub(all) struct TaintSpec {
  rule_id : String
  sources : Array[SourceModel]
  call_models : Array[CallModel]
  unknown_call_policy : UnknownCallPolicy
  bind_call : (CallInfo) -> (CallInfo) -> CallTransfer?
}

///|
pub extend CallTransfer with Eq::{not_equal, equal}

///|
pub extend CallTransfer with Debug::{to_repr}

///|
pub extend UnknownCallPolicy with Eq::{not_equal, equal}

///|
pub extend UnknownCallPolicy with Debug::{to_repr}

///|
pub extend SourceModel with Eq::{not_equal, equal}

///|
pub extend SourceModel with Debug::{to_repr}

///|
pub extend CallMatcher with Eq::{not_equal, equal}

///|
pub extend CallMatcher with Debug::{to_repr}

///|
pub extend CallModel with Eq::{not_equal, equal}

///|
pub extend CallModel with Debug::{to_repr}

///|
pub extend CallEffect with Eq::{not_equal, equal}

///|
pub extend CallEffect with Debug::{to_repr}

///|
pub extend CallOutcome with Eq::{equal, not_equal}

///|
pub extend CallOutcome with Debug::{to_repr}

///|
pub extend StorageWrite with Eq::{equal, not_equal}

///|
pub extend StorageWrite with Debug::{to_repr}
