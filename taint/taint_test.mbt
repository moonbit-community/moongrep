///|
test "taint package exposes public path and site models" {
  let path : StoragePath = { root: "input", segments: [Field("body")] }
  let site = ValueSite::Path(path)
  match site {
    Path(found) => inspect(found.root, content="input")
    _ => fail("expected path site")
  }
}

///|
fn parse_single_impl(source : String) -> @syntax.Impl raise {
  let (impls, reports) = @parser.parse_string(source, name="taint test")
  guard reports is [] else { fail("expected source to parse") }
  let nodes = impls.to_array()
  guard nodes is [node] else { fail("expected exactly one impl") }
  node
}

///|
fn no_custom_transfer(_call : CallInfo) -> CallTransfer? {
  None
}

///|
fn simple_spec(
  sources~ : Array[SourceModel],
  call_models~ : Array[CallModel],
  unknown_call_policy? : UnknownCallPolicy = PropagateArgumentsToReturn,
) -> TaintSpec {
  {
    rule_id: "test/rule",
    sources,
    call_models,
    unknown_call_policy,
    max_fixpoint_iterations: 6,
    custom_transfer_call: no_custom_transfer,
  }
}

///|
test "taint engine reports entry parameter source reaching sink argument" {
  let source =
    #|fn sample(input) {
    #|  sink(input)
    #|}
    #|
  let input_path : StoragePath = { root: "input", segments: [] }
  let node = parse_single_impl(source)
  let result = analyze_function_like(
    node,
    simple_spec(sources=[EntryPath(input_path, "entry:input", None)], call_models=[
      { matcher: CalleeName("sink"), effects: [ReportSinkArg("sink:0", 0)] },
    ]),
  )
  assert_eq(result.findings.length(), 1)
  inspect(result.findings[0].sink_id, content="sink:0")
  inspect(result.findings[0].origins[0].origin_id, content="entry:input")
}

