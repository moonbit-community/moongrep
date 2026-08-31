///|
async fn prepare_scan_rules(
  mode : ScanMode,
  options : CliOptions,
) -> Array[@rule_model.CompiledRule] {
  let builtin_rules = load_builtin_scan_rules(mode)
  let raw_rules = builtin_rules.copy()
  raw_rules.append(load_scan_rules(options))
  let enabled_rules = disable_scan_rules(raw_rules, options.disabled_rules)
  @rule_compile.compile_rules(enabled_rules) catch {
    @rule_model.RuleLoadError::InvalidPattern(..) as err =>
      raise new_compiled_rule_error(err, options.patterns)
    @rule_model.RuleLoadError::InvalidRule(..) as err =>
      raise new_compiled_rule_error(err, options.patterns)
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
  ignore(
    @rule_compile.compile_rules(rules) catch {
      err => raise new_internal_error("builtin rule compilation failed: \{err}")
    },
  )
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
  disabled_rules : Array[String],
) -> Array[@rule_model.RawRuleSpec] raise {
  if disabled_rules.is_empty() {
    return raw_rules
  }
  ensure_disabled_rule_ids_exist(raw_rules, disabled_rules)
  let disabled : Map[String, Bool] = Map([])
  for rule_id in disabled_rules {
    disabled[rule_id] = true
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
fn ensure_disabled_rule_ids_exist(
  raw_rules : Array[@rule_model.RawRuleSpec],
  disabled_rules : Array[String],
) -> Unit raise {
  let loaded : Map[String, Bool] = Map([])
  for raw in raw_rules {
    loaded[raw.rule_id] = true
  }
  for rule_id in disabled_rules {
    if !loaded.contains(rule_id) {
      raise new_unknown_disabled_rule_error(rule_id)
    }
  }
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
