///|
priv struct TestResult {
  findings : Array[@taint.SinkFinding]
}

///|
fn analyze_prepared(
  node : @untyped_cst.CstNode,
  spec : @taint.TaintSpec,
) -> TestResult raise {
  match @taint.prepare_function_like(node) {
    Prepared(graph) =>
      match @taint.analyze(graph, spec) {
        Complete(findings) => { findings, }
        Incomplete(diagnostics) =>
          fail("unexpected incomplete analysis: \{Repr(diagnostics)}")
      }
    Unsupported(diagnostics) =>
      fail("unexpected unsupported syntax: \{Repr(diagnostics)}")
    NotApplicable => fail("expected an executable function")
  }
}

///|
fn parse_single_impl(source : String) -> @untyped_cst.CstNode raise {
  let parsed = @untyped_cst.parse_structure(source, name="taint test")
  guard parsed.diagnostics_view().is_empty() else {
    fail("expected source to parse")
  }
  let nodes = @cst.toplevel_nodes(parsed.root())
  guard nodes is [node] else { fail("expected exactly one impl") }
  node
}

///|
fn no_custom_transfer(_call : @taint.CallInfo) -> @taint.CallTransfer? {
  None
}

///|
fn observe_sink_origins(
  spec : @taint.TaintSpec,
  sink_origins : Array[Array[@taint.TaintOrigin]],
) -> @taint.TaintSpec {
  let bind = spec.bind_call
  {
    ..spec,
    bind_call: static_call => {
      let transfer_call = bind(static_call)
      let mut observed_index : Int32? = None
      call => {
        if call.callee_name == Some("sink") &&
          call.argument_at(0) is Some(argument) {
          let origins = argument.taint.origins()
          if observed_index is Some(index) {
            sink_origins[index] = origins
          } else {
            observed_index = Some(sink_origins.length())
            sink_origins.push(origins)
          }
        }
        transfer_call(call)
      }
    },
  }
}

///|
fn sink_location(finding : @taint.SinkFinding) -> (Int32, Int32, Int32, Int32) {
  let loc = finding.sink_loc
  (loc.start.lnum, loc.start.column(), loc.end.lnum, loc.end.column())
}

///|
fn simple_spec(
  sources~ : Array[@taint.SourceModel],
  call_models~ : Array[@taint.CallModel],
  unknown_call_policy~ : @taint.UnknownCallPolicy = PropagateArgumentsToReturn,
) -> @taint.TaintSpec {
  {
    rule_id: "test/rule",
    sources,
    call_models,
    unknown_call_policy,
    bind_call: _ => no_custom_transfer,
  }
}

///|
fn inspect_node_transfer(call : @taint.CallInfo) -> @taint.CallTransfer? {
  let findings : Array[@taint.SinkFinding] = []
  if call.cst.kind is Expr_Apply &&
    call.arguments is [arg] &&
    arg.expr.kind is Expr_Ident {
    findings.push({ sink_id: Named("node-kinds"), sink_loc: arg.loc, })
  }
  Some(@taint.CallTransfer::normal(@taint.TaintValue::clean(), findings~))
}

///|
test "taint engine passes CST nodes to custom transfer" {
  let source =
    #|fn sample(input) {
    #|  sink(input)
    #|}
    #|
  let node = parse_single_impl(source)
  let result = analyze_prepared(node, {
    rule_id: "test/node-transfer",
    sources: [],
    call_models: [],
    unknown_call_policy: NoEffect,
    bind_call: _ => inspect_node_transfer,
  })
  assert_eq(result.findings.length(), 1)
  assert_eq(result.findings[0].sink_id, Named("node-kinds"))
  debug_inspect(
    sink_location(result.findings[0]),
    content=(
      #|(2, 8, 2, 13)
    ),
  )
}

///|
fn analyze_single_entry_sink(
  source : String,
  root : String,
) -> TestResult raise {
  let path : @taint.ParameterPath = { root, segments: [], }
  let node = parse_single_impl(source)
  analyze_prepared(
    node,
    simple_spec(sources=[EntryPath(path, "entry:\{root}", None)], call_models=[
      {
        matcher: CalleeName("sink"),
        effects: [ReportSinkArg(Named("sink:0"), 0)],
      },
    ]),
  )
}

///|
fn analyze_call_source_sink(
  source : String,
  sink_origins? : Array[Array[@taint.TaintOrigin]],
) -> TestResult raise {
  let node = parse_single_impl(source)
  let spec = simple_spec(
    sources=[
      CallReturn(CalleeName("get_user_input"), "source:single", None, []),
      CallReturn(CalleeName("get_user_inputs"), "source:many", None, []),
    ],
    call_models=[
      {
        matcher: CalleeName("sink"),
        effects: [ReportSinkArg(Named("sink:0"), 0)],
      },
    ],
  )
  analyze_prepared(
    node,
    if sink_origins is Some(origins) {
      observe_sink_origins(spec, origins)
    } else {
      spec
    },
  )
}

