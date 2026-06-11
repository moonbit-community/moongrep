///|
fn invalid_rule(path~ : String, info~ : String) -> RuleLoadError {
  RuleLoadError::InvalidRule(path~, info~)
}

///|
pub fn load_rules(rules_root : String) -> Array[RawRuleSpec] raise {
  let files = collect_rule_files(rules_root)
  if files.is_empty() {
    raise invalid_rule(path=rules_root, info="no YAML rule files found")
  }
  let rules : Array[RawRuleSpec] = []
  for file in files {
    let source = @miniio.read_text_file(file)
    rules.push(parse_rule_source(file, rules_root, source))
  }
  rules
}

///|
pub fn parse_rule_source(
  path : String,
  rules_root : String,
  source : String,
) -> RawRuleSpec raise {
  let docs = @yaml.Yaml::load_from_string(source)
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
    "package", "description", "patterns", "inside-expr", "taint",
  ])
  let package_name = expect_yaml_string(doc, path, "package")
  let description = expect_yaml_string(doc, path, "description")
  let definition = expect_rule_definition(doc, path)
  {
    path,
    rule_id: rule_id_from_path(path, rules_root),
    package_name,
    description,
    definition,
  }
}

///|
fn collect_rule_files(rules_root : String) -> Array[String] raise {
  let files : Array[String] = []
  walk_rule_dir(rules_root, files)
  files.sort()
  files
}

///|
fn walk_rule_dir(dir : String, files : Array[String]) -> Unit raise {
  let entries = @miniio.readdir(dir)
  entries.sort()
  for entry in entries {
    let path = "\{dir}/\{entry}"
    if @miniio.is_dir(path) {
      walk_rule_dir(path, files)
    } else if has_yaml_suffix(path) {
      files.push(path)
    }
  }
}

///|
fn has_yaml_suffix(path : String) -> Bool {
  path.has_suffix(".yaml") || path.has_suffix(".yml")
}

///|
fn expect_rule_definition(
  doc : Map[String, @yaml.Yaml],
  path : String,
) -> RuleDefinitionSpec raise {
  let has_patterns = doc.contains("patterns")
  let has_taint = doc.contains("taint")
  let has_inside_expr = doc.contains("inside-expr")
  if has_taint && has_inside_expr {
    raise invalid_rule(
      path~,
      info="inside-expr is only supported for structural rules",
    )
  }
  if has_patterns == has_taint {
    raise invalid_rule(
      path~,
      info="rule must contain exactly one of patterns or taint",
    )
  }
  if has_patterns {
    Structural(expect_structural_rule(doc, path))
  } else {
    Taint(expect_taint_rule(doc, path))
  }
}

///|
fn expect_structural_rule(
  doc : Map[String, @yaml.Yaml],
  path : String,
) -> StructuralRuleSpec raise {
  let patterns = parse_rule_clause_array(
    expect_yaml_array(doc, path, "patterns"),
    path,
    "patterns",
  )
  if patterns.is_empty() {
    raise invalid_rule(path~, info="patterns must not be empty")
  }
  let inside_expr = expect_inside_expr(doc, path)
  { inside_expr, patterns }
}

///|
fn expect_inside_expr(
  doc : Map[String, @yaml.Yaml],
  path : String,
) -> RulePatternSpec? raise {
  match doc.get("inside-expr") {
    None => None
    Some(Map(clause_map)) =>
      Some(parse_rule_clause_map(clause_map, path, "inside-expr"))
    Some(_) => raise invalid_rule(path~, info="inside-expr must be a mapping")
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
  )
  if sources.is_empty() {
    raise invalid_rule(path~, info="taint.sources must not be empty")
  }
  let sinks = parse_rule_clause_array(
    expect_yaml_array(taint_map, path, "sinks"),
    path,
    "taint.sinks",
  )
  if sinks.is_empty() {
    raise invalid_rule(path~, info="taint.sinks must not be empty")
  }
  let sanitizers = match taint_map.get("sanitizers") {
    None => []
    Some(Array(values)) =>
      parse_rule_clause_array(values, path, "taint.sanitizers")
    Some(_) => raise invalid_rule(path~, info="sanitizers must be an array")
  }
  { sources, sinks, sanitizers }
}

