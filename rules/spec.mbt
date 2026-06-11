///|
pub suberror RuleLoadError {
  InvalidRule(path~ : String, info~ : String)
} derive(Debug)

///|
pub(all) struct RulePatternSpec {
  shape : String
  subtree_metavars : Array[String]
  identifier_metavars : Array[String]
}

///|
pub(all) struct StructuralRuleSpec {
  inside_expr : RulePatternSpec?
  patterns : Array[RulePatternSpec]
}

///|
pub(all) struct TaintRuleSpec {
  sources : Array[RulePatternSpec]
  sinks : Array[RulePatternSpec]
  sanitizers : Array[RulePatternSpec]
}

///|
pub(all) enum RuleDefinitionSpec {
  Structural(StructuralRuleSpec)
  Taint(TaintRuleSpec)
}

///|
pub(all) struct RawRuleSpec {
  path : String
  rule_id : String
  package_name : String
  description : String
  definition : RuleDefinitionSpec
}
