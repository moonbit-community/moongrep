///|
fn invalid_rule(path~ : String, info~ : String) -> RuleLoadError {
  InvalidRule(path~, info~)
}

///|
/// Parses one YAML rule document into a raw rule spec.
///
/// `path` is used in diagnostics and rule id derivation. `rules_root` must be
/// an ancestor path of `path`; the rule id is the relative directory below
/// `rules_root` joined with the YAML `id`.
pub fn RawRuleSpec::from_str(
  path : String,
  rules_root : String,
  source : String,
) -> RawRuleSpec raise {
  let docs = @yaml.Yaml::load_from_string(source) catch {
    @yaml.YamlError::YamlError(mark~, info~) =>
      raise invalid_rule(
        path~,
        info="line \{mark.line}, column \{mark.col + 1}: \{info}",
      )
  }
  if docs.length() != 1 {
    raise invalid_rule(
      path~,
      info="rule file must contain exactly one YAML document",
    )
  }
  guard docs[0] is Map(doc) else {
    raise invalid_rule(path~, info="top-level YAML document must be a mapping")
  }
  ensure_allowed_keys(path, "top-level rule", doc, [
    "id", "description", "patterns", "patterns-not", "inside-expr", "inside-toplevel",
    "taint",
  ])
  let id = expect_rule_id(doc, path)
  let description = expect_yaml_string(doc, path, "description")
  let definition = expect_rule_definition(doc, path)
  {
    path,
    rule_id: rule_id_from_path(path, rules_root, id),
    description,
    definition,
  }
}

///|
fn expect_rule_definition(
  doc : Map[String, @yaml.Yaml],
  path : String,
) -> RuleDefinitionSpec raise {
  let has_patterns = doc.contains("patterns")
  let has_patterns_not = doc.contains("patterns-not")
  let has_taint = doc.contains("taint")
  let has_inside_expr = doc.contains("inside-expr")
  let has_inside_toplevel = doc.contains("inside-toplevel")
  if has_taint && has_inside_expr {
    raise invalid_rule(
      path~,
      info="inside-expr is only supported for structural rules",
    )
  }
  if has_taint && has_inside_toplevel {
    raise invalid_rule(
      path~,
      info="inside-toplevel is only supported for structural rules",
    )
  }
  if has_inside_expr && has_inside_toplevel {
    raise invalid_rule(
      path~,
      info="inside-expr and inside-toplevel are mutually exclusive",
    )
  }
  if has_taint && has_patterns_not {
    raise invalid_rule(
      path~,
      info="patterns-not is only supported for structural rules",
    )
  }
  if has_taint && has_patterns {
    raise invalid_rule(
      path~,
      info="rule must contain exactly one of patterns or taint",
    )
  }
  if has_taint {
    Taint(expect_taint_rule(doc, path))
  } else if has_patterns ||
    has_patterns_not ||
    has_inside_expr ||
    has_inside_toplevel {
    Structural(expect_structural_rule(doc, path))
  } else {
    raise invalid_rule(
      path~,
      info="rule must contain patterns, patterns-not with inside-expr or inside-toplevel, or taint",
    )
  }
}

