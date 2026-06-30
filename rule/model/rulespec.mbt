///|
/// Errors raised while loading, validating, or compiling a rule set.
pub(all) suberror RuleLoadError {
  /// The rule set or rule at `path` is malformed, conflicts with another rule,
  /// or cannot be represented by runtime AST matching. `path` may be the rules
  /// root for directory-level failures. `info` is written for rule authors.
  InvalidRule(path~ : String, info~ : String)
} derive(Debug)

///|
/// A single YAML pattern clause before it is parsed into a MoonBit AST.
///
/// `shape` must be a valid MoonBit expression. Inline `$(name:exp)`,
/// `$(name:id)`, `$(name:const)`, and `$(name:pat)` placeholders in the shape
/// are discovered during compilation. `guard`, when present, maps id or const
/// capture names to regex strings.
pub(all) struct RulePatternSpec {
  shape : String
  guards : Map[String, String]
}

///|
/// Raw structural-rule definition loaded from YAML.
///
/// `inside_expr`, when present, is a MoonBit expression string that must
/// contain a single `__TARGET__` placeholder. The normal `patterns` are then
/// matched inside that target.
pub(all) struct StructuralRuleSpec {
  inside_expr : String?
  patterns : Array[RulePatternSpec]
}

///|
/// Raw taint-rule definition loaded from YAML.
///
/// Sources introduce taint from matching call results. Sinks report tainted
/// values at their `__SOURCE__` target. Sanitizers contribute no return taint
/// and kill stored taint when `__SOURCE__` resolves to a storage path.
/// All taint clauses must be call expressions. Source shapes must not contain
/// `__SOURCE__`. Sink and sanitizer shapes must contain exactly one
/// `__SOURCE__` placeholder, placed as the whole receiver or whole argument
/// value.
pub(all) struct TaintRuleSpec {
  sources : Array[RulePatternSpec]
  sinks : Array[RulePatternSpec]
  sanitizers : Array[RulePatternSpec]
}

///|
/// The mutually exclusive rule bodies supported by a YAML rule file.
pub(all) enum RuleDefinitionSpec {
  Structural(StructuralRuleSpec)
  Taint(TaintRuleSpec)
}

///|
/// A validated rule decoded from YAML plus metadata from its file path.
///
/// `rule_id` is the rule file's relative directory below the rules root joined
/// with the YAML `id`. `definition` is still uncompiled and contains source
/// text shapes.
pub(all) struct RawRuleSpec {
  path : String
  rule_id : String
  description : String
  definition : RuleDefinitionSpec
}

///|
/// Runtime matcher implementation selected by callers that support switching.
pub(all) enum MatcherBackend {
  JsonMatcher
  AstMatcher
}

///|
/// A parsed and compiled pattern clause.
///
/// `source` preserves the user-facing YAML clause for diagnostics and metadata.
/// `compiled` and `json_compiled` are matcher-ready AST and JSON
/// representations. `guards` are evaluated after structural matching succeeds.
pub(all) struct CompiledRulePattern {
  source : RulePatternSpec
  compiled : @matching.CompiledExprPattern
  json_compiled : @json_matching.CompiledJsonExprPattern
  guards : Array[CompiledRuleGuard]
}

///|
/// The kind of bound value a compiled guard reads.
pub(all) enum RuleGuardCaptureKind {
  IdentifierGuard
  ConstantGuard
}

///|
/// A compiled regex filter for one id or const capture.
pub(all) struct CompiledRuleGuard {
  name : String
  capture_kind : RuleGuardCaptureKind
  regex_source : String
  regex : Regex
}

///|
/// A structural rule after shape parsing and metavar validation.
pub(all) struct CompiledStructuralRule {
  inside_expr : CompiledRulePattern?
  patterns : Array[CompiledRulePattern]
}

///|
/// The whole receiver or argument value that a taint sink or sanitizer targets.
///
/// `LabelledArg` stores both label and positional index so matching can confirm
/// the original argument slot even when labelled and positional arguments mix.
pub(all) enum TaintTarget {
  Receiver
  PositionalArg(Int)
  LabelledArg(label~ : String, index~ : Int)
}

///|
/// A compiled taint source call pattern.
pub(all) struct CompiledTaintSource {
  pattern : CompiledRulePattern
}

///|
/// A compiled taint sink call pattern plus the value it checks for taint.
pub(all) struct CompiledTaintSink {
  pattern : CompiledRulePattern
  target : TaintTarget
}

///|
/// A compiled sanitizer call pattern plus the value whose taint it removes.
pub(all) struct CompiledTaintSanitizer {
  pattern : CompiledRulePattern
  target : TaintTarget
}

///|
/// A taint rule lowered enough to run through the generic taint engine.
pub(all) struct CompiledTaintRule {
  sources : Array[CompiledTaintSource]
  sinks : Array[CompiledTaintSink]
  sanitizers : Array[CompiledTaintSanitizer]
}

///|
/// The executable rule body produced by `compile_rules`.
pub(all) enum CompiledRuleDefinition {
  Structural(CompiledStructuralRule)
  Taint(CompiledTaintRule)
}

///|
/// Source-text prefilter compiled from rule shapes.
///
/// Each inner array is a conjunction of literals that must all occur in the
/// source text. The outer array is a disjunction. Empty alternatives mean the
/// rule cannot be filtered safely and must remain relevant.
pub(all) struct RulePrefilter {
  alternatives : Array[Array[String]]
}

///|
/// A rule ready to apply to parser AST nodes.
pub(all) struct CompiledRule {
  rule_id : String
  description : String
  definition : CompiledRuleDefinition
  prefilter : RulePrefilter
}
