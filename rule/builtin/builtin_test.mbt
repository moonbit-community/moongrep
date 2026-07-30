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
      #|  "moonbitlang/unnessary_else",
      #|  "moonbitlang/simplifiable_assignment",
      #|  "moonbitlang/cstyle_forward_simple_forloop",
      #|  "moonbitlang/cstyle_backward_simple_forloop",
      #|  "moonbitlang/cstyle_forward_array_iteration",
      #|  "moonbitlang/cstyle_backward_array_iteration",
      #|]
    ),
  )
}

///|
test "builtin catch_all matches async function signature variants" {
  let source =
    #|async fn no_parameters {
    #|  try risky() catch { _ => () }
    #|}
    #|
    #|async fn varied_parameters(
    #|  positional : Int,
    #|  labelled~ : String,
    #|  optional? : Bool = false,
    #|) {
    #|  try risky() catch { error => () }
    #|}
    #|
    #|async fn no_parameters_with_return -> Array[Int] {
    #|  try risky() catch { _ => [] }
    #|}
    #|
    #|async fn parameters_with_return(_, value : Int) -> Int {
    #|  try risky() catch { error => value }
    #|}
    #|
    #|async fn no_parameters_noraise noraise {
    #|  try risky() catch { _ => () }
    #|}
    #|
    #|async fn parameters_with_return_noraise(value : Int) -> Int noraise {
    #|  try risky() catch { error => value }
    #|}
    #|
    #|pub async fn public_no_parameters {
    #|  try risky() catch { _ => () }
    #|}
    #|
    #|pub async fn public_parameters_with_return(value : Int) -> Int {
    #|  try risky() catch { error => value }
    #|}
    #|
    #|pub async fn public_noraise(value : Int) noraise {
    #|  try risky() catch { _ => () }
    #|}
    #|
    #|priv async fn private_no_parameters -> Unit {
    #|  try risky() catch { error => () }
    #|}
    #|
    #|priv async fn private_parameters(value : Int) {
    #|  try risky() catch { _ => () }
    #|}
    #|
    #|priv async fn private_noraise -> Unit noraise {
    #|  try risky() catch { error => () }
    #|}
    #|
    #|/// Qualified generic function.
    #|#custom.attribute
    #|priv async fn[T] Box::qualified(value : T) -> T {
    #|  try risky() catch { error => value }
    #|}
    #|
    #|fn synchronous_function(value : Int) -> Int {
    #|  try risky() catch { _ => value }
    #|}
    #|
  let (impls, reports) = @parser.parse_string(source, name="catch_all test")
  guard reports is [] else { fail("expected source to parse") }
  let plan = @apply.ScanPlan::from_rules(
    @compile.compile_rules(@builtin.load_rules()),
  )
  let findings = @apply.apply_structural_scan_plan_to_node(
    "sample.mbt",
    @untyped_ast.from_impls(impls),
    plan,
  )
  assert_eq(findings.length(), 13)
  for finding in findings {
    assert_eq(finding.rule_id, "moonbitlang/catch_all")
  }
}

///|
test "builtin simplifiable_assignment matches supported augmented assignment operators" {
  let source =
    #|fn sample(step : Int) -> Unit {
    #|  let mut add = 0
    #|  add = add + step
    #|  let mut subtract = 0
    #|  subtract = subtract - step
    #|  let mut multiply = 1
    #|  multiply = multiply * step
    #|  let mut divide = 1
    #|  divide = divide / step
    #|  let mut remainder = 1
    #|  remainder = remainder % step
    #|  let mut different = 0
    #|  different = add + step
    #|  let mut reversed = 0
    #|  reversed = step - reversed
    #|  add += step
    #|}
    #|
  let (impls, reports) = @parser.parse_string(
    source,
    name="simplifiable_assignment test",
  )
  guard reports is [] else { fail("expected source to parse") }
  let plan = @apply.ScanPlan::from_rules(
    @compile.compile_rules(@builtin.load_rules()),
  )
  let findings = @apply.apply_structural_scan_plan_to_node(
    "sample.mbt",
    @untyped_ast.from_impls(impls),
    plan,
  )
  let matches : Array[String] = []
  for finding in findings {
    if finding.rule_id == "moonbitlang/simplifiable_assignment" {
      matches.push("\{finding.pattern_index}@\{finding.loc.start.lnum}")
    }
  }
  inspect(matches.join(","), content="0@3,6@5,9@7,15@9")
}
