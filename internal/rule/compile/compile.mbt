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
/// Compiles one structural expression pattern into the matcher representation.
///
/// The pattern uses the same CST, metavar, and reserved-placeholder validation
/// as one ordinary `patterns[0]` rule entry, but does not create rule metadata,
/// guards, or a rule-level prefilter.
pub fn compile_expr_pattern(
  pattern : String,
) -> @matching.CompiledExprPattern raise {
  compile_structural_expr_pattern(
    pattern_compile_context(pattern, "patterns[0]", pattern),
    "",
    [],
  )
}

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
    let pattern = spec.patterns[index]
    let context = pattern_compile_context(
      path,
      "patterns[\{index}]",
      pattern.shape,
    )
    let compiled = compile_structural_expr_pattern(
      context, outer_context, outer_shapes,
    )
    patterns.push(compile_rule_pattern(pattern, compiled, context))
  }
  let patterns_not : Array[CompiledRulePattern] = []
  for index in 0..<spec.patterns_not.length() {
    let pattern = spec.patterns_not[index]
    let context = pattern_compile_context(
      path,
      "patterns-not[\{index}]",
      pattern.shape,
    )
    let compiled = compile_structural_expr_pattern(
      context, outer_context, outer_shapes,
    )
    patterns_not.push(compile_rule_pattern(pattern, compiled, context))
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
fn compile_structural_expr_pattern(
  context : PatternCompileContext,
  outer_context : String,
  outer_shapes : Array[MetavarShape],
) -> @matching.CompiledExprPattern raise {
  let compiled_shape = compile_metavar_shape(context)
  ensure_inherited_inside_context_metavar_forms_for_all(
    context.path,
    context.location,
    outer_context,
    compiled_shape,
    outer_shapes,
  )
  if count_bindable_expr_identifier_in_node(compiled_shape.cst, "__TARGET__") !=
    0 {
    raise context.invalid_pattern("the pattern must not contain __TARGET__")
  }
  build_compiled_expr_pattern(compiled_shape)
}

///|
fn compile_inside_context_patterns(
  path : String,
  patterns : Array[RulePatternSpec],
  clause : String,
  is_toplevel~ : Bool,
) -> (Array[CompiledRulePattern], Array[MetavarShape]) raise {
  let compiled_patterns : Array[CompiledRulePattern] = []
  let compiled_shapes : Array[MetavarShape] = []
  for index in 0..<patterns.length() {
    let pattern = patterns[index]
    let context = pattern_compile_context(
      path,
      "\{clause}[\{index}]",
      pattern.shape,
    )
    let compiled_shape = if is_toplevel {
      compile_toplevel_metavar_shape(context)
    } else {
      compile_metavar_shape(context)
    }
    let cst = compiled_shape.cst
    let ignored_fields = if is_toplevel {
      inside_toplevel_ignored_fields(context, pattern.match_mode, cst)
    } else {
      []
    }
    let target_count = count_bindable_expr_identifier_in_node(cst, "__TARGET__")
    if target_count != 1 {
      raise context.invalid_pattern(
        "the pattern must contain exactly one __TARGET__ placeholder in a supported expression position",
      )
    }
    compiled_patterns.push(
      compile_pattern(
        pattern,
        compiled_shape,
        context,
        special_expr_placeholders=["__TARGET__"],
        ignored_fields~,
      ),
    )
    compiled_shapes.push(compiled_shape)
  }
  (compiled_patterns, compiled_shapes)
}

///|
fn inside_toplevel_ignored_fields(
  context : PatternCompileContext,
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
        raise context.invalid_pattern(
          "the pattern uses match-mode partial, which is only supported for function definition shapes",
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
    ignored.push({ parent_kind, child_name, })
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
      ignored.push({ parent_kind, child_name, })
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
      ignored.push({ parent_kind, child_name: "vis", })
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
    let pattern = spec.sources[index]
    let context = pattern_compile_context(
      path,
      "taint.sources[\{index}]",
      pattern.shape,
    )
    let compiled_shape = compile_metavar_shape(context)
    let cst = compiled_shape.cst
    ensure_taint_call_shape(context, cst)
    if count_supported_name_in_node(cst, "__SOURCE__") != 0 {
      raise context.invalid_pattern("the pattern must not contain __SOURCE__")
    }
    sources.push({ pattern: compile_pattern(pattern, compiled_shape, context), })
  }
  let sinks : Array[CompiledTaintSink] = []
  for index in 0..<spec.sinks.length() {
    let pattern = spec.sinks[index]
    let context = pattern_compile_context(
      path,
      "taint.sinks[\{index}]",
      pattern.shape,
    )
    let compiled_shape = compile_metavar_shape(context)
    let cst = compiled_shape.cst
    ensure_taint_call_shape(context, cst)
    // `__SOURCE__` must be captured as a whole argument or receiver so the
    // lowering layer can read or kill a concrete taint path.
    let target = require_source_target(context, cst)
    sinks.push({
      pattern: compile_pattern(pattern, compiled_shape, context, special_expr_placeholders=[
        "__SOURCE__",
      ]),
      target,
    })
  }
  let sanitizers : Array[CompiledTaintSanitizer] = []
  for index in 0..<spec.sanitizers.length() {
    let pattern = spec.sanitizers[index]
    let context = pattern_compile_context(
      path,
      "taint.sanitizers[\{index}]",
      pattern.shape,
    )
    let compiled_shape = compile_metavar_shape(context)
    let cst = compiled_shape.cst
    ensure_taint_call_shape(context, cst)
    // Sanitizers share the same target restrictions as sinks because both
    // operate on one concrete call value.
    let target = require_source_target(context, cst)
    sanitizers.push({
      pattern: compile_pattern(pattern, compiled_shape, context, special_expr_placeholders=[
        "__SOURCE__",
      ]),
      target,
    })
  }
  { sources, sinks, sanitizers, }
}

///|
fn compile_pattern(
  pattern : RulePatternSpec,
  compiled_shape : MetavarShape,
  context : PatternCompileContext,
  special_expr_placeholders? : Array[String] = [],
  ignored_fields? : Array[@matching.IgnoredPatternField] = [],
) -> CompiledRulePattern raise {
  let compiled = build_compiled_expr_pattern(
    compiled_shape,
    special_expr_placeholders~,
    ignored_fields~,
  )
  compile_rule_pattern(pattern, compiled, context)
}

///|
fn build_compiled_expr_pattern(
  compiled_shape : MetavarShape,
  special_expr_placeholders? : Array[String] = [],
  ignored_fields? : Array[@matching.IgnoredPatternField] = [],
) -> @matching.CompiledExprPattern {
  let metavars = compiled_shape.metavars.copy()
  for placeholder in special_expr_placeholders {
    metavars.register_special_expr_placeholder(placeholder)
  }
  { cst: compiled_shape.cst, metavars, ignored_fields, }
}

///|
fn compile_rule_pattern(
  pattern : RulePatternSpec,
  compiled : @matching.CompiledExprPattern,
  context : PatternCompileContext,
) -> CompiledRulePattern raise {
  let guards = compile_guards(pattern.guards, context, compiled.metavars)
  { source: pattern, compiled, guards, }
}

///|
fn compile_guards(
  raw_guards : Map[String, String],
  context : PatternCompileContext,
  metavars : @matching.MetavarRegistry,
) -> Array[CompiledRuleGuard] raise {
  let guards : Array[CompiledRuleGuard] = []
  for raw_name, regex_source in raw_guards {
    let name = guard_metavar_name(context, raw_name)
    let capture_kind = guard_capture_kind(context, raw_name, name, metavars)
    let regex = Regex::Regex(regex_source) catch {
      _ =>
        raise RuleLoadError::InvalidRule(
          path=context.path,
          info="\{context.location}.guard.\{raw_name} has invalid regex",
        )
    }
    guards.push({ name, capture_kind, regex_source, regex, })
  }
  guards
}

///|
fn guard_metavar_name(
  context : PatternCompileContext,
  raw_name : String,
) -> String raise {
  if !raw_name.has_prefix("$") || raw_name.length() <= 1 {
    raise RuleLoadError::InvalidRule(
      path=context.path,
      info="\{context.location}.guard.\{raw_name} must be a $-prefixed metavar name",
    )
  }
  raw_name[1:].to_owned()
}

///|
fn guard_capture_kind(
  context : PatternCompileContext,
  raw_name : String,
  name : String,
  metavars : @matching.MetavarRegistry,
) -> RuleGuardCaptureKind raise {
  if metavars.kind_of(name) is Some(kind) {
    match kind {
      Identifier => IdentifierGuard
      Constant => ConstantGuard
      Ellipsis(_) =>
        raise RuleLoadError::InvalidRule(
          path=context.path,
          info="\{context.location}.guard.\{raw_name} cannot reference ellipsis metavar \{name}",
        )
      _ =>
        raise RuleLoadError::InvalidRule(
          path=context.path,
          info="\{context.location}.guard.\{raw_name} cannot reference \{kind.syntax_name()} metavar \{name}",
        )
    }
  } else {
    raise RuleLoadError::InvalidRule(
      path=context.path,
      info="\{context.location}.guard.\{raw_name} references unknown metavar",
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
  context : PatternCompileContext,
  name : String,
  reserve_source : Bool,
) -> Unit raise {
  if is_builtin_ignore_metavar_name(name) {
    raise context.invalid_pattern(
      "the pattern cannot declare metavar \{name} because it is a built-in ignore placeholder",
    )
  } else if name == "__TARGET__" {
    raise context.invalid_pattern(
      "the pattern cannot declare metavar __TARGET__ because it is reserved for inside-expr target traversal",
    )
  } else if reserve_source && name == "__SOURCE__" {
    raise context.invalid_pattern(
      "the pattern cannot declare metavar __SOURCE__ because it is reserved for taint source targets",
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
  for inner_entry in inner.metavars.entries {
    let mut inherited = false
    for outer in outers {
      if outer.metavars.kind_of(inner_entry.name) is Some(_) {
        inherited = true
        break
      }
    }
    if !inherited {
      continue
    }
    // Preserve the former diagnostic precedence: incompatible declarations are
    // reported before a missing declaration in another alternative.
    for index in 0..<outers.length() {
      if outers[index].metavars.kind_of(inner_entry.name) is Some(outer_kind) &&
        outer_kind != inner_entry.kind {
        reject_inherited_inside_context_kind_mismatch(
          path,
          context,
          "\{outer_context}[\{index}]",
          inner_entry,
          outer_kind,
        )
      }
    }
    for index in 0..<outers.length() {
      if outers[index].metavars.kind_of(inner_entry.name) is None {
        reject_missing_inherited_inside_context_metavar(
          path, context, outer_context, index, inner_entry,
        )
      }
    }
  }
}

///|
fn reject_inherited_inside_context_kind_mismatch(
  path : String,
  context : String,
  outer_context : String,
  inner : @matching.MetavarEntry,
  outer_kind : @matching.MetavarKind,
) -> Unit raise {
  let info = match (inner.kind, outer_kind) {
    (Ellipsis(_), Ellipsis(_)) =>
      "\{context} cannot use inherited \{outer_context} ellipsis metavar \{inner.name} with a different kind"
    (_, Ellipsis(_)) =>
      "\{context} cannot use inherited \{outer_context} ellipsis metavar \{inner.name} as \{inner.kind.syntax_name()}"
    _ =>
      "\{context} cannot use inherited \{outer_context} metavar \{inner.name} as \{inner.kind.syntax_name()} because it was declared as \{outer_kind.syntax_name()}"
  }
  raise RuleLoadError::InvalidRule(path~, info~)
}

///|
fn reject_missing_inherited_inside_context_metavar(
  path : String,
  context : String,
  outer_context : String,
  outer_index : Int,
  inner : @matching.MetavarEntry,
) -> Unit raise {
  let info = match inner.kind {
    Ellipsis(kind) =>
      "\{context} cannot use inherited \{outer_context} ellipsis metavar \{inner.name} because \{outer_context}[\{outer_index}] does not declare it with kind \{kind.syntax_name()}"
    _ =>
      "\{context} cannot use inherited \{outer_context} metavar \{inner.name} as \{inner.kind.syntax_name()} because \{outer_context}[\{outer_index}] does not declare it"
  }
  raise RuleLoadError::InvalidRule(path~, info~)
}

///|
fn ensure_taint_call_shape(
  context : PatternCompileContext,
  cst : @untyped_cst.CstNode,
) -> Unit raise {
  match cst.kind {
    @untyped_cst.Expr_Apply | @untyped_cst.Expr_DotApply => ()
    _ => raise context.invalid_pattern("the pattern must be a call expression")
  }
}

///|
fn require_source_target(
  context : PatternCompileContext,
  cst : @untyped_cst.CstNode,
) -> TaintTarget raise {
  let count = count_supported_name_in_node(cst, "__SOURCE__")
  if count != 1 {
    raise context.invalid_pattern(
      "the pattern must contain exactly one __SOURCE__ placeholder",
    )
  }
  if whole_source_target(cst) is Some(target) {
    target
  } else {
    raise context.invalid_pattern(
      "the pattern must place __SOURCE__ as the whole receiver or argument value",
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
