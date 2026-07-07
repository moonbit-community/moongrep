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
priv enum RuleTraversalAction {
  RuleContinue
  RulePrune
}

///|
priv enum InsideTargetScanAction {
  InsideTargetContinue
  InsideTargetPrune
  InsideTargetReject
}

///|
priv struct AstStructuralRuleEntry {
  rule : CompiledRule
  structural : CompiledStructuralRule
  pattern_buckets : ExprPatternBuckets
  negative_pattern_buckets : ExprPatternBuckets
  inside_root_key : @untyped_ast.NodeKind?
}

///|
/// Applies only structural rules to the supplied untyped AST root.
///
/// Supported expression subtrees are visited in source-tree order. For a
/// single expression and rule, the first matching pattern wins and determines
/// `pattern_index`.
pub fn apply_structural_rules(
  file : String,
  root_node : @untyped_ast.Node,
  rules : Array[CompiledRule],
) -> Array[RuleFinding] {
  apply_structural_rules_to_node(file, root_node, rules)
}

///|
pub fn apply_structural_rules_to_node(
  file : String,
  node : @untyped_ast.Node,
  rules : Array[CompiledRule],
) -> Array[RuleFinding] {
  let hits : Array[RuleFinding] = []
  let entries = ast_structural_rule_entries(rules)
  @untyped_ast.visit_node_scoped_expr_roots(node, fn(scoped_expr) {
    apply_ast_structural_rule_entries_to_scoped_expr(
      file, entries, scoped_expr, hits,
    )
    NodeVisitPrune
  })
  hits
}

///|
fn ast_structural_rule_entries(
  rules : Array[CompiledRule],
) -> Array[AstStructuralRuleEntry] {
  let entries : Array[AstStructuralRuleEntry] = []
  for rule in rules {
    match rule.definition {
      Structural(structural) => {
        let inside_root_key = if structural.inside_expr is Some(inside) {
          compiled_pattern_root_key(inside)
        } else {
          None
        }
        entries.push({
          rule,
          structural,
          pattern_buckets: ExprPatternBuckets::from_patterns(
            structural.patterns,
          ),
          negative_pattern_buckets: ExprPatternBuckets::from_patterns(
            structural.patterns_not,
          ),
          inside_root_key,
        })
      }
      _ => ()
    }
  }
  entries
}

///|
fn apply_ast_structural_rule_entries_to_scoped_expr(
  file : String,
  entries : Array[AstStructuralRuleEntry],
  scoped_expr : @untyped_ast.ScopedNodeExpr,
  hits : Array[RuleFinding],
) -> Unit {
  let child_entries : Array[AstStructuralRuleEntry] = []
  for entry in entries {
    match
      apply_ast_structural_rule_entry_to_scoped_expr(
        file, entry, scoped_expr, hits,
      ) {
      RuleContinue => child_entries.push(entry)
      RulePrune => ()
    }
  }
  if child_entries.length() == 0 {
    return
  }
  @untyped_ast.visit_node_scoped_expr_children(
    scoped_expr.expr,
    scoped_expr.shadowed_names,
    fn(child) {
      apply_ast_structural_rule_entries_to_scoped_expr(
        file, child_entries, child, hits,
      )
    },
  )
}

///|
fn apply_ast_structural_rule_entry_to_scoped_expr(
  file : String,
  entry : AstStructuralRuleEntry,
  scoped_expr : @untyped_ast.ScopedNodeExpr,
  hits : Array[RuleFinding],
) -> RuleTraversalAction {
  if entry.structural.inside_expr is Some(inside) {
    apply_inside_expr_ast_bucketed(
      file,
      entry.rule,
      entry.structural,
      inside,
      entry.inside_root_key,
      entry.pattern_buckets,
      entry.negative_pattern_buckets,
      scoped_expr.expr,
      hits,
    )
    RuleContinue
  } else {
    apply_ast_patterns_at_node(
      file,
      entry.rule,
      entry.pattern_buckets,
      entry.negative_pattern_buckets,
      scoped_expr.expr,
      None,
      None,
      hits,
    )
  }
}

