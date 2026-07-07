///|
using @model {type RawRuleSpec, type RuleLoadError}

///|
/// Loads all YAML rule files below `rules_root`.
///
/// Files are discovered recursively, sorted for deterministic output, and
/// parsed as raw specs. An empty rule directory is treated as a rule-load error.
pub async fn load_rules(rules_root : String) -> Array[RawRuleSpec] {
  let files = collect_rule_files(rules_root)
  if files.is_empty() {
    raise RuleLoadError::InvalidRule(
      path=rules_root,
      info="no YAML rule files found",
    )
  }
  let rules : Array[RawRuleSpec] = []
  for file in files {
    let source = read_text_file(file)
    rules.push(@model.RawRuleSpec::from_str(file, rules_root, source))
  }
  rules
}

///|
/// Loads exactly one YAML rule file.
pub async fn load_rule(rule_file : String) -> RawRuleSpec {
  let source = read_text_file(rule_file)
  @model.RawRuleSpec::from_str(
    rule_file,
    rule_file_rules_root(rule_file),
    source,
  )
}

///|
fn rule_file_rules_root(rule_file : String) -> String {
  match rule_file.rev_split_once("/") {
    Some((directory, _file_name)) => directory.to_owned()
    None => ""
  }
}

///|
async fn collect_rule_files(rules_root : String) -> Array[String] {
  let files : Array[String] = []
  walk_rule_dir(rules_root, files)
  files.sort()
  files
}

///|
async fn walk_rule_dir(dir : String, files : Array[String]) -> Unit {
  let entries = @fs.readdir(dir, sort=true)
  for entry in entries {
    let path = "\{dir}/\{entry}"
    match @fs.kind(path) {
      Directory => walk_rule_dir(path, files)
      Regular => if has_yaml_suffix(path) { files.push(path) }
      _ => ()
    }
  }
}

///|
async fn read_text_file(path : String) -> String {
  @fs.read_file(path).text()
}

///|
fn has_yaml_suffix(path : String) -> Bool {
  path.has_suffix(".yaml") || path.has_suffix(".yml")
}
