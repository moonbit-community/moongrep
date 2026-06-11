///|
pub suberror TaintAnalysisError {
  UnsupportedFunctionLike(kind~ : String, loc~ : @basic.Location)
} derive(Debug)

///|
pub(all) struct AnalysisResult {
  rule_id : String
  function_name : String
  function_loc : @basic.Location
  findings : Array[SinkFinding]
}

///|
pub(all) struct CallTransfer {
  return_taint : TaintTree
  killed_paths : Array[StoragePath]
  findings : Array[SinkFinding]
} derive(Eq, Debug)

///|
pub(all) enum UnknownCallPolicy {
  NoEffect
  PropagateArgumentsToReturn
} derive(Eq, Debug)

///|
pub(all) enum SourceModel {
  EntryPath(StoragePath, String, String?)
  CallReturn(CallMatcher, String, String?, Array[PathSegment])
} derive(Eq, Debug)

///|
pub(all) enum CallMatcher {
  CalleeName(String)
  MethodName(String)
  AnyCall
} derive(Eq, Debug)

///|
pub(all) struct CallModel {
  matcher : CallMatcher
  effects : Array[CallEffect]
} derive(Eq, Debug)

///|
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
pub(all) struct TaintSpec {
  rule_id : String
  sources : Array[SourceModel]
  call_models : Array[CallModel]
  unknown_call_policy : UnknownCallPolicy
  max_fixpoint_iterations : Int
  custom_transfer_call : (CallInfo) -> CallTransfer?
}
