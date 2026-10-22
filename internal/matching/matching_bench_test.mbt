///|
fn bench_trailing_ellipsis(it : @bench.T, count : Int32) -> Unit raise {
  let arguments = [ for index in 0..<count => "arg\{index}" ]
  let candidate = test_expr("target(" + arguments.join(", ") + ")")
  let compiled = test_compiled(test_expr("target($$$args)"), entries=[
    test_metavar_entry("args", Ellipsis(AnyItem)),
  ])
  it.bench(fn() { it.keep(@matching.match_expr_pattern(compiled, candidate)) })
}

///|
test "bench trailing ellipsis arguments=64" (it : @bench.T) {
  bench_trailing_ellipsis(it, 64)
}

///|
test "bench trailing ellipsis arguments=256" (it : @bench.T) {
  bench_trailing_ellipsis(it, 256)
}
