///|
/// Return value and storage writes produced by one call completion path.
#derive(Eq, Debug)
pub(all) struct CallOutcome {
  value : TaintValue
  writes : Array[StorageWrite]
}

///|
/// A post-call mutation applied to a resolved storage path.
#derive(Eq, Debug)
pub(all) enum StorageWrite {
  Set(StoragePath, TaintValue)
  Sanitize(StoragePath)
}

///|
/// Normal and exceptional outcomes produced by modeling one call site.
///
/// `None` marks an impossible completion path; unknown calls never raise.
#derive(Eq, Debug)
pub(all) struct CallTransfer {
  normal : CallOutcome?
  exceptional : CallOutcome?
  findings : Array[SinkFinding]
}

///|
/// Constructs a normal-only `CallTransfer` with optional sanitized paths and
/// sink findings.
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
/// Fallback behavior for calls that match no custom transfer, source, or call
/// model.
///
/// - `NoEffect`: returns a clean value.
/// - `PropagateArgumentsToReturn`: joins receiver and argument taint into the
///   return value.
#derive(Eq, Debug)
pub(all) enum UnknownCallPolicy {
  NoEffect
  PropagateArgumentsToReturn
}

///|
/// A rule-level taint source.
///
/// - `EntryPath`: taints a named function parameter (or relative subpath) at
///   function entry; segments are not checked against type declarations.
/// - `CallReturn`: introduces fresh taint on matching call return values at a
///   relative path (`[]` taints the return value itself).
#derive(Eq, Debug)
pub(all) enum SourceModel {
  EntryPath(ParameterPath, String, String?)
  CallReturn(CallMatcher, String, String?, Array[PathSegment])
}

///|
/// Predicate selecting calls for declarative sources and call models.
///
/// - `CalleeName`: matches normalized `callee_name` across direct, method,
///   pipe, and reverse-pipe calls.
/// - `CalleeBinding`: matches a resolved local or parameter target, preserving
///   lexical shadowing.
/// - `MethodName`: matches method and pipe calls by normalized `callee_name`
///   (excludes reverse-pipe calls).
/// - `AnyCall`: matches every call.
#derive(Eq, Debug)
pub(all) enum CallMatcher {
  CalleeName(String)
  CalleeBinding(BindingId)
  MethodName(String)
  AnyCall
}

///|
/// Declarative transfer model for calls outside the analyzed function body.
///
/// Every matching model runs in array order (not first-match).
#derive(Eq, Debug)
pub(all) struct CallModel {
  matcher : CallMatcher
  effects : Array[CallEffect]
}

///|
/// Individual taint effect applied when a `CallModel` matches.
///
/// - `ReturnFreshSource`: taints the return value at a relative path (`[]` for
///   the return value itself).
/// - `PropagateArgToReturn` / `PropagateReceiverToReturn`: flows argument or
///   receiver taint into the return value.
/// - `PropagateArgSubpathToReturn`: projects an argument subpath and returns
///   it with that prefix stripped.
/// - `KillArg` / `KillReceiver`: sanitizes post-call storage when the target
///   has a `StoragePath` (does not alter pre-evaluated snapshots seen by other
///   effects on the same call).
/// - `ReportSinkArg` / `ReportSinkReceiver`: emits a sink finding with the
///   given `SinkId` (`Named` for generic models; `PatternIndex` for YAML rules).
/// - `RaiseArg`: adds an exceptional completion carrying this argument's taint.
/// - `NoReturn`: marks normal completion impossible.
#derive(Eq, Debug)
pub(all) enum CallEffect {
  ReturnFreshSource(String, String?, Array[PathSegment])
  PropagateArgToReturn(Int32)
  PropagateReceiverToReturn
  PropagateArgSubpathToReturn(Int32, Array[PathSegment])
  KillArg(Int32)
  KillReceiver
  ReportSinkArg(SinkId, Int32)
  ReportSinkReceiver(SinkId)
  RaiseArg(Int32)
  NoReturn
}

///|
/// Complete taint configuration for one rule.
///
/// Resolution order at each call site:
/// 1. `bind_call` runs once on static metadata (with clean taint) and returns a
///    pure transfer closure invoked on evaluated `CallInfo` snapshots.
/// 2. If the transfer returns `Some`, declarative sources, `call_models`, and
///    `unknown_call_policy` are skipped.
/// 3. Otherwise, all matching `CallReturn` sources and `call_models` run in
///    array order and merge their effects.
/// 4. If nothing matched, `unknown_call_policy` applies.
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
