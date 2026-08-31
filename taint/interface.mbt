///|
pub using @domain {
  type PathSegment,
  type StoragePath,
  type ValueSite,
  type TaintOrigin,
  type RelativeTaint,
  type TaintTree,
  type SinkId,
  type SinkFinding,
  taint_tree_origins,
}

///|
pub using @model {
  type CallKind,
  type CallArgument,
  type CallInfo,
  type CallTransfer,
  type UnknownCallPolicy,
  type SourceModel,
  type CallMatcher,
  type CallModel,
  type CallEffect,
  type TaintSpec,
}

///|
pub using @engine {
  type TaintAnalysisError,
  type AnalysisResult,
  analyze_function_like,
  analyze_function_like_multi,
}
