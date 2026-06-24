///|
using @model {type RawRuleSpec, type RuleLoadError}

///|
/// Loads all YAML rule files below `rules_root`.
///
/// Files are discovered recursively, sorted for deterministic output, and
/// parsed as raw specs. An empty rule directory is treated as a rule-load error.
pub fn load_rules(rules_root : String) -> Array[RawRuleSpec] raise {
  let files = collect_rule_files(rules_root)
  if files.is_empty() {
    raise RuleLoadError::InvalidRule(
      path=rules_root,
      info="no YAML rule files found",
    )
  }
  let rules : Array[RawRuleSpec] = []
  for file in files {
    let source = @miniio.read_text_file(file)
    rules.push(@model.RawRuleSpec::from_str(file, rules_root, source))
  }
  rules
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
  let entries = @miniio.readdir(dir, sort=true, follow_symlink=true)
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
