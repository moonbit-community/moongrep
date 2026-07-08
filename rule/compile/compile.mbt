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
using @traverse {count_supported_name_in_node}

///|
/// Validates and compiles raw YAML rule specs into executable rules.
///
/// This step parses each `shape`, discovers metavars, rejects reserved
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
  if spec.inside_expr is Some(_) && spec.inside_toplevel is Some(_) {
    raise RuleLoadError::InvalidRule(
      path~,
      info="inside-expr and inside-toplevel are mutually exclusive",
    )
  }
  let outer_pattern_names : Array[String] = []
  let inside_expr = if spec.inside_expr is Some(pattern) {
    Some(
      compile_inside_context_pattern(
        path, pattern, "inside-expr", false, outer_pattern_names,
      ),
    )
  } else {
    None
  }
  let inside_toplevel = if spec.inside_toplevel is Some(pattern) {
    Some(
      compile_inside_context_pattern(
        path, pattern, "inside-toplevel", true, outer_pattern_names,
      ),
    )
  } else {
    None
  }
  // Metavars from the outer context remain visible while matching each target
  // expression. Inner patterns reuse them by repeating the same inline kind.
  let outer_context = if inside_toplevel is Some(_) {
    "inside-toplevel"
  } else {
    "inside-expr"
  }
  let outer_pattern = if inside_toplevel is Some(pattern) {
    Some(pattern)
  } else {
    inside_expr
  }
  let outer_expr = if outer_pattern is Some(pattern) {
    pattern.compiled.expr_metavars
  } else {
    []
  }
  let outer_identifier = if outer_pattern is Some(pattern) {
    pattern.compiled.identifier_metavars
  } else {
    []
  }
  let outer_constant = if outer_pattern is Some(pattern) {
    pattern.compiled.constant_metavars
  } else {
    []
  }
  let outer_arg = if outer_pattern is Some(pattern) {
    pattern.compiled.arg_metavars
  } else {
    []
  }
  let patterns : Array[CompiledRulePattern] = []
  for index in 0..<spec.patterns.length() {
    let context = "patterns[\{index}]"
    let pattern = spec.patterns[index]
    let compiled_shape = compile_metavar_shape(path, context, pattern.shape)
    ensure_inherited_inside_context_metavar_forms(
      path,
      context,
      outer_context,
      compiled_shape.expr_metavars,
      compiled_shape.identifier_metavars,
      compiled_shape.constant_metavars,
      compiled_shape.arg_metavars,
      compiled_shape.pattern_metavars,
      outer_expr,
      outer_identifier,
      outer_constant,
      outer_arg,
      outer_pattern_names,
    )
    let ast = compiled_shape.ast
    if count_supported_name_in_node(ast, "__TARGET__") != 0 {
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
        compiled_shape.expr_metavars,
        compiled_shape.identifier_metavars,
        compiled_shape.constant_metavars,
        compiled_shape.arg_metavars,
        compiled_shape.pattern_metavars,
        target_metavar=None,
        source_metavar=None,
      ),
    )
  }
  let patterns_not : Array[CompiledRulePattern] = []
  for index in 0..<spec.patterns_not.length() {
    let context = "patterns-not[\{index}]"
    let pattern = spec.patterns_not[index]
    let compiled_shape = compile_metavar_shape(path, context, pattern.shape)
    ensure_inherited_inside_context_metavar_forms(
      path,
      context,
      outer_context,
      compiled_shape.expr_metavars,
      compiled_shape.identifier_metavars,
      compiled_shape.constant_metavars,
      compiled_shape.arg_metavars,
      compiled_shape.pattern_metavars,
      outer_expr,
      outer_identifier,
      outer_constant,
      outer_arg,
      outer_pattern_names,
    )
    let ast = compiled_shape.ast
    if count_supported_name_in_node(ast, "__TARGET__") != 0 {
      raise RuleLoadError::InvalidRule(
        path~,
        info="\{context}.shape must not contain __TARGET__",
      )
    }
    patterns_not.push(
      compile_pattern_with_effective_metavars(
        pattern,
        path,
        context,
        ast,
        compiled_shape.expr_metavars,
        compiled_shape.identifier_metavars,
        compiled_shape.constant_metavars,
        compiled_shape.arg_metavars,
        compiled_shape.pattern_metavars,
        target_metavar=None,
        source_metavar=None,
      ),
    )
  }
  {
    inside_expr,
    inside_toplevel,
    patterns,
    patterns_not,
    patterns_not_mode: spec.patterns_not_mode,
  }
}