///|
test "taint engine propagates foreach collection taint to its binder" {
  let source =
    #|fn sample {
    #|  for item in get_user_inputs() { sink(item) }
    #|}
    #|
  assert_eq(analyze_call_source_sink(source).findings.length(), 1)
}

///|
test "taint engine propagates try result taint into noraise cases" {
  let source =
    #|fn sample {
    #|  try get_user_input() catch {
    #|    _ => ()
    #|  } noraise {
    #|    result => sink(result)
    #|  }
    #|}
    #|
  assert_eq(analyze_call_source_sink(source).findings.length(), 1)
}

///|
test "taint engine reads taint through an array index" {
  let source =
    #|fn sample {
    #|  let values = [get_user_input()];
    #|  sink(values[0])
    #|}
    #|
  assert_eq(analyze_call_source_sink(source).findings.length(), 1)
}

///|
test "taint engine evaluates an array assignment target and value" {
  let source =
    #|fn sample {
    #|  values[0] = sink(get_user_input())
    #|}
    #|
  assert_eq(analyze_call_source_sink(source).findings.length(), 1)
}

///|
test "taint engine evaluates a field assignment receiver before its value" {
  let sink_source =
    #|fn sample {
    #|  holder(sink(get_user_input())).field = clean()
    #|}
    #|
  assert_eq(analyze_call_source_sink(sink_source).findings.length(), 1)
  let state_source =
    #|fn sample(input, clean) {
    #|  let mut value = clean;
    #|  { value = input; holder() }.field = sink(value)
    #|}
    #|
  assert_eq(
    analyze_single_entry_sink(state_source, "input").findings.length(),
    1,
  )
}

///|
test "taint engine overwrites variable assignments" {
  let clean_to_tainted =
    #|fn sample(input, clean) {
    #|  let mut value = clean;
    #|  value = input;
    #|  sink(value)
    #|}
    #|
  assert_eq(
    analyze_single_entry_sink(clean_to_tainted, "input").findings.length(),
    1,
  )
  let tainted_to_clean =
    #|fn sample(input, clean) {
    #|  let mut value = input;
    #|  value = clean;
    #|  sink(value)
    #|}
    #|
  assert_eq(
    analyze_single_entry_sink(tainted_to_clean, "input").findings.length(),
    0,
  )
}

///|
test "taint engine writes and clears fields without changing siblings" {
  let write_source =
    #|fn sample(record, input) {
    #|  record.target = input;
    #|  sink(record.target);
    #|  sink(record.sibling)
    #|}
    #|
  assert_eq(
    analyze_single_entry_sink(write_source, "input").findings.length(),
    1,
  )
  let clear_source =
    #|fn sample(record, clean) {
    #|  record.target = clean;
    #|  sink(record.target);
    #|  sink(record.sibling)
    #|}
    #|
  let target_path : @taint.ParameterPath = {
    root: "record",
    segments: [Field("target")],
  }
  let sibling_path : @taint.ParameterPath = {
    root: "record",
    segments: [Field("sibling")],
  }
  let sink_origins : Array[Array[@taint.TaintOrigin]] = []
  let clear_result = analyze_prepared(
    parse_single_impl(clear_source),
    observe_sink_origins(
      simple_spec(
        sources=[
          EntryPath(target_path, "entry:target", None),
          EntryPath(sibling_path, "entry:sibling", None),
        ],
        call_models=[
          {
            matcher: CalleeName("sink"),
            effects: [ReportSinkArg(Named("sink:0"), 0)],
          },
        ],
      ),
      sink_origins,
    ),
  )
  assert_eq(clear_result.findings.length(), 1)
  debug_inspect(
    sink_origins.map(origins => origins.map(origin => origin.origin_id)),
    content="[[], [\"entry:sibling\"]]",
  )
  assert_eq(clear_result.findings[0].sink_id, Named("sink:0"))
  debug_inspect(
    sink_location(clear_result.findings[0]),
    content=(
      #|(4, 8, 4, 22)
    ),
  )
}

///|
test "taint engine evaluates a sink that occurs only in an if else branch" {
  let source =
    #|fn sample {
    #|  if clean() { () } else { sink(get_user_input()) }
    #|}
    #|
  assert_eq(analyze_call_source_sink(source).findings.length(), 1)
}

