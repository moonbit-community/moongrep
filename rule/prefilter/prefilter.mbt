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
  let inside_literals : Array[String] = if rule.inside_toplevel is Some(pattern) {
    required_literals_from_compiled_pattern(pattern)
  } else if rule.inside_expr is Some(pattern) {
    required_literals_from_compiled_pattern(pattern)
  } else {
    []
  }
  if rule.patterns.is_empty() {
    alternatives.push(unique_literals(inside_literals))
  }
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
  collect_node_literals(pattern.compiled.ast, pattern.compiled, literals)
  unique_literals(literals)
}

///|
fn collect_node_literals(
  node : @untyped_ast.Node,
  compiled : @matching.CompiledExprPattern,
  literals : Array[String],
) -> Unit {
  match node.kind {
    Var =>
      if node.normalized_var_name() is Some(name) {
        if !is_filter_placeholder(name, compiled) {
          push_literal(literals, name)
        }
      }
    Binder | Label =>
      if prefilter_leaf_string_child(node, "name") is Some(name) {
        if !is_filter_placeholder(name, compiled) {
          push_literal(literals, name)
        }
      }
    ConstrName =>
      if prefilter_leaf_string_child(node, "name") is Some(name) {
        if !is_filter_placeholder(name, compiled) {
          push_literal(literals, name)
        }
      }
    Type_Name =>
      if prefilter_type_placeholder_name(node) is Some(name) {
        if !is_filter_placeholder(name, compiled) {
          collect_node_children_literals(node, compiled, literals)
        }
      } else {
        collect_node_children_literals(node, compiled, literals)
      }
    Constant_BigInt
    | Constant_Byte
    | Constant_Bytes
    | Constant_Char
    | Constant_Double
    | Constant_Float
    | Constant_Int64
    | Constant_Regex
    | Constant_String
    | Constant_UInt
    | Constant_UInt64 =>
      if prefilter_first_leaf_string(node) is Some(value) {
        push_literal(literals, value)
      }
    Constant_Int =>
      if prefilter_first_leaf_string(node) is Some(value) {
        if value.length() >= 2 {
          push_literal(literals, value)
        }
      }
    Constant_Bool =>
      if prefilter_first_leaf_bool(node) is Some(value) {
        push_literal(literals, "\{value}")
      }
    InterpElem_Literal =>
      if prefilter_leaf_string_child(node, "repr") is Some(value) {
        push_literal(literals, value)
      }
    MultilineString_String =>
      if prefilter_leaf_string_child(node, "value") is Some(value) {
        push_literal(literals, value)
      }
    Leaf(_) => ()
    _ => collect_node_children_literals(node, compiled, literals)
  }
}

///|
fn collect_node_children_literals(
  node : @untyped_ast.Node,
  compiled : @matching.CompiledExprPattern,
  literals : Array[String],
) -> Unit {
  for entry in node.children {
    let (_, child) = entry
    collect_node_literals(child, compiled, literals)
  }
}

///|
fn prefilter_type_placeholder_name(node : @untyped_ast.Node) -> String? {
  if node.kind != Type_Name {
    return None
  }
  guard prefilter_child(node, "tys") is Some(tys) else { return None }
  if !tys.children.is_empty() {
    return None
  }
  guard prefilter_child(node, "constr_id") is Some(constr_id) else {
    return None
  }
  guard prefilter_child(constr_id, "id") is Some(long_ident) else {
    return None
  }
  guard long_ident.kind == LongIdent_Ident else { return None }
  prefilter_leaf_string_child(long_ident, "value")
}

///|
fn prefilter_child(
  node : @untyped_ast.Node,
  name : String,
) -> @untyped_ast.Node? {
  for entry in node.children {
    let (child_name, value) = entry
    if child_name == Some(name) {
      return Some(value)
    }
  }
  None
}

///|
fn prefilter_leaf_string(node : @untyped_ast.Node) -> String? {
  match node.kind {
    Leaf(PString(value)) => Some(value)
    _ => None
  }
}

///|
fn prefilter_leaf_bool(node : @untyped_ast.Node) -> Bool? {
  match node.kind {
    Leaf(PBool(value)) => Some(value)
    _ => None
  }
}

///|
fn prefilter_leaf_string_child(
  node : @untyped_ast.Node,
  name : String,
) -> String? {
  if prefilter_child(node, name) is Some(value) {
    prefilter_leaf_string(value)
  } else {
    None
  }
}

///|
fn prefilter_first_leaf_string(node : @untyped_ast.Node) -> String? {
  if node.children.length() == 0 {
    None
  } else {
    let (_, value) = node.children[0]
    prefilter_leaf_string(value)
  }
}

///|
fn prefilter_first_leaf_bool(node : @untyped_ast.Node) -> Bool? {
  if node.children.length() == 0 {
    None
  } else {
    let (_, value) = node.children[0]
    prefilter_leaf_bool(value)
  }
}

///|
fn is_filter_placeholder(
  name : String,
  compiled : @matching.CompiledExprPattern,
) -> Bool {
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
