///|
using @model {
  type CompiledRule,
  type CompiledRuleGuard,
  type CompiledRulePattern,
  type CompiledStructuralRule,
  type CompiledTaintRule,
  type RuleFinding,
}

///|
using @taint_lowering {lower_compiled_taint_rule}

///|
using @traverse {collect_exprs, collect_impl_exprs}

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
) -> Array[RuleFinding] {
  let hits : Array[RuleFinding] = []
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
) -> Array[RuleFinding] {
  let hits : Array[RuleFinding] = []
  let exprs : Array[@syntax.Expr] = []
  collect_impl_exprs(node, exprs)
  for expr in exprs {
    for rule in rules {
      match rule.definition {
        Structural(structural) =>
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
) -> Array[RuleFinding] raise {
  let hits : Array[RuleFinding] = []
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
) -> Array[RuleFinding] raise {
  let hits : Array[RuleFinding] = []
  for rule in rules {
    match rule.definition {
      Taint(taint_rule) =>
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
  hits : Array[RuleFinding],
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
  hits : Array[RuleFinding],
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
      if match_rule_pattern(inside, expr, None) is Some(outer_match) {
        match outer_match.bindings.get("__TARGET__") {
          Some(Expr(target)) => {
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
  hits : Array[RuleFinding],
) -> Unit {
  for index in 0..<patterns.length() {
    if match_rule_pattern(patterns[index], expr, initial_bindings) is Some(_) {
      hits.push({
        file,
        rule_id: rule.rule_id,
        description: rule.description,
        pattern_index: index,
        loc: expr.loc(),
        outer_loc,
      })
      return
    }
  }
}

///|
fn match_rule_pattern(
  pattern : CompiledRulePattern,
  expr : @syntax.Expr,
  initial_bindings : @hashmap.HashMap[String, @matching.BoundValue]?,
) -> @matching.ExprMatch? {
  let matched = if initial_bindings is Some(bindings) {
    @matching.match_expr_pattern_with_bindings(pattern.compiled, expr, bindings)
  } else {
    @matching.match_expr_pattern(pattern.compiled, expr)
  }
  match matched {
    Some(result) =>
      if guards_match(pattern.guards, result.bindings) {
        Some(result)
      } else {
        None
      }
    None => None
  }
}

///|
fn guards_match(
  guards : Array[CompiledRuleGuard],
  bindings : @hashmap.HashMap[String, @matching.BoundValue],
) -> Bool {
  for guard_entry in guards {
    match guard_entry.capture_kind {
      @model.RuleGuardCaptureKind::IdentifierGuard =>
        match bindings.get(guard_entry.name) {
          Some(Identifier(value)) =>
            if guard_entry.regex.execute(value) is None {
              return false
            }
          _ => return false
        }
      @model.RuleGuardCaptureKind::ConstantGuard =>
        match bindings.get(guard_entry.name) {
          Some(Constant(value)) =>
            if guard_entry.regex.execute(constant_guard_value(value)) is None {
              return false
            }
          _ => return false
        }
    }
  }
  true
}

///|
fn constant_guard_value(constant : @syntax.Constant) -> String {
  match constant {
    BigInt(value)
    | Byte(value)
    | Bytes(value)
    | Char(value)
    | Double(value)
    | Float(value)
    | Int(value)
    | Int64(value)
    | Regex(value)
    | String(value)
    | UInt(value)
    | UInt64(value) => value
    Bool(value) => value.to_string()
  }
}