///|
test "taint engine adapts array slices and record fields" {
  let source =
    #|fn sample {
    #|  let values = [get_user_input()];
    #|  sink(values[0:1]);
    #|  let record = { field: get_user_input() };
    #|  sink(record.field);
    #|  let updated = { ..record, field: get_user_input() };
    #|  sink(updated.field)
    #|}
    #|
  assert_eq(analyze_call_source_sink(source).findings.length(), 3)
}

///|
test "taint engine adapts foreach init continue and nobreak fields" {
  let init_source =
    #|fn sample {
    #|  for item in clean_items(); acc = get_user_input(); acc = acc {
    #|    sink(acc);
    #|    break
    #|  }
    #|}
    #|
  assert_eq(analyze_call_source_sink(init_source).findings.length(), 1)
  let continue_source =
    #|fn sample {
    #|  for item in clean_items(); acc = (); acc = get_user_input() {
    #|    ()
    #|  } nobreak {
    #|    sink(acc)
    #|  }
    #|}
    #|
  assert_eq(analyze_call_source_sink(continue_source).findings.length(), 1)
  let nobreak_source =
    #|fn sample {
    #|  for item in clean_items() { () } nobreak {
    #|    sink(get_user_input())
    #|  }
    #|}
    #|
  assert_eq(analyze_call_source_sink(nobreak_source).findings.length(), 1)
}

///|
test "taint engine reports entry parameter source reaching sink argument" {
  let source =
    #|fn sample(input) {
    #|  sink(input)
    #|}
    #|
  let input_path : @taint.ParameterPath = { root: "input", segments: [], }
  let node = parse_single_impl(source)
  let sink_origins : Array[Array[@taint.TaintOrigin]] = []
  let result = analyze_prepared(
    node,
    observe_sink_origins(
      simple_spec(sources=[EntryPath(input_path, "entry:input", None)], call_models=[
        {
          matcher: CalleeName("sink"),
          effects: [ReportSinkArg(Named("sink:0"), 0)],
        },
      ]),
      sink_origins,
    ),
  )
  assert_eq(result.findings.length(), 1)
  assert_eq(result.findings[0].sink_id, Named("sink:0"))
  debug_inspect(
    sink_origins.map(origins => origins.map(origin => origin.origin_id)),
    content="[[\"entry:input\"]]",
  )
  assert_eq(
    sink_origins[0][0].site,
    Path({ root: @taint.BindingId(0), segments: input_path.segments, }),
  )
  inspect(sink_origins[0][0].rule_id, content="test/rule")
  debug_inspect(
    sink_location(result.findings[0]),
    content=(
      #|(2, 8, 2, 13)
    ),
  )
}

///|
test "taint engine sanitizer kills argument path before later sink" {
  let source =
    #|fn sample(input) {
    #|  sanitize(input);
    #|  sink(input)
    #|}
    #|
  let input_path : @taint.ParameterPath = { root: "input", segments: [], }
  let node = parse_single_impl(source)
  let result = analyze_prepared(
    node,
    simple_spec(sources=[EntryPath(input_path, "entry:input", None)], call_models=[
      { matcher: CalleeName("sanitize"), effects: [KillArg(0)], },
      {
        matcher: CalleeName("sink"),
        effects: [ReportSinkArg(Named("sink:0"), 0)],
      },
    ]),
  )
  assert_eq(result.findings.length(), 0)
}

///|
test "taint engine reports tainted receiver reaching method sink" {
  let source =
    #|fn sample(receiver, clean) {
    #|  receiver.sink();
    #|  clean.sink()
    #|}
    #|
  let receiver_path : @taint.ParameterPath = { root: "receiver", segments: [], }
  let node = parse_single_impl(source)
  let result = analyze_prepared(
    node,
    simple_spec(sources=[EntryPath(receiver_path, "entry:receiver", None)], call_models=[
      {
        matcher: MethodName("sink"),
        effects: [ReportSinkReceiver(Named("sink:receiver"))],
      },
    ]),
  )
  assert_eq(result.findings.length(), 1)
  assert_eq(result.findings[0].sink_id, Named("sink:receiver"))
  debug_inspect(
    sink_location(result.findings[0]),
    content=(
      #|(2, 3, 2, 18)
    ),
  )
}

///|
test "taint engine analyzes impl method bodies" {
  let source =
    #|impl Show for Sample with fn output(receiver, logger) {
    #|  sink(receiver)
    #|}
    #|
  let receiver_path : @taint.ParameterPath = { root: "receiver", segments: [], }
  let node = parse_single_impl(source)
  let result = analyze_prepared(
    node,
    simple_spec(sources=[EntryPath(receiver_path, "entry:receiver", None)], call_models=[
      {
        matcher: CalleeName("sink"),
        effects: [ReportSinkArg(Named("sink:0"), 0)],
      },
    ]),
  )
  assert_eq(result.findings.length(), 1)
  assert_eq(result.findings[0].sink_id, Named("sink:0"))
  debug_inspect(
    sink_location(result.findings[0]),
    content=(
      #|(2, 8, 2, 16)
    ),
  )
}

