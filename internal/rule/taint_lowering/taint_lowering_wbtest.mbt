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
  assert_eq(spec.max_fixpoint_iterations, 64)
  let sink_origins : Array[Array[@taint.TaintOrigin]] = []
  let transfer_call = spec.custom_transfer_call
  let observed_spec : @taint.TaintSpec = {
    ..spec,
    custom_transfer_call: call => {
      if call.callee_name == Some("sink") &&
        call.argument_at(0) is Some(argument) {
        sink_origins.push(@taint.taint_tree_origins(argument.taint))
      }
      transfer_call(call)
    },
  }
  let result = @taint.analyze_function_like(
    parse_single_taint_impl(source),
    observed_spec,
  )
  assert_eq(result.findings.length(), 1)
  assert_eq(result.findings[0].sink_id, PatternIndex(0))
  debug_inspect(
    sink_origins.map(origins => origins.map(origin => origin.origin_id)),
    content="[[\"source:0\"]]",
  )
  assert_eq(sink_origins[0][0].rule_id, rule.rule_id)
  guard sink_origins[0][0].site is CallResult(callee, loc) else {
    fail("expected call-result source")
  }
  debug_inspect(callee, content="Some(\"get_user_input\")")
  inspect(loc.start.lnum, content="2")
  let sink_loc = result.findings[0].sink_loc
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