///|
fn expect_structural_rule(
  doc : Map[String, @yaml.Yaml],
  path : String,
) -> StructuralRuleSpec raise {
  let has_patterns = doc.contains("patterns")
  let has_patterns_not = doc.contains("patterns-not")
  let patterns = if doc.get("patterns") is Some(value) {
    parse_rule_clause_array(
      expect_yaml_array_value(value, path, "patterns"),
      path,
      "patterns",
      allow_guard=true,
      allow_match_mode=false,
    )
  } else {
    []
  }
  if has_patterns && patterns.is_empty() {
    raise invalid_rule(path~, info="patterns must not be empty")
  }
  let patterns_not = if doc.get("patterns-not") is Some(value) {
    parse_rule_clause_array(
      expect_yaml_array_value(value, path, "patterns-not"),
      path,
      "patterns-not",
      allow_guard=true,
      allow_match_mode=false,
    )
  } else {
    []
  }
  if has_patterns_not && patterns_not.is_empty() {
    raise invalid_rule(path~, info="patterns-not must not be empty")
  }
  let inside_expr = expect_inside_expr(doc, path)
  let inside_toplevel = expect_inside_toplevel(doc, path)
  if !has_patterns &&
    has_patterns_not &&
    inside_expr.is_empty() &&
    inside_toplevel.is_empty() {
    raise invalid_rule(
      path~,
      info="patterns-not requires patterns, inside-expr, or inside-toplevel",
    )
  }
  if !has_patterns && patterns_not.is_empty() && !inside_expr.is_empty() {
    raise invalid_rule(
      path~,
      info="inside-expr requires patterns or patterns-not",
    )
  }
  if !has_patterns && patterns_not.is_empty() && !inside_toplevel.is_empty() {
    raise invalid_rule(
      path~,
      info="inside-toplevel requires patterns or patterns-not",
    )
  }
  let patterns_not_mode = expect_patterns_not_mode(
    inside_expr, inside_toplevel, patterns, patterns_not,
  )
  { inside_expr, inside_toplevel, patterns, patterns_not, patterns_not_mode, }
}

///|
fn expect_patterns_not_mode(
  inside_expr : Array[RulePatternSpec],
  inside_toplevel : Array[RulePatternSpec],
  patterns : Array[RulePatternSpec],
  patterns_not : Array[RulePatternSpec],
) -> StructuralPatternsNotMode {
  if (!inside_expr.is_empty() || !inside_toplevel.is_empty()) &&
    !patterns.is_empty() &&
    !patterns_not.is_empty() {
    RejectUncoveredNegative
  } else {
    PruneOnNegative
  }
}

///|
fn expect_inside_expr(
  doc : Map[String, @yaml.Yaml],
  path : String,
) -> Array[RulePatternSpec] raise {
  if doc.get("inside-expr") is Some(value) {
    let patterns = parse_rule_clause_array(
      expect_yaml_array_value(value, path, "inside-expr"),
      path,
      "inside-expr",
      allow_guard=true,
      allow_match_mode=false,
    )
    if patterns.is_empty() {
      raise invalid_rule(path~, info="inside-expr must not be empty")
    }
    patterns
  } else {
    []
  }
}

///|
fn expect_inside_toplevel(
  doc : Map[String, @yaml.Yaml],
  path : String,
) -> Array[RulePatternSpec] raise {
  if doc.get("inside-toplevel") is Some(value) {
    let patterns = parse_rule_clause_array(
      expect_yaml_array_value(value, path, "inside-toplevel"),
      path,
      "inside-toplevel",
      allow_guard=true,
      allow_match_mode=true,
    )
    if patterns.is_empty() {
      raise invalid_rule(path~, info="inside-toplevel must not be empty")
    }
    patterns
  } else {
    []
  }
}

///|
fn expect_taint_rule(
  doc : Map[String, @yaml.Yaml],
  path : String,
) -> TaintRuleSpec raise {
  guard doc.get("taint") is Some(Map(taint_map)) else {
    raise invalid_rule(path~, info="taint must be a mapping")
  }
  ensure_allowed_keys(path, "taint", taint_map, [
    "sources", "sinks", "sanitizers",
  ])
  let sources = parse_rule_clause_array(
    expect_yaml_array(taint_map, path, "sources"),
    path,
    "taint.sources",
    allow_guard=false,
    allow_match_mode=false,
  )
  if sources.is_empty() {
    raise invalid_rule(path~, info="taint.sources must not be empty")
  }
  let sinks = parse_rule_clause_array(
    expect_yaml_array(taint_map, path, "sinks"),
    path,
    "taint.sinks",
    allow_guard=false,
    allow_match_mode=false,
  )
  if sinks.is_empty() {
    raise invalid_rule(path~, info="taint.sinks must not be empty")
  }
  let sanitizers = match taint_map.get("sanitizers") {
    None => []
    Some(Array(values)) =>
      parse_rule_clause_array(
        values,
        path,
        "taint.sanitizers",
        allow_guard=false,
        allow_match_mode=false,
      )
    Some(_) => raise invalid_rule(path~, info="sanitizers must be an array")
  }
  { sources, sinks, sanitizers, }
}

