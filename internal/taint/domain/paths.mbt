///|
/// One step in a storage path or relative taint path.
///
/// `AnyIndex` represents an unknown array index and also summarizes all
/// elements when array contents are merged.
pub(all) enum PathSegment {
  Field(String)
  TupleIndex(Int32)
  ConstIndex(String)
  AnyIndex
} derive(Eq, Debug)

///|
/// A resolved binding plus optional field, tuple, or index segments.
///
/// The root is a unique local variable or parameter identity. Segments describe a
/// subvalue such as `payload.body` or `pair.0`.
pub(all) struct StoragePath {
  root : BindingId
  segments : Array[PathSegment]
} derive(Eq, Debug)

///|
pub extend PathSegment with Eq::{not_equal, equal}

///|
pub extend PathSegment with Debug::{to_repr}

///|
pub extend StoragePath with Eq::{not_equal, equal}

///|
pub extend StoragePath with Debug::{to_repr}

///|
/// Identity allocated by the lowering pass, independent of the source name.
pub(all) struct BindingId(Int32) derive(Eq, Compare, Hash, Debug)

///|
/// A parameter source configured by name, resolved when analysis starts.
pub(all) struct ParameterPath {
  root : String
  segments : Array[PathSegment]
} derive(Eq, Debug)

///|
pub extend BindingId with Eq::{equal, not_equal}

///|
pub extend BindingId with Debug::{to_repr}

///|
pub extend BindingId with Compare::{compare, op_lt, op_le, op_gt, op_ge}

///|
pub extend BindingId with Hash::{hash, hash_combine}

///|
pub extend ParameterPath with Eq::{equal, not_equal}

///|
pub extend ParameterPath with Debug::{to_repr}
