///|
using @rule_model {type RulePrefilter}

///|
priv suberror QueryError {
  ParseError(source_name~ : String, info~ : String)
} derive(Debug)

///|
pub using @model {type BoundValue}

///|
struct ExprQuery {
  pattern : @matching.CompiledExprPattern
  prefilter : RulePrefilter
}

///|
pub fn ExprQuery::ExprQuery(pattern : String) -> ExprQuery raise {
  let compiled = @rule_compile.compile_expr_pattern(pattern)
  {
    pattern: compiled,
    prefilter: @rule_prefilter.compile_expr_pattern_prefilter(compiled),
  }
}

///|
pub fn ExprQuery::captures(
  self : ExprQuery,
  source_name~ : String,
  source : String,
) -> ArrayView[Map[String, BoundValue]] raise {
  let matches : Array[Map[String, BoundValue]] = []
  if !@rule_prefilter.prefilter_matches_source(self.prefilter, source) {
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
    if @rule_prefilter.prefilter_matches_source(self.prefilter, impl_source) {
      collect_node_matches(self.pattern, node, matches)
    }
  }
  matches
}

///|
pub fn ExprQuery::captures_from_cst(
  self : ExprQuery,
  cst~ : @untyped_cst.CstNode,
) -> ArrayView[Map[String, BoundValue]] {
  let matches : Array[Map[String, BoundValue]] = []
  collect_node_matches(self.pattern, cst, matches)
  matches
}

///|
fn collect_node_matches(
  pattern : @matching.CompiledExprPattern,
  cst : @untyped_cst.CstNode,
  matches : Array[Map[String, BoundValue]],
) -> Unit {
  @cst.visit_scoped_expr_match_candidate_roots(cst, fn(scoped_candidate) {
    collect_scoped_candidate_matches(pattern, scoped_candidate, matches)
    @cst.NodeVisitPrune
  })
}

///|
fn collect_scoped_candidate_matches(
  pattern : @matching.CompiledExprPattern,
  scoped_candidate : @cst.ScopedExprMatchCandidate,
  matches : Array[Map[String, BoundValue]],
) -> Unit {
  if @matching.match_expr_pattern_candidate(pattern, scoped_candidate.candidate)
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
  bindings : @hashmap.HashMap[String, @model.BoundValue],
) -> Map[String, BoundValue] {
  let captures : Map[String, BoundValue] = Map([])
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
