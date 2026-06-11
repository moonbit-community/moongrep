///|
/// A rule match reported by the rules package.
///
/// `loc` points at the structural expression match or taint sink target
/// location. Receiver sink targets currently use the enclosing call location.
/// `outer_loc` is present for structural `inside-expr` rules and points at the
/// context expression that contained the target.
pub(all) struct MatchHit {
  file : String
  rule_id : String
  package_name : String
  description : String
  pattern_index : Int
  loc : @basic.Location
  outer_loc : @basic.Location?
}