///|
fn parse_rule_clause_array(
  clauses_yaml : Array[@yaml.Yaml],
  path : String,
  context : String,
  allow_guard~ : Bool,
  allow_match_mode~ : Bool,
) -> Array[RulePatternSpec] raise {
  let clauses : Array[RulePatternSpec] = []
  for index in 0..<clauses_yaml.length() {
    let clause_context = "\{context}[\{index}]"
    guard clauses_yaml[index] is Map(clause_map) else {
      raise invalid_rule(path~, info="\{clause_context} must be a mapping")
    }
    // `match-mode` belongs only to `inside-toplevel` pattern objects. Keep
    // this distinction at schema decoding time so later compilation can
    // resolve `Default` independently for each alternative.
    clauses.push(
      parse_rule_clause_map(
        clause_map,
        path,
        clause_context,
        allow_guard~,
        allow_match_mode~,
      ),
    )
  }
  clauses
}

///|
fn parse_rule_clause_map(
  clause_map : Map[String, @yaml.Yaml],
  path : String,
  clause_context : String,
  allow_guard~ : Bool,
  allow_match_mode~ : Bool,
) -> RulePatternSpec raise {
  let allowed_keys = if allow_match_mode {
    ["shape", "guard", "match-mode"]
  } else {
    ["shape", "guard"]
  }
  ensure_allowed_keys(path, clause_context, clause_map, allowed_keys)
  if clause_map.contains("guard") && !allow_guard {
    raise invalid_rule(
      path~,
      info="\{clause_context}.guard is not supported for taint rules",
    )
  }
  let shape = expect_rule_clause_shape(clause_map, path, clause_context)
  let guards = parse_guard_map(clause_map, path, clause_context)
  let match_mode = parse_inside_toplevel_match_mode(
    clause_map, path, clause_context,
  )
  { shape, guards, match_mode, }
}

///|
fn parse_inside_toplevel_match_mode(
  clause_map : Map[String, @yaml.Yaml],
  path : String,
  clause_context : String,
) -> InsideToplevelMatchMode raise {
  match clause_map.get("match-mode") {
    None => Default
    Some(String("exact")) => Exact
    Some(String("partial")) => Partial
    Some(String(_)) =>
      raise invalid_rule(
        path~,
        info="\{clause_context}.match-mode must be exact or partial",
      )
    Some(_) =>
      raise invalid_rule(
        path~,
        info="\{clause_context}.match-mode must be a string",
      )
  }
}

///|
fn parse_guard_map(
  clause_map : Map[String, @yaml.Yaml],
  path : String,
  clause_context : String,
) -> Map[String, String] raise {
  match clause_map.get("guard") {
    None => Map([])
    Some(Map(guard_map)) => {
      let guards : Map[String, String] = Map([])
      for key, value in guard_map {
        ensure_guard_key(key, path, clause_context)
        match value {
          String(regex_source) => guards[key] = regex_source
          _ =>
            raise invalid_rule(
              path~,
              info="\{clause_context}.guard.\{key} must be a string",
            )
        }
      }
      guards
    }
    Some(_) =>
      raise invalid_rule(
        path~,
        info="\{clause_context}.guard must be a mapping",
      )
  }
}

///|
fn ensure_guard_key(
  key : String,
  path : String,
  clause_context : String,
) -> Unit raise {
  if !key.has_prefix("$") || key.length() <= 1 {
    raise invalid_rule(
      path~,
      info="\{clause_context}.guard.\{key} must be a $-prefixed metavar name",
    )
  }
}

