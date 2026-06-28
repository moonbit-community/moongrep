///|
test "builtin rules load moonbitlang rules" {
  let rules = @builtin.load_rules()
  let ids : Array[String] = []
  for rule in rules {
    ids.push(rule.rule_id)
  }
  debug_inspect(
    ids,
    content=(
      #|[
      #|  "moonbitlang/catch_all",
      #|  "moonbitlang/inspect_boolean",
      #|  "moonbitlang/inspect_number",
      #|  "moonbitlang/match_option",
      #|]
    ),
  )
}
