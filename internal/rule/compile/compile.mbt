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
  let (inside_toplevel, outer_shapes) = compile_inside_toplevel_patterns(
    path,
    spec.inside_toplevel,
  )
  let group = compile_structural_group(
    path,
    spec.group,
    "",
    outer_shapes,
    !inside_toplevel.is_empty(),
  )
  { inside_toplevel, group, }
}

///|
fn compile_structural_group(
  path : String,
  group : @model.StructuralPatternGroupSpec,
  prefix : String,
  ancestors : Array[MetavarShape],
  reject_negative : Bool,
) -> @model.CompiledStructuralPatternGroup raise {
  let patterns = group.patterns.mapi(fn(index, entry) raise {
    let context = pattern_compile_context(
      path,
      "\{prefix}patterns[\{index}]",
      entry.pattern.shape,
    )
    let shape = compile_metavar_shape(context)
    let visible = structural_visible_shapes(
      context,
      shape,
      entry.pattern.guards,
      ancestors,
    )
    let count = count_bindable_expr_identifier_in_node(shape.cst, "__TARGET__")
    let placeholders = if entry.then_body is Some(_) {
      if count != 1 {
        raise context.invalid_pattern(
          "the pattern must contain exactly one __TARGET__ placeholder in a supported expression position",
        )
      }
      ["__TARGET__"]
    } else {
      if count != 0 {
        raise context.invalid_pattern("the pattern must not contain __TARGET__")
      }
      []
    }
    let compiled = build_compiled_expr_pattern(
      shape,
      special_expr_placeholders=placeholders,
    )
    let pattern : CompiledRulePattern = {
      source: entry.pattern,
      compiled,
      guards: compile_guards(entry.pattern.guards, context, visible[0].metavars),
    }
    let then_body = entry.then_body.map(fn(body) raise {
      compile_structural_group(
        path,
        body,
        "\{context.location}.then.",
        visible,
        true,
      )
    })
    @model.CompiledStructuralPattern::{ pattern, then_body, }
  })
  let patterns_not = group.patterns_not.mapi(fn(index, pattern) raise {
    let context = pattern_compile_context(
      path,
      "\{prefix}patterns-not[\{index}]",
      pattern.shape,
    )
    let shape = compile_metavar_shape(context)
    let visible = structural_visible_shapes(
      context,
      shape,
      pattern.guards,
      ancestors,
    )
    if count_bindable_expr_identifier_in_node(shape.cst, "__TARGET__") != 0 {
      raise context.invalid_pattern("the pattern must not contain __TARGET__")
    }
    CompiledRulePattern::{
      source: pattern,
      compiled: build_compiled_expr_pattern(shape),
      guards: compile_guards(pattern.guards, context, visible[0].metavars),
    }
  })
  {
    patterns,
    patterns_not,
    patterns_not_mode: if reject_negative {
      RejectUncoveredNegative
    } else {
      PruneOnNegative
    },
  }
}

///|
// Keep one visible environment per top-level alternative. Local registrations
// are separate from these environments, so siblings cannot introduce captures.
fn structural_visible_shapes(
  context : PatternCompileContext,
  shape : MetavarShape,
  guards : Map[String, String],
  ancestors : Array[MetavarShape],
) -> Array[MetavarShape] raise {
  let referenced = shape.metavars.copy()
  for raw_name, _ in guards {
    let name = guard_metavar_name(context, raw_name)
    if referenced.kind_of(name) is None {
      for ancestor in ancestors {
        if ancestor.metavars.kind_of(name) is Some(kind) {
          ignore(referenced.register(name, kind))
          break
        }
      }
    }
  }
  ensure_inherited_inside_context_metavar_forms_for_all(
    context.path,
    context.location,
    "ancestor",
    { ..shape, metavars: referenced, },
    ancestors,
  )
  if ancestors.is_empty() {
    return [shape]
  }
  ancestors.map(fn(ancestor) {
    let metavars = ancestor.metavars.copy()
    for entry in shape.metavars.entries {
      ignore(metavars.register(entry.name, entry.kind))
    }
    { ..shape, metavars, }
  })
}

///|
fn compile_structural_expr_pattern(
  context : PatternCompileContext,
) -> @matching.CompiledExprPattern raise {
  let compiled_shape = compile_metavar_shape(context)
  if count_bindable_expr_identifier_in_node(compiled_shape.cst, "__TARGET__") !=
    0 {
    raise context.invalid_pattern("the pattern must not contain __TARGET__")
  }
  build_compiled_expr_pattern(compiled_shape)
}

///|
fn compile_inside_toplevel_patterns(
  path : String,
  patterns : Array[RulePatternSpec],
) -> (Array[CompiledRulePattern], Array[MetavarShape]) raise {
  let compiled_patterns : Array[CompiledRulePattern] = []
  let compiled_shapes : Array[MetavarShape] = []
  for index in 0..<patterns.length() {
    let pattern = patterns[index]
    let context = pattern_compile_context(
      path,
      "inside-toplevel[\{index}]",
      pattern.shape,
    )
    let compiled_shape = compile_toplevel_metavar_shape(context)
    let cst = compiled_shape.cst
    let ignored_fields = inside_toplevel_ignored_fields(
      context,
      pattern.match_mode,
      cst,
    )
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
      "the pattern cannot declare metavar __TARGET__ because it is reserved for then target traversal",
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
