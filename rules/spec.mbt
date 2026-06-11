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

///|
pub(all) struct CompiledRulePattern {
  source : RulePatternSpec
  compiled : @matching.CompiledExprPattern
}

///|
pub(all) struct CompiledStructuralRule {
  inside_expr : CompiledRulePattern?
  patterns : Array[CompiledRulePattern]
}

///|
pub(all) enum TaintTarget {
  Receiver
  PositionalArg(Int)
  LabelledArg(label~ : String, index~ : Int)
}

///|
pub(all) struct CompiledTaintSource {
  pattern : CompiledRulePattern
}

///|
pub(all) struct CompiledTaintSink {
  pattern : CompiledRulePattern
  target : TaintTarget
}

///|
pub(all) struct CompiledTaintSanitizer {
  pattern : CompiledRulePattern
  target : TaintTarget
}

///|
pub(all) struct CompiledTaintRule {
  sources : Array[CompiledTaintSource]
  sinks : Array[CompiledTaintSink]
  sanitizers : Array[CompiledTaintSanitizer]
}

///|
pub(all) enum CompiledRuleDefinition {
  Structural(CompiledStructuralRule)
  Taint(CompiledTaintRule)
}

///|
pub(all) struct CompiledRule {
  rule_id : String
  package_name : String
  description : String
  definition : CompiledRuleDefinition
}
