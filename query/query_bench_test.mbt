///|
test "bench query captures from CST" (it : @bench.T) {
  let source = "fn sample { wrapper(wrapper(wrapper(wrapper(wrapper(wrapper(missing()))))))       }\n"
  let root = @untyped_cst.parse_structure(source, name="query-bench").root()
  let query = ExprQuery("missing()")
  it.bench(fn() { it.keep(query.captures_from_cst(cst=root)) })
}
