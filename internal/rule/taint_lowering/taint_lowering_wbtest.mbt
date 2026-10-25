///|
using @compile {compile_rules}

///|
fn parse_single_taint_impl(source : String) -> @untyped_cst.CstNode raise {
  let parsed = @untyped_cst.parse_structure(source, name="taint lowering test")
  guard parsed.diagnostics_view().is_empty() else {
    fail("expected source to parse")
  }
  let nodes = @cst.toplevel_nodes(parsed.root())
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
  let spec = lower_compiled_taint_rule(rule, taint_rule)
  guard @taint.prepare_function_like(parse_single_taint_impl(source))
    is Prepared(graph) else {
    fail("expected CFG")
  }
  guard @taint.analyze(graph, spec) is Complete(findings) else {
    fail("expected complete analysis")
  }
  assert_eq(findings.length(), 1)
  assert_eq(findings[0].sink_id, PatternIndex(0))
  let sink_loc = findings[0].sink_loc
  debug_inspect(
    (
      sink_loc.start.lnum,
      sink_loc.start.column(),
      sink_loc.end.lnum,
      sink_loc.end.column(),
    ),
    content=(
      #|(3, 8, 3, 9)
    ),
  )
}
