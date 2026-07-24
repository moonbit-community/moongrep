///|
using @model {type RawRuleSpec}

///|
/// Loads embedded builtin rules.
pub fn load_rules() -> Array[RawRuleSpec] raise {
  let rules : Array[RawRuleSpec] = []
  for source in builtin_rule_sources() {
    rules.push(
      @model.RawRuleSpec::from_str(source.path, builtin_rules_root, source.yaml),
    )
  }
  rules
}

///|
priv struct BuiltinRuleSource {
  path : String
  yaml : String
}

///|
let builtin_rules_root : String = "builtin"

///|
fn builtin_rule_sources() -> Array[BuiltinRuleSource] {
  [
    {
      path: "builtin/moonbitlang/catch_all.yaml",
      yaml: @moonbitlang_rules.catch_all_yaml,
    },
    {
      path: "builtin/moonbitlang/inspect_boolean.yaml",
      yaml: @moonbitlang_rules.inspect_boolean_yaml,
    },
    {
      path: "builtin/moonbitlang/inspect_number.yaml",
      yaml: @moonbitlang_rules.inspect_number_yaml,
    },
    {
      path: "builtin/moonbitlang/match_option.yaml",
      yaml: @moonbitlang_rules.match_option_yaml,
    },
    {
      path: "builtin/moonbitlang/unnessary_else.yaml",
      yaml: @moonbitlang_rules.unnessary_else_yaml,
    },
    {
      path: "builtin/moonbitlang/cstyle_forward_simple_forloop.yaml",
      yaml: @moonbitlang_rules.cstyle_forward_simple_forloop_yaml,
    },
    {
      path: "builtin/moonbitlang/cstyle_backward_simple_forloop.yaml",
      yaml: @moonbitlang_rules.cstyle_backward_simple_forloop_yaml,
    },
    {
      path: "builtin/moonbitlang/cstyle_forward_array_iteration.yaml",
      yaml: @moonbitlang_rules.cstyle_forward_array_iteration_yaml,
    },
    {
      path: "builtin/moonbitlang/cstyle_backward_array_iteration.yaml",
      yaml: @moonbitlang_rules.cstyle_backward_array_iteration_yaml,
    },
  ]
}