///|
test "declarations without executable bodies are not applicable" {
  let node = parse_single_impl(
    "extern \"c\" fn sample(input : Int) -> Unit = \"sample\"",
  )
  guard @taint.prepare_function_like(node) is NotApplicable else {
    fail("expected a declaration to be inapplicable")
  }
}

///|
test "taint engine keeps field paths precise" {
  let source =
    #|fn sample(payload) {
    #|  sink(payload.secret);
    #|  sink(payload.clean)
    #|}
    #|
  let secret_path : @taint.ParameterPath = {
    root: "payload",
    segments: [Field("secret")],
  }
  let node = parse_single_impl(source)
  let sink_origins : Array[Array[@taint.TaintOrigin]] = []
  let result = analyze_prepared(
    node,
    observe_sink_origins(
      simple_spec(sources=[EntryPath(secret_path, "entry:secret", None)], call_models=[
        {
          matcher: CalleeName("sink"),
          effects: [ReportSinkArg(Named("sink:0"), 0)],
        },
      ]),
      sink_origins,
    ),
  )
  assert_eq(result.findings.length(), 1)
  debug_inspect(
    sink_origins.map(origins => origins.map(origin => origin.origin_id)),
    content="[[\"entry:secret\"], []]",
  )
  assert_eq(result.findings[0].sink_id, Named("sink:0"))
  debug_inspect(
    sink_location(result.findings[0]),
    content=(
      #|(2, 8, 2, 22)
    ),
  )
}

///|
test "taint engine projects tuple element taint through let binding" {
  let source =
    #|fn sample(input, clean) {
    #|  let pair = (input, clean);
    #|  sink(pair.0);
    #|  sink(pair.1)
    #|}
    #|
  let input_path : @taint.ParameterPath = { root: "input", segments: [], }
  let node = parse_single_impl(source)
  let result = analyze_prepared(
    node,
    simple_spec(sources=[EntryPath(input_path, "entry:input", None)], call_models=[
      {
        matcher: CalleeName("sink"),
        effects: [ReportSinkArg(Named("sink:0"), 0)],
      },
    ]),
  )
  assert_eq(result.findings.length(), 1)
}

///|
test "taint engine joins branch states before following sink" {
  let source =
    #|fn sample(flag, input, clean) {
    #|  let mut x = clean;
    #|  if flag { x = input } else { x = clean };
    #|  sink(x)
    #|}
    #|
  let input_path : @taint.ParameterPath = { root: "input", segments: [], }
  let node = parse_single_impl(source)
  let result = analyze_prepared(
    node,
    simple_spec(sources=[EntryPath(input_path, "entry:input", None)], call_models=[
      {
        matcher: CalleeName("sink"),
        effects: [ReportSinkArg(Named("sink:0"), 0)],
      },
    ]),
  )
  assert_eq(result.findings.length(), 1)
}

///|
test "taint engine does not continue sequence after return" {
  let source =
    #|fn sample(input) {
    #|  return ();
    #|  sink(input)
    #|}
    #|
  let input_path : @taint.ParameterPath = { root: "input", segments: [], }
  let node = parse_single_impl(source)
  let result = analyze_prepared(
    node,
    simple_spec(sources=[EntryPath(input_path, "entry:input", None)], call_models=[
      {
        matcher: CalleeName("sink"),
        effects: [ReportSinkArg(Named("sink:0"), 0)],
      },
    ]),
  )
  assert_eq(result.findings.length(), 0)
}

///|
test "taint engine analyzes sinks inside labelled blocks" {
  let source =
    #|fn sample {
    #|  labelled~: {
    #|    sink(get_user_input())
    #|  }
    #|}
    #|
  assert_eq(analyze_call_source_sink(source).findings.length(), 1)
}

///|
test "taint engine propagates labelled block completion and break values" {
  let source =
    #|fn sample {
    #|  let completed = completed~: {
    #|    get_user_input()
    #|  };
    #|  sink(completed);
    #|  let broken = broken~: {
    #|    break broken~ get_user_input()
    #|  };
    #|  sink(broken)
    #|}
    #|
  assert_eq(analyze_call_source_sink(source).findings.length(), 2)
}