///|
fn expect_rule_clause_shape(
  map : Map[String, @yaml.Yaml],
  path : String,
  clause_context : String,
) -> String raise {
  match map.get("shape") {
    Some(String(value)) => value
    Some(_) =>
      raise invalid_rule(path~, info="\{clause_context}.shape must be a string")
    None =>
      raise invalid_rule(
        path~,
        info="missing required key \{clause_context}.shape",
      )
  }
}

///|
fn ensure_allowed_keys(
  path : String,
  context : String,
  map : Map[String, @yaml.Yaml],
  allowed : Array[String],
) -> Unit raise {
  for key, _value in map {
    if !array_contains(allowed, key) {
      raise invalid_rule(
        path~,
        info="\{context} contains unsupported key \{key}",
      )
    }
  }
}

///|
fn expect_yaml_string(
  map : Map[String, @yaml.Yaml],
  path : String,
  key : String,
) -> String raise {
  match map.get(key) {
    Some(String(value)) => value
    Some(_) => raise invalid_rule(path~, info="\{key} must be a string")
    None => raise invalid_rule(path~, info="missing required key \{key}")
  }
}

///|
fn expect_rule_id(map : Map[String, @yaml.Yaml], path : String) -> String raise {
  let id = expect_yaml_string(map, path, "id")
  if id.length() == 0 {
    raise invalid_rule(path~, info="id must not be empty")
  }
  if id.contains("/") {
    raise invalid_rule(path~, info="id must not contain /")
  }
  id
}

///|
fn expect_yaml_array(
  map : Map[String, @yaml.Yaml],
  path : String,
  key : String,
) -> Array[@yaml.Yaml] raise {
  if map.get(key) is Some(value) {
    expect_yaml_array_value(value, path, key)
  } else {
    raise invalid_rule(path~, info="missing required key \{key}")
  }
}

///|
fn expect_yaml_array_value(
  value : @yaml.Yaml,
  path : String,
  key : String,
) -> Array[@yaml.Yaml] raise {
  match value {
    Array(values) => values
    _ => raise invalid_rule(path~, info="\{key} must be an array")
  }
}

///|
fn rule_id_from_path(
  path : String,
  rules_root : String,
  id : String,
) -> String raise {
  if @path.sep == '\\' {
    return windows_rule_id_from_path(path, rules_root, id)
  }
  let relative = if rules_root == "" {
    path
  } else {
    let prefix = "\{rules_root}/"
    if !path.has_prefix(prefix) {
      raise invalid_rule(
        path~,
        info="rule path is outside rules root \{rules_root}",
      )
    }
    path[prefix.length():].to_owned()
  }
  let relative_without_suffix = if relative.has_suffix(".yaml") {
    relative[0:relative.length() - 5].to_owned()
  } else if relative.has_suffix(".yml") {
    relative[0:relative.length() - 4].to_owned()
  } else {
    raise invalid_rule(path~, info="unsupported rule file suffix")
  }
  match relative_without_suffix.rev_split_once("/") {
    None => id
    Some((directory, _file_stem)) => "\{directory.to_owned()}/\{id}"
  }
}

///|
fn windows_rule_id_from_path(
  path : String,
  rules_root : String,
  id : String,
) -> String raise {
  let relative = @path.Path::relative(path, base=rules_root).to_string()
  if @path.Path::is_absolute(relative) ||
    relative == ".." ||
    relative.has_prefix("..\\") {
    raise invalid_rule(
      path~,
      info="rule path is outside rules root \{rules_root}",
    )
  }
  let relative_without_suffix = if relative.has_suffix(".yaml") {
    relative[0:relative.length() - 5].to_owned()
  } else if relative.has_suffix(".yml") {
    relative[0:relative.length() - 4].to_owned()
  } else {
    raise invalid_rule(path~, info="unsupported rule file suffix")
  }
  match relative_without_suffix.rev_split_once("\\") {
    None => id
    Some((directory, _file_stem)) =>
      "\{directory.to_owned().replace_all(old="\\", new="/")}/\{id}"
  }
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
