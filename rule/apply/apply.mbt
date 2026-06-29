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
using @traverse {collect_impl_exprs, collect_scoped_exprs, type ScopedExpr}

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
priv struct AstStructuralRuleEntry {
  rule : CompiledRule
  structural : CompiledStructuralRule
  pattern_buckets : ExprPatternBuckets
  inside_root_key : String?
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
  match backend {
    @model.MatcherBackend::AstMatcher => {
      let entries = ast_structural_rule_entries(rules)
      for expr in exprs {
        for entry in entries {
          apply_ast_structural_rule_entry_to_expr(file, entry, expr, hits)
        }
      }
    }
    @model.MatcherBackend::JsonMatcher =>
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
  }
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
        let inside_root_key = match structural.inside_expr {
          Some(inside) => Some(compiled_pattern_root_key(inside))
          None => None
        }
        entries.push({
          rule,
          structural,
          pattern_buckets: ExprPatternBuckets::from_patterns(
            structural.patterns,
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
fn apply_ast_structural_rule_entry_to_expr(
  file : String,
  entry : AstStructuralRuleEntry,
  expr : @syntax.Expr,
  hits : Array[RuleFinding],
) -> Unit {
  if entry.structural.inside_expr is Some(inside) {
    let inside_root_key = match entry.inside_root_key {
      Some(key) => key
      None => ast_bucket_wildcard_key()
    }
    apply_inside_expr_ast_bucketed(
      file,
      entry.rule,
      inside,
      inside_root_key,
      entry.pattern_buckets,
      expr,
      hits,
    )
  } else {
    apply_ast_patterns_at_expr(
      file,
      entry.rule,
      entry.pattern_buckets,
      expr,
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
  if structural.inside_expr is Some(inside) {
    match backend {
      @model.MatcherBackend::AstMatcher =>
        apply_inside_expr_ast(file, rule, structural, inside, expr, hits)
      @model.MatcherBackend::JsonMatcher =>
        apply_inside_expr_json(file, rule, structural, inside, expr, hits)
    }
  } else {
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
  }
}

///|
fn apply_inside_expr_ast(
  file : String,
  rule : CompiledRule,
  structural : CompiledStructuralRule,
  inside : CompiledRulePattern,
  expr : @syntax.Expr,
  hits : Array[RuleFinding],
) -> Unit {
  if match_ast_rule_pattern(inside, expr, None) is Some(AstRuleMatch(result)) {
    if result.bindings.get("__TARGET__")
      is Some(@matching.BoundValue::Expr(target)) {
      // The context rule can bind a larger expression than the final hit.
      // Search supported expressions under `__TARGET__`, while carrying any
      // bindings established by the outer match.
      let target_exprs : Array[ScopedExpr] = []
      collect_scoped_exprs(target, target_exprs)
      for target_expr in target_exprs {
        apply_ast_patterns_at_scoped_expr(
          file,
          rule,
          structural.patterns,
          target_expr,
          Some(expr.loc()),
          result.bindings,
          inside.compiled.identifier_metavars,
          hits,
        )
      }
    }
  }
}

///|
fn apply_inside_expr_ast_bucketed(
  file : String,
  rule : CompiledRule,
  inside : CompiledRulePattern,
  inside_root_key : String,
  pattern_buckets : ExprPatternBuckets,
  expr : @syntax.Expr,
  hits : Array[RuleFinding],
) -> Unit {
  if !ast_bucket_root_key_matches(inside_root_key, expr) {
    return
  }
  if match_ast_rule_pattern(inside, expr, None) is Some(AstRuleMatch(result)) {
    if result.bindings.get("__TARGET__")
      is Some(@matching.BoundValue::Expr(target)) {
      let target_exprs : Array[ScopedExpr] = []
      collect_scoped_exprs(target, target_exprs)
      for target_expr in target_exprs {
        apply_ast_bucketed_patterns_at_scoped_expr(
          file,
          rule,
          pattern_buckets,
          target_expr,
          Some(expr.loc()),
          result.bindings,
          inside.compiled.identifier_metavars,
          hits,
        )
      }
    }
  }
}

///|
fn apply_inside_expr_json(
  file : String,
  rule : CompiledRule,
  structural : CompiledStructuralRule,
  inside : CompiledRulePattern,
  expr : @syntax.Expr,
  hits : Array[RuleFinding],
) -> Unit {
  if match_json_rule_pattern(inside, expr, None) is Some(JsonRuleMatch(result)) {
    if result.bindings.get("__TARGET__")
      is Some(@json_matching.JsonBoundValue::Expr(target)) {
      let target_exprs : Array[@json_matching.ScopedJsonExpr] = []
      @json_matching.collect_scoped_expr_jsons(target, target_exprs)
      for target_expr in target_exprs {
        apply_json_patterns_at_scoped_expr_json(
          file,
          rule,
          structural.patterns,
          target_expr,
          Some(expr.loc()),
          result.bindings,
          inside.compiled.identifier_metavars,
          hits,
        )
      }
    }
  }
}

///|
fn apply_ast_bucketed_patterns_at_scoped_expr(
  file : String,
  rule : CompiledRule,
  pattern_buckets : ExprPatternBuckets,
  scoped_expr : ScopedExpr,
  outer_loc : @basic.Location?,
  outer_bindings : @hashmap.HashMap[String, @matching.BoundValue],
  inherited_identifier_metavars : Array[String],
  hits : Array[RuleFinding],
) -> Unit {
  for indexed in pattern_buckets.patterns_for_expr(scoped_expr.expr) {
    if ast_pattern_blocked_by_shadowed_outer_id(
        indexed.pattern,
        outer_bindings,
        inherited_identifier_metavars,
        scoped_expr.shadowed_names,
      ) {
      continue
    }
    if match_ast_rule_pattern(
        indexed.pattern,
        scoped_expr.expr,
        Some(AstBindings(outer_bindings)),
      )
      is Some(_) {
      hits.push({
        file,
        rule_id: rule.rule_id,
        description: rule.description,
        pattern_index: indexed.pattern_index,
        loc: scoped_expr.expr.loc(),
        outer_loc,
      })
      return
    }
  }
}

///|
fn apply_ast_patterns_at_scoped_expr(
  file : String,
  rule : CompiledRule,
  patterns : Array[CompiledRulePattern],
  scoped_expr : ScopedExpr,
  outer_loc : @basic.Location?,
  outer_bindings : @hashmap.HashMap[String, @matching.BoundValue],
  inherited_identifier_metavars : Array[String],
  hits : Array[RuleFinding],
) -> Unit {
  for index in 0..<patterns.length() {
    if ast_pattern_blocked_by_shadowed_outer_id(
        patterns[index],
        outer_bindings,
        inherited_identifier_metavars,
        scoped_expr.shadowed_names,
      ) {
      continue
    }
    if match_ast_rule_pattern(
        patterns[index],
        scoped_expr.expr,
        Some(AstBindings(outer_bindings)),
      )
      is Some(_) {
      hits.push({
        file,
        rule_id: rule.rule_id,
        description: rule.description,
        pattern_index: index,
        loc: scoped_expr.expr.loc(),
        outer_loc,
      })
      return
    }
  }
}

///|
fn apply_ast_patterns_at_expr(
  file : String,
  rule : CompiledRule,
  pattern_buckets : ExprPatternBuckets,
  expr : @syntax.Expr,
  outer_loc : @basic.Location?,
  initial_bindings : RulePatternBindings?,
  hits : Array[RuleFinding],
) -> Unit {
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
      return
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
fn apply_json_patterns_at_scoped_expr_json(
  file : String,
  rule : CompiledRule,
  patterns : Array[CompiledRulePattern],
  scoped_expr : @json_matching.ScopedJsonExpr,
  outer_loc : @basic.Location?,
  outer_bindings : @hashmap.HashMap[String, @json_matching.JsonBoundValue],
  inherited_identifier_metavars : Array[String],
  hits : Array[RuleFinding],
) -> Unit {
  for index in 0..<patterns.length() {
    if json_pattern_blocked_by_shadowed_outer_id(
        patterns[index],
        outer_bindings,
        inherited_identifier_metavars,
        scoped_expr.shadowed_names,
      ) {
      continue
    }
    if match_json_rule_pattern_json(
        patterns[index],
        scoped_expr.expr,
        Some(JsonBindings(outer_bindings)),
      )
      is Some(_) {
      if json_expr_location(scoped_expr.expr) is Some(loc) {
        hits.push({
          file,
          rule_id: rule.rule_id,
          description: rule.description,
          pattern_index: index,
          loc,
          outer_loc,
        })
      }
      return
    }
  }
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
      if outer_bindings.get(metavar)
        is Some(@matching.BoundValue::Identifier(bound_name)) {
        if names_contain(shadowed_names, bound_name) {
          return true
        }
      }
    }
  }
  false
}

///|
fn json_pattern_blocked_by_shadowed_outer_id(
  pattern : CompiledRulePattern,
  outer_bindings : @hashmap.HashMap[String, @json_matching.JsonBoundValue],
  inherited_identifier_metavars : Array[String],
  shadowed_names : Array[String],
) -> Bool {
  for metavar in inherited_identifier_metavars {
    if names_contain(pattern.compiled.identifier_metavars, metavar) {
      if outer_bindings.get(metavar)
        is Some(@json_matching.JsonBoundValue::Identifier(bound_name)) {
        if names_contain(shadowed_names, bound_name) {
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
  match_json_rule_pattern_json(
    pattern,
    expr_json_with_locations(expr),
    initial_bindings,
  )
}

///|
fn match_json_rule_pattern_json(
  pattern : CompiledRulePattern,
  expr : Json,
  initial_bindings : RulePatternBindings?,
) -> RulePatternMatch? {
  let matched = match initial_bindings {
    Some(JsonBindings(bindings)) =>
      @json_matching.match_expr_pattern_with_bindings(
        pattern.json_compiled,
        expr,
        bindings,
      )
    Some(AstBindings(_)) => None
    None => @json_matching.match_expr_pattern(pattern.json_compiled, expr)
  }
  match matched {
    Some(result) if json_guards_match(pattern.guards, result.bindings) =>
      Some(JsonRuleMatch(result))
    _ => None
  }
}

///|
fn expr_json_with_locations(expr : @syntax.Expr) -> Json {
  let previous = @basic.show_loc.val
  @basic.show_loc.val = @basic.LocStyle::Json
  let result = expr.to_json()
  @basic.show_loc.val = previous
  result
}

///|
fn json_expr_location(expr : Json) -> @basic.Location? {
  match json_object_field(expr, "loc") {
    Some(loc) => json_location(loc)
    None => None
  }
}

///|
fn json_location(value : Json) -> @basic.Location? {
  match value {
    Json::Object(fields) =>
      match (fields.get("start"), fields.get("end")) {
        (Some(start), Some(end)) =>
          if json_position(start) is Some(start) {
            if json_position(end) is Some(end) {
              Some({ start, end })
            } else {
              json_line_column_location(fields)
            }
          } else {
            json_line_column_location(fields)
          }
        _ => json_line_column_location(fields)
      }
    _ => None
  }
}

///|
fn json_line_column_location(fields : Map[String, Json]) -> @basic.Location? {
  match (fields.get("file"), fields.get("start"), fields.get("end")) {
    (Some(Json::String(fname)), Some(start), Some(end)) =>
      if json_line_column_position(fname, start) is Some(start) {
        if json_line_column_position(fname, end) is Some(end) {
          Some({ start, end })
        } else {
          None
        }
      } else {
        None
      }
    _ => None
  }
}

///|
fn json_position(value : Json) -> @basic.Position? {
  match value {
    Json::Object(fields) =>
      match
        (
          json_string_field(fields, "fname"),
          json_int_field(fields, "lnum"),
          json_int_field(fields, "bol"),
          json_int_field(fields, "cnum"),
        ) {
        (Some(fname), Some(lnum), Some(bol), Some(cnum)) =>
          Some({ fname, lnum, bol, cnum })
        _ => None
      }
    _ => None
  }
}

///|
fn json_line_column_position(fname : String, value : Json) -> @basic.Position? {
  match value {
    Json::Object(fields) =>
      match (json_int_field(fields, "line"), json_int_field(fields, "column")) {
        (Some(lnum), Some(column)) =>
          Some({ fname, lnum, bol: 0, cnum: column - 1 })
        _ => None
      }
    _ => None
  }
}

///|
fn json_string_field(fields : Map[String, Json], name : String) -> String? {
  match fields.get(name) {
    Some(Json::String(value)) => Some(value)
    _ => None
  }
}

///|
fn json_int_field(fields : Map[String, Json], name : String) -> Int? {
  match fields.get(name) {
    Some(value) =>
      try {
        let decoded : Int = @json.from_json(value)
        Some(decoded)
      } catch {
        _ => None
      }
    None => None
  }
}

///|
fn json_object_field(value : Json, name : String) -> Json? {
  match value {
    Json::Object(fields) => fields.get(name)
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
            if @json_matching.json_constant_guard_value(value) is Some(text) {
              if guard_entry.regex.execute(text) is None {
                return false
              }
            } else {
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