///|
test "taint engine resumes after a matching labelled block break" {
  let source =
    #|fn sample {
    #|  done~: {
    #|    break done~;
    #|    sink(get_user_input())
    #|  };
    #|  sink(get_user_input())
    #|}
    #|
  assert_eq(analyze_call_source_sink(source).findings.length(), 1)
}

///|
test "taint engine propagates outer breaks through nested loops" {
  let for_source =
    #|fn sample {
    #|  outer~: {
    #|    for ;; {
    #|      break outer~
    #|    };
    #|    sink(get_user_input())
    #|  }
    #|}
    #|
  assert_eq(analyze_call_source_sink(for_source).findings.length(), 0)
  let foreach_source =
    #|fn sample {
    #|  let mut value = ();
    #|  outer~: {
    #|    for item in clean_items() {
    #|      value = get_user_input();
    #|      break outer~
    #|    };
    #|    sink(get_user_input())
    #|  };
    #|  sink(value)
    #|}
    #|
  assert_eq(analyze_call_source_sink(foreach_source).findings.length(), 2)
}

///|
test "taint engine propagates outer continues through nested loops" {
  let source =
    #|fn sample {
    #|  let mut value = ();
    #|  outer~: for ;; {
    #|    while clean() {
    #|      value = get_user_input();
    #|      continue outer~
    #|    };
    #|    break
    #|  };
    #|  sink(value)
    #|}
    #|
  assert_eq(analyze_call_source_sink(source).findings.length(), 1)
}

///|
test "taint engine consumes unlabelled and current-label continues" {
  let source =
    #|fn sample {
    #|  current~: while clean() {
    #|    continue current~;
    #|    sink(get_user_input())
    #|  };
    #|  for item in clean_items() {
    #|    continue;
    #|    sink(get_user_input())
    #|  };
    #|  sink(get_user_input())
    #|}
    #|
  assert_eq(analyze_call_source_sink(source).findings.length(), 1)
}

///|
test "taint engine preserves matching labelled loop break values" {
  let source =
    #|fn sample {
    #|  let value = current~: for ;; {
    #|    break current~ get_user_input()
    #|  };
    #|  sink(value)
    #|}
    #|
  assert_eq(analyze_call_source_sink(source).findings.length(), 1)
}

///|
test "taint engine normalizes transparent control labels" {
  let source =
    #|fn sample {
    #|  let value = transparent~~: {
    #|    break transparent~~ get_user_input()
    #|  };
    #|  sink(value)
    #|}
    #|
  assert_eq(analyze_call_source_sink(source).findings.length(), 1)
}

///|
test "taint engine propagates unknown call argument taint to return by default" {
  let source =
    #|fn sample(input) {
    #|  sink(wrap(input))
    #|}
    #|
  let input_path : @taint.ParameterPath = { root: "input", segments: [], }
  let node = parse_single_impl(source)
  let result = analyze_prepared(
    node,
    simple_spec(sources=[EntryPath(input_path, "entry:input", None)], call_models=[
      {
        matcher: CalleeName("sink"),
        effects: [ReportSinkArg(Named("sink:0"), 0)],
      },
    ]),
  )
  assert_eq(result.findings.length(), 1)
}

///|
test "taint engine can disable unknown call return propagation" {
  let source =
    #|fn sample(input) {
    #|  sink(wrap(input))
    #|}
    #|
  let input_path : @taint.ParameterPath = { root: "input", segments: [], }
  let node = parse_single_impl(source)
  let result = analyze_prepared(
    node,
    simple_spec(
      sources=[EntryPath(input_path, "entry:input", None)],
      call_models=[
        {
          matcher: CalleeName("sink"),
          effects: [ReportSinkArg(Named("sink:0"), 0)],
        },
      ],
      unknown_call_policy=NoEffect,
    ),
  )
  assert_eq(result.findings.length(), 0)
}

///|
test "taint engine treats reverse pipe as argument zero" {
  let source =
    #|fn sample(input) {
    #|  sink <| input
    #|}
    #|
  let input_path : @taint.ParameterPath = { root: "input", segments: [], }
  let node = parse_single_impl(source)
  let result = analyze_prepared(
    node,
    simple_spec(sources=[EntryPath(input_path, "entry:input", None)], call_models=[
      {
        matcher: CalleeName("sink"),
        effects: [ReportSinkArg(Named("sink:0"), 0)],
      },
    ]),
  )
  assert_eq(result.findings.length(), 1)
}

