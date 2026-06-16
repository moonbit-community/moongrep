///|
/// Applies only structural rules to the supplied parser AST nodes.
///
/// Supported expression subtrees collected by `collect_impl_exprs` and
/// `collect_exprs` are visited in source-tree order. For a single expression
/// and rule, the first matching pattern wins and determines `pattern_index`.
pub fn apply_structural_rules(
  file : String,
  impls : @list.List[@syntax.Impl],
  rules : Array[CompiledRule],
) -> Array[MatchHit] {
  let hits : Array[MatchHit] = []
  for node in impls {
    let node_hits = apply_structural_rules_to_impl(file, node, rules)
    for hit in node_hits {
      hits.push(hit)
    }
  }
  hits
}

///|
pub fn apply_structural_rules_to_impl(
  file : String,
  node : @syntax.Impl,
  rules : Array[CompiledRule],
) -> Array[MatchHit] {
  let hits : Array[MatchHit] = []
  let exprs : Array[@syntax.Expr] = []
  collect_impl_exprs(node, exprs)
  for expr in exprs {
    for rule in rules {
      match rule.definition {
        CompiledRuleDefinition::Structural(structural) =>
          apply_structural_rule_to_expr(file, rule, structural, expr, hits)
        _ => ()
      }
    }
  }
  hits
}

///|
/// Applies only taint rules to function-like parser AST nodes.
///
/// Unsupported top-level nodes are ignored. Other taint-analysis errors are
/// propagated to the caller.
pub fn apply_taint_rules(
  file : String,
  impls : @list.List[@syntax.Impl],
  rules : Array[CompiledRule],
) -> Array[MatchHit] raise {
  let hits : Array[MatchHit] = []
  for node in impls {
    let node_hits = apply_taint_rules_to_impl(file, node, rules)
    for hit in node_hits {
      hits.push(hit)
    }
  }
  hits
}

///|
pub fn apply_taint_rules_to_impl(
  file : String,
  node : @syntax.Impl,
  rules : Array[CompiledRule],
) -> Array[MatchHit] raise {
  let hits : Array[MatchHit] = []
  for rule in rules {
    match rule.definition {
      CompiledRuleDefinition::Taint(taint_rule) =>
        apply_taint_rule_to_impl(file, rule, taint_rule, node, hits)
      _ => ()
    }
  }
  hits
}

///|
fn apply_taint_rule_to_impl(
  file : String,
  rule : CompiledRule,
  taint_rule : CompiledTaintRule,
  node : @syntax.Impl,
  hits : Array[MatchHit],
) -> Unit raise {
  let spec = lower_compiled_taint_rule(rule, taint_rule)
  try @taint.analyze_function_like(node, spec) catch {
    @taint.TaintAnalysisError::UnsupportedFunctionLike(..) => ()
    err => raise err
  } noraise {
    result =>
      for finding in result.findings {
        hits.push({
          file,
          rule_id: rule.rule_id,
          package_name: rule.package_name,
          description: rule.description,
          pattern_index: sink_pattern_index(taint_rule, finding.sink_id),
          loc: finding.sink_loc,
          outer_loc: None,
        })
      }
  }
}

///|
fn sink_pattern_index(taint_rule : CompiledTaintRule, sink_id : String) -> Int {
  for index in 0..<taint_rule.sinks.length() {
    if sink_id == "sink:\{index}" {
      return index
    }
  }
  0
}

///|
fn apply_structural_rule_to_expr(
  file : String,
  rule : CompiledRule,
  structural : CompiledStructuralRule,
  expr : @syntax.Expr,
  hits : Array[MatchHit],
) -> Unit {
  match structural.inside_expr {
    None =>
      apply_patterns_at_expr(
        file,
        rule,
        structural.patterns,
        expr,
        None,
        None,
        hits,
      )
    Some(inside) =>
      match @matching.match_expr_pattern(inside.compiled, expr) {
        Some(outer_match) =>
          match outer_match.bindings.get("__TARGET__") {
            Some(@matching.BoundValue::Expr(target)) => {
              // The context rule can bind a larger expression than the final
              // hit. Search supported expressions under `__TARGET__`, while
              // carrying any bindings established by the outer match.
              let target_exprs : Array[@syntax.Expr] = []
              collect_exprs(target, target_exprs)
              for target_expr in target_exprs {
                apply_patterns_at_expr(
                  file,
                  rule,
                  structural.patterns,
                  target_expr,
                  Some(expr.loc()),
                  Some(outer_match.bindings),
                  hits,
                )
              }
            }
            _ => ()
          }
        None => ()
      }
  }
}

///|
fn apply_patterns_at_expr(
  file : String,
  rule : CompiledRule,
  patterns : Array[CompiledRulePattern],
  expr : @syntax.Expr,
  outer_loc : @basic.Location?,
  initial_bindings : @hashmap.HashMap[String, @matching.BoundValue]?,
  hits : Array[MatchHit],
) -> Unit {
  for index in 0..<patterns.length() {
    let matched = match initial_bindings {
      Some(bindings) =>
        @matching.match_expr_pattern_with_bindings(
          patterns[index].compiled,
          expr,
          bindings,
        )
        is Some(_)
      None =>
        @matching.match_expr_pattern(patterns[index].compiled, expr) is Some(_)
    }
    if matched {
      hits.push({
        file,
        rule_id: rule.rule_id,
        package_name: rule.package_name,
        description: rule.description,
        pattern_index: index,
        loc: expr.loc(),
        outer_loc,
      })
      return
    }
  }
}
