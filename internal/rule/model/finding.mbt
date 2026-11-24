///|
/// One match reported by a structural or taint rule.
///
/// Location (`loc`) rules:
/// - Ordinary structural rules report the root positive pattern's match span
///   and `pattern_index` (nested `then` groups only gate that entry).
/// - `inside-toplevel` rules with `patterns` report each inner positive match;
///   rules with only `patterns-not` report the matched top-level item.
/// - Taint rules report the sink target's span (or the enclosing call span when
///   targeting the receiver).
pub(all) struct RuleFinding {
  file : String
  rule_id : String
  description : String
  pattern_index : Int32
  loc : @basic.Location
}
