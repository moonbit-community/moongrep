///|
/// One step in a storage path or relative taint path.
///
/// `AnyIndex` represents an unknown array index and also summarizes all
/// elements when array contents are merged.
pub(all) enum PathSegment {
  Field(String)
  TupleIndex(Int)
  ConstIndex(String)
  AnyIndex
} derive(Eq, Debug)

///|
/// A named value plus optional field, tuple, or index segments.
///
/// The root is normally a local variable or parameter name. Segments describe a
/// subvalue such as `payload.body` or `pair.0`.
pub(all) struct StoragePath {
  root : String
  segments : Array[PathSegment]
} derive(Eq, Debug)
