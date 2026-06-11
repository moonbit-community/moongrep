///|
pub(all) struct MatchHit {
  file : String
  rule_id : String
  package_name : String
  description : String
  pattern_index : Int
  loc : @basic.Location
  outer_loc : @basic.Location?
}