///|
test "taint engine analyzes normal match cases after early-return cases" {
  let source =
    #|fn sample(flag, input) {
    #|  match flag {
    #|    true => return ();
    #|    _ => sink(input)
    #|  }
    #|}
    #|
  let input_path : @taint.ParameterPath = { root: "input", segments: [], }
  let node = parse_single_impl(source)
  let result = analyze_prepared(
    node,
    simple_spec(sources=[EntryPath(input_path, "entry:input", None)], call_models=[
      {
        matcher: CalleeName("sink"),
        effects: [ReportSinkArg(Named("sink:0"), 0)],
      },
    ]),
  )
  assert_eq(result.findings.length(), 1)
}

///|
test "taint engine binds raised value in catch pattern" {
  let source =
    #|fn sample(input) {
    #|  try {
    #|    raise input
    #|  } catch {
    #|    err => sink(err)
    #|  }
    #|}
    #|
  let input_path : @taint.ParameterPath = { root: "input", segments: [], }
  let node = parse_single_impl(source)
  let result = analyze_prepared(
    node,
    simple_spec(sources=[EntryPath(input_path, "entry:input", None)], call_models=[
      {
        matcher: CalleeName("sink"),
        effects: [ReportSinkArg(Named("sink:0"), 0)],
      },
    ]),
  )
  assert_eq(result.findings.length(), 1)
}

///|
test "taint engine does not execute call transfer after argument return" {
  let source =
    #|fn sample(input) {
    #|  sink(input, { return input })
    #|}
    #|
  let input_path : @taint.ParameterPath = { root: "input", segments: [], }
  let node = parse_single_impl(source)
  let result = analyze_prepared(
    node,
    simple_spec(sources=[EntryPath(input_path, "entry:input", None)], call_models=[
      {
        matcher: CalleeName("sink"),
        effects: [ReportSinkArg(Named("sink:0"), 0)],
      },
    ]),
  )
  assert_eq(result.findings.length(), 0)
}

///|
test "taint engine condition pattern shadows outer root only in if true branch" {
  let source =
    #|fn sample(input, clean) {
    #|  if clean is Some(input) {
    #|    sink(input)
    #|  }
    #|}
    #|
  let result = analyze_single_entry_sink(source, "input")
  assert_eq(result.findings.length(), 0)
}

///|
test "taint engine condition pattern binds tainted value in if true branch" {
  let source =
    #|fn sample(input) {
    #|  if input is Some(item) {
    #|    sink(item)
    #|  }
    #|}
    #|
  let result = analyze_single_entry_sink(source, "input")
  assert_eq(result.findings.length(), 1)
}

///|
test "taint engine restores match case binder before following expression" {
  let source =
    #|fn sample(input, clean) {
    #|  match clean {
    #|    input => ()
    #|  };
    #|  sink(input)
    #|}
    #|
  let result = analyze_single_entry_sink(source, "input")
  assert_eq(result.findings.length(), 1)
}

///|
test "taint engine match case binder shadows outer root in case body" {
  let source =
    #|fn sample(input, clean) {
    #|  match clean {
    #|    input => sink(input)
    #|  }
    #|}
    #|
  let result = analyze_single_entry_sink(source, "input")
  assert_eq(result.findings.length(), 0)
}

///|
test "taint engine lexscan binder receives scrutinee taint" {
  let source =
    #|fn sample(input) {
    #|  lexscan input {
    #|    item => sink(item);
    #|    _ => ()
    #|  }
    #|}
    #|
  let result = analyze_single_entry_sink(source, "input")
  assert_eq(result.findings.length(), 1)
}

///|
test "taint engine lexscan regex alias receives scrutinee taint" {
  let source =
    #|fn sample(input) {
    #|  lexscan input {
    #|    re"." as item => sink(item);
    #|    _ => ()
    #|  }
    #|}
    #|
  let result = analyze_single_entry_sink(source, "input")
  assert_eq(result.findings.length(), 1)
}

///|
test "taint engine lexmatch regex alias receives scrutinee taint" {
  let source =
    #|fn sample(input) {
    #|  lexmatch input {
    #|    re"." as item => sink(item);
    #|    _ => ()
    #|  }
    #|}
    #|
  let result = analyze_single_entry_sink(source, "input")
  assert_eq(result.findings.length(), 1)
}

///|
test "taint engine lexscan regex binding receives scrutinee taint" {
  let source =
    #|fn sample(input) {
    #|  lexscan input {
    #|    (re".", before=head) => sink(head);
    #|    _ => ()
    #|  }
    #|}
    #|
  let result = analyze_single_entry_sink(source, "input")
  assert_eq(result.findings.length(), 1)
}

///|
test "taint engine lexmatch regex binding receives scrutinee taint" {
  let source =
    #|fn sample(input) {
    #|  lexmatch input {
    #|    (re".", before=head) => sink(head);
    #|    _ => ()
    #|  }
    #|}
    #|
  let result = analyze_single_entry_sink(source, "input")
  assert_eq(result.findings.length(), 1)
}

