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
fn inspect_node_transfer(call : CallInfo) -> CallTransfer? {
  let findings : Array[SinkFinding] = []
  if call.cst.kind is @untyped_cst.Expr_Apply &&
    call.arguments is [arg] &&
    arg.expr.kind is @untyped_cst.Expr_Ident {
    findings.push({
      rule_id: "test/node-transfer",
      sink_id: "node-kinds",
      sink_loc: arg.loc,
      sink_site: arg.site,
      origins: [
        {
          rule_id: "test/node-transfer",
          origin_id: "observed-node",
          site: arg.site,
          note: None,
        },
      ],
    })
  }
  Some({ return_taint: [], killed_paths: [], findings })
}

///|
test "taint engine passes CST nodes to custom transfer" {
  let source =
    #|fn sample(input) {
    #|  sink(input)
    #|}
    #|
  let node = parse_single_impl(source)
  let result = analyze_function_like(node, {
    rule_id: "test/node-transfer",
    sources: [],
    call_models: [],
    unknown_call_policy: NoEffect,
    max_fixpoint_iterations: 6,
    custom_transfer_call: inspect_node_transfer,
  })
  inspect(result.function_name, content="sample")
  assert_eq(result.findings.length(), 1)
  inspect(result.findings[0].sink_id, content="node-kinds")
}

///|
fn analyze_single_entry_sink(
  source : String,
  root : String,
) -> AnalysisResult raise {
  let path : StoragePath = { root, segments: [] }
  let node = parse_single_impl(source)
  analyze_function_like(
    node,
    simple_spec(sources=[EntryPath(path, "entry:\{root}", None)], call_models=[
      { matcher: CalleeName("sink"), effects: [ReportSinkArg("sink:0", 0)] },
    ]),
  )
}

///|
fn analyze_call_source_sink(source : String) -> AnalysisResult raise {
  let node = parse_single_impl(source)
  analyze_function_like(
    node,
    simple_spec(
      sources=[
        CallReturn(CalleeName("get_user_input"), "source:single", None, []),
        CallReturn(CalleeName("get_user_inputs"), "source:many", None, []),
      ],
      call_models=[
        { matcher: CalleeName("sink"), effects: [ReportSinkArg("sink:0", 0)] },
      ],
    ),
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
  let target_path : StoragePath = {
    root: "record",
    segments: [Field("target")],
  }
  let sibling_path : StoragePath = {
    root: "record",
    segments: [Field("sibling")],
  }
  let clear_result = analyze_function_like(
    parse_single_impl(clear_source),
    simple_spec(
      sources=[
        EntryPath(target_path, "entry:target", None),
        EntryPath(sibling_path, "entry:sibling", None),
      ],
      call_models=[
        { matcher: CalleeName("sink"), effects: [ReportSinkArg("sink:0", 0)] },
      ],
    ),
  )
  assert_eq(clear_result.findings.length(), 1)
  inspect(
    clear_result.findings[0].origins[0].origin_id,
    content="entry:sibling",
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
    #|  outer~: {
    #|    for item in clean_items() {
    #|      break outer~
    #|    };
    #|    sink(get_user_input())
    #|  }
    #|}
    #|
  assert_eq(analyze_call_source_sink(foreach_source).findings.length(), 0)
}

///|
test "taint engine propagates outer continues through nested loops" {
  let source =
    #|fn sample {
    #|  outer~: for ;; {
    #|    while clean() {
    #|      continue outer~
    #|    };
    #|    sink(get_user_input())
    #|  }
    #|}
    #|
  assert_eq(analyze_call_source_sink(source).findings.length(), 0)
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
test "taint engine lexscan regex alias feeds guard pattern binding" {
  let source =
    #|fn sample(input) {
    #|  lexscan input {
    #|    re"." as item if item is Some(part) => sink(part);
    #|    _ => ()
    #|  }
    #|}
    #|
  let result = analyze_single_entry_sink(source, "input")
  assert_eq(result.findings.length(), 1)
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
