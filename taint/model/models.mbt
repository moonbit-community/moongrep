///|
/// Effects produced by a call transfer.
///
/// `return_taint` becomes the call expression value. `killed_paths` remove
/// taint from storage after the call. `findings` are appended to the analysis
/// result as-is; custom transfers are responsible for preserving
/// `SinkFinding` invariants such as non-empty origins and correct loc/site.
pub(all) struct CallTransfer {
  return_taint : TaintTree
  killed_paths : Array[StoragePath]
  findings : Array[SinkFinding]
} derive(Eq, Debug)

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
  EntryPath(StoragePath, String, String?)
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
pub(all) enum CallEffect {
  ReturnFreshSource(String, String?, Array[PathSegment])
  PropagateArgToReturn(Int)
  PropagateReceiverToReturn
  PropagateArgSubpathToReturn(Int, Array[PathSegment])
  KillArg(Int)
  KillReceiver
  ReportSinkArg(String, Int)
  ReportSinkReceiver(String)
} derive(Eq, Debug)

///|
/// Complete taint-analysis configuration for one rule.
///
/// `custom_transfer_call` has first chance to model each call. When it returns
/// `Some`, declared sources, call models, and `unknown_call_policy` are skipped
/// for that call. Otherwise all matching `CallReturn` sources and `CallModel`s
/// are applied in array order and their effects are merged. `unknown_call_policy`
/// only applies after custom transfer, sources, and call models do not match.
pub(all) struct TaintSpec {
  rule_id : String
  sources : Array[SourceModel]
  call_models : Array[CallModel]
  unknown_call_policy : UnknownCallPolicy
  max_fixpoint_iterations : Int
  custom_transfer_call : (CallInfo) -> CallTransfer?
}
