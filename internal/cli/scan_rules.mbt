///|
async fn prepare_scan_rules(
  mode : ScanMode,
  options : CliOptions,
) -> Array[@rule_model.CompiledRule] {
  let builtin_rules = load_builtin_scan_rules(mode)
  let raw_rules = builtin_rules.copy()
  raw_rules.append(load_scan_rules(options))
  compile_scan_rules(
    builtin_rules,
    raw_rules,
    options.disabled_rules,
    options.patterns,
  )
}

///|
fn compile_scan_rules(
  builtin_rules : Array[@rule_model.RawRuleSpec],
  raw_rules : Array[@rule_model.RawRuleSpec],
  disabled_rules : Array[String],
  patterns : Array[@rule_model.RulePatternSpec],
) -> Array[@rule_model.CompiledRule] raise {
  let disabled = resolve_disabled_scan_rule_ids(raw_rules, disabled_rules)
  let enabled_builtin_rules = disable_scan_rules(builtin_rules, disabled)
  ignore(
    @rule_compile.compile_rules(enabled_builtin_rules) catch {
      err => raise new_internal_error("builtin rule compilation failed: \{err}")
    },
  )
  let enabled_rules = disable_scan_rules(raw_rules, disabled)
  @rule_compile.compile_rules(enabled_rules) catch {
    @rule_model.RuleLoadError::InvalidPattern(..) as err =>
      raise new_compiled_rule_error(err, patterns)
    @rule_model.RuleLoadError::InvalidRule(..) as err =>
      raise new_compiled_rule_error(err, patterns)
    @rule_model.RuleLoadError::NoRuleFiles(..) as err =>
      raise new_rule_load_error(err)
    err => raise new_internal_error("rule compilation failed: \{err}")
  }
}

///|
fn load_builtin_scan_rules(
  mode : ScanMode,
) -> Array[@rule_model.RawRuleSpec] raise {
  if mode is Scan {
    return []
  }
  let rules = @rule_builtin.load_rules() catch {
    err => raise new_internal_error("could not load builtin rules: \{err}")
  }
  rules
}

///|
async fn load_scan_rules(
  options : CliOptions,
) -> Array[@rule_model.RawRuleSpec] {
  let raw_rules : Array[@rule_model.RawRuleSpec] = []
  if options.rules_root is Some(rules_root) {
    raw_rules.append(load_rule_directory(rules_root))
  }
  if options.rule_file is Some(rule_file) {
    raw_rules.push(load_rule_file(rule_file))
  }
  for index in 0..<options.patterns.length() {
    raw_rules.push(anonymous_pattern_rule(options.patterns[index], index))
  }
  raw_rules
}

///|
async fn load_rule_directory(
  rules_root : String,
) -> Array[@rule_model.RawRuleSpec] {
  @rule_load.load_rules(rules_root) catch {
    @rule_model.RuleLoadError::NoRuleFiles(..) as err =>
      raise new_rule_load_error(err)
    @rule_model.RuleLoadError::InvalidPattern(..) as err =>
      raise new_rule_load_error(err)
    @rule_model.RuleLoadError::InvalidRule(..) as err =>
      raise new_rule_load_error(err)
    @os_error.OSError(_) as err =>
      raise new_rule_source_os_error(rules_root, "read rule directory", err)
    err =>
      raise new_internal_error(
        "could not load rule directory \{rules_root}: \{err}",
      )
  }
}

///|
async fn load_rule_file(rule_file : String) -> @rule_model.RawRuleSpec {
  @rule_load.load_rule(rule_file) catch {
    @rule_model.RuleLoadError::NoRuleFiles(..) as err =>
      raise new_rule_load_error(err)
    @rule_model.RuleLoadError::InvalidPattern(..) as err =>
      raise new_rule_load_error(err)
    @rule_model.RuleLoadError::InvalidRule(..) as err =>
      raise new_rule_load_error(err)
    @os_error.OSError(_) as err =>
      raise new_rule_source_os_error(rule_file, "read rule file", err)
    err =>
      raise new_internal_error("could not load rule file \{rule_file}: \{err}")
  }
}

///|
fn disable_scan_rules(
  raw_rules : Array[@rule_model.RawRuleSpec],
  disabled : Map[String, Bool],
) -> Array[@rule_model.RawRuleSpec] {
  if disabled.is_empty() {
    return raw_rules
  }
  let enabled : Array[@rule_model.RawRuleSpec] = []
  for raw in raw_rules {
    if !disabled.contains(raw.rule_id) {
      enabled.push(raw)
    }
  }
  enabled
}

///|
fn resolve_disabled_scan_rule_ids(
  raw_rules : Array[@rule_model.RawRuleSpec],
  disabled_rules : Array[String],
) -> Map[String, Bool] raise {
  let loaded : Map[String, Bool] = Map([])
  for raw in raw_rules {
    loaded[raw.rule_id] = true
  }
  let disabled : Map[String, Bool] = Map([])
  for requested_rule_id in disabled_rules {
    match resolve_disabled_rule_id(loaded, requested_rule_id) {
      Some(rule_id) => disabled[rule_id] = true
      None => raise new_unknown_disabled_rule_error(requested_rule_id)
    }
  }
  disabled
}

///|
let legacy_unnecessary_else_rule_id : String = "moonbitlang/unnessary_else"

///|
let unnecessary_else_rule_id : String = "moonbitlang/unnecessary_else"

///|
fn resolve_disabled_rule_id(
  loaded : Map[String, Bool],
  requested_rule_id : String,
) -> String? {
  if loaded.contains(requested_rule_id) {
    return Some(requested_rule_id)
  }
  if requested_rule_id == legacy_unnecessary_else_rule_id &&
    loaded.contains(unnecessary_else_rule_id) {
    return Some(unnecessary_else_rule_id)
  }
  None
}

///|
fn anonymous_pattern_rule(
  pattern : @rule_model.RulePatternSpec,
  _index : Int,
) -> @rule_model.RawRuleSpec {
  {
    path: pattern.shape,
    rule_id: pattern.shape,
    description: "Anonymous CLI pattern.",
    definition: Structural({
      inside_expr: [],
      inside_toplevel: [],
      patterns: [pattern],
      patterns_not: [],
      patterns_not_mode: PruneOnNegative,
    }),
  }
}
