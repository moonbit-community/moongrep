///|
/// Validates and compiles raw YAML rule specs into executable rules.
///
/// This step parses each `shape`, checks declared metavars, rejects reserved
/// names, and records taint `__SOURCE__` targets. It raises `RuleLoadError`
/// when a rule cannot be represented by the runtime AST matcher.
pub fn compile_rules(
  raw_rules : Array[RawRuleSpec],
) -> Array[CompiledRule] raise {
  ensure_unique_matcher_names(raw_rules)
  let compiled : Array[CompiledRule] = []
  for raw in raw_rules {
    compiled.push(compile_rule(raw))
  }
  compiled
}

///|
fn compile_rule(raw : RawRuleSpec) -> CompiledRule raise {
  let definition = match raw.definition {
    RuleDefinitionSpec::Structural(spec) =>
      CompiledRuleDefinition::Structural(
        compile_structural_rule(raw.path, spec),
      )
    RuleDefinitionSpec::Taint(spec) =>
      CompiledRuleDefinition::Taint(compile_taint_rule(raw.path, spec))
  }
  {
    rule_id: raw.rule_id,
    package_name: raw.package_name,
    description: raw.description,
    definition,
    prefilter: compile_rule_prefilter(definition),
  }
}

///|
fn compile_structural_rule(
  path : String,
  spec : StructuralRuleSpec,
) -> CompiledStructuralRule raise {
  let inside_expr = match spec.inside_expr {
    None => None
    Some(pattern) => {
      validate_declared_metavars(path, "inside-expr", pattern, false)
      let ast = parse_shape(path, "inside-expr", pattern.shape)
      let metas = effective_metavars(path, "inside-expr", pattern, ast, false)
      let target_count = count_supported_name_in_expr(ast, "__TARGET__")
      if target_count != 1 {
        raise RuleLoadError::InvalidRule(
          path~,
          info="inside-expr.shape must contain exactly one __TARGET__ placeholder in a supported expression position",
        )
      }
      validate_used_metavars(path, "inside-expr", pattern, ast)
      Some(
        compile_pattern_with_effective_metavars(
          pattern,
          ast,
          metas.subtree,
          metas.identifier,
          metas.auto,
          target_metavar=Some("__TARGET__"),
          source_metavar=None,
        ),
      )
    }
  }
  // Metavars from `inside-expr` remain visible while matching each target
  // expression. Inner patterns cannot redeclare them because that would make
  // binding consistency ambiguous.
  let outer_subtree = match spec.inside_expr {
    Some(_) =>
      match inside_expr {
        Some(pattern) => pattern.compiled.subtree_metavars
        None => []
      }
    None => []
  }
  let outer_identifier = match spec.inside_expr {
    Some(_) =>
      match inside_expr {
        Some(pattern) => pattern.compiled.identifier_metavars
        None => []
      }
    None => []
  }
  let outer_auto = match spec.inside_expr {
    Some(_) =>
      match inside_expr {
        Some(pattern) => pattern.compiled.auto_metavars
        None => []
      }
    None => []
  }
  let patterns : Array[CompiledRulePattern] = []
  for index in 0..<spec.patterns.length() {
    let context = "patterns[\{index}]"
    let pattern = spec.patterns[index]
    validate_declared_metavars(path, context, pattern, false)
    let ast = parse_shape(path, context, pattern.shape)
    let metas = effective_metavars(path, context, pattern, ast, false)
    ensure_not_redeclared_from_inside_expr(
      path,
      context,
      metas.subtree,
      outer_subtree,
    )
    ensure_not_redeclared_from_inside_expr(
      path,
      context,
      metas.identifier,
      outer_subtree,
    )
    ensure_not_redeclared_from_inside_expr(
      path,
      context,
      metas.auto,
      outer_subtree,
    )
    ensure_not_redeclared_from_inside_expr(
      path,
      context,
      metas.subtree,
      outer_identifier,
    )
    ensure_not_redeclared_from_inside_expr(
      path,
      context,
      metas.identifier,
      outer_identifier,
    )
    ensure_not_redeclared_from_inside_expr(
      path,
      context,
      metas.auto,
      outer_identifier,
    )
    ensure_not_redeclared_from_inside_expr(
      path,
      context,
      metas.subtree,
      outer_auto,
    )
    ensure_not_redeclared_from_inside_expr(
      path,
      context,
      metas.identifier,
      outer_auto,
    )
    ensure_not_redeclared_from_inside_expr(
      path,
      context,
      metas.auto,
      outer_auto,
    )
    if count_supported_name_in_expr(ast, "__TARGET__") != 0 {
      raise RuleLoadError::InvalidRule(
        path~,
        info="\{context}.shape must not contain __TARGET__",
      )
    }
    validate_used_metavars(path, context, pattern, ast)
    patterns.push(
      compile_pattern_with_effective_metavars(
        pattern,
        ast,
        concat_arrays(outer_subtree, metas.subtree),
        concat_arrays(outer_identifier, metas.identifier),
        concat_arrays(outer_auto, metas.auto),
        target_metavar=None,
        source_metavar=None,
      ),
    )
  }
  { inside_expr, patterns }
}