///|
test "taint engine sanitizer kills argument path before later sink" {
  let source =
    #|fn sample(input) {
    #|  sanitize(input);
    #|  sink(input)
    #|}
    #|
  let input_path : StoragePath = { root: "input", segments: [] }
  let node = parse_single_impl(source)
  let result = analyze_function_like(
    node,
    simple_spec(sources=[EntryPath(input_path, "entry:input", None)], call_models=[
      { matcher: CalleeName("sanitize"), effects: [KillArg(0)] },
      { matcher: CalleeName("sink"), effects: [ReportSinkArg("sink:0", 0)] },
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
  let receiver_path : StoragePath = { root: "receiver", segments: [] }
  let node = parse_single_impl(source)
  let result = analyze_function_like(
    node,
    simple_spec(sources=[EntryPath(receiver_path, "entry:receiver", None)], call_models=[
      {
        matcher: MethodName("sink"),
        effects: [ReportSinkReceiver("sink:receiver")],
      },
    ]),
  )
  assert_eq(result.findings.length(), 1)
  inspect(result.findings[0].sink_id, content="sink:receiver")
}

///|
test "taint engine analyzes impl method bodies" {
  let source =
    #|impl Show for Sample with fn output(receiver, logger) {
    #|  sink(receiver)
    #|}
    #|
  let receiver_path : StoragePath = { root: "receiver", segments: [] }
  let node = parse_single_impl(source)
  let result = analyze_function_like(
    node,
    simple_spec(sources=[EntryPath(receiver_path, "entry:receiver", None)], call_models=[
      { matcher: CalleeName("sink"), effects: [ReportSinkArg("sink:0", 0)] },
    ]),
  )
  inspect(result.function_name, content="output")
  assert_eq(result.findings.length(), 1)
}

///|
test "taint engine rejects unsupported function declarations" {
  let source =
    #|extern "c" fn sample(input : Int) -> Unit = "sample"
    #|
  let node = parse_single_impl(source)
  try
    analyze_function_like(node, simple_spec(sources=[], call_models=[]))
  catch {
    TaintAnalysisError::UnsupportedFunctionLike(kind~, ..) =>
      inspect(kind, content="TopFuncDef.DeclStubs")
    err => fail("unexpected error \{err}")
  } noraise {
    _ => fail("expected unsupported function-like error")
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
  let secret_path : StoragePath = {
    root: "payload",
    segments: [Field("secret")],
  }
  let node = parse_single_impl(source)
  let result = analyze_function_like(
    node,
    simple_spec(sources=[EntryPath(secret_path, "entry:secret", None)], call_models=[
      { matcher: CalleeName("sink"), effects: [ReportSinkArg("sink:0", 0)] },
    ]),
  )
  assert_eq(result.findings.length(), 1)
  inspect(result.findings[0].origins[0].origin_id, content="entry:secret")
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
  let input_path : StoragePath = { root: "input", segments: [] }
  let node = parse_single_impl(source)
  let result = analyze_function_like(
    node,
    simple_spec(sources=[EntryPath(input_path, "entry:input", None)], call_models=[
      { matcher: CalleeName("sink"), effects: [ReportSinkArg("sink:0", 0)] },
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
  let input_path : StoragePath = { root: "input", segments: [] }
  let node = parse_single_impl(source)
  let result = analyze_function_like(
    node,
    simple_spec(sources=[EntryPath(input_path, "entry:input", None)], call_models=[
      { matcher: CalleeName("sink"), effects: [ReportSinkArg("sink:0", 0)] },
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
  let input_path : StoragePath = { root: "input", segments: [] }
  let node = parse_single_impl(source)
  let result = analyze_function_like(
    node,
    simple_spec(sources=[EntryPath(input_path, "entry:input", None)], call_models=[
      { matcher: CalleeName("sink"), effects: [ReportSinkArg("sink:0", 0)] },
    ]),
  )
  assert_eq(result.findings.length(), 0)
}

///|
test "taint engine propagates unknown call argument taint to return by default" {
  let source =
    #|fn sample(input) {
    #|  sink(wrap(input))
    #|}
    #|
  let input_path : StoragePath = { root: "input", segments: [] }
  let node = parse_single_impl(source)
  let result = analyze_function_like(
    node,
    simple_spec(sources=[EntryPath(input_path, "entry:input", None)], call_models=[
      { matcher: CalleeName("sink"), effects: [ReportSinkArg("sink:0", 0)] },
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
  let input_path : StoragePath = { root: "input", segments: [] }
  let node = parse_single_impl(source)
  let result = analyze_function_like(
    node,
    simple_spec(
      sources=[EntryPath(input_path, "entry:input", None)],
      call_models=[
        { matcher: CalleeName("sink"), effects: [ReportSinkArg("sink:0", 0)] },
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
  let input_path : StoragePath = { root: "input", segments: [] }
  let node = parse_single_impl(source)
  let result = analyze_function_like(
    node,
    simple_spec(sources=[EntryPath(input_path, "entry:input", None)], call_models=[
      { matcher: CalleeName("sink"), effects: [ReportSinkArg("sink:0", 0)] },
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
  let input_path : StoragePath = { root: "input", segments: [] }
  let node = parse_single_impl(source)
  let result = analyze_function_like(
    node,
    simple_spec(sources=[EntryPath(input_path, "entry:input", None)], call_models=[
      { matcher: CalleeName("sink"), effects: [ReportSinkArg("sink:0", 0)] },
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
  let input_path : StoragePath = { root: "input", segments: [] }
  let node = parse_single_impl(source)
  let result = analyze_function_like(
    node,
    simple_spec(sources=[EntryPath(input_path, "entry:input", None)], call_models=[
      { matcher: CalleeName("sink"), effects: [ReportSinkArg("sink:0", 0)] },
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
  let input_path : StoragePath = { root: "input", segments: [] }
  let node = parse_single_impl(source)
  let result = analyze_function_like(
    node,
    simple_spec(sources=[EntryPath(input_path, "entry:input", None)], call_models=[
      { matcher: CalleeName("sink"), effects: [ReportSinkArg("sink:0", 0)] },
    ]),
  )
  assert_eq(result.findings.length(), 0)
}
