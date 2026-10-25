///|
fn prepared(source : String) -> @cfg.PreparedFunction raise {
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
test "shadowed names have distinct binding and scope identities" {
  let graph = prepared(
    "fn sample(input) { let x = input; sink(x); { let x = (); sink(x) }; sink(x) }",
  ).graph()
  let xs = graph.bindings.filter(binding => binding.name == "x")
  assert_eq(xs.length(), 2)
  assert_true(xs[0].id != xs[1].id)
  assert_true(xs[0].scope != xs[1].scope)
  let paths = graph.calls
    .filter(call => call.callee_name == Some("sink"))
    .map(call => call.arguments[0].path.unwrap().root)
  assert_eq(paths, [xs[0].id, xs[1].id, xs[0].id])
}

///|
test "malformed required CST fields produce unsupported diagnostics" {
  let parsed = @untyped_cst.parse_structure("fn sample {}")
  let original = @cst.toplevel_nodes(parsed.root())[0]
  let broken = @untyped_cst.CstNode::expr_array_set(
    loc=original.loc,
    source_span=original.source_span,
    entries=[],
  )
  let function = @untyped_cst.CstNode::impl_function(
    loc=original.loc,
    source_span=original.source_span,
    entries=[Body(broken)],
  )
  guard @lowering.prepare_function_like(function) is Unsupported(diagnostics) else {
    fail("expected unsupported syntax")
  }
  assert_eq(diagnostics[0].loc, original.loc)
  inspect(
    diagnostics[0].reason,
    content="missing required field self in Expr_ArraySet",
  )
}

///|
test "support table rejects unimplemented executable syntax" {
  for source in ["[for x in xs => x]", "[..xs]"] {
    let parsed = @untyped_cst.parse_expression(source)
    guard parsed.diagnostics_view().is_empty() else {
      fail("expected valid syntax")
    }
    let expr = @cst.expression_root(parsed.root())
    inspect(@lowering.supports(expr.kind), content="false")
  }
}

///|
test "cloned cleanup chains retain lexical binding and source identities" {
  let graph = prepared(
    "fn sample(flag, input) { defer { let x = input; sink(x) }\nif flag { return input } else { return input } }",
  ).graph()
  let xs = graph.bindings.filter(binding => binding.name == "x")
  assert_eq(xs.length(), 1)
  let sinks = graph.calls.filter(call => call.callee_name == Some("sink"))
  assert_true(sinks.length() >= 1 && sinks.length() <= 2)
  for sink in sinks {
    assert_eq(sink.arguments[0].path.unwrap().root, xs[0].id)
    assert_eq(sink.arguments[0].loc.start.lnum, 1)
  }
}

///|
test "normalized call metadata preserves labels receiver and original locations" {
  let graph = prepared(
    "fn sample(input) { input |> client.send(label=input); sink <| input }",
  ).graph()
  assert_eq(graph.calls.length(), 2)
  let piped = graph.calls[0]
  assert_eq(piped.kind, Pipe)
  assert_eq(piped.callee_name, Some("send"))
  assert_true(piped.receiver is Some(_))
  debug_inspect(
    piped.arguments.map(arg => (arg.index, arg.label)),
    content="[(0, None), (1, Some(\"label\"))]",
  )
  assert_eq(graph.calls[1].kind, RevPipe)
  assert_eq(graph.calls[1].arguments[0].index, 0)
}