///|
fn compile_taint_rule(
  path : String,
  spec : TaintRuleSpec,
) -> CompiledTaintRule raise {
  let sources : Array[CompiledTaintSource] = []
  for index in 0..<spec.sources.length() {
    let context = "taint.sources[\{index}]"
    let pattern = spec.sources[index]
    validate_declared_metavars(path, context, pattern, true)
    let ast = parse_shape(path, context, pattern.shape)
    let metas = effective_metavars(path, context, pattern, ast, true)
    ensure_taint_call_shape(path, context, ast)
    if count_supported_name_in_expr(ast, "__SOURCE__") != 0 {
      raise RuleLoadError::InvalidRule(
        path~,
        info="\{context} must not contain __SOURCE__",
      )
    }
    validate_used_metavars(path, context, pattern, ast)
    sources.push({
      pattern: compile_pattern_with_effective_metavars(
        pattern,
        ast,
        metas.subtree,
        metas.identifier,
        metas.auto,
        target_metavar=None,
        source_metavar=None,
      ),
    })
  }
  let sinks : Array[CompiledTaintSink] = []
  for index in 0..<spec.sinks.length() {
    let context = "taint.sinks[\{index}]"
    let pattern = spec.sinks[index]
    validate_declared_metavars(path, context, pattern, true)
    let ast = parse_shape(path, context, pattern.shape)
    let metas = effective_metavars(path, context, pattern, ast, true)
    ensure_taint_call_shape(path, context, ast)
    // `__SOURCE__` must be captured as a whole argument or receiver so the
    // lowering layer can read or kill a concrete taint path.
    let target = require_source_target(path, context, ast)
    validate_used_metavars(path, context, pattern, ast)
    sinks.push({
      pattern: compile_pattern_with_effective_metavars(
        pattern,
        ast,
        metas.subtree,
        metas.identifier,
        metas.auto,
        target_metavar=None,
        source_metavar=Some("__SOURCE__"),
      ),
      target,
    })
  }
  let sanitizers : Array[CompiledTaintSanitizer] = []
  for index in 0..<spec.sanitizers.length() {
    let context = "taint.sanitizers[\{index}]"
    let pattern = spec.sanitizers[index]
    validate_declared_metavars(path, context, pattern, true)
    let ast = parse_shape(path, context, pattern.shape)
    let metas = effective_metavars(path, context, pattern, ast, true)
    ensure_taint_call_shape(path, context, ast)
    // Sanitizers share the same target restrictions as sinks because both
    // operate on one concrete call value.
    let target = require_source_target(path, context, ast)
    validate_used_metavars(path, context, pattern, ast)
    sanitizers.push({
      pattern: compile_pattern_with_effective_metavars(
        pattern,
        ast,
        metas.subtree,
        metas.identifier,
        metas.auto,
        target_metavar=None,
        source_metavar=Some("__SOURCE__"),
      ),
      target,
    })
  }
  { sources, sinks, sanitizers }
}

///|
fn compile_pattern_with_effective_metavars(
  pattern : RulePatternSpec,
  ast : @syntax.Expr,
  subtree_metavars : Array[String],
  identifier_metavars : Array[String],
  auto_metavars : Array[String],
  target_metavar~ : String?,
  source_metavar~ : String?,
) -> CompiledRulePattern {
  {
    source: pattern,
    compiled: {
      ast,
      subtree_metavars,
      identifier_metavars,
      auto_metavars,
      target_metavar,
      source_metavar,
    },
  }
}

///|
priv struct EffectiveMetavars {
  subtree : Array[String]
  identifier : Array[String]
  auto : Array[String]
}

