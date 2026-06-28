///|
using @model {
  type CompiledRule,
  type CompiledRuleGuard,
  type CompiledRulePattern,
  type CompiledStructuralRule,
  type CompiledTaintRule,
  type MatcherBackend,
  type RuleFinding,
}

///|
using @taint_lowering {
  lower_compiled_taint_rule,
  lower_compiled_taint_rule_with_backend,
}

///|
using @traverse {collect_exprs, collect_impl_exprs}

///|
priv enum RulePatternBindings {
  AstBindings(@hashmap.HashMap[String, @matching.BoundValue])
  JsonBindings(@hashmap.HashMap[String, @json_matching.JsonBoundValue])
}

///|
priv enum RulePatternMatch {
  AstRuleMatch(@matching.ExprMatch)
  JsonRuleMatch(@json_matching.JsonExprMatch)
}

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
  apply_structural_rules_with_backend(
    file,
    impls,
    rules,
    @model.MatcherBackend::AstMatcher,
  )
}

///|
pub fn apply_structural_rules_with_backend(
  file : String,
  impls : @list.List[@syntax.Impl],
  rules : Array[CompiledRule],
  backend : MatcherBackend,
) -> Array[RuleFinding] {
  let hits : Array[RuleFinding] = []
  for node in impls {
    let node_hits = apply_structural_rules_to_impl_with_backend(
      file, node, rules, backend,
    )
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
  apply_structural_rules_to_impl_with_backend(
    file,
    node,
    rules,
    @model.MatcherBackend::AstMatcher,
  )
}

///|
pub fn apply_structural_rules_to_impl_with_backend(
  file : String,
  node : @syntax.Impl,
  rules : Array[CompiledRule],
  backend : MatcherBackend,
) -> Array[RuleFinding] {
  let hits : Array[RuleFinding] = []
  let exprs : Array[@syntax.Expr] = []
  collect_impl_exprs(node, exprs)
  for expr in exprs {
    for rule in rules {
      match rule.definition {
        Structural(structural) =>
          apply_structural_rule_to_expr(
            file, rule, structural, expr, backend, hits,
          )
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
  apply_taint_rules_with_backend(
    file,
    impls,
    rules,
    @model.MatcherBackend::AstMatcher,
  )
}

///|
pub fn apply_taint_rules_with_backend(
  file : String,
  impls : @list.List[@syntax.Impl],
  rules : Array[CompiledRule],
  backend : MatcherBackend,
) -> Array[RuleFinding] raise {
  let hits : Array[RuleFinding] = []
  for node in impls {
    let node_hits = apply_taint_rules_to_impl_with_backend(
      file, node, rules, backend,
    )
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
  apply_taint_rules_to_impl_with_backend(
    file,
    node,
    rules,
    @model.MatcherBackend::AstMatcher,
  )
}

///|
pub fn apply_taint_rules_to_impl_with_backend(
  file : String,
  node : @syntax.Impl,
  rules : Array[CompiledRule],
  backend : MatcherBackend,
) -> Array[RuleFinding] raise {
  let hits : Array[RuleFinding] = []
  for rule in rules {
    match rule.definition {
      Taint(taint_rule) =>
        apply_taint_rule_to_impl(file, rule, taint_rule, node, backend, hits)
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
  backend : MatcherBackend,
  hits : Array[RuleFinding],
) -> Unit raise {
  let spec = match backend {
    @model.MatcherBackend::AstMatcher =>
      lower_compiled_taint_rule(rule, taint_rule)
    @model.MatcherBackend::JsonMatcher =>
      lower_compiled_taint_rule_with_backend(rule, taint_rule, backend)
  }
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
  backend : MatcherBackend,
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
        backend,
        hits,
      )
    Some(inside) =>
      if match_rule_pattern(inside, expr, None, backend) is Some(outer_match) {
        if target_expr_from_match(expr, outer_match) is Some(target) {
          // The context rule can bind a larger expression than the final hit.
          // Search supported expressions under `__TARGET__`, while carrying any
          // bindings established by the outer match.
          let target_exprs : Array[@syntax.Expr] = []
          collect_exprs(target, target_exprs)
          for target_expr in target_exprs {
            apply_patterns_at_expr(
              file,
              rule,
              structural.patterns,
              target_expr,
              Some(expr.loc()),
              Some(bindings_from_match(outer_match)),
              backend,
              hits,
            )
          }
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
  initial_bindings : RulePatternBindings?,
  backend : MatcherBackend,
  hits : Array[RuleFinding],
) -> Unit {
  for index in 0..<patterns.length() {
    if match_rule_pattern(patterns[index], expr, initial_bindings, backend)
      is Some(_) {
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
  initial_bindings : RulePatternBindings?,
  backend : MatcherBackend,
) -> RulePatternMatch? {
  match backend {
    @model.MatcherBackend::AstMatcher =>
      match_ast_rule_pattern(pattern, expr, initial_bindings)
    @model.MatcherBackend::JsonMatcher =>
      match_json_rule_pattern(pattern, expr, initial_bindings)
  }
}

///|
fn match_ast_rule_pattern(
  pattern : CompiledRulePattern,
  expr : @syntax.Expr,
  initial_bindings : RulePatternBindings?,
) -> RulePatternMatch? {
  let matched = match initial_bindings {
    Some(AstBindings(bindings)) =>
      @matching.match_expr_pattern_with_bindings(
        pattern.compiled,
        expr,
        bindings,
      )
    Some(JsonBindings(_)) => None
    None => @matching.match_expr_pattern(pattern.compiled, expr)
  }
  match matched {
    Some(result) if ast_guards_match(pattern.guards, result.bindings) =>
      Some(AstRuleMatch(result))
    _ => None
  }
}

///|
fn match_json_rule_pattern(
  pattern : CompiledRulePattern,
  expr : @syntax.Expr,
  initial_bindings : RulePatternBindings?,
) -> RulePatternMatch? {
  let matched = match initial_bindings {
    Some(JsonBindings(bindings)) =>
      @json_matching.match_expr_pattern_ast_with_bindings(
        pattern.json_compiled,
        expr,
        bindings,
      )
    Some(AstBindings(_)) => None
    None => @json_matching.match_expr_pattern_ast(pattern.json_compiled, expr)
  }
  match matched {
    Some(result) if json_guards_match(pattern.guards, result.bindings) =>
      Some(JsonRuleMatch(result))
    _ => None
  }
}

///|
fn bindings_from_match(result : RulePatternMatch) -> RulePatternBindings {
  match result {
    AstRuleMatch(result) => AstBindings(result.bindings)
    JsonRuleMatch(result) => JsonBindings(result.bindings)
  }
}

///|
fn target_expr_from_match(
  root : @syntax.Expr,
  result : RulePatternMatch,
) -> @syntax.Expr? {
  match result {
    AstRuleMatch(result) =>
      match result.bindings.get("__TARGET__") {
        Some(@matching.BoundValue::Expr(target)) => Some(target)
        _ => None
      }
    JsonRuleMatch(result) =>
      match result.bindings.get("__TARGET__") {
        Some(@json_matching.JsonBoundValue::Expr(target)) =>
          find_expr_by_json(root, target)
        _ => None
      }
  }
}

///|
fn find_expr_by_json(root : @syntax.Expr, target : Json) -> @syntax.Expr? {
  let exprs : Array[@syntax.Expr] = []
  collect_exprs(root, exprs)
  for expr in exprs {
    if @json_matching.json_exact_equal(expr.to_json(), target) {
      return Some(expr)
    }
  }
  None
}

///|
fn ast_guards_match(
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
fn json_guards_match(
  guards : Array[CompiledRuleGuard],
  bindings : @hashmap.HashMap[String, @json_matching.JsonBoundValue],
) -> Bool {
  for guard_entry in guards {
    match guard_entry.capture_kind {
      @model.RuleGuardCaptureKind::IdentifierGuard =>
        match bindings.get(guard_entry.name) {
          Some(@json_matching.JsonBoundValue::Identifier(value)) =>
            if guard_entry.regex.execute(value) is None {
              return false
            }
          _ => return false
        }
      @model.RuleGuardCaptureKind::ConstantGuard =>
        match bindings.get(guard_entry.name) {
          Some(@json_matching.JsonBoundValue::Constant(value)) =>
            match @json_matching.json_constant_guard_value(value) {
              Some(text) =>
                if guard_entry.regex.execute(text) is None {
                  return false
                }
              None => return false
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
