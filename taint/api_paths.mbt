///|
pub(all) enum PathSegment {
  Field(String)
  TupleIndex(Int)
  ConstIndex(String)
  AnyIndex
} derive(Eq, Debug)

///|
pub(all) struct StoragePath {
  root : String
  segments : Array[PathSegment]
} derive(Eq, Debug)
