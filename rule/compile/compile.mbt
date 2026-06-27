///|
using @model {
  type CompiledRule,
  type CompiledRuleDefinition,
  type CompiledRuleGuard,
  type CompiledRulePattern,
  type CompiledStructuralRule,
  type CompiledTaintRule,
  type CompiledTaintSanitizer,
  type CompiledTaintSink,
  type CompiledTaintSource,
  type RawRuleSpec,
  type RuleLoadError,
  type RuleGuardCaptureKind,
  type RulePatternSpec,
  type StructuralRuleSpec,
  type TaintRuleSpec,
  type TaintTarget,
}

///|
using @prefilter {compile_rule_prefilter}

///|
using @traverse {count_supported_name_in_expr}

///|
/// Validates and compiles raw YAML rule specs into executable rules.
///
/// This step parses each `shape`, discovers inline metavars, rejects reserved
/// names, and records taint `__SOURCE__` targets. It raises `RuleLoadError`
/// when a rule cannot be represented by the runtime AST matcher.
pub fn compile_rules(
  raw_rules : Array[RawRuleSpec],
) -> Array[CompiledRule] raise {
  ensure_unique_rule_ids(raw_rules)
  let compiled : Array[CompiledRule] = []
  for raw in raw_rules {
    compiled.push(compile_rule(raw))
  }
  compiled
}