///|
fn compile_inside_context_pattern(
  path : String,
  pattern : RulePatternSpec,
  context : String,
  is_toplevel : Bool,
  outer_pattern_names : Array[String],
) -> CompiledRulePattern raise {
  let compiled_shape = if is_toplevel {
    compile_toplevel_metavar_shape(path, context, pattern.shape)
  } else {
    compile_metavar_shape(path, context, pattern.shape)
  }
  let ast = compiled_shape.ast
  let target_count = count_supported_name_in_node(ast, "__TARGET__")
  if target_count != 1 {
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{context} must contain exactly one __TARGET__ placeholder in a supported expression position",
    )
  }
  for name in compiled_shape.pattern_metavars {
    outer_pattern_names.push(name)
  }
  compile_pattern(
    pattern,
    compiled_shape,
    path,
    context,
    target_metavar=Some("__TARGET__"),
    source_metavar=None,
  )
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
    let compiled_shape = compile_metavar_shape(path, context, pattern.shape)
    let ast = compiled_shape.ast
    ensure_taint_call_shape(path, context, ast)
    if count_supported_name_in_node(ast, "__SOURCE__") != 0 {
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
    let compiled_shape = compile_metavar_shape(path, context, pattern.shape)
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
    let compiled_shape = compile_metavar_shape(path, context, pattern.shape)
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
  compiled_shape : MetavarShape,
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
    compiled_shape.arg_metavars,
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
  ast : @untyped_ast.Node,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
  constant_metavars : Array[String],
  arg_metavars : Array[String],
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
    arg_metavars,
    pattern_metavars,
  )
  let compiled : @matching.CompiledExprPattern = {
    ast,
    expr_metavars,
    identifier_metavars,
    constant_metavars,
    arg_metavars,
    target_metavar,
    source_metavar,
  }
  { source: pattern, compiled, guards }
}

///|
#moongrep.skip
fn compile_guards(
  raw_guards : Map[String, String],
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
  constant_metavars : Array[String],
  arg_metavars : Array[String],
  pattern_metavars : Array[String],
) -> Array[CompiledRuleGuard] raise {
  let guards : Array[CompiledRuleGuard] = []
  for raw_name, regex_source in raw_guards {
    let name = guard_metavar_name(path, raw_name)
    let capture_kind = guard_capture_kind(
      path, context, raw_name, name, expr_metavars, identifier_metavars, constant_metavars,
      arg_metavars, pattern_metavars,
    )
    let regex = Regex::Regex(regex_source) catch {
      _ =>
        raise RuleLoadError::InvalidRule(
          path~,
          info="\{context}.guard.\{raw_name} has invalid regex",
        )
    }
    guards.push({ name, capture_kind, regex_source, regex })
  }
  guards
}

///|
fn guard_metavar_name(path : String, raw_name : String) -> String raise {
  if !raw_name.has_prefix("$") || raw_name.length() <= 1 {
    raise RuleLoadError::InvalidRule(
      path~,
      info="guard key \{raw_name} must be a $-prefixed metavar name",
    )
  }
  raw_name[1:].to_owned()
}

