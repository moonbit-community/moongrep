///|
using @rule_model {
  type CompiledRule,
  type CompiledRulePattern,
  type RawRuleSpec,
}

///|
using @rule_traverse {type ScopedExpr}

///|
priv suberror QueryError {
  ParseError(source_name~ : String, info~ : String)
} derive(Debug)

///|
struct ExprQuery {
  rule : CompiledRule
  pattern : CompiledRulePattern
}

///|
pub fn ExprQuery::ExprQuery(pattern : String) -> ExprQuery raise {
  let rules = @rule_compile.compile_rules([anonymous_pattern_rule(pattern)])
  guard rules.length() == 1 else {
    fail("expected one compiled anonymous pattern rule")
  }
  let rule = rules[0]
  match rule.definition {
    Structural(structural) => {
      guard structural.patterns.length() == 1 else {
        fail("expected one compiled structural pattern")
      }
      { rule, pattern: structural.patterns[0] }
    }
    Taint(_) => fail("expected anonymous pattern to compile as structural rule")
  }
}

///|
pub fn ExprQuery::matches_all(
  self : ExprQuery,
  source_name~ : String,
  source : String,
) -> ArrayView[Map[String, @untyped_ast.Node]] raise {
  let matches : Array[Map[String, @untyped_ast.Node]] = []
  if !@rule_prefilter.rule_is_relevant_to_source(self.rule, source) {
    return matches
  }
  let (impls, reports) = @parser.parse_string(source, name=source_name)
  if reports.length() > 0 {
    raise QueryError::ParseError(
      source_name~,
      info="parse failed due to \{compact_reports(reports)}",
    )
  }
  for node in impls {
    let impl_source = source_text_for_impl(source, node)
    if @rule_prefilter.rule_is_relevant_to_source(self.rule, impl_source) {
      collect_impl_matches(self.pattern, node, matches)
    }
  }
  matches
}

///|
fn anonymous_pattern_rule(pattern : String) -> RawRuleSpec {
  {
    path: pattern,
    rule_id: pattern,
    description: "Anonymous query pattern.",
    definition: Structural({
      inside_expr: None,
      patterns: [{ shape: pattern, guards: {} }],
      patterns_not: [],
      patterns_not_mode: @rule_model.StructuralPatternsNotMode::PruneOnNegative,
    }),
  }
}

///|
fn collect_impl_matches(
  pattern : CompiledRulePattern,
  node : @syntax.Impl,
  matches : Array[Map[String, @untyped_ast.Node]],
) -> Unit {
  @rule_traverse.visit_impl_scoped_expr_roots(node, fn(scoped_expr) {
    collect_scoped_expr_matches(pattern, scoped_expr, matches)
  })
}

///|
fn collect_scoped_expr_matches(
  pattern : CompiledRulePattern,
  scoped_expr : ScopedExpr,
  matches : Array[Map[String, @untyped_ast.Node]],
) -> Unit {
  let candidate = @untyped_ast.from_expr(scoped_expr.expr)
  if @matching.match_expr_pattern(pattern.compiled, candidate) is Some(result) {
    matches.push(capture_map_from_bindings(result.bindings))
  } else {
    @rule_traverse.visit_scoped_expr_children(scoped_expr, fn(child) {
      collect_scoped_expr_matches(pattern, child, matches)
    })
  }
}

///|
fn capture_map_from_bindings(
  bindings : @hashmap.HashMap[String, @matching.BoundValue],
) -> Map[String, @untyped_ast.Node] {
  let captures : Map[String, @untyped_ast.Node] = {}
  bindings.each(fn(name, value) { captures[name] = value })
  captures
}

///|
fn source_text_for_impl(source : String, node : @syntax.Impl) -> String {
  source_text_for_location(source, node.loc())
}

///|
fn source_text_for_location(source : String, loc : @basic.Location) -> String {
  let lines = source.split("\n").to_array()
  let start_line = loc.start.lnum
  let end_line = loc.end.lnum
  if start_line <= 0 || end_line <= 0 || end_line < start_line {
    return source
  }
  let start_index = start_line - 1
  let end_index = end_line
  if start_index >= lines.length() || end_index > lines.length() {
    return source
  }
  let block_lines = []
  for line in lines[start_index:end_index] {
    block_lines.push(line)
  }
  let block = block_lines.join("\n")
  if block.length() == 0 {
    source
  } else {
    block
  }
}

///|
fn compact_reports(reports : Array[@basic.Report]) -> String {
  let messages : Array[String] = []
  for report in reports {
    messages.push(report.msg.replace_all(old="\n", new=" "))
  }
  messages.join(" ")
}
