///|
using @compile {compile_rules}

///|
fn parse_single_taint_impl(source : String) -> @syntax.Impl raise {
  let (impls, reports) = @parser.parse_string(
    source,
    name="taint lowering test",
  )
  guard reports is [] else { fail("expected source to parse") }
  let nodes = impls.to_array()
  guard nodes is [node] else { fail("expected exactly one impl") }
  node
}

///|
fn compile_single_taint_rule(
  source : String,
) -> (CompiledRule, CompiledTaintRule) raise {
  let rules = compile_rules([
    @model.RawRuleSpec::from_str(
      "/tmp/rules/example.yaml", "/tmp/rules", source,
    ),
  ])
  guard rules is [rule] else { fail("expected one compiled rule") }
  match rule.definition {
    Taint(taint_rule) => (rule, taint_rule)
    Structural(_) => fail("expected taint rule")
  }
}

///|
test "taint lowering preserves internal source and sink ids" {
  let rule_source =
    #|id: example
    #|description: |
    #|  User input reaches sink.
    #|taint:
    #|  sources:
    #|    - shape: get_user_input()
    #|  sinks:
    #|    - shape: sink(__SOURCE__)
    #|
  let source =
    #|fn sample {
    #|  let x = get_user_input();
    #|  sink(x)
    #|}
    #|
  let (rule, taint_rule) = compile_single_taint_rule(rule_source)
  let result = @taint.analyze_function_like(
    parse_single_taint_impl(source),
    lower_compiled_taint_rule(rule, taint_rule),
  )
  assert_eq(result.findings.length(), 1)
  inspect(result.findings[0].sink_id, content="sink:0")
  inspect(result.findings[0].origins[0].origin_id, content="source:0")
}