///|
fn guard_capture_kind(
  path : String,
  context : String,
  raw_name : String,
  name : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
  constant_metavars : Array[String],
  arg_metavars : Array[String],
  pattern_metavars : Array[String],
) -> RuleGuardCaptureKind raise {
  if array_contains(identifier_metavars, name) {
    IdentifierGuard
  } else if array_contains(constant_metavars, name) {
    ConstantGuard
  } else if array_contains(expr_metavars, name) {
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{context}.guard.\{raw_name} cannot reference exp metavar \{name}",
    )
  } else if array_contains(arg_metavars, name) {
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{context}.guard.\{raw_name} cannot reference arg metavar \{name}",
    )
  } else if array_contains(pattern_metavars, name) {
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{context}.guard.\{raw_name} cannot reference pat metavar \{name}",
    )
  } else {
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{context}.guard.\{raw_name} references unknown metavar",
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
fn ensure_inherited_inside_context_metavar_forms(
  path : String,
  context : String,
  outer_context : String,
  inner_expr : Array[String],
  inner_identifier : Array[String],
  inner_constant : Array[String],
  inner_arg : Array[String],
  inner_pattern : Array[String],
  outer_expr : Array[String],
  outer_identifier : Array[String],
  outer_constant : Array[String],
  outer_arg : Array[String],
  outer_pattern : Array[String],
) -> Unit raise {
  ensure_not_inherited_as_other_kind(
    path, context, outer_context, inner_expr, "exp", outer_identifier, "id",
  )
  ensure_not_inherited_as_other_kind(
    path, context, outer_context, inner_expr, "exp", outer_constant, "const",
  )
  ensure_not_inherited_as_other_kind(
    path, context, outer_context, inner_expr, "exp", outer_pattern, "pat",
  )
  ensure_not_inherited_as_other_kind(
    path, context, outer_context, inner_expr, "exp", outer_arg, "arg",
  )
  ensure_not_inherited_as_other_kind(
    path, context, outer_context, inner_identifier, "id", outer_expr, "exp",
  )
  ensure_not_inherited_as_other_kind(
    path, context, outer_context, inner_identifier, "id", outer_constant, "const",
  )
  ensure_not_inherited_as_other_kind(
    path, context, outer_context, inner_identifier, "id", outer_pattern, "pat",
  )
  ensure_not_inherited_as_other_kind(
    path, context, outer_context, inner_identifier, "id", outer_arg, "arg",
  )
  ensure_not_inherited_as_other_kind(
    path, context, outer_context, inner_constant, "const", outer_expr, "exp",
  )
  ensure_not_inherited_as_other_kind(
    path, context, outer_context, inner_constant, "const", outer_identifier, "id",
  )
  ensure_not_inherited_as_other_kind(
    path, context, outer_context, inner_constant, "const", outer_pattern, "pat",
  )
  ensure_not_inherited_as_other_kind(
    path, context, outer_context, inner_constant, "const", outer_arg, "arg",
  )
  ensure_not_inherited_as_other_kind(
    path, context, outer_context, inner_arg, "arg", outer_expr, "exp",
  )
  ensure_not_inherited_as_other_kind(
    path, context, outer_context, inner_arg, "arg", outer_identifier, "id",
  )
  ensure_not_inherited_as_other_kind(
    path, context, outer_context, inner_arg, "arg", outer_constant, "const",
  )
  ensure_not_inherited_as_other_kind(
    path, context, outer_context, inner_arg, "arg", outer_pattern, "pat",
  )
  ensure_not_inherited_as_other_kind(
    path, context, outer_context, inner_pattern, "pat", outer_expr, "exp",
  )
  ensure_not_inherited_as_other_kind(
    path, context, outer_context, inner_pattern, "pat", outer_identifier, "id",
  )
  ensure_not_inherited_as_other_kind(
    path, context, outer_context, inner_pattern, "pat", outer_constant, "const",
  )
  ensure_not_inherited_as_other_kind(
    path, context, outer_context, inner_pattern, "pat", outer_arg, "arg",
  )
}

///|
fn ensure_not_inherited_as_other_kind(
  path : String,
  context : String,
  outer_context : String,
  names : Array[String],
  kind : String,
  outer : Array[String],
  outer_kind : String,
) -> Unit raise {
  for name in names {
    if array_contains(outer, name) {
      raise RuleLoadError::InvalidRule(
        path~,
        info="\{context} cannot use inherited \{outer_context} metavar \{name} as \{kind} because it was declared as \{outer_kind}",
      )
    }
  }
}

///|
fn ensure_taint_call_shape(
  path : String,
  context : String,
  ast : @untyped_ast.Node,
) -> Unit raise {
  match ast.kind {
    Expr_Apply | Expr_DotApply => ()
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
  ast : @untyped_ast.Node,
) -> TaintTarget raise {
  let count = count_supported_name_in_node(ast, "__SOURCE__")
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
fn whole_source_target(ast : @untyped_ast.Node) -> TaintTarget? {
  match ast.kind {
    Expr_DotApply =>
      if node_child(ast, "self") is Some(self) &&
        is_source_placeholder_node(self) {
        Some(Receiver)
      } else {
        match node_child(ast, "args") {
          Some(args) => source_target_from_args(args)
          None => None
        }
      }
    Expr_Apply =>
      match node_child(ast, "args") {
        Some(args) => source_target_from_args(args)
        None => None
      }
    _ => None
  }
}

///|
fn source_target_from_args(args : @untyped_ast.Node) -> TaintTarget? {
  for index in 0..<args.children.length() {
    let (_, argument) = args.children[index]
    if node_child(argument, "value") is Some(value) &&
      is_source_placeholder_node(value) {
      guard node_child(argument, "kind") is Some(kind) else { return None }
      return match kind.kind {
        ArgumentKind_Positional => Some(PositionalArg(index))
        ArgumentKind_Labelled
        | ArgumentKind_LabelledPun
        | ArgumentKind_LabelledOption
        | ArgumentKind_LabelledOptionPun =>
          if argument_kind_label_name(kind) is Some(label) {
            Some(LabelledArg(label~, index~))
          } else {
            None
          }
        _ => None
      }
    }
  }
  None
}

///|
fn argument_kind_label_name(kind : @untyped_ast.Node) -> String? {
  match kind.kind {
    ArgumentKind_Labelled | ArgumentKind_LabelledPun =>
      if node_child(kind, "value") is Some(label) {
        label.normalized_label_name()
      } else {
        None
      }
    ArgumentKind_LabelledOption | ArgumentKind_LabelledOptionPun =>
      if node_child(kind, "label") is Some(label) {
        label.normalized_label_name()
      } else {
        None
      }
    _ => None
  }
}

///|
fn is_source_placeholder_node(node : @untyped_ast.Node) -> Bool {
  if node.kind == Expr_Ident {
    node.normalized_expr_identifier_name() == Some("__SOURCE__")
  } else {
    false
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
fn array_contains(items : Array[String], needle : String) -> Bool {
  for item in items {
    if item == needle {
      return true
    }
  }
  false
}
