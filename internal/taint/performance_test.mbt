///|
fn performance_fixture() -> (@untyped_cst.CstNode, @taint.TaintSpec) raise {
  let source =
    #|fn sample(flag) {
    #|  let mut x0 = get_user_input();
    #|  let mut x1 = (); let mut x2 = (); let mut x3 = (); let mut x4 = ();
    #|  let mut x5 = (); let mut x6 = (); let mut x7 = ();
    #|  while flag {
    #|    x7 = x6; x6 = x5; x5 = x4; x4 = x3;
    #|    x3 = x2; x2 = x1; x1 = x0
    #|  };
    #|  sink(x7)
    #|}
  (
    parse_single_impl(source),
    simple_spec(
      sources=[CallReturn(CalleeName("get_user_input"), "source", None, [])],
      call_models=[
        {
          matcher: CalleeName("sink"),
          effects: [ReportSinkArg(Named("sink"), 0)],
        },
      ],
    ),
  )
}

///|
test "bench taint prepare CFG" (it : @bench.T) {
  let (node, _) = performance_fixture()
  it.bench(fn() { it.keep(try! @taint.prepare_function_like(node)) })
}

///|
test "bench taint solve prepared CFG" (it : @bench.T) {
  let (node, spec) = performance_fixture()
  guard @taint.prepare_function_like(node) is Prepared(prepared) else {
    fail("expected CFG")
  }
  it.bench(fn() { it.keep(@taint.analyze(prepared, spec)) })
}

///|
test "bench taint complete function" (it : @bench.T) {
  let (node, spec) = performance_fixture()
  it.bench(fn() {
    let prepared = performance_prepare(node)
    it.keep(@taint.analyze(prepared, spec))
  })
}

///|
fn performance_prepare(node : @untyped_cst.CstNode) -> @taint.PreparedFunction {
  let prepared = match (try! @taint.prepare_function_like(node)) {
    Prepared(prepared) => Some(prepared)
    _ => None
  }
  prepared.unwrap()
}
