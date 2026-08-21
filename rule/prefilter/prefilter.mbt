///|
using @model {
  type CompiledRule,
  type CompiledRuleDefinition,
  type CompiledRulePattern,
  type CompiledStructuralRule,
  type CompiledTaintRule,
  type RulePrefilter,
}

///|
pub fn rule_is_relevant_to_source(rule : CompiledRule, source : String) -> Bool {
  prefilter_matches_source(rule.prefilter, source)
}

///|
fn prefilter_matches_source(prefilter : RulePrefilter, source : String) -> Bool {
  prefilter_matches_with_literal_matcher(prefilter, fn(literal) {
    literal_matches_source(literal, source)
  })
}

///|
pub fn prefilter_matches_with_literal_matcher(
  prefilter : RulePrefilter,
  literal_matches : (String) -> Bool,
) -> Bool {
  if prefilter.alternatives.is_empty() {
    return true
  }
  for alternative in prefilter.alternatives {
    if alternative.is_empty() {
      return true
    }
    let mut matched = true
    for literal in alternative {
      if !literal_matches(literal) {
        matched = false
        break
      }
    }
    if matched {
      return true
    }
  }
  false
}

///|
fn literal_matches_source(literal : String, source : String) -> Bool {
  source.contains(literal)
}

///|
fn contains_string(values : Array[String], value : String) -> Bool {
  for item in values {
    if item == value {
      return true
    }
  }
  false
}

///|
fn push_literal(literals : Array[String], value : String) -> Unit {
  if value.length() > 0 {
    literals.push(value)
  }
}

///|
fn concat_string_arrays(
  left : Array[String],
  right : Array[String],
) -> Array[String] {
  let result : Array[String] = []
  for item in left {
    result.push(item)
  }
  for item in right {
    result.push(item)
  }
  result
}

///|
fn unique_literals(values : Array[String]) -> Array[String] {
  let result : Array[String] = []
  for value in values {
    if !contains_string(result, value) {
      result.push(value)
    }
  }
  result
}

///|
pub fn compile_rule_prefilter(
  definition : CompiledRuleDefinition,
) -> RulePrefilter {
  match definition {
    Structural(rule) => compile_structural_prefilter(rule)
    Taint(rule) => compile_taint_prefilter(rule)
  }
}

///|
fn compile_structural_prefilter(rule : CompiledStructuralRule) -> RulePrefilter {
  let alternatives : Array[Array[String]] = []
  let inside_patterns = if !rule.inside_toplevel.is_empty() {
    rule.inside_toplevel
  } else {
    rule.inside_expr
  }
  if inside_patterns.is_empty() {
    for pattern in rule.patterns {
      alternatives.push(
        unique_literals(required_literals_from_compiled_pattern(pattern)),
      )
    }
  } else {
    for inside in inside_patterns {
      let inside_literals = required_literals_from_compiled_pattern(inside)
      if rule.patterns.is_empty() {
        alternatives.push(unique_literals(inside_literals))
      } else {
        for pattern in rule.patterns {
          alternatives.push(
            unique_literals(
              concat_string_arrays(
                inside_literals,
                required_literals_from_compiled_pattern(pattern),
              ),
            ),
          )
        }
      }
    }
  }
  { alternatives, }
}

///|
fn compile_taint_prefilter(rule : CompiledTaintRule) -> RulePrefilter {
  let alternatives : Array[Array[String]] = []
  for source in rule.sources {
    let source_literals = required_literals_from_compiled_pattern(
      source.pattern,
    )
    for sink in rule.sinks {
      let sink_literals = required_literals_from_compiled_pattern(sink.pattern)
      alternatives.push(
        unique_literals(concat_string_arrays(source_literals, sink_literals)),
      )
    }
  }
  { alternatives, }
}

///|
fn required_literals_from_compiled_pattern(
  pattern : CompiledRulePattern,
) -> Array[String] {
  let literals : Array[String] = []
  collect_node_literals(pattern.compiled.cst, pattern.compiled, literals)
  unique_literals(literals)
}