///|
priv struct InferredMetavars {
  subtree : Array[String]
  identifier : Array[String]
}

///|
fn InferredMetavars::record(self : Self, meta : @syntax.MetaVar) -> Unit {
  match meta.kind {
    Subtree => push_unique(self.subtree, meta.name)
    Identifier => push_unique(self.identifier, meta.name)
  }
}

///|
impl @syntax.IterVisitor for InferredMetavars with fn visit_Var(self, var_) {
  match var_.metavar() {
    Some(meta) => self.record(meta)
    None => ()
  }
}

///|
impl @syntax.IterVisitor for InferredMetavars with fn visit_Binder(self, binder) {
  match binder.metavar() {
    Some(meta) => self.record(meta)
    None => ()
  }
}

///|
impl @syntax.IterVisitor for InferredMetavars with fn visit_Label(self, label) {
  match label.metavar() {
    Some(meta) => self.record(meta)
    None => ()
  }
}

///|
fn infer_metavars(ast : @syntax.Expr) -> InferredMetavars {
  let collector = InferredMetavars::{ subtree: [], identifier: [] }
  collector.visit_Expr(ast)
  collector
}

///|
fn effective_metavars(
  path : String,
  context : String,
  pattern : RulePatternSpec,
  ast : @syntax.Expr,
  reserve_source : Bool,
) -> EffectiveMetavars raise {
  let inferred = infer_metavars(ast)
  validate_inferred_metavars(path, context, inferred.subtree, reserve_source)
  validate_inferred_metavars(path, context, inferred.identifier, reserve_source)
  let subtree = merge_metavar_bucket(pattern.subtree_metavars, inferred.subtree)
  let identifier = merge_metavar_bucket(
    pattern.identifier_metavars,
    inferred.identifier,
  )
  let auto = merge_metavar_bucket(pattern.auto_metavars, [])
  ensure_metavar_bucket_conflict_free(path, context, subtree, identifier)
  ensure_metavar_bucket_conflict_free(path, context, subtree, auto)
  ensure_metavar_bucket_conflict_free(path, context, identifier, auto)
  { subtree, identifier, auto }
}

///|
fn validate_inferred_metavars(
  path : String,
  context : String,
  names : Array[String],
  reserve_source : Bool,
) -> Unit raise {
  for name in names {
    validate_declared_metavar(path, context, name, reserve_source)
  }
}

///|
fn merge_metavar_bucket(
  declared : Array[String],
  inferred : Array[String],
) -> Array[String] {
  let result : Array[String] = []
  for name in declared {
    push_unique(result, name)
  }
  for name in inferred {
    push_unique(result, name)
  }
  result
}

///|
fn ensure_metavar_bucket_conflict_free(
  path : String,
  context : String,
  left : Array[String],
  right : Array[String],
) -> Unit raise {
  for name in left {
    if array_contains(right, name) {
      raise RuleLoadError::InvalidRule(
        path~,
        info="\{context} contains conflicting metavar \{name}",
      )
    }
  }
}

///|
fn ensure_unique_matcher_names(raw_rules : Array[RawRuleSpec]) -> Unit raise {
  let seen : Map[String, String] = {}
  for raw in raw_rules {
    let normalized = normalized_matcher_name(raw.rule_id)
    if seen.contains(normalized) {
      raise RuleLoadError::InvalidRule(
        path=raw.path,
        info="rule id \{raw.rule_id} conflicts with another rule after matcher name normalization",
      )
    }
    seen[normalized] = raw.rule_id
  }
}

///|
fn normalized_matcher_name(rule_id : String) -> String {
  let builder = StringBuilder()
  for char in rule_id {
    if char == '/' || char == '-' {
      builder.write_char('_')
    } else {
      builder.write_char(char)
    }
  }
  builder.to_string()
}

///|
fn validate_declared_metavars(
  path : String,
  context : String,
  pattern : RulePatternSpec,
  reserve_source : Bool,
) -> Unit raise {
  for name in pattern.subtree_metavars {
    validate_declared_metavar(path, context, name, reserve_source)
  }
  for name in pattern.identifier_metavars {
    validate_declared_metavar(path, context, name, reserve_source)
  }
  for name in pattern.auto_metavars {
    validate_declared_metavar(path, context, name, reserve_source)
  }
}

