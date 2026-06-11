///|
pub fn apply_structural_rules(
  file : String,
  impls : @list.List[@syntax.Impl],
  rules : Array[CompiledRule],
) -> Array[MatchHit] {
  let hits : Array[MatchHit] = []
  let exprs = traverse_impl_exprs(impls)
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
fn apply_structural_rule_to_expr(
  file : String,
  rule : CompiledRule,
  structural : CompiledStructuralRule,
  expr : @syntax.Expr,
  hits : Array[MatchHit],
) -> Unit {
  match structural.inside_expr {
    None => apply_patterns_at_expr(file, rule, structural.patterns, expr, None, None, hits)
    Some(inside) =>
      match @matching.match_expr_pattern(inside.compiled, expr) {
        Some(outer_match) =>
          match outer_match.bindings.get("__TARGET__") {
            Some(@matching.BoundValue::Expr(target)) => {
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
        ) is Some(_)
      None => @matching.match_expr_pattern(patterns[index].compiled, expr) is Some(_)
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
