///|
test "unknown calls have no exceptional completion" {
  let source = "fn sample(input) { try unknown(input) catch { err => sink(err) } }"
  inspect(
    analyze_single_entry_sink(source, "input").findings.length(),
    content="0",
  )
}

///|
test "declared exceptional outcomes enter catches and no-return blocks normal edges" {
  let spec = simple_spec(
    sources=[EntryPath({ root: "input", segments: [], }, "input", None)],
    call_models=[
      { matcher: CalleeName("maybe"), effects: [RaiseArg(0)], },
      { matcher: CalleeName("stop"), effects: [NoReturn], },
      {
        matcher: CalleeName("sink"),
        effects: [ReportSinkArg(Named("sink"), 0)],
      },
    ],
  )
  let throwing = analyze_prepared(
    parse_single_impl(
      "fn sample(input) { try maybe(input) catch { err => sink(err) } }",
    ),
    spec,
  )
  let stopped = analyze_prepared(
    parse_single_impl("fn sample(input) { stop(); sink(input) }"),
    spec,
  )
  debug_inspect(
    (throwing.findings.length(), stopped.findings.length()),
    content="(1, 0)",
  )
}

///|
test "call completions have separate writes and evaluated argument snapshots" {
  let spec = {
    ..simple_spec(
      sources=[EntryPath({ root: "input", segments: [], }, "input", None)],
      call_models=[
        {
          matcher: CalleeName("sink"),
          effects: [ReportSinkArg(Named("sink"), 0)],
        },
      ],
    ),
    bind_call: static_call => {
      if static_call.callee_name == Some("effect") {
        call => {
          let arg = call.argument_at(0).unwrap()
          let path = arg.path.unwrap()
          Some({
            normal: Some({
              value: @taint.TaintValue::clean(),
              writes: [Sanitize(path)],
            }),
            exceptional: Some({
              value: arg.taint,
              writes: [Set(path, arg.taint)],
            }),
            findings: [],
          })
        }
      } else {
        no_custom_transfer
      }
    },
  }
  let source = "fn sample(input) { try { effect(input); sink(input) } catch { err => { sink(err); sink(input) } } }"
  let result = analyze_prepared(parse_single_impl(source), spec)
  inspect(result.findings.length(), content="2")
}

///|
test "arguments keep snapshots when a later argument sanitizes storage" {
  let spec = simple_spec(
    sources=[EntryPath({ root: "input", segments: [], }, "input", None)],
    call_models=[
      { matcher: CalleeName("sanitize"), effects: [KillArg(0)], },
      { matcher: CalleeName("pair"), effects: [PropagateArgToReturn(0)], },
      {
        matcher: CalleeName("sink"),
        effects: [ReportSinkArg(Named("sink"), 0)],
      },
    ],
  )
  let result = analyze_prepared(
    parse_single_impl(
      "fn sample(input) { sink(pair(input, { sanitize(input); () })); sink(input) }",
    ),
    spec,
  )
  inspect(result.findings.length(), content="1")
}

///|
test "overlapping entry sources add origins without replacing ancestor taint" {
  let origins : Array[Array[@taint.TaintOrigin]] = []
  let spec = observe_sink_origins(
    simple_spec(
      sources=[
        EntryPath({ root: "input", segments: [], }, "whole", None),
        EntryPath(
          { root: "input", segments: [Field("secret")], },
          "field",
          None,
        ),
      ],
      call_models=[
        {
          matcher: CalleeName("sink"),
          effects: [ReportSinkArg(Named("sink"), 0)],
        },
      ],
    ),
    origins,
  )
  let result = analyze_prepared(
    parse_single_impl("fn sample(input) { sink(input.secret) }"),
    spec,
  )
  assert_eq(result.findings.length(), 1)
  debug_inspect(
    origins[0].map(origin => origin.origin_id),
    content="[\"whole\", \"field\"]",
  )
}

///|
test "call targets retain binding identities through shadowing" {
  let source = "fn sample(handler) { sink(handler()); { let handler = replacement; sink(handler()) }; sink(handler()) }"
  guard @taint.prepare_function_like(parse_single_impl(source))
    is Prepared(prepared) else {
    fail("expected CFG")
  }
  let calls = prepared.graph().calls.filter(call => {
    call.callee_name == Some("handler")
  })
  debug_inspect(
    calls.map(call => call.callee_binding.map(binding => binding.0)),
    content="[Some(0), Some(1), Some(0)]",
  )
  let spec = simple_spec(
    sources=[
      CallReturn(
        CalleeBinding(@taint.BindingId(0)),
        "parameter-handler",
        None,
        [],
      ),
    ],
    call_models=[
      {
        matcher: CalleeName("sink"),
        effects: [ReportSinkArg(Named("sink"), 0)],
      },
    ],
  )
  guard @taint.analyze(prepared, spec) is Complete(findings) else {
    fail("expected convergence")
  }
  inspect(findings.length(), content="2")
}
