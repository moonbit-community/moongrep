///|
pub(all) enum ValueSite {
  Path(StoragePath)
  CallResult(String?, @basic.Location)
  Expr(@basic.Location, String?)
  Synthetic(String)
} derive(Eq, Debug)

///|
pub(all) struct TaintOrigin {
  rule_id : String
  origin_id : String
  site : ValueSite
  note : String?
} derive(Eq, Debug)

///|
pub(all) struct RelativeTaint {
  path : Array[PathSegment]
  origins : Array[TaintOrigin]
} derive(Eq, Debug)

///|
pub type TaintTree = Array[RelativeTaint]

///|
pub(all) struct SinkFinding {
  rule_id : String
  sink_id : String
  sink_loc : @basic.Location
  sink_site : ValueSite
  origins : Array[TaintOrigin]
} derive(Eq, Debug)