///|
fn parse_rule_clause_array(
  clauses_yaml : Array[@yaml.Yaml],
  path : String,
  context : String,
) -> Array[RulePatternSpec] raise {
  let clauses : Array[RulePatternSpec] = []
  for index in 0..<clauses_yaml.length() {
    let clause_context = "\{context}[\{index}]"
    guard clauses_yaml[index] is Map(clause_map) else {
      raise invalid_rule(path~, info="\{clause_context} must be a mapping")
    }
    clauses.push(parse_rule_clause_map(clause_map, path, clause_context))
  }
  clauses
}

///|
fn parse_rule_clause_map(
  clause_map : Map[String, @yaml.Yaml],
  path : String,
  clause_context : String,
) -> RulePatternSpec raise {
  ensure_allowed_keys(path, clause_context, clause_map, [
    "shape", "metavars", "guard",
  ])
  if clause_map.contains("guard") {
    raise invalid_rule(
      path~,
      info="\{clause_context}.guard is not supported in runtime AST mode",
    )
  }
  let shape = expect_yaml_string(clause_map, path, "shape")
  let (subtree_metavars, identifier_metavars) = expect_metavars(
    clause_map, path, clause_context,
  )
  { shape, subtree_metavars, identifier_metavars }
}

///|
fn expect_metavars(
  map : Map[String, @yaml.Yaml],
  path : String,
  clause_context : String,
) -> (Array[String], Array[String]) raise {
  match map.get("metavars") {
    Some(Map(meta_map)) => {
      ensure_allowed_keys(path, "\{clause_context}.metavars", meta_map, [
        "subtree", "identifier",
      ])
      let subtree = expect_metavar_bucket(
        meta_map, path, clause_context, "subtree",
      )
      let identifier = expect_metavar_bucket(
        meta_map, path, clause_context, "identifier",
      )
      ensure_metavar_buckets_disjoint(path, clause_context, subtree, identifier)
      (subtree, identifier)
    }
    Some(_) =>
      raise invalid_rule(
        path~,
        info="\{clause_context}.metavars must be a mapping",
      )
    None => ([], [])
  }
}

///|
fn expect_metavar_bucket(
  map : Map[String, @yaml.Yaml],
  path : String,
  clause_context : String,
  bucket : String,
) -> Array[String] raise {
  match map.get(bucket) {
    None => []
    Some(Array(values)) => {
      let metavars : Array[String] = []
      for index in 0..<values.length() {
        guard values[index] is String(meta_name) else {
          raise invalid_rule(
            path~,
            info="\{clause_context}.metavars.\{bucket}[\{index}] must be a string",
          )
        }
        if array_contains(metavars, meta_name) {
          raise invalid_rule(
            path~,
            info="\{clause_context}.metavars.\{bucket} contains duplicate metavar \{meta_name}",
          )
        }
        metavars.push(meta_name)
      }
      metavars
    }
    Some(_) =>
      raise invalid_rule(
        path~,
        info="\{clause_context}.metavars.\{bucket} must be an array",
      )
  }
}

///|
fn ensure_metavar_buckets_disjoint(
  path : String,
  clause_context : String,
  subtree : Array[String],
  identifier : Array[String],
) -> Unit raise {
  for name in identifier {
    if array_contains(subtree, name) {
      raise invalid_rule(
        path~,
        info="\{clause_context}.metavars contains duplicate metavar \{name}",
      )
    }
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
fn expect_yaml_array(
  map : Map[String, @yaml.Yaml],
  path : String,
  key : String,
) -> Array[@yaml.Yaml] raise {
  match map.get(key) {
    Some(Array(values)) => values
    Some(_) => raise invalid_rule(path~, info="\{key} must be an array")
    None => raise invalid_rule(path~, info="missing required key \{key}")
  }
}

///|
fn rule_id_from_path(path : String, rules_root : String) -> String raise {
  let prefix = "\{rules_root}/"
  if !path.has_prefix(prefix) {
    raise invalid_rule(
      path~,
      info="rule path is outside rules root \{rules_root}",
    )
  }
  let relative = path[prefix.length():].to_owned()
  if relative.has_suffix(".yaml") {
    relative[0:relative.length() - 5].to_owned()
  } else if relative.has_suffix(".yml") {
    relative[0:relative.length() - 4].to_owned()
  } else {
    raise invalid_rule(path~, info="unsupported rule file suffix")
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
