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
  type InsideToplevelMatchMode,
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
/// Validates and compiles raw YAML rule specs into executable rules.
///
/// This step parses each `shape`, discovers metavars, rejects reserved
/// names, and records taint `__SOURCE__` targets. It raises `RuleLoadError`
/// when a rule cannot be represented by the runtime CST matcher.
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
  if !spec.inside_expr.is_empty() && !spec.inside_toplevel.is_empty() {
    raise RuleLoadError::InvalidRule(
      path~,
      info="inside-expr and inside-toplevel are mutually exclusive",
    )
  }
  let (inside_expr, inside_expr_shapes) = compile_inside_context_patterns(
    path,
    spec.inside_expr,
    "inside-expr",
    is_toplevel=false,
  )
  let (inside_toplevel, inside_toplevel_shapes) = compile_inside_context_patterns(
    path,
    spec.inside_toplevel,
    "inside-toplevel",
    is_toplevel=true,
  )
  // Metavars from the outer context remain visible while matching each target
  // expression. A metavar reused by an inner pattern must be declared with the
  // same kind by every ordered outer alternative.
  let outer_context = if !inside_toplevel.is_empty() {
    "inside-toplevel"
  } else {
    "inside-expr"
  }
  let outer_shapes = if !inside_toplevel_shapes.is_empty() {
    inside_toplevel_shapes
  } else {
    inside_expr_shapes
  }
  let patterns : Array[CompiledRulePattern] = []
  for index in 0..<spec.patterns.length() {
    let context = "patterns[\{index}]"
    let pattern = spec.patterns[index]
    let compiled_shape = compile_metavar_shape(path, context, pattern.shape)
    ensure_inherited_inside_context_metavar_forms_for_all(
      path, context, outer_context, compiled_shape, outer_shapes,
    )
    let cst = compiled_shape.cst
    if count_supported_name_in_node(cst, "__TARGET__") != 0 {
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
        cst,
        compiled_shape.expr_metavars,
        compiled_shape.identifier_metavars,
        compiled_shape.constant_metavars,
        compiled_shape.arg_metavars,
        compiled_shape.type_metavars,
        compiled_shape.pattern_metavars,
        compiled_shape.ellipsis_metavars,
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
    ensure_inherited_inside_context_metavar_forms_for_all(
      path, context, outer_context, compiled_shape, outer_shapes,
    )
    let cst = compiled_shape.cst
    if count_supported_name_in_node(cst, "__TARGET__") != 0 {
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
        cst,
        compiled_shape.expr_metavars,
        compiled_shape.identifier_metavars,
        compiled_shape.constant_metavars,
        compiled_shape.arg_metavars,
        compiled_shape.type_metavars,
        compiled_shape.pattern_metavars,
        compiled_shape.ellipsis_metavars,
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
fn compile_inside_context_patterns(
  path : String,
  patterns : Array[RulePatternSpec],
  context : String,
  is_toplevel~ : Bool,
) -> (Array[CompiledRulePattern], Array[MetavarShape]) raise {
  let compiled_patterns : Array[CompiledRulePattern] = []
  let compiled_shapes : Array[MetavarShape] = []
  for index in 0..<patterns.length() {
    let pattern = patterns[index]
    let item_context = "\{context}[\{index}]"
    let compiled_shape = if is_toplevel {
      compile_toplevel_metavar_shape(path, item_context, pattern.shape)
    } else {
      compile_metavar_shape(path, item_context, pattern.shape)
    }
    let cst = compiled_shape.cst
    let ignored_fields = if is_toplevel {
      inside_toplevel_ignored_fields(
        path,
        item_context,
        pattern.match_mode,
        cst,
      )
    } else {
      []
    }
    let target_count = count_supported_name_in_node(cst, "__TARGET__")
    if target_count != 1 {
      raise RuleLoadError::InvalidRule(
        path~,
        info="\{shape_context_name(item_context)} must contain exactly one __TARGET__ placeholder in a supported expression position",
      )
    }
    compiled_patterns.push(
      compile_pattern(
        pattern,
        compiled_shape,
        path,
        item_context,
        target_metavar=Some("__TARGET__"),
        source_metavar=None,
        ignored_fields~,
      ),
    )
    compiled_shapes.push(compiled_shape)
  }
  (compiled_patterns, compiled_shapes)
}

///|
fn inside_toplevel_ignored_fields(
  path : String,
  context : String,
  match_mode : InsideToplevelMatchMode,
  cst : @untyped_cst.CstNode,
) -> Array[@matching.IgnoredPatternField] raise {
  let is_partial = match match_mode {
    Default => cst.kind is @untyped_cst.Impl_Function
    Exact => false
    Partial =>
      if cst.kind is @untyped_cst.Impl_Function {
        true
      } else {
        raise RuleLoadError::InvalidRule(
          path~,
          info="\{context}.match-mode partial is only supported for function definition shapes",
        )
      }
  }
  if !is_partial {
    return []
  }
  partial_top_func_ignored_fields(cst)
}

///|
fn partial_top_func_ignored_fields(
  cst : @untyped_cst.CstNode,
) -> Array[@matching.IgnoredPatternField] {
  let ignored : Array[@matching.IgnoredPatternField] = []
  let kind = cst.kind
  add_ignored_field_if_absent(ignored, cst, kind, "semantic_type_name")
  add_ignored_field_if_default_bool(ignored, cst, kind, "async")
  add_ignored_field_if_absent(ignored, cst, kind, "params")
  add_ignored_field_if_absent(ignored, cst, kind, "quantifier")
  add_ignored_field_if_absent(ignored, cst, kind, "clause")
  add_ignored_visibility_if_default(ignored, cst, kind)
  add_ignored_field_if_absent(ignored, cst, kind, "attrs")
  add_ignored_field_if_absent(ignored, cst, kind, "where")
  ignored
}

///|
fn add_ignored_field_if_absent(
  ignored : Array[@matching.IgnoredPatternField],
  node : @untyped_cst.CstNode,
  parent_kind : @untyped_cst.NodeKind,
  child_name : String,
) -> Unit {
  if @cst.child(node, child_name) is None {
    ignored.push({ parent_kind, child_name })
  }
}

///|
fn add_ignored_field_if_default_bool(
  ignored : Array[@matching.IgnoredPatternField],
  node : @untyped_cst.CstNode,
  parent_kind : @untyped_cst.NodeKind,
  child_name : String,
) -> Unit {
  match @cst.raw_child(node, child_name) {
    Some(value) if @cst.bool_payload(value) == Some(false) =>
      ignored.push({ parent_kind, child_name })
    _ => ()
  }
}

///|
fn add_ignored_visibility_if_default(
  ignored : Array[@matching.IgnoredPatternField],
  node : @untyped_cst.CstNode,
  parent_kind : @untyped_cst.NodeKind,
) -> Unit {
  match @cst.raw_child(node, "vis") {
    Some(value) if value.kind is @untyped_cst.Visibility_Default =>
      ignored.push({ parent_kind, child_name: "vis" })
    _ => ()
  }
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
    let cst = compiled_shape.cst
    ensure_taint_call_shape(path, context, cst)
    if count_supported_name_in_node(cst, "__SOURCE__") != 0 {
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
    let cst = compiled_shape.cst
    ensure_taint_call_shape(path, context, cst)
    // `__SOURCE__` must be captured as a whole argument or receiver so the
    // lowering layer can read or kill a concrete taint path.
    let target = require_source_target(path, context, cst)
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
    let cst = compiled_shape.cst
    ensure_taint_call_shape(path, context, cst)
    // Sanitizers share the same target restrictions as sinks because both
    // operate on one concrete call value.
    let target = require_source_target(path, context, cst)
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
  ignored_fields? : Array[@matching.IgnoredPatternField] = [],
) -> CompiledRulePattern raise {
  compile_pattern_with_effective_metavars(
    pattern,
    path,
    context,
    compiled_shape.cst,
    compiled_shape.expr_metavars,
    compiled_shape.identifier_metavars,
    compiled_shape.constant_metavars,
    compiled_shape.arg_metavars,
    compiled_shape.type_metavars,
    compiled_shape.pattern_metavars,
    compiled_shape.ellipsis_metavars,
    target_metavar~,
    source_metavar~,
    ignored_fields~,
  )
}

///|
fn compile_pattern_with_effective_metavars(
  pattern : RulePatternSpec,
  path : String,
  context : String,
  cst : @untyped_cst.CstNode,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
  constant_metavars : Array[String],
  arg_metavars : Array[String],
  type_metavars : Array[String],
  pattern_metavars : Array[String],
  ellipsis_metavars : Array[@matching.EllipsisMetavar],
  target_metavar~ : String?,
  source_metavar~ : String?,
  ignored_fields? : Array[@matching.IgnoredPatternField] = [],
) -> CompiledRulePattern raise {
  let guards = compile_guards(
    pattern.guards,
    path,
    context,
    expr_metavars,
    identifier_metavars,
    constant_metavars,
    arg_metavars,
    type_metavars,
    pattern_metavars,
    ellipsis_metavars,
  )
  let compiled : @matching.CompiledExprPattern = {
    cst,
    expr_metavars,
    identifier_metavars,
    constant_metavars,
    arg_metavars,
    type_metavars,
    ellipsis_metavars,
    target_metavar,
    source_metavar,
    ignored_fields,
  }
  { source: pattern, compiled, guards }
}

///|
fn compile_guards(
  raw_guards : Map[String, String],
  path : String,
  context : String,
  expr_metavars : Array[String],
  identifier_metavars : Array[String],
  constant_metavars : Array[String],
  arg_metavars : Array[String],
  type_metavars : Array[String],
  pattern_metavars : Array[String],
  ellipsis_metavars : Array[@matching.EllipsisMetavar],
) -> Array[CompiledRuleGuard] raise {
  let guards : Array[CompiledRuleGuard] = []
  for raw_name, regex_source in raw_guards {
    let name = guard_metavar_name(path, context, raw_name)
    let capture_kind = guard_capture_kind(
      path, context, raw_name, name, expr_metavars, identifier_metavars, constant_metavars,
      arg_metavars, type_metavars, pattern_metavars, ellipsis_metavars,
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
fn guard_metavar_name(
  path : String,
  context : String,
  raw_name : String,
) -> String raise {
  if !raw_name.has_prefix("$") || raw_name.length() <= 1 {
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{context}.guard.\{raw_name} must be a $-prefixed metavar name",
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
  type_metavars : Array[String],
  pattern_metavars : Array[String],
  ellipsis_metavars : Array[@matching.EllipsisMetavar],
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
  } else if array_contains(type_metavars, name) {
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{context}.guard.\{raw_name} cannot reference type metavar \{name}",
    )
  } else if array_contains(pattern_metavars, name) {
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{context}.guard.\{raw_name} cannot reference pat metavar \{name}",
    )
  } else if ellipsis_metavars_contain(ellipsis_metavars, name) {
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{context}.guard.\{raw_name} cannot reference ellipsis metavar \{name}",
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
  let seen : Map[String, String] = Map([])
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
fn ensure_inherited_inside_context_metavar_forms_for_all(
  path : String,
  context : String,
  outer_context : String,
  inner : MetavarShape,
  outers : Array[MetavarShape],
) -> Unit raise {
  for index in 0..<outers.length() {
    let outer = outers[index]
    ensure_inherited_inside_context_metavar_forms(
      path,
      context,
      "\{outer_context}[\{index}]",
      inner.expr_metavars,
      inner.identifier_metavars,
      inner.constant_metavars,
      inner.arg_metavars,
      inner.type_metavars,
      inner.pattern_metavars,
      inner.ellipsis_metavars,
      outer.expr_metavars,
      outer.identifier_metavars,
      outer.constant_metavars,
      outer.arg_metavars,
      outer.type_metavars,
      outer.pattern_metavars,
      outer.ellipsis_metavars,
    )
  }
  ensure_reused_single_metavars_declared_by_all(
    path,
    context,
    outer_context,
    inner.expr_metavars,
    "exp",
    outers,
  )
  ensure_reused_single_metavars_declared_by_all(
    path,
    context,
    outer_context,
    inner.identifier_metavars,
    "id",
    outers,
  )
  ensure_reused_single_metavars_declared_by_all(
    path,
    context,
    outer_context,
    inner.constant_metavars,
    "const",
    outers,
  )
  ensure_reused_single_metavars_declared_by_all(
    path,
    context,
    outer_context,
    inner.arg_metavars,
    "arg",
    outers,
  )
  ensure_reused_single_metavars_declared_by_all(
    path,
    context,
    outer_context,
    inner.type_metavars,
    "type",
    outers,
  )
  ensure_reused_single_metavars_declared_by_all(
    path,
    context,
    outer_context,
    inner.pattern_metavars,
    "pat",
    outers,
  )
  ensure_reused_ellipsis_metavars_declared_by_all(
    path,
    context,
    outer_context,
    inner.ellipsis_metavars,
    outers,
  )
}

///|
fn ensure_reused_single_metavars_declared_by_all(
  path : String,
  context : String,
  outer_context : String,
  inner_names : Array[String],
  kind : String,
  outers : Array[MetavarShape],
) -> Unit raise {
  for name in inner_names {
    let mut inherited = false
    for outer in outers {
      if metavar_shape_declares_name(outer, name) {
        inherited = true
        break
      }
    }
    if inherited {
      for index in 0..<outers.length() {
        if !metavar_shape_declares_single_kind(outers[index], name, kind) {
          raise RuleLoadError::InvalidRule(
            path~,
            info="\{context} cannot use inherited \{outer_context} metavar \{name} as \{kind} because \{outer_context}[\{index}] does not declare it",
          )
        }
      }
    }
  }
}

///|
fn ensure_reused_ellipsis_metavars_declared_by_all(
  path : String,
  context : String,
  outer_context : String,
  inner_metavars : Array[@matching.EllipsisMetavar],
  outers : Array[MetavarShape],
) -> Unit raise {
  for metavar in inner_metavars {
    let mut inherited = false
    for outer in outers {
      if metavar_shape_declares_name(outer, metavar.name) {
        inherited = true
        break
      }
    }
    if inherited {
      for index in 0..<outers.length() {
        let outer_kind = ellipsis_metavar_kind(
          outers[index].ellipsis_metavars,
          metavar.name,
        )
        if outer_kind != Some(metavar.kind) {
          raise RuleLoadError::InvalidRule(
            path~,
            info="\{context} cannot use inherited \{outer_context} ellipsis metavar \{metavar.name} because \{outer_context}[\{index}] does not declare it with kind \{ellipsis_kind_text(metavar.kind)}",
          )
        }
      }
    }
  }
}

///|
fn metavar_shape_declares_name(shape : MetavarShape, name : String) -> Bool {
  array_contains(shape.expr_metavars, name) ||
  array_contains(shape.identifier_metavars, name) ||
  array_contains(shape.constant_metavars, name) ||
  array_contains(shape.arg_metavars, name) ||
  array_contains(shape.type_metavars, name) ||
  array_contains(shape.pattern_metavars, name) ||
  ellipsis_metavars_contain(shape.ellipsis_metavars, name)
}

///|
fn metavar_shape_declares_single_kind(
  shape : MetavarShape,
  name : String,
  kind : String,
) -> Bool {
  match kind {
    "exp" => array_contains(shape.expr_metavars, name)
    "id" => array_contains(shape.identifier_metavars, name)
    "const" => array_contains(shape.constant_metavars, name)
    "arg" => array_contains(shape.arg_metavars, name)
    "type" => array_contains(shape.type_metavars, name)
    "pat" => array_contains(shape.pattern_metavars, name)
    _ => false
  }
}

///|
fn ellipsis_metavar_kind(
  metavars : Array[@matching.EllipsisMetavar],
  name : String,
) -> @matching.EllipsisMetavarKind? {
  for metavar in metavars {
    if metavar.name == name {
      return Some(metavar.kind)
    }
  }
  None
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
  inner_type : Array[String],
  inner_pattern : Array[String],
  inner_ellipsis : Array[@matching.EllipsisMetavar],
  outer_expr : Array[String],
  outer_identifier : Array[String],
  outer_constant : Array[String],
  outer_arg : Array[String],
  outer_type : Array[String],
  outer_pattern : Array[String],
  outer_ellipsis : Array[@matching.EllipsisMetavar],
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
    path, context, outer_context, inner_expr, "exp", outer_type, "type",
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
    path, context, outer_context, inner_identifier, "id", outer_type, "type",
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
    path, context, outer_context, inner_constant, "const", outer_type, "type",
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
    path, context, outer_context, inner_arg, "arg", outer_type, "type",
  )
  ensure_not_inherited_as_other_kind(
    path, context, outer_context, inner_type, "type", outer_expr, "exp",
  )
  ensure_not_inherited_as_other_kind(
    path, context, outer_context, inner_type, "type", outer_identifier, "id",
  )
  ensure_not_inherited_as_other_kind(
    path, context, outer_context, inner_type, "type", outer_constant, "const",
  )
  ensure_not_inherited_as_other_kind(
    path, context, outer_context, inner_type, "type", outer_arg, "arg",
  )
  ensure_not_inherited_as_other_kind(
    path, context, outer_context, inner_type, "type", outer_pattern, "pat",
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
  ensure_not_inherited_as_other_kind(
    path, context, outer_context, inner_pattern, "pat", outer_type, "type",
  )
  ensure_single_metavars_not_inherited_from_ellipsis(
    path, context, outer_context, inner_expr, "exp", outer_ellipsis,
  )
  ensure_single_metavars_not_inherited_from_ellipsis(
    path, context, outer_context, inner_identifier, "id", outer_ellipsis,
  )
  ensure_single_metavars_not_inherited_from_ellipsis(
    path, context, outer_context, inner_constant, "const", outer_ellipsis,
  )
  ensure_single_metavars_not_inherited_from_ellipsis(
    path, context, outer_context, inner_arg, "arg", outer_ellipsis,
  )
  ensure_single_metavars_not_inherited_from_ellipsis(
    path, context, outer_context, inner_type, "type", outer_ellipsis,
  )
  ensure_single_metavars_not_inherited_from_ellipsis(
    path, context, outer_context, inner_pattern, "pat", outer_ellipsis,
  )
  for metavar in inner_ellipsis {
    ensure_not_inherited_as_other_kind(
      path,
      context,
      outer_context,
      [metavar.name],
      "ellipsis",
      outer_expr,
      "exp",
    )
    ensure_not_inherited_as_other_kind(
      path,
      context,
      outer_context,
      [metavar.name],
      "ellipsis",
      outer_identifier,
      "id",
    )
    ensure_not_inherited_as_other_kind(
      path,
      context,
      outer_context,
      [metavar.name],
      "ellipsis",
      outer_constant,
      "const",
    )
    ensure_not_inherited_as_other_kind(
      path,
      context,
      outer_context,
      [metavar.name],
      "ellipsis",
      outer_arg,
      "arg",
    )
    ensure_not_inherited_as_other_kind(
      path,
      context,
      outer_context,
      [metavar.name],
      "ellipsis",
      outer_type,
      "type",
    )
    ensure_not_inherited_as_other_kind(
      path,
      context,
      outer_context,
      [metavar.name],
      "ellipsis",
      outer_pattern,
      "pat",
    )
    for inherited in outer_ellipsis {
      if inherited.name == metavar.name && inherited.kind != metavar.kind {
        raise RuleLoadError::InvalidRule(
          path~,
          info="\{context} cannot use inherited \{outer_context} ellipsis metavar \{metavar.name} with a different kind",
        )
      }
    }
  }
}

///|
fn ensure_single_metavars_not_inherited_from_ellipsis(
  path : String,
  context : String,
  outer_context : String,
  names : Array[String],
  kind : String,
  outer_ellipsis : Array[@matching.EllipsisMetavar],
) -> Unit raise {
  for name in names {
    if ellipsis_metavars_contain(outer_ellipsis, name) {
      raise RuleLoadError::InvalidRule(
        path~,
        info="\{context} cannot use inherited \{outer_context} ellipsis metavar \{name} as \{kind}",
      )
    }
  }
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
  cst : @untyped_cst.CstNode,
) -> Unit raise {
  match cst.kind {
    @untyped_cst.Expr_Apply | @untyped_cst.Expr_DotApply => ()
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
  cst : @untyped_cst.CstNode,
) -> TaintTarget raise {
  let count = count_supported_name_in_node(cst, "__SOURCE__")
  if count != 1 {
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{context}.shape must contain exactly one __SOURCE__ placeholder",
    )
  }
  if whole_source_target(cst) is Some(target) {
    target
  } else {
    raise RuleLoadError::InvalidRule(
      path~,
      info="\{context}.shape must place __SOURCE__ as the whole receiver or argument value",
    )
  }
}

///|
fn whole_source_target(cst : @untyped_cst.CstNode) -> TaintTarget? {
  match cst.kind {
    @untyped_cst.Expr_DotApply =>
      if @cst.raw_child(cst, "self") is Some(self) &&
        is_source_placeholder_node(self) {
        Some(Receiver)
      } else if @cst.raw_child(cst, "arg") is Some(args) {
        source_target_from_args(args)
      } else {
        None
      }
    @untyped_cst.Expr_Apply =>
      if @cst.raw_child(cst, "arg") is Some(args) {
        source_target_from_args(args)
      } else {
        None
      }
    _ => None
  }
}

///|
fn source_target_from_args(args : @untyped_cst.CstNode) -> TaintTarget? {
  let arguments = @cst.raw_children(args, "item")
  for index in 0..<arguments.length() {
    let argument = arguments[index]
    if @cst.argument_value(argument) is Some(value) &&
      is_source_placeholder_node(value) {
      return match argument.kind {
        @untyped_cst.Argument_Positional => Some(PositionalArg(index))
        @untyped_cst.Argument_Labelled
        | @untyped_cst.Argument_LabelledPun
        | @untyped_cst.Argument_LabelledOption
        | @untyped_cst.Argument_LabelledOptionPun =>
          if @cst.argument_label_name(argument) is Some(label) {
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
fn is_source_placeholder_node(node : @untyped_cst.CstNode) -> Bool {
  if node.kind is @untyped_cst.Expr_Ident {
    @cst.normalized_expr_identifier_name(node) == Some("__SOURCE__")
  } else {
    false
  }
}

///|
fn is_builtin_ignore_metavar_name(name : String) -> Bool {
  name == "$_"
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
