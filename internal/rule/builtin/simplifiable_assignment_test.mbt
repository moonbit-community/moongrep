///|
fn simplifiable_assignment_matches(source : String) -> Array[String] raise {
  let parsed = @untyped_cst.parse_structure(
    source,
    name="simplifiable_assignment test",
  )
  assert_true(parsed.diagnostics_view().is_empty(), msg=source)
  let rules = @builtin.load_rules().filter(rule => {
    rule.rule_id == "moonbitlang/simplifiable_assignment"
  })
  let plan = @apply.ScanPlan::from_rules(@compile.compile_rules(rules))
  @apply.apply_structural_scan_plan_to_node(
    "sample.mbt",
    parsed.root(),
    plan.filter_source(source[:]),
  ).map(finding => "\{finding.pattern_index}@\{finding.loc.start.lnum}")
}

///|
test "builtin simplifiable_assignment preserves string concatenation order" {
  let source =
    #|struct TextTarget {
    #|  mut text : String
    #|}
    #|
    #|fn sample(target : TextTarget, values : Array[String]) -> Unit {
    #|  let mut s = "world"
    #|  s = "hello " + s
    #|  s = s + "!"
    #|  target.text = "hello " + target.text
    #|  target.text = target.text + "!"
    #|  values[0] = "hello " + values[0]
    #|  values[0] = values[0] + "!"
    #|}
    #|
  inspect(
    simplifiable_assignment_matches(source).join(","),
    content="0@8,1@10,2@12",
  )
}

///|
test "builtin simplifiable_assignment excludes reversed overloaded multiplication" {
  let source =
    #|struct Word {
    #|  value : String
    #|}
    #|
    #|impl Mul for Word with fn mul(self, other) {
    #|  { value: self.value + other.value }
    #|}
    #|
    #|fn sample {
    #|  let prefix : Word = { value: "left" }
    #|  let mut word : Word = { value: "right" }
    #|  word = prefix * word
    #|}
    #|
  debug_inspect(simplifiable_assignment_matches(source), content="[]")
}

///|
test "builtin simplifiable_assignment excludes reversed effectful integer addition" {
  let source =
    #|fn sample {
    #|  let mut value = 10
    #|  let other = fn() {
    #|    value = 20
    #|    1
    #|  }
    #|  value = other() + value
    #|}
    #|
  debug_inspect(simplifiable_assignment_matches(source), content="[]")
}
