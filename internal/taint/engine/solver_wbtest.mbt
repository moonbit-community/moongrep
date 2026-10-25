///|
fn prepared_fixture(source : String) -> @cfg.PreparedFunction raise {
  let parsed = @untyped_cst.parse_structure(source)
  guard parsed.diagnostics_view().is_empty() else {
    fail("expected valid source")
  }
  guard @lowering.prepare_function_like(@cst.toplevel_nodes(parsed.root())[0])
    is Prepared(prepared) else {
    fail("expected prepared function")
  }
  prepared
}

///|
fn solver_spec() -> TaintSpec {
  {
    rule_id: "solver",
    sources: [CallReturn(CalleeName("source"), "source", None, [])],
    call_models: [
      {
        matcher: CalleeName("sink"),
        effects: [ReportSinkArg(Named("sink"), 0)],
      },
    ],
    unknown_call_policy: NoEffect,
    bind_call: _ => _ => None,
  }
}

///|
fn complete(result : AnalysisResult) -> Array[SinkFinding] raise {
  match result {
    Complete(findings) => findings
    Incomplete(_) => fail("expected convergence")
  }
}

///|
test "SCC block scheduling order does not change findings" {
  let prepared = prepared_fixture(
    "fn sample(flag) { let mut a = source(); let mut b = (); while flag { b = a; sink(b); a = b }; sink(b) }",
  )
  let spec = solver_spec()
  let forward = complete(solve(prepared, spec, AnalysisOptions::default()))
  let reverse = complete(
    solve(prepared, spec, AnalysisOptions::default(), reverse=true),
  )
  assert_eq(forward, reverse)
  inspect(forward.length(), content="2")
}

///|
test "bind calls once per rule and do not schedule unchanged states" {
  let prepared = prepared_fixture(
    "fn sample(flag) { let mut a = (); while flag { a = a; clean() }; clean() }",
  )
  let mut bindings = 0
  let spec = {
    ..solver_spec(),
    bind_call: _ => {
      bindings += 1
      _ => None
    },
  }
  let stats = AnalysisMetrics::new()
  let _ = analyze(prepared, spec, metrics=stats)
  assert_eq(bindings, prepared.graph().calls.length())
  assert_eq(stats.bound_calls, bindings)
  // A completely clean back edge equals the header's initial state.
  assert_true(stats.block_visits <= prepared.graph().blocks.length())
  assert_true(stats.input_updates < prepared.graph().blocks.length())
}

///|
test "a reachable clean state is distinct from an unreachable state" {
  let prepared = prepared_fixture(
    "fn sample { clean(); return (); sink(source()) }",
  )
  let stats = AnalysisMetrics::new()
  let hits = complete(analyze(prepared, solver_spec(), metrics=stats))
  inspect(hits.length(), content="0")
  assert_true(stats.block_visits > 0)
}

///|
test "source call identities stay stable around a cycle and findings are deduplicated" {
  let prepared = prepared_fixture(
    "fn sample(flag) { while flag { sink(source()) } }",
  )
  let result = complete(analyze(prepared, solver_spec()))
  inspect(result.length(), content="1")
}

///|
test "all copies of a cleanup source call bind the model once" {
  let prepared = prepared_fixture(
    "fn sample(flag, input) { defer { let x = input; sink(x) }\nif flag { return input } else { return input } }",
  )
  let mut sink_bindings = 0
  let spec = {
    ..solver_spec(),
    sources: [EntryPath({ root: "input", segments: [], }, "input", None)],
    bind_call: static_call => {
      if static_call.callee_name == Some("sink") {
        sink_bindings += 1
        let path = static_call.argument_at(0).unwrap().path
        call => {
          let arg = call.argument_at(0).unwrap()
          let findings : Array[SinkFinding] = if arg.path != path {
            [{ sink_id: Named("path mismatch"), sink_loc: arg.loc, }]
          } else if !arg.taint.is_clean() {
            [{ sink_id: Named("sink"), sink_loc: arg.loc, }]
          } else {
            []
          }
          Some(CallTransfer::normal(TaintValue::clean(), findings~))
        }
      } else {
        _ => None
      }
    },
  }
  let findings = complete(analyze(prepared, spec))
  assert_eq(sink_bindings, 1)
  assert_eq(findings.length(), 1)
  assert_eq(findings[0].sink_id, Named("sink"))
}