///|
fn compile_rule(raw : RawRuleSpec) -> CompiledRule raise {
  let definition = match raw.definition {
    Structural(spec) =>
      CompiledRuleDefinition::Structural(
        compile_structural_rule(raw.path, spec),
      )
    Taint(spec) => Taint(compile_taint_rule(raw.path, spec))
  }
  {
    rule_id: raw.rule_id,
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
  let outer_pattern_names : Array[String] = []
  let inside_expr = match spec.inside_expr {
    None => None
    Some(pattern) => {
      let compiled_shape = compile_inline_metavar_shape(
        path,
        "inside-expr",
        pattern.shape,
      )
      let ast = compiled_shape.ast
      let target_count = count_supported_name_in_expr(ast, "__TARGET__")
      if target_count != 1 {
        raise RuleLoadError::InvalidRule(
          path~,
          info="inside-expr.shape must contain exactly one __TARGET__ placeholder in a supported expression position",
        )
      }
      for name in compiled_shape.pattern_metavars {
        outer_pattern_names.push(name)
      }
      Some(
        compile_pattern(
          pattern,
          compiled_shape,
          path,
          "inside-expr",
          target_metavar=Some("__TARGET__"),
          source_metavar=None,
        ),
      )
    }
  }
  // Metavars from `inside-expr` remain visible while matching each target
  // expression. Inner patterns cannot redeclare them because that would make
  // binding consistency ambiguous.
  let outer_expr = if inside_expr is Some(pattern) {
    pattern.compiled.expr_metavars
  } else {
    []
  }
  let outer_identifier = if inside_expr is Some(pattern) {
    pattern.compiled.identifier_metavars
  } else {
    []
  }
  let outer_constant = if inside_expr is Some(pattern) {
    pattern.compiled.constant_metavars
  } else {
    []
  }
  let outer_metavars = concat_arrays(
    concat_arrays(concat_arrays(outer_expr, outer_identifier), outer_constant),
    outer_pattern_names,
  )
  let patterns : Array[CompiledRulePattern] = []
  for index in 0..<spec.patterns.length() {
    let context = "patterns[\{index}]"
    let pattern = spec.patterns[index]
    let compiled_shape = compile_inline_metavar_shape(
      path,
      context,
      pattern.shape,
    )
    ensure_not_redeclared_from_inside_expr(
      path,
      context,
      compiled_shape.expr_metavars,
      outer_metavars,
    )
    ensure_not_redeclared_from_inside_expr(
      path,
      context,
      compiled_shape.identifier_metavars,
      outer_metavars,
    )
    ensure_not_redeclared_from_inside_expr(
      path,
      context,
      compiled_shape.constant_metavars,
      outer_metavars,
    )
    ensure_not_redeclared_from_inside_expr(
      path,
      context,
      compiled_shape.pattern_metavars,
      outer_metavars,
    )
    let ast = compiled_shape.ast
    if count_supported_name_in_expr(ast, "__TARGET__") != 0 {
      raise RuleLoadError::InvalidRule(
        path~,
        info="\{context}.shape must not contain __TARGET__",
      )
    }
    patterns.push(
      compile_pattern_with_effective_metavars(
        pattern,
        path,
        context,
        ast,
        concat_arrays(outer_expr, compiled_shape.expr_metavars),
        concat_arrays(outer_identifier, compiled_shape.identifier_metavars),
        concat_arrays(outer_constant, compiled_shape.constant_metavars),
        concat_arrays(outer_pattern_names, compiled_shape.pattern_metavars),
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
    let compiled_shape = compile_inline_metavar_shape(
      path,
      context,
      pattern.shape,
    )
    let ast = compiled_shape.ast
    ensure_taint_call_shape(path, context, ast)
    if count_supported_name_in_expr(ast, "__SOURCE__") != 0 {
      raise RuleLoadError::InvalidRule(
        path~,
        info="\{context} must not contain __SOURCE__",
      )
    }
    sources.push({
      pattern: compile_pattern(
        pattern,
        compiled_shape,
        path,
        context,
        target_metavar=None,
        source_metavar=None,
      ),
    })
  }
  let sinks : Array[CompiledTaintSink] = []
  for index in 0..<spec.sinks.length() {
    let context = "taint.sinks[\{index}]"
    let pattern = spec.sinks[index]
    let compiled_shape = compile_inline_metavar_shape(
      path,
      context,
      pattern.shape,
    )
    let ast = compiled_shape.ast
    ensure_taint_call_shape(path, context, ast)
    // `__SOURCE__` must be captured as a whole argument or receiver so the
    // lowering layer can read or kill a concrete taint path.
    let target = require_source_target(path, context, ast)
    sinks.push({
      pattern: compile_pattern(
        pattern,
        compiled_shape,
        path,
        context,
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
    let compiled_shape = compile_inline_metavar_shape(
      path,
      context,
      pattern.shape,
    )
    let ast = compiled_shape.ast
    ensure_taint_call_shape(path, context, ast)
    // Sanitizers share the same target restrictions as sinks because both
    // operate on one concrete call value.
    let target = require_source_target(path, context, ast)
    sanitizers.push({
      pattern: compile_pattern(
        pattern,
        compiled_shape,
        path,
        context,
        target_metavar=None,
        source_metavar=Some("__SOURCE__"),
      ),
      target,
    })
  }
  { sources, sinks, sanitizers }
}

///|
fn compile_pattern(
  pattern : RulePatternSpec,
  compiled_shape : InlineMetavarShape,
  path : String,
  context : String,
  target_metavar~ : String?,
  source_metavar~ : String?,
) -> CompiledRulePattern raise {
  compile_pattern_with_effective_metavars(
    pattern,
    path,
    context,
    compiled_shape.ast,
    compiled_shape.expr_metavars,
    compiled_shape.identifier_metavars,
    compiled_shape.constant_metavars,
    compiled_shape.pattern_metavars,
    target_metavar~,
    source_metavar~,
  )
}

///|
fn compile_pattern_with_effective_metavars(
  pattern : RulePatternSpec,
  path : String,
  context : String,
  ast : @syntax.Expr,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
  constant_metavars : Array[String],
  pattern_metavars : Array[String],
  target_metavar~ : String?,
  source_metavar~ : String?,
) -> CompiledRulePattern raise {
  let guards = compile_guards(
    pattern.guards,
    path,
    context,
    expr_metavars,
    identifier_metavars,
    constant_metavars,
    pattern_metavars,
  )
  {
    source: pattern,
    compiled: {
      ast,
      expr_metavars,
      identifier_metavars,
      constant_metavars,
      target_metavar,
      source_metavar,
    },
    guards,
  }
}

///|
fn compile_guards(
  raw_guards : Map[String, String],
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
  constant_metavars : Array[String],
  pattern_metavars : Array[String],
) -> Array[CompiledRuleGuard] raise {
  let guards : Array[CompiledRuleGuard] = []
  for name, regex_source in raw_guards {
    let capture_kind = guard_capture_kind(
      path, context, name, expr_metavars, identifier_metavars, constant_metavars,
      pattern_metavars,
    )
    let regex = Regex::Regex(regex_source) catch {
      _ =>
        raise RuleLoadError::InvalidRule(
          path~,
          info="\{context}.guard.\{name} has invalid regex",
        )
    }
    guards.push({ name, capture_kind, regex_source, regex })
  }
  guards
}

///|
fn guard_capture_kind(
  path : String,
  context : String,
  name : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
  constant_metavars : Array[String],
  pattern_metavars : Array[String],
) -> RuleGuardCaptureKind raise {
  if array_contains(identifier_metavars, name) {
    IdentifierGuard
  } else if array_contains(constant_metavars, name) {
    ConstantGuard
  } else if array_contains(expr_metavars, name) {
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{context}.guard.\{name} cannot reference exp metavar \{name}",
    )
  } else if array_contains(pattern_metavars, name) {
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{context}.guard.\{name} cannot reference pat metavar \{name}",
    )
  } else {
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{context}.guard.\{name} references unknown metavar",
    )
  }
}

///|
fn ensure_unique_rule_ids(raw_rules : Array[RawRuleSpec]) -> Unit raise {
  let seen : Map[String, String] = {}
  for raw in raw_rules {
    if seen.contains(raw.rule_id) {
      raise RuleLoadError::InvalidRule(
        path=raw.path,
        info="rule id \{raw.rule_id} conflicts with another rule",
      )
    }
    seen[raw.rule_id] = raw.rule_id
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
  if whole_source_target(ast) is Some(target) {
    target
  } else {
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
      @id.normalize_identifier_name_from_var(id) == Some("__SOURCE__")
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
fn array_contains(items : Array[String], needle : String) -> Bool {
  for item in items {
    if item == needle {
      return true
    }
  }
  false
}