///|
fn collect_node_literals(
  node : @untyped_cst.CstNode,
  compiled : @matching.CompiledExprPattern,
  literals : Array[String],
) -> Unit {
  if node.kind.is_constant() {
    if @cst.string_payload(node) is Some(value) {
      if node.kind is @untyped_cst.Constant_Int {
        if value.length() >= 2 {
          push_literal(literals, value)
        }
      } else {
        push_literal(literals, value)
      }
    } else if @cst.bool_payload(node) is Some(value) {
      push_literal(literals, "\{value}")
    }
    return
  }
  if @cst.normalized_name(node) is Some(name) {
    collect_name_literals(name, compiled, literals)
    return
  }
  match node.kind {
    @untyped_cst.InterpSegment_Literal
    | @untyped_cst.MultilineStringElement_String =>
      if @cst.string_payload(node) is Some(value) {
        push_literal(literals, value)
      }
    _ => collect_node_children_literals(node, compiled, literals)
  }
}

///|
fn collect_node_children_literals(
  node : @untyped_cst.CstNode,
  compiled : @matching.CompiledExprPattern,
  literals : Array[String],
) -> Unit {
  for entry in @cst.semantic_children(node) {
    let (child_name, child) = entry
    let ignored = if child_name is Some(name) {
      prefilter_ignores_field(compiled, node.kind, name)
    } else {
      false
    }
    if !ignored {
      collect_node_literals(child, compiled, literals)
    }
  }
}

///|
fn prefilter_ignores_field(
  compiled : @matching.CompiledExprPattern,
  parent_kind : @untyped_cst.NodeKind,
  child_name : String,
) -> Bool {
  for field in compiled.ignored_fields {
    if field.parent_kind == parent_kind && field.child_name == child_name {
      return true
    }
  }
  false
}

///|
fn collect_name_literals(
  name : String,
  compiled : @matching.CompiledExprPattern,
  literals : Array[String],
) -> Unit {
  if is_filter_placeholder(name, compiled) {
    return
  }
  let mut component_start = if name.has_prefix("@") { 1 } else { 0 }
  for index in 0..<name.length() {
    if name[index] == '.' || name[index] == ':' {
      if index > component_start {
        let component = name[component_start:index].to_owned()
        if !is_filter_placeholder(component, compiled) {
          push_literal(literals, component)
        }
      }
      component_start = index + 1
    }
  }
  if component_start < name.length() {
    let component = name[component_start:].to_owned()
    if !is_filter_placeholder(component, compiled) {
      push_literal(literals, component)
    }
  }
}

///|
fn is_filter_placeholder(
  name : String,
  compiled : @matching.CompiledExprPattern,
) -> Bool {
  name.has_prefix("$$$") ||
  name.has_prefix("__moongrep_ellipsis_") ||
  name.has_prefix("MoongrepEllipsis_") ||
  name.has_prefix("__moongrep_exp_") ||
  name.has_prefix("__moongrep_const_") ||
  name.has_prefix("__moongrep_arg_") ||
  name.has_prefix("__moongrep_pat_") ||
  name.has_prefix("__moongrep_id_") ||
  name.has_prefix("__moongrep_bare_") ||
  name.has_prefix("MoongrepId_") ||
  name.has_prefix("MoongrepType_") ||
  name.has_prefix("MoongrepBare_") ||
  name == "__moongrep_ignore" ||
  is_underscore_placeholder(name) ||
  is_pattern_placeholder(name) ||
  compiled.target_metavar == Some(name) ||
  compiled.source_metavar == Some(name) ||
  contains_string(compiled.expr_metavars, name) ||
  contains_string(compiled.identifier_metavars, name) ||
  contains_string(compiled.constant_metavars, name) ||
  contains_string(compiled.arg_metavars, name) ||
  contains_string(compiled.type_metavars, name)
}

///|
fn is_pattern_placeholder(name : String) -> Bool {
  if name.has_prefix("$(") && name.has_suffix(")") {
    let end = name.length() - 1
    for index in 2..<end {
      if name[index] == ':' && name[index + 1:end].to_owned() == "pat" {
        return index > 2
      }
    }
  }
  false
}

///|
fn is_underscore_placeholder(name : String) -> Bool {
  name == "$_"
}
