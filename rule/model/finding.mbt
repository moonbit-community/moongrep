///|
/// A rule finding reported by the rule package family.
///
/// `loc` points at the structural expression match or taint sink target.
/// Structural `inside-expr` rules report the matched outer expression instead
/// and emit at most one finding for each outer match. Structural
/// `inside-toplevel` rules report an inner positive match, or the matched
/// top-level item when they contain only `patterns-not`. Receiver sink targets
/// currently use the enclosing call location.
pub(all) struct RuleFinding {
  file : String
  rule_id : String
  description : String
  pattern_index : Int
  loc : @basic.Location
}
