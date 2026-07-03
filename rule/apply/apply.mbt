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
using @traverse {type ScopedExpr}

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
priv enum NodeVisitAction {
  NodeVisitContinue
  NodeVisitPrune
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
priv struct ScopedNodeExpr {
  expr : @untyped_ast.Node
  shadowed_names : Array[String]
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
  let entries = ast_structural_rule_entries(rules)
  @traverse.visit_impl_scoped_expr_roots(node, fn(scoped_expr) {
    apply_ast_structural_rule_entries_to_scoped_expr(
      file, entries, scoped_expr, hits,
    )
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
  scoped_expr : ScopedExpr,
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
  @traverse.visit_scoped_expr_children(scoped_expr, fn(child) {
    apply_ast_structural_rule_entries_to_scoped_expr(
      file, child_entries, child, hits,
    )
  })
}

///|
fn apply_ast_structural_rule_entry_to_scoped_expr(
  file : String,
  entry : AstStructuralRuleEntry,
  scoped_expr : ScopedExpr,
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
    apply_ast_patterns_at_expr(
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
fn apply_inside_expr_ast_bucketed(
  file : String,
  rule : CompiledRule,
  structural : CompiledStructuralRule,
  inside : CompiledRulePattern,
  inside_root_key : @untyped_ast.NodeKind?,
  pattern_buckets : ExprPatternBuckets,
  negative_pattern_buckets : ExprPatternBuckets,
  expr : @syntax.Expr,
  hits : Array[RuleFinding],
) -> Unit {
  if !ast_bucket_root_key_matches(inside_root_key, expr) {
    return
  }
  if match_ast_rule_pattern(inside, expr, None) is Some(result) {
    if result.bindings.get("__TARGET__") is Some(target) {
      if structural.patterns.is_empty() {
        let target_exprs : Array[ScopedNodeExpr] = []
        collect_node_scoped_exprs(target, target_exprs)
        apply_inside_expr_only_ast_bucketed(
          file,
          rule,
          negative_pattern_buckets,
          target_exprs,
          expr.loc(),
          result.bindings,
          inside.compiled.identifier_metavars,
          hits,
        )
      } else {
        match structural.patterns_not_mode {
          @model.StructuralPatternsNotMode::RejectUncoveredNegative =>
            apply_ast_bucketed_covered_patterns_in_target_subtree(
              file,
              rule,
              pattern_buckets,
              negative_pattern_buckets,
              target,
              Some(expr.loc()),
              result.bindings,
              inside.compiled.identifier_metavars,
              hits,
            )
          @model.StructuralPatternsNotMode::PruneOnNegative =>
            apply_ast_bucketed_patterns_in_target_subtree(
              file,
              rule,
              pattern_buckets,
              negative_pattern_buckets,
              target,
              Some(expr.loc()),
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
  visit_node_scoped_exprs(target, fn(scoped_expr) {
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
  visit_node_scoped_exprs(target, fn(scoped_expr) {
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
  target_exprs : Array[ScopedNodeExpr],
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
  scoped_expr : ScopedNodeExpr,
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
  scoped_expr : ScopedNodeExpr,
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
fn apply_ast_patterns_at_expr(
  file : String,
  rule : CompiledRule,
  pattern_buckets : ExprPatternBuckets,
  negative_pattern_buckets : ExprPatternBuckets,
  expr : @syntax.Expr,
  outer_loc : @basic.Location?,
  initial_bindings : @hashmap.HashMap[String, @matching.BoundValue]?,
  hits : Array[RuleFinding],
) -> RuleTraversalAction {
  for indexed in pattern_buckets.patterns_for_expr(expr) {
    if match_ast_rule_pattern(indexed.pattern, expr, initial_bindings)
      is Some(_) {
      hits.push({
        file,
        rule_id: rule.rule_id,
        description: rule.description,
        pattern_index: indexed.pattern_index,
        loc: expr.loc(),
        outer_loc,
      })
      return RulePrune
    }
  }
  if ast_negative_patterns_match_expr(
      negative_pattern_buckets, expr, initial_bindings,
    ) {
    return RulePrune
  }
  RuleContinue
}

///|
fn ast_negative_patterns_match_expr(
  negative_pattern_buckets : ExprPatternBuckets,
  expr : @syntax.Expr,
  initial_bindings : @hashmap.HashMap[String, @matching.BoundValue]?,
) -> Bool {
  for indexed in negative_pattern_buckets.patterns_for_expr(expr) {
    if match_ast_rule_pattern(indexed.pattern, expr, initial_bindings)
      is Some(_) {
      return true
    }
  }
  false
}

///|
fn ast_bucketed_negative_patterns_match_scoped_expr(
  negative_pattern_buckets : ExprPatternBuckets,
  scoped_expr : ScopedNodeExpr,
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
  target_exprs : Array[ScopedNodeExpr],
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
fn match_ast_rule_pattern(
  pattern : CompiledRulePattern,
  expr : @syntax.Expr,
  initial_bindings : @hashmap.HashMap[String, @matching.BoundValue]?,
) -> @matching.ExprMatch? {
  match_node_rule_pattern(
    pattern,
    @untyped_ast.from_expr(expr),
    initial_bindings,
  )
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
      @model.RuleGuardCaptureKind::IdentifierGuard =>
        match bindings.get(guard_entry.name) {
          Some(value) => {
            guard node_leaf_string(value) is Some(text) else { return false }
            if guard_entry.regex.execute(text) is None {
              return false
            }
          }
          _ => return false
        }
      @model.RuleGuardCaptureKind::ConstantGuard =>
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
fn collect_node_scoped_exprs(
  expr : @untyped_ast.Node,
  exprs : Array[ScopedNodeExpr],
) -> Unit {
  collect_node_scoped_exprs_with_shadow(expr, [], exprs)
}

///|
fn collect_node_scoped_exprs_with_shadow(
  expr : @untyped_ast.Node,
  shadowed : Array[String],
  exprs : Array[ScopedNodeExpr],
) -> Unit {
  exprs.push({ expr, shadowed_names: copy_names(shadowed) })
  visit_node_scoped_expr_children(expr, shadowed, fn(child) {
    collect_node_scoped_exprs_with_shadow(
      child.expr,
      child.shadowed_names,
      exprs,
    )
  })
}

///|
fn visit_node_scoped_exprs(
  expr : @untyped_ast.Node,
  visitor : (ScopedNodeExpr) -> NodeVisitAction,
) -> Unit {
  visit_node_scoped_exprs_with_shadow(expr, [], visitor)
}

///|
fn visit_node_scoped_exprs_with_shadow(
  expr : @untyped_ast.Node,
  shadowed : Array[String],
  visitor : (ScopedNodeExpr) -> NodeVisitAction,
) -> Unit {
  let scoped_expr = { expr, shadowed_names: copy_names(shadowed) }
  match visitor(scoped_expr) {
    NodeVisitPrune => ()
    NodeVisitContinue =>
      visit_node_scoped_expr_children(expr, shadowed, fn(child) {
        visit_node_scoped_exprs_with_shadow(
          child.expr,
          child.shadowed_names,
          visitor,
        )
      })
  }
}

///|
fn visit_node_scoped_expr_children(
  expr : @untyped_ast.Node,
  shadowed : Array[String],
  visitor : (ScopedNodeExpr) -> Unit,
) -> Unit {
  match expr.kind {
    Expr_Let => {
      visit_node_named_expr(expr, "expr", shadowed, visitor)
      let body_shadowed = if node_child(expr, "pattern") is Some(pattern) {
        shadowed_with_node_pattern(shadowed, pattern)
      } else {
        copy_names(shadowed)
      }
      visit_node_named_expr(expr, "body", body_shadowed, visitor)
    }
    Expr_LetMut => {
      visit_node_named_expr(expr, "expr", shadowed, visitor)
      let body_shadowed = if node_child(expr, "binder") is Some(binder) {
        shadowed_with_node_binder(shadowed, binder)
      } else {
        copy_names(shadowed)
      }
      visit_node_named_expr(expr, "body", body_shadowed, visitor)
    }
    Expr_For => {
      visit_node_binding_list_exprs(expr, "binders", shadowed, visitor)
      let loop_shadowed = if node_child(expr, "binders") is Some(binders) {
        shadowed_with_node_binding_list_binders(shadowed, binders)
      } else {
        copy_names(shadowed)
      }
      visit_node_named_expr(expr, "condition", loop_shadowed, visitor)
      visit_node_binding_list_exprs(
        expr, "continue_block", loop_shadowed, visitor,
      )
      visit_node_named_expr(expr, "body", loop_shadowed, visitor)
      visit_node_named_expr(expr, "for_else", loop_shadowed, visitor)
      visit_node_named_container_exprs(
        expr, "where_clause", loop_shadowed, visitor,
      )
    }
    Expr_ForEach => {
      visit_node_named_expr(expr, "expr", shadowed, visitor)
      visit_node_binding_list_exprs(expr, "init", shadowed, visitor)
      let loop_shadowed = if node_child(expr, "binders") is Some(binders) {
        shadowed_with_node_optional_binders(shadowed, binders)
      } else {
        copy_names(shadowed)
      }
      if node_child(expr, "init") is Some(init) {
        add_node_binding_list_names(loop_shadowed, init)
      }
      visit_node_binding_list_exprs(
        expr, "continue_block", loop_shadowed, visitor,
      )
      visit_node_named_expr(expr, "body", loop_shadowed, visitor)
      visit_node_named_expr(expr, "else_block", loop_shadowed, visitor)
      visit_node_named_container_exprs(
        expr, "where_clause", loop_shadowed, visitor,
      )
    }
    Expr_Match => {
      visit_node_named_expr(expr, "expr", shadowed, visitor)
      visit_node_case_list_exprs(expr, "cases", shadowed, visitor)
    }
    Expr_Lexmatch => {
      visit_node_named_expr(expr, "expr", shadowed, visitor)
      visit_node_lex_case_list_exprs(expr, "cases", shadowed, visitor)
    }
    Expr_ListComprehension => {
      let body_shadowed = if node_child(expr, "kind") is Some(kind) {
        visit_node_list_comprehension_kind_exprs(kind, shadowed, visitor)
      } else {
        copy_names(shadowed)
      }
      visit_node_named_expr(expr, "guard", body_shadowed, visitor)
      visit_node_named_expr(expr, "body", body_shadowed, visitor)
    }
    Expr_Function =>
      if node_child(expr, "func") is Some(func) {
        visit_node_func_exprs(func, shadowed, visitor)
      }
    Expr_LetFn => {
      let name_shadowed = if node_child(expr, "name") is Some(binder) {
        shadowed_with_node_binder(shadowed, binder)
      } else {
        copy_names(shadowed)
      }
      if node_child(expr, "func") is Some(func) {
        visit_node_func_exprs(func, name_shadowed, visitor)
      }
      visit_node_named_expr(expr, "body", name_shadowed, visitor)
    }
    Expr_LetAnd => {
      let binding_shadowed = if node_child(expr, "bindings") is Some(bindings) {
        shadowed_with_node_let_and_binders(shadowed, bindings)
      } else {
        copy_names(shadowed)
      }
      if node_child(expr, "bindings") is Some(bindings) {
        for entry in bindings.children {
          let (_, binding) = entry
          if node_child(binding, "func") is Some(func) {
            visit_node_func_exprs(func, binding_shadowed, visitor)
          }
        }
      }
      visit_node_named_expr(expr, "body", binding_shadowed, visitor)
    }
    Expr_Quantifier => {
      let body_shadowed = if node_child(expr, "binder") is Some(binder) {
        shadowed_with_node_binder(shadowed, binder)
      } else {
        copy_names(shadowed)
      }
      visit_node_named_expr(expr, "body", body_shadowed, visitor)
    }
    Expr_Try => {
      visit_node_named_expr(expr, "body", shadowed, visitor)
      visit_node_case_list_exprs(expr, "catch", shadowed, visitor)
      visit_node_case_list_exprs(expr, "try_else", shadowed, visitor)
    }
    Expr_IsLexmatch => {
      visit_node_named_expr(expr, "expr", shadowed, visitor)
      visit_node_named_container_exprs(expr, "pat", shadowed, visitor)
    }
    Expr_RegexMatch => {
      visit_node_named_expr(expr, "expr", shadowed, visitor)
      visit_node_named_container_exprs(expr, "pat", shadowed, visitor)
    }
    _ => visit_node_all_child_exprs(expr, shadowed, visitor)
  }
}

///|
fn visit_node_named_expr(
  node : @untyped_ast.Node,
  name : String,
  shadowed : Array[String],
  visitor : (ScopedNodeExpr) -> Unit,
) -> Unit {
  if node_child(node, name) is Some(child) {
    visit_node_descendant_exprs(child, shadowed, visitor)
  }
}

///|
fn visit_node_named_container_exprs(
  node : @untyped_ast.Node,
  name : String,
  shadowed : Array[String],
  visitor : (ScopedNodeExpr) -> Unit,
) -> Unit {
  if node_child(node, name) is Some(child) {
    visit_node_all_child_exprs(child, shadowed, visitor)
  }
}

///|
fn visit_node_descendant_exprs(
  node : @untyped_ast.Node,
  shadowed : Array[String],
  visitor : (ScopedNodeExpr) -> Unit,
) -> Unit {
  if is_expr_node(node) {
    visitor({ expr: node, shadowed_names: copy_names(shadowed) })
  } else {
    visit_node_all_child_exprs(node, shadowed, visitor)
  }
}

///|
fn visit_node_all_child_exprs(
  node : @untyped_ast.Node,
  shadowed : Array[String],
  visitor : (ScopedNodeExpr) -> Unit,
) -> Unit {
  for entry in node.children {
    let (_, child) = entry
    visit_node_descendant_exprs(child, shadowed, visitor)
  }
}

///|
fn visit_node_binding_list_exprs(
  node : @untyped_ast.Node,
  name : String,
  shadowed : Array[String],
  visitor : (ScopedNodeExpr) -> Unit,
) -> Unit {
  if node_child(node, name) is Some(list) {
    for entry in list.children {
      let (_, binding) = entry
      visit_node_named_expr(binding, "expr", shadowed, visitor)
    }
  }
}

///|
fn visit_node_case_list_exprs(
  node : @untyped_ast.Node,
  name : String,
  shadowed : Array[String],
  visitor : (ScopedNodeExpr) -> Unit,
) -> Unit {
  if node_child(node, name) is Some(list) {
    visit_node_case_container_exprs(list, shadowed, visitor)
  }
}

///|
fn visit_node_case_container_exprs(
  list : @untyped_ast.Node,
  shadowed : Array[String],
  visitor : (ScopedNodeExpr) -> Unit,
) -> Unit {
  for entry in list.children {
    let (_, case) = entry
    let case_shadowed = if node_child(case, "pattern") is Some(pattern) {
      shadowed_with_node_pattern(shadowed, pattern)
    } else {
      copy_names(shadowed)
    }
    visit_node_named_expr(case, "guard", case_shadowed, visitor)
    visit_node_named_expr(case, "body", case_shadowed, visitor)
  }
}

///|
fn visit_node_lex_case_list_exprs(
  node : @untyped_ast.Node,
  name : String,
  shadowed : Array[String],
  visitor : (ScopedNodeExpr) -> Unit,
) -> Unit {
  if node_child(node, name) is Some(list) {
    for entry in list.children {
      let (_, case) = entry
      let case_shadowed = if node_child(case, "pat") is Some(patterns) {
        shadowed_with_node_patterns(shadowed, patterns)
      } else {
        copy_names(shadowed)
      }
      visit_node_named_expr(case, "guard", case_shadowed, visitor)
      visit_node_named_expr(case, "body", case_shadowed, visitor)
    }
  }
}

///|
fn visit_node_list_comprehension_kind_exprs(
  kind : @untyped_ast.Node,
  shadowed : Array[String],
  visitor : (ScopedNodeExpr) -> Unit,
) -> Array[String] {
  match kind.kind {
    Expr_ListComprehension_Kind_For => {
      visit_node_binding_list_exprs(kind, "binders", shadowed, visitor)
      let loop_shadowed = if node_child(kind, "binders") is Some(binders) {
        shadowed_with_node_binding_list_binders(shadowed, binders)
      } else {
        copy_names(shadowed)
      }
      visit_node_named_expr(kind, "condition", loop_shadowed, visitor)
      visit_node_binding_list_exprs(
        kind, "continue_block", loop_shadowed, visitor,
      )
      loop_shadowed
    }
    Expr_ListComprehension_Kind_Foreach => {
      visit_node_named_expr(kind, "expr", shadowed, visitor)
      visit_node_binding_list_exprs(kind, "init", shadowed, visitor)
      let loop_shadowed = if node_child(kind, "binders") is Some(binders) {
        shadowed_with_node_optional_binders(shadowed, binders)
      } else {
        copy_names(shadowed)
      }
      if node_child(kind, "init") is Some(init) {
        add_node_binding_list_names(loop_shadowed, init)
      }
      visit_node_binding_list_exprs(
        kind, "continue_block", loop_shadowed, visitor,
      )
      loop_shadowed
    }
    _ => {
      visit_node_all_child_exprs(kind, shadowed, visitor)
      copy_names(shadowed)
    }
  }
}

///|
fn visit_node_func_exprs(
  func : @untyped_ast.Node,
  shadowed : Array[String],
  visitor : (ScopedNodeExpr) -> Unit,
) -> Unit {
  let body_shadowed = if node_child(func, "parameters") is Some(parameters) {
    shadowed_with_node_parameters(shadowed, parameters)
  } else {
    copy_names(shadowed)
  }
  visit_node_named_expr(func, "body", body_shadowed, visitor)
}

///|
fn is_expr_node(node : @untyped_ast.Node) -> Bool {
  match node.kind {
    Expr_Apply
    | Expr_Array
    | Expr_ArrayAugmentedSet
    | Expr_ArrayGet
    | Expr_ArrayGetSlice
    | Expr_ArraySet
    | Expr_ArraySpread
    | Expr_As
    | Expr_Assign
    | Expr_Break
    | Expr_Constant
    | Expr_Constr
    | Expr_Constraint
    | Expr_Continue
    | Expr_Defer
    | Expr_DotApply
    | Expr_Field
    | Expr_For
    | Expr_ForEach
    | Expr_Function
    | Expr_Group
    | Expr_Guard
    | Expr_Hole
    | Expr_Ident
    | Expr_If
    | Expr_Implies
    | Expr_Infix
    | Expr_Interp
    | Expr_Is
    | Expr_IsLexmatch
    | Expr_Let
    | Expr_LetAnd
    | Expr_LetFn
    | Expr_LetMut
    | Expr_Lexmatch
    | Expr_ListComprehension
    | Expr_Map
    | Expr_Match
    | Expr_Method
    | Expr_MultilineString
    | Expr_Mutate
    | Expr_Pipe
    | Expr_ProofAssert
    | Expr_ProofLet
    | Expr_Quantifier
    | Expr_Raise
    | Expr_Record
    | Expr_RecordUpdate
    | Expr_RegexMatch
    | Expr_Return
    | Expr_RevPipe
    | Expr_Sequence
    | Expr_StaticAssert
    | Expr_TemplateWriting
    | Expr_Try
    | Expr_TryOperator
    | Expr_Tuple
    | Expr_Unary
    | Expr_Unit
    | Expr_While => true
    _ => false
  }
}

///|
fn copy_names(names : Array[String]) -> Array[String] {
  let copied : Array[String] = []
  for name in names {
    copied.push(name)
  }
  copied
}

///|
fn add_unique_name(names : Array[String], name : String) -> Unit {
  for existing in names {
    if existing == name {
      return
    }
  }
  names.push(name)
}

///|
fn shadowed_with_node_binder(
  shadowed : Array[String],
  binder : @untyped_ast.Node,
) -> Array[String] {
  let next = copy_names(shadowed)
  add_node_binder_name(next, binder)
  next
}

///|
fn shadowed_with_node_pattern(
  shadowed : Array[String],
  pattern : @untyped_ast.Node,
) -> Array[String] {
  let next = copy_names(shadowed)
  add_node_pattern_names(next, pattern)
  next
}

///|
fn shadowed_with_node_patterns(
  shadowed : Array[String],
  patterns : @untyped_ast.Node,
) -> Array[String] {
  let next = copy_names(shadowed)
  for entry in patterns.children {
    let (_, pattern) = entry
    add_node_pattern_names(next, pattern)
  }
  next
}

///|
fn shadowed_with_node_parameters(
  shadowed : Array[String],
  parameters : @untyped_ast.Node,
) -> Array[String] {
  let next = copy_names(shadowed)
  for entry in parameters.children {
    let (_, parameter) = entry
    if node_child(parameter, "binder") is Some(binder) {
      add_node_binder_name(next, binder)
    }
  }
  next
}

///|
fn shadowed_with_node_binding_list_binders(
  shadowed : Array[String],
  bindings : @untyped_ast.Node,
) -> Array[String] {
  let next = copy_names(shadowed)
  add_node_binding_list_names(next, bindings)
  next
}

///|
fn shadowed_with_node_optional_binders(
  shadowed : Array[String],
  binders : @untyped_ast.Node,
) -> Array[String] {
  let next = copy_names(shadowed)
  for entry in binders.children {
    let (_, binder) = entry
    add_node_binder_name(next, binder)
  }
  next
}

///|
fn shadowed_with_node_let_and_binders(
  shadowed : Array[String],
  bindings : @untyped_ast.Node,
) -> Array[String] {
  let next = copy_names(shadowed)
  for entry in bindings.children {
    let (_, binding) = entry
    if node_child(binding, "binder") is Some(binder) {
      add_node_binder_name(next, binder)
    }
  }
  next
}

///|
fn add_node_binding_list_names(
  names : Array[String],
  bindings : @untyped_ast.Node,
) -> Unit {
  for entry in bindings.children {
    let (_, binding) = entry
    if node_child(binding, "binder") is Some(binder) {
      add_node_binder_name(names, binder)
    }
    if node_child(binding, "init") is Some(binder) {
      add_node_binder_name(names, binder)
    }
  }
}

///|
fn add_node_pattern_names(
  names : Array[String],
  pattern : @untyped_ast.Node,
) -> Unit {
  if pattern.kind == Binder {
    add_node_binder_name(names, pattern)
  } else {
    for entry in pattern.children {
      let (_, child) = entry
      add_node_pattern_names(names, child)
    }
  }
}

///|
fn add_node_binder_name(
  names : Array[String],
  binder : @untyped_ast.Node,
) -> Unit {
  if node_binder_name(binder) is Some(name) {
    add_unique_name(names, name)
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

///|
fn node_binder_name(node : @untyped_ast.Node) -> String? {
  if node.kind == Binder {
    node_leaf_string_child(node, "name")
  } else {
    None
  }
}