///|
test "taint engine restores lex regex binding before following expression" {
  let source =
    #|fn sample(input, clean) {
    #|  lexmatch clean {
    #|    (re".", before=input) => ()
    #|  };
    #|  sink(input)
    #|}
    #|
  let result = analyze_single_entry_sink(source, "input")
  assert_eq(result.findings.length(), 1)
}

///|
test "taint engine evaluates errdefer expressions" {
  let source =
    #|fn sample(input) {
    #|  errdefer sink(input)
    #|  ()
    #|}
    #|
  let result = analyze_single_entry_sink(source, "input")
  assert_eq(result.findings.length(), 0)
}

///|
test "taint engine restores lexscan binder before following expression" {
  let source =
    #|fn sample(input, clean) {
    #|  lexscan clean {
    #|    input => sink(input);
    #|    _ => ()
    #|  };
    #|  sink(input)
    #|}
    #|
  let result = analyze_single_entry_sink(source, "input")
  assert_eq(result.findings.length(), 1)
}

///|
test "taint engine restores catch binder before following expression" {
  let source =
    #|fn sample(input, clean) {
    #|  try {
    #|    raise clean
    #|  } catch {
    #|    input => ()
    #|  };
    #|  sink(input)
    #|}
    #|
  let result = analyze_single_entry_sink(source, "input")
  assert_eq(result.findings.length(), 1)
}

///|
test "taint engine guard condition binder applies in continuation body" {
  let source =
    #|fn sample(input) {
    #|  guard input is Some(item) else { return () };
    #|  sink(item)
    #|}
    #|
  let result = analyze_single_entry_sink(source, "input")
  assert_eq(result.findings.length(), 1)
}

///|
test "taint engine while condition binder applies only in loop body" {
  let source =
    #|fn sample(input) {
    #|  while input is Some(item) {
    #|    sink(item);
    #|    break
    #|  };
    #|  sink(item)
    #|}
    #|
  let result = analyze_single_entry_sink(source, "input")
  assert_eq(result.findings.length(), 1)
}

///|
test "taint engine for condition binder applies only in loop body" {
  let source =
    #|fn sample(input) {
    #|  for cursor = input; cursor is Some(item); {
    #|    sink(item);
    #|    break
    #|  };
    #|  sink(item)
    #|}
    #|
  let result = analyze_single_entry_sink(source, "input")
  assert_eq(result.findings.length(), 1)
}

///|
test "taint engine restores for loop binder before following expression" {
  let source =
    #|fn sample(input, clean) {
    #|  for input = clean; ; {
    #|    break
    #|  };
    #|  sink(input)
    #|}
    #|
  let result = analyze_single_entry_sink(source, "input")
  assert_eq(result.findings.length(), 1)
}

///|
test "taint engine local function name shadows outer root in let-fn body" {
  let source =
    #|fn sample(helper, clean) {
    #|  fn helper() { clean };
    #|  sink(helper)
    #|}
    #|
  let result = analyze_single_entry_sink(source, "helper")
  assert_eq(result.findings.length(), 0)
}

///|
fn sink_origin_ids_for_source(source : String) -> Array[String] raise {
  let sink_origins : Array[Array[@taint.TaintOrigin]] = []
  let result = analyze_call_source_sink(source, sink_origins~)
  assert_eq(result.findings.length(), 1)
  let ids : Array[String] = []
  for origins in sink_origins {
    for origin in origins {
      if !ids.contains(origin.origin_id) {
        ids.push(origin.origin_id)
      }
    }
  }
  ids.sort()
  ids
}

