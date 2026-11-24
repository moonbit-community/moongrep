///|
/// Errors raised while loading, validating, or compiling a rule set.
#derive(Debug)
pub(all) suberror RuleLoadError {
  /// No YAML rule files were found below `path`.
  NoRuleFiles(path~ : String)
  /// The rule pattern at `path` cannot be compiled. `shape` is the original
  /// pattern text and `info` explains why it is invalid.
  InvalidPattern(path~ : String, shape~ : String, info~ : String)
  /// The rule set or rule at `path` is malformed, conflicts with another rule,
  /// or cannot be represented by runtime CST matching. `path` may be the rules
  /// root for directory-level failures. `info` is written for rule authors.
  InvalidRule(path~ : String, info~ : String)
}

///|
pub impl Show for RuleLoadError with fn output(self, logger) {
  match self {
    NoRuleFiles(path~) => {
      logger.write_string(path)
      logger.write_string(": no YAML rule files found")
    }
    InvalidPattern(path~, shape~, info~) => {
      logger.write_string(path)
      logger.write_string(":\n  pattern:")
      let normalized_shape = normalize_rule_pattern_shape(shape)
      if normalized_shape != "" {
        for line in normalized_shape.split("\n") {
          logger.write_string("\n    ")
          logger.write_string(line.to_owned())
        }
      }
      logger.write_string("\n  reason: ")
      logger.write_string(info)
    }
    InvalidRule(path~, info~) => {
      logger.write_string(path)
      logger.write_string(": ")
      logger.write_string(info)
    }
  }
}

///|
fn normalize_rule_pattern_shape(shape : String) -> String {
  let normalized = shape
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
  if normalized.has_suffix("\n") {
    normalized[:normalized.length() - 1].to_owned()
  } else {
    normalized
  }
}

///|
/// How an `inside-toplevel` shape matches its target top-level item.
///
/// - `Default`: resolved per alternative during compilation (`Partial` for
///   function definitions, `Exact` for all other top-level items).
/// - `Exact`: compares every semantic CST field of the top-level item.
/// - `Partial`: ignores omitted default function-header fields (supported only
///   for function definitions).
pub(all) enum InsideToplevelMatchMode {
  Default
  Exact
  Partial
}

///|
/// One raw YAML pattern clause prior to CST parsing and validation.
///
/// - `shape`: one MoonBit expression (or one top-level item for
///   `inside-toplevel`). Inline metavars (`$(name:kind)`, `$name`) and
///   ordered-list ellipses (`$$$name`, `$$$(name:kind)`) are resolved during
///   compilation.
/// - `guards`: optional map from `$`-prefixed `id`/`const` capture names to
///   regex strings.
/// - `match_mode`: configurable only on `inside-toplevel` entries; other
///   clauses always use `Default`.
pub(all) struct RulePatternSpec {
  shape : String
  guards : Map[String, String]
  match_mode : InsideToplevelMatchMode
}

///|
/// Semantics for `patterns-not` within a structural pattern group.
///
/// - `PruneOnNegative`: root-level negative matches prune only their candidate
///   branch after all positive patterns fail.
/// - `RejectUncoveredNegative`: inside `then` or `inside-toplevel`, positive
///   matches cover their matched subtrees while any uncovered negative match
///   rejects the enclosing group or context.
pub(all) enum StructuralPatternsNotMode {
  PruneOnNegative
  RejectUncoveredNegative
}

///|
/// A positive structural clause, optionally constrained by a nested `then`
/// group.
pub(all) struct StructuralPatternSpec {
  pattern : RulePatternSpec
  then_body : StructuralPatternGroupSpec?
}

///|
/// An ordered set of positive and negative structural clauses evaluated at one
/// nesting level.
pub(all) struct StructuralPatternGroupSpec {
  patterns : Array[StructuralPatternSpec]
  patterns_not : Array[RulePatternSpec]
}

///|
/// Raw structural rule with optional `inside-toplevel` contexts.
pub(all) struct StructuralRuleSpec {
  inside_toplevel : Array[RulePatternSpec]
  group : StructuralPatternGroupSpec
}

///|
/// Raw taint rule decoded from YAML.
///
/// All clauses must parse as direct calls or method calls:
/// - `sources`: mark matching call return values as tainted (must not contain
///   `__SOURCE__`).
/// - `sinks`: report tainted values at their single `__SOURCE__` receiver or
///   argument.
/// - `sanitizers`: produce clean return values and clear stored taint when
///   their single `__SOURCE__` resolves to a storage path.
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
/// A parsed and compiled pattern clause.
///
/// `source` preserves the user-facing YAML clause for diagnostics and metadata.
/// `compiled` is the matcher-ready CST representation. `guards` are evaluated
/// after structural matching succeeds.
pub(all) struct CompiledRulePattern {
  source : RulePatternSpec
  compiled : @matching.CompiledExprPattern
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
  inside_toplevel : Array[CompiledRulePattern]
  group : CompiledStructuralPatternGroup
}

///|
pub(all) struct CompiledStructuralPattern {
  pattern : CompiledRulePattern
  then_body : CompiledStructuralPatternGroup?
}

///|
pub(all) struct CompiledStructuralPatternGroup {
  patterns : Array[CompiledStructuralPattern]
  patterns_not : Array[CompiledRulePattern]
  patterns_not_mode : StructuralPatternsNotMode
}

///|
/// The whole receiver or argument value that a taint sink or sanitizer targets.
///
/// `LabelledArg` stores both label and positional index so matching can confirm
/// the original argument slot even when labelled and positional arguments mix.
pub(all) enum TaintTarget {
  Receiver
  PositionalArg(Int32)
  LabelledArg(label~ : String, index~ : Int32)
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
/// A rule ready to apply to parser CST nodes.
pub(all) struct CompiledRule {
  rule_id : String
  description : String
  definition : CompiledRuleDefinition
  prefilter : RulePrefilter
}

///|
pub extend RuleLoadError with Debug::{to_repr}

///|
pub extend RuleLoadError with Show::{to_string, output}