///|
/// Applies only taint rules to function-like untyped AST nodes.
///
/// Unsupported top-level nodes are ignored. Other taint-analysis errors are
/// propagated to the caller.
pub fn apply_taint_rules(
  file : String,
  root_node : @untyped_ast.Node,
  rules : Array[CompiledRule],
) -> Array[RuleFinding] raise {
  let hits : Array[RuleFinding] = []
  if root_node.kind == ImplList {
    for entry in root_node.children {
      let (_, node) = entry
      let node_hits = apply_taint_rules_to_node(file, node, rules)
      for hit in node_hits {
        hits.push(hit)
      }
    }
  } else {
    let node_hits = apply_taint_rules_to_node(file, root_node, rules)
    for hit in node_hits {
      hits.push(hit)
    }
  }
  hits
}

///|
pub fn apply_taint_rules_to_node(
  file : String,
  node : @untyped_ast.Node,
  rules : Array[CompiledRule],
) -> Array[RuleFinding] raise {
  let hits : Array[RuleFinding] = []
  for rule in rules {
    match rule.definition {
      Taint(taint_rule) =>
        apply_taint_rule_to_node(file, rule, taint_rule, node, hits)
      _ => ()
    }
  }
  hits
}

///|
fn apply_taint_rule_to_node(
  file : String,
  rule : CompiledRule,
  taint_rule : CompiledTaintRule,
  node : @untyped_ast.Node,
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
fn apply_inside_expr_ast_bucketed(
  file : String,
  rule : CompiledRule,
  structural : CompiledStructuralRule,
  inside : CompiledRulePattern,
  inside_root_key : @untyped_ast.NodeKind?,
  pattern_buckets : ExprPatternBuckets,
  negative_pattern_buckets : ExprPatternBuckets,
  expr : @untyped_ast.Node,
  hits : Array[RuleFinding],
) -> Unit {
  if !node_root_key_matches(inside_root_key, expr) {
    return
  }
  if match_node_rule_pattern(inside, expr, None) is Some(result) {
    if result.bindings.get("__TARGET__") is Some(target) {
      if structural.patterns.is_empty() {
        let target_exprs : Array[@untyped_ast.ScopedNodeExpr] = []
        @untyped_ast.collect_node_scoped_exprs(target, target_exprs)
        apply_inside_expr_only_ast_bucketed(
          file,
          rule,
          negative_pattern_buckets,
          target_exprs,
          expr.loc,
          result.bindings,
          inside.compiled.identifier_metavars,
          hits,
        )
      } else {
        match structural.patterns_not_mode {
          RejectUncoveredNegative =>
            apply_ast_bucketed_covered_patterns_in_target_subtree(
              file,
              rule,
              pattern_buckets,
              negative_pattern_buckets,
              target,
              Some(expr.loc),
              result.bindings,
              inside.compiled.identifier_metavars,
              hits,
            )
          PruneOnNegative =>
            apply_ast_bucketed_patterns_in_target_subtree(
              file,
              rule,
              pattern_buckets,
              negative_pattern_buckets,
              target,
              Some(expr.loc),
              result.bindings,
              inside.compiled.identifier_metavars,
              hits,
            )
        }
      }
    }
  }
}

///|
fn apply_ast_bucketed_patterns_in_target_subtree(
  file : String,
  rule : CompiledRule,
  pattern_buckets : ExprPatternBuckets,
  negative_pattern_buckets : ExprPatternBuckets,
  target : @untyped_ast.Node,
  outer_loc : @basic.Location?,
  outer_bindings : @hashmap.HashMap[String, @matching.BoundValue],
  inherited_identifier_metavars : Array[String],
  hits : Array[RuleFinding],
) -> Unit {
  @untyped_ast.visit_node_scoped_exprs(target, fn(scoped_expr) {
    match
      apply_ast_bucketed_patterns_at_scoped_expr(
        file, rule, pattern_buckets, negative_pattern_buckets, scoped_expr, outer_loc,
        outer_bindings, inherited_identifier_metavars, hits,
      ) {
      RulePrune => NodeVisitPrune
      RuleContinue => NodeVisitContinue
    }
  })
}

///|
fn apply_ast_bucketed_covered_patterns_in_target_subtree(
  file : String,
  rule : CompiledRule,
  pattern_buckets : ExprPatternBuckets,
  negative_pattern_buckets : ExprPatternBuckets,
  target : @untyped_ast.Node,
  outer_loc : @basic.Location?,
  outer_bindings : @hashmap.HashMap[String, @matching.BoundValue],
  inherited_identifier_metavars : Array[String],
  hits : Array[RuleFinding],
) -> Unit {
  let pending_hits : Array[RuleFinding] = []
  let mut rejected = false
  @untyped_ast.visit_node_scoped_exprs(target, fn(scoped_expr) {
    if rejected {
      NodeVisitPrune
    } else {
      match
        apply_ast_bucketed_covered_patterns_at_scoped_expr(
          file, rule, pattern_buckets, negative_pattern_buckets, scoped_expr, outer_loc,
          outer_bindings, inherited_identifier_metavars, pending_hits,
        ) {
        InsideTargetPrune => NodeVisitPrune
        InsideTargetReject => {
          rejected = true
          NodeVisitPrune
        }
        InsideTargetContinue => NodeVisitContinue
      }
    }
  })
  if !rejected && !pending_hits.is_empty() {
    hits.append(pending_hits)
  }
}

///|
fn apply_inside_expr_only_ast_bucketed(
  file : String,
  rule : CompiledRule,
  negative_pattern_buckets : ExprPatternBuckets,
  target_exprs : Array[@untyped_ast.ScopedNodeExpr],
  outer_loc : @basic.Location,
  outer_bindings : @hashmap.HashMap[String, @matching.BoundValue],
  inherited_identifier_metavars : Array[String],
  hits : Array[RuleFinding],
) -> Unit {
  if ast_bucketed_negative_patterns_match_any_scoped_expr(
      negative_pattern_buckets, target_exprs, outer_bindings, inherited_identifier_metavars,
    ) {
    return
  }
  push_inside_expr_only_hit(file, rule, outer_loc, hits)
}

///|
fn push_inside_expr_only_hit(
  file : String,
  rule : CompiledRule,
  outer_loc : @basic.Location,
  hits : Array[RuleFinding],
) -> Unit {
  hits.push({
    file,
    rule_id: rule.rule_id,
    description: rule.description,
    pattern_index: 0,
    loc: outer_loc,
    outer_loc: Some(outer_loc),
  })
}

///|
fn apply_ast_bucketed_covered_patterns_at_scoped_expr(
  file : String,
  rule : CompiledRule,
  pattern_buckets : ExprPatternBuckets,
  negative_pattern_buckets : ExprPatternBuckets,
  scoped_expr : @untyped_ast.ScopedNodeExpr,
  outer_loc : @basic.Location?,
  outer_bindings : @hashmap.HashMap[String, @matching.BoundValue],
  inherited_identifier_metavars : Array[String],
  hits : Array[RuleFinding],
) -> InsideTargetScanAction {
  for indexed in pattern_buckets.patterns_for_node(scoped_expr.expr) {
    if ast_pattern_blocked_by_shadowed_outer_id(
        indexed.pattern,
        outer_bindings,
        inherited_identifier_metavars,
        scoped_expr.shadowed_names,
      ) {
      continue
    }
    if match_node_rule_pattern(
        indexed.pattern,
        scoped_expr.expr,
        Some(outer_bindings),
      )
      is Some(_) {
      hits.push({
        file,
        rule_id: rule.rule_id,
        description: rule.description,
        pattern_index: indexed.pattern_index,
        loc: scoped_expr.expr.loc,
        outer_loc,
      })
      return InsideTargetPrune
    }
  }
  if ast_bucketed_negative_patterns_match_scoped_expr(
      negative_pattern_buckets, scoped_expr, outer_bindings, inherited_identifier_metavars,
    ) {
    return InsideTargetReject
  }
  InsideTargetContinue
}

///|
fn apply_ast_bucketed_patterns_at_scoped_expr(
  file : String,
  rule : CompiledRule,
  pattern_buckets : ExprPatternBuckets,
  negative_pattern_buckets : ExprPatternBuckets,
  scoped_expr : @untyped_ast.ScopedNodeExpr,
  outer_loc : @basic.Location?,
  outer_bindings : @hashmap.HashMap[String, @matching.BoundValue],
  inherited_identifier_metavars : Array[String],
  hits : Array[RuleFinding],
) -> RuleTraversalAction {
  for indexed in pattern_buckets.patterns_for_node(scoped_expr.expr) {
    if ast_pattern_blocked_by_shadowed_outer_id(
        indexed.pattern,
        outer_bindings,
        inherited_identifier_metavars,
        scoped_expr.shadowed_names,
      ) {
      continue
    }
    if match_node_rule_pattern(
        indexed.pattern,
        scoped_expr.expr,
        Some(outer_bindings),
      )
      is Some(_) {
      hits.push({
        file,
        rule_id: rule.rule_id,
        description: rule.description,
        pattern_index: indexed.pattern_index,
        loc: scoped_expr.expr.loc,
        outer_loc,
      })
      return RulePrune
    }
  }
  if ast_bucketed_negative_patterns_match_scoped_expr(
      negative_pattern_buckets, scoped_expr, outer_bindings, inherited_identifier_metavars,
    ) {
    return RulePrune
  }
  RuleContinue
}

///|
fn apply_ast_patterns_at_node(
  file : String,
  rule : CompiledRule,
  pattern_buckets : ExprPatternBuckets,
  negative_pattern_buckets : ExprPatternBuckets,
  expr : @untyped_ast.Node,
  outer_loc : @basic.Location?,
  initial_bindings : @hashmap.HashMap[String, @matching.BoundValue]?,
  hits : Array[RuleFinding],
) -> RuleTraversalAction {
  for indexed in pattern_buckets.patterns_for_node(expr) {
    if match_node_rule_pattern(indexed.pattern, expr, initial_bindings)
      is Some(_) {
      hits.push({
        file,
        rule_id: rule.rule_id,
        description: rule.description,
        pattern_index: indexed.pattern_index,
        loc: expr.loc,
        outer_loc,
      })
      return RulePrune
    }
  }
  if ast_negative_patterns_match_node(
      negative_pattern_buckets, expr, initial_bindings,
    ) {
    return RulePrune
  }
  RuleContinue
}

///|
fn ast_negative_patterns_match_node(
  negative_pattern_buckets : ExprPatternBuckets,
  expr : @untyped_ast.Node,
  initial_bindings : @hashmap.HashMap[String, @matching.BoundValue]?,
) -> Bool {
  for indexed in negative_pattern_buckets.patterns_for_node(expr) {
    if match_node_rule_pattern(indexed.pattern, expr, initial_bindings)
      is Some(_) {
      return true
    }
  }
  false
}

///|
fn ast_bucketed_negative_patterns_match_scoped_expr(
  negative_pattern_buckets : ExprPatternBuckets,
  scoped_expr : @untyped_ast.ScopedNodeExpr,
  initial_bindings : @hashmap.HashMap[String, @matching.BoundValue],
  inherited_identifier_metavars : Array[String],
) -> Bool {
  for indexed in negative_pattern_buckets.patterns_for_node(scoped_expr.expr) {
    if ast_pattern_blocked_by_shadowed_outer_id(
        indexed.pattern,
        initial_bindings,
        inherited_identifier_metavars,
        scoped_expr.shadowed_names,
      ) {
      continue
    }
    if match_node_rule_pattern(
        indexed.pattern,
        scoped_expr.expr,
        Some(initial_bindings),
      )
      is Some(_) {
      return true
    }
  }
  false
}

///|
fn ast_bucketed_negative_patterns_match_any_scoped_expr(
  negative_pattern_buckets : ExprPatternBuckets,
  target_exprs : Array[@untyped_ast.ScopedNodeExpr],
  initial_bindings : @hashmap.HashMap[String, @matching.BoundValue],
  inherited_identifier_metavars : Array[String],
) -> Bool {
  for scoped_expr in target_exprs {
    if ast_bucketed_negative_patterns_match_scoped_expr(
        negative_pattern_buckets, scoped_expr, initial_bindings, inherited_identifier_metavars,
      ) {
      return true
    }
  }
  false
}

///|
fn ast_pattern_blocked_by_shadowed_outer_id(
  pattern : CompiledRulePattern,
  outer_bindings : @hashmap.HashMap[String, @matching.BoundValue],
  inherited_identifier_metavars : Array[String],
  shadowed_names : Array[String],
) -> Bool {
  for metavar in inherited_identifier_metavars {
    if names_contain(pattern.compiled.identifier_metavars, metavar) {
      if outer_bindings.get(metavar) is Some(bound_node) {
        if node_leaf_string(bound_node) is Some(bound_name) &&
          names_contain(shadowed_names, bound_name) {
          return true
        }
      }
    }
  }
  false
}

///|
fn names_contain(names : Array[String], needle : String) -> Bool {
  for name in names {
    if name == needle {
      return true
    }
  }
  false
}

///|
fn match_node_rule_pattern(
  pattern : CompiledRulePattern,
  expr : @untyped_ast.Node,
  initial_bindings : @hashmap.HashMap[String, @matching.BoundValue]?,
) -> @matching.ExprMatch? {
  let matched = if initial_bindings is Some(bindings) {
    @matching.match_expr_pattern_with_bindings(pattern.compiled, expr, bindings)
  } else {
    @matching.match_expr_pattern(pattern.compiled, expr)
  }
  match matched {
    Some(result) if ast_guards_match(pattern.guards, result.bindings) =>
      Some(result)
    _ => None
  }
}

///|
fn ast_guards_match(
  guards : Array[CompiledRuleGuard],
  bindings : @hashmap.HashMap[String, @matching.BoundValue],
) -> Bool {
  for guard_entry in guards {
    match guard_entry.capture_kind {
      IdentifierGuard =>
        match bindings.get(guard_entry.name) {
          Some(value) => {
            guard node_leaf_string(value) is Some(text) else { return false }
            if guard_entry.regex.execute(text) is None {
              return false
            }
          }
          _ => return false
        }
      ConstantGuard =>
        match bindings.get(guard_entry.name) {
          Some(value) => {
            guard constant_guard_value(value) is Some(text) else {
              return false
            }
            if guard_entry.regex.execute(text) is None {
              return false
            }
          }
          _ => return false
        }
    }
  }
  true
}

///|
fn constant_guard_value(constant : @untyped_ast.Node) -> String? {
  match constant.kind {
    Constant_Bool =>
      if node_leaf_bool_child(constant, "value") is Some(value) {
        Some(value.to_string())
      } else {
        None
      }
    Constant_BigInt
    | Constant_Byte
    | Constant_Bytes
    | Constant_Char
    | Constant_Double
    | Constant_Float
    | Constant_Int
    | Constant_Int64
    | Constant_Regex
    | Constant_String
    | Constant_UInt
    | Constant_UInt64 => node_leaf_string_child(constant, "value")
    _ => None
  }
}

///|
fn node_child(node : @untyped_ast.Node, name : String) -> @untyped_ast.Node? {
  for entry in node.children {
    let (child_name, value) = entry
    if child_name == Some(name) {
      return Some(value)
    }
  }
  None
}

///|
fn node_leaf_string(node : @untyped_ast.Node) -> String? {
  match node.kind {
    Leaf(PString(value)) => Some(value)
    _ => None
  }
}

///|
fn node_leaf_bool(node : @untyped_ast.Node) -> Bool? {
  match node.kind {
    Leaf(PBool(value)) => Some(value)
    _ => None
  }
}

///|
fn node_leaf_string_child(node : @untyped_ast.Node, name : String) -> String? {
  if node_child(node, name) is Some(value) {
    node_leaf_string(value)
  } else {
    None
  }
}

///|
fn node_leaf_bool_child(node : @untyped_ast.Node, name : String) -> Bool? {
  if node_child(node, name) is Some(value) {
    node_leaf_bool(value)
  } else {
    None
  }
}
