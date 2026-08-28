///|
using @rule_model {
  type CompiledRule,
  type CompiledRulePattern,
  type RawRuleSpec,
}

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
      { rule, pattern: structural.patterns[0], }
    }
    Taint(_) => fail("expected anonymous pattern to compile as structural rule")
  }
}

///|
pub fn ExprQuery::captures(
  self : ExprQuery,
  source_name~ : String,
  source : String,
) -> ArrayView[Map[String, @matching.BoundValue]] raise {
  let matches : Array[Map[String, @matching.BoundValue]] = []
  if !@rule_prefilter.rule_is_relevant_to_source(self.rule, source) {
    return matches
  }
  let parsed = @untyped_cst.parse_structure(source, name=source_name)
  let reports = parsed.diagnostics_view()
  if reports.length() > 0 {
    raise QueryError::ParseError(
      source_name~,
      info="parse failed due to \{compact_reports(reports)}",
    )
  }
  if @cst.first_recovery_node(parsed.root()) is Some(_) {
    raise QueryError::ParseError(
      source_name~,
      info="parse failed due to an incomplete recovered CST node",
    )
  }
  for node in @cst.toplevel_nodes(parsed.root()) {
    let impl_source = @cst.source_text(node, source)
    if @rule_prefilter.rule_is_relevant_to_source(self.rule, impl_source) {
      collect_node_matches(self.pattern, node, matches)
    }
  }
  matches
}

///|
pub fn ExprQuery::captures_from_cst(
  self : ExprQuery,
  cst~ : @untyped_cst.CstNode,
) -> ArrayView[Map[String, @matching.BoundValue]] {
  let matches : Array[Map[String, @matching.BoundValue]] = []
  collect_node_matches(self.pattern, cst, matches)
  matches
}

///|
fn anonymous_pattern_rule(pattern : String) -> RawRuleSpec {
  {
    path: pattern,
    rule_id: pattern,
    description: "Anonymous query pattern.",
    definition: Structural({
      inside_expr: [],
      inside_toplevel: [],
      patterns: [{ shape: pattern, guards: Map([]), match_mode: Default, }],
      patterns_not: [],
      patterns_not_mode: PruneOnNegative,
    }),
  }
}

///|
fn collect_node_matches(
  pattern : CompiledRulePattern,
  cst : @untyped_cst.CstNode,
  matches : Array[Map[String, @matching.BoundValue]],
) -> Unit {
  @cst.visit_scoped_expr_match_candidate_roots(cst, fn(scoped_candidate) {
    collect_scoped_candidate_matches(pattern, scoped_candidate, matches)
    @cst.NodeVisitPrune
  })
}

///|
fn collect_scoped_candidate_matches(
  pattern : CompiledRulePattern,
  scoped_candidate : @cst.ScopedExprMatchCandidate,
  matches : Array[Map[String, @matching.BoundValue]],
) -> Unit {
  if @matching.match_expr_pattern_candidate(
      pattern.compiled,
      scoped_candidate.candidate,
    )
    is Some(result) {
    matches.push(capture_map_from_bindings(result.bindings))
  } else {
    @cst.visit_scoped_expr_match_candidate_children(
      scoped_candidate.candidate,
      scoped_candidate.shadowed_names,
      fn(child) { collect_scoped_candidate_matches(pattern, child, matches) },
    )
  }
}

///|
fn capture_map_from_bindings(
  bindings : @hashmap.HashMap[String, @matching.BoundValue],
) -> Map[String, @matching.BoundValue] {
  let captures : Map[String, @matching.BoundValue] = Map([])
  bindings.each(fn(name, value) { captures[name] = value })
  captures
}

///|
fn compact_reports(reports : ArrayView[@basic.Report]) -> String {
  let messages : Array[String] = []
  for report in reports {
    messages.push(report.msg.replace_all(old="\n", new=" "))
  }
  messages.join(" ")
}