///|
test "taint engine keeps mixed branch exits independent of branch order" {
  let sources = [
    (
      #|fn sample(flag) {
      #|  for ;; {
      #|    if flag { return () } else { break }
      #|  };
      #|  sink(get_user_input())
      #|}
    ),
    (
      #|fn sample(flag) {
      #|  for ;; {
      #|    if flag { break } else { return () }
      #|  };
      #|  sink(get_user_input())
      #|}
    ),
    (
      #|fn sample(flag) {
      #|  for ;; {
      #|    match flag { true => return (); _ => break }
      #|  };
      #|  sink(get_user_input())
      #|}
    ),
    (
      #|fn sample(flag) {
      #|  for ;; {
      #|    match flag { _ => break; true => return () }
      #|  };
      #|  sink(get_user_input())
      #|}
    ),
    (
      #|fn sample(flag) {
      #|  for ;; {
      #|    lexmatch flag { _ => return (); _ => break }
      #|  };
      #|  sink(get_user_input())
      #|}
    ),
    (
      #|fn sample(flag) {
      #|  for ;; {
      #|    lexmatch flag { _ => break; _ => return () }
      #|  };
      #|  sink(get_user_input())
      #|}
    ),
    (
      #|fn sample(flag) {
      #|  for ;; {
      #|    lexscan flag { _ => return (); _ => break }
      #|  };
      #|  sink(get_user_input())
      #|}
    ),
    (
      #|fn sample(flag) {
      #|  for ;; {
      #|    lexscan flag { _ => break; _ => return () }
      #|  };
      #|  sink(get_user_input())
      #|}
    ),
    (
      #|fn sample(flag) {
      #|  for ;; {
      #|    try { raise flag } catch { true => return (); _ => break }
      #|  };
      #|  sink(get_user_input())
      #|}
    ),
    (
      #|fn sample(flag) {
      #|  for ;; {
      #|    try { raise flag } catch { _ => break; true => return () }
      #|  };
      #|  sink(get_user_input())
      #|}
    ),
  ]
  let summaries : Array[Array[String]] = []
  for source in sources {
    summaries.push(sink_origin_ids_for_source(source))
  }
  debug_inspect(
    summaries,
    content=(
      #|[
      #|  ["source:single"],
      #|  ["source:single"],
      #|  ["source:single"],
      #|  ["source:single"],
      #|  ["source:single"],
      #|  ["source:single"],
      #|  ["source:single"],
      #|  ["source:single"],
      #|  ["source:single"],
      #|  ["source:single"],
      #|]
    ),
  )
}

///|
test "taint engine does not evaluate after branches that only exit" {
  let source =
    #|fn sample(flag) {
    #|  if flag { return () } else { raise clean() };
    #|  sink(get_user_input())
    #|}
    #|
  assert_eq(analyze_call_source_sink(source).findings.length(), 0)
}

///|
test "taint engine reaches a sink after seven reverse loop assignments" {
  let while_source =
    #|fn sample {
    #|  let mut x0 = get_user_input();
    #|  let mut x1 = (); let mut x2 = (); let mut x3 = (); let mut x4 = ();
    #|  let mut x5 = (); let mut x6 = (); let mut x7 = ();
    #|  while clean() {
    #|    x7 = x6; x6 = x5; x5 = x4; x4 = x3;
    #|    x3 = x2; x2 = x1; x1 = x0
    #|  };
    #|  sink(x7)
    #|}
    #|
  let for_source =
    #|fn sample {
    #|  let mut x0 = get_user_input();
    #|  let mut x1 = (); let mut x2 = (); let mut x3 = (); let mut x4 = ();
    #|  let mut x5 = (); let mut x6 = (); let mut x7 = ();
    #|  for ; clean(); {
    #|    x7 = x6; x6 = x5; x5 = x4; x4 = x3;
    #|    x3 = x2; x2 = x1; x1 = x0
    #|  };
    #|  sink(x7)
    #|}
    #|
  let foreach_source =
    #|fn sample {
    #|  let mut x0 = get_user_input();
    #|  let mut x1 = (); let mut x2 = (); let mut x3 = (); let mut x4 = ();
    #|  let mut x5 = (); let mut x6 = (); let mut x7 = ();
    #|  for item in clean_items() {
    #|    x7 = x6; x6 = x5; x5 = x4; x4 = x3;
    #|    x3 = x2; x2 = x1; x1 = x0
    #|  };
    #|  sink(x7)
    #|}
    #|
  let counts = [
    analyze_call_source_sink(while_source).findings.length(),
    analyze_call_source_sink(for_source).findings.length(),
    analyze_call_source_sink(foreach_source).findings.length(),
  ]
  debug_inspect(
    counts,
    content=(
      #|[1, 1, 1]
    ),
  )
}

///|
test "taint engine returns incomplete without publishing partial findings" {
  let source =
    #|fn sample {
    #|  let mut value = { secret: get_user_input() };
    #|  sink(value);
    #|  while clean() { value = { next: value } };
    #|  sink(value)
    #|}
  let spec = simple_spec(
    sources=[CallReturn(CalleeName("get_user_input"), "source", None, [])],
    call_models=[
      {
        matcher: CalleeName("sink"),
        effects: [ReportSinkArg(Named("sink"), 0)],
      },
    ],
  )
  guard @taint.prepare_function_like(parse_single_impl(source))
    is Prepared(graph) else {
    fail("expected CFG")
  }
  guard @taint.analyze(graph, spec, options={ max_scc_rounds: 2, })
    is Incomplete(diagnostics) else {
    fail("expected incomplete result")
  }
  assert_eq(diagnostics.length(), 1)
  assert_true(diagnostics[0].reason.contains("2 rounds"))
}