///|
fn validate_declared_metavar(
  path : String,
  context : String,
  name : String,
  reserve_source : Bool,
) -> Unit raise {
  if is_builtin_ignore_metavar_name(name) {
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{context} cannot declare metavar \{name} because it is a built-in ignore placeholder",
    )
  } else if name == "__TARGET__" {
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{context} cannot declare metavar __TARGET__ because it is reserved for inside-expr target traversal",
    )
  } else if reserve_source && name == "__SOURCE__" {
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{context} cannot declare metavar __SOURCE__ because it is reserved for taint source targets",
    )
  }
}

///|
fn validate_used_metavars(
  path : String,
  context : String,
  pattern : RulePatternSpec,
  ast : @syntax.Expr,
) -> Unit raise {
  for name in pattern.subtree_metavars {
    if count_supported_name_in_expr(ast, name) == 0 {
      raise RuleLoadError::InvalidRule(
        path~,
        info="\{context} declares unused metavar \{name}",
      )
    }
  }
  for name in pattern.identifier_metavars {
    if count_supported_name_in_expr(ast, name) == 0 {
      raise RuleLoadError::InvalidRule(
        path~,
        info="\{context} declares unused metavar \{name}",
      )
    }
  }
  for name in pattern.auto_metavars {
    if count_supported_name_in_expr(ast, name) == 0 {
      raise RuleLoadError::InvalidRule(
        path~,
        info="\{context} declares unused metavar \{name}",
      )
    }
  }
}

///|
fn ensure_not_redeclared_from_inside_expr(
  path : String,
  context : String,
  names : Array[String],
  outer : Array[String],
) -> Unit raise {
  for name in names {
    if array_contains(outer, name) {
      raise RuleLoadError::InvalidRule(
        path~,
        info="\{context} cannot declare metavar \{name} because it is already visible from inside-expr",
      )
    }
  }
}

///|
fn ensure_taint_call_shape(
  path : String,
  context : String,
  ast : @syntax.Expr,
) -> Unit raise {
  match ast {
    Apply(..) | DotApply(..) => ()
    _ =>
      raise RuleLoadError::InvalidRule(
        path~,
        info="\{context}.shape must be a call expression",
      )
  }
}

///|
fn require_source_target(
  path : String,
  context : String,
  ast : @syntax.Expr,
) -> TaintTarget raise {
  let count = count_supported_name_in_expr(ast, "__SOURCE__")
  if count != 1 {
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{context}.shape must contain exactly one __SOURCE__ placeholder",
    )
  }
  match whole_source_target(ast) {
    Some(target) => target
    None =>
      raise RuleLoadError::InvalidRule(
        path~,
        info="\{context}.shape must place __SOURCE__ as the whole receiver or argument value",
      )
  }
}

///|
fn whole_source_target(ast : @syntax.Expr) -> TaintTarget? {
  match ast {
    DotApply(self~, args~, ..) =>
      if is_source_placeholder_expr(self) {
        Some(Receiver)
      } else {
        source_target_from_args(args)
      }
    Apply(args~, ..) => source_target_from_args(args)
    _ => None
  }
}

///|
fn source_target_from_args(args : @list.List[@syntax.Argument]) -> TaintTarget? {
  let arr = args.to_array()
  for index in 0..<arr.length() {
    if is_source_placeholder_expr(arr[index].value) {
      return match arr[index].kind {
        Positional => Some(PositionalArg(index))
        Labelled(label) | LabelledPun(label) =>
          Some(LabelledArg(label=label.name, index~))
        LabelledOption(label~, ..) | LabelledOptionPun(label~, ..) =>
          Some(LabelledArg(label=label.name, index~))
      }
    }
  }
  None
}

///|
fn is_source_placeholder_expr(expr : @syntax.Expr) -> Bool {
  match expr {
    Ident(id~, ..) =>
      @ident.normalize_identifier_name_from_var(id) == Some("__SOURCE__")
    _ => false
  }
}

///|
fn is_builtin_ignore_metavar_name(name : String) -> Bool {
  if name.length() < 2 {
    return false
  }
  for char in name {
    if char != '_' {
      return false
    }
  }
  true
}

///|
fn concat_arrays(left : Array[String], right : Array[String]) -> Array[String] {
  let result : Array[String] = []
  for name in left {
    result.push(name)
  }
  for name in right {
    result.push(name)
  }
  result
}

///|
fn push_unique(items : Array[String], name : String) -> Unit {
  if !array_contains(items, name) {
    items.push(name)
  }
}
