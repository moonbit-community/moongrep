///|
fn recursive_bench_rule(depth : Int, leaf : String) -> CompiledRule raise {
  let mut source = "id: recursive-bench\ndescription: Recursive scan baseline.\n"
  let mut indent = ""
  for _ in 0..<depth {
    source += "\{indent}patterns:\n\{indent}  - shape: __TARGET__\n\{indent}    then:\n"
    indent += "      "
  }
  source += "\{indent}patterns:\n\{indent}  - shape: \{leaf}\n"
  compile_scan_plan_rules([source])[0]
}

///|
test "bench builtin structural scan" (it : @bench.T) {
  let source = "fn sample { inspect(true); inspect(42); try source() catch { _ => () }; value = value + 1 }"
  let node = parse_scan_plan_root(source)
  let rules = @compile.compile_rules(@builtin.load_rules())
  let plan = ScanPlan::from_rules(rules).filter_source(source)
  it.bench(fn() {
    it.keep(apply_structural_scan_plan_to_node("bench.mbt", node, plan))
  })
}

///|
fn recursive_bench_source() -> String {
  "fn sample { wrapper(wrapper(wrapper(wrapper(wrapper(wrapper(missing()))))))       }\n"
}

///|
test "bench recursive failure bytes=84 depth=8" (it : @bench.T) {
  let source = recursive_bench_source()
  assert_eq(source.length(), 84)
  let node = parse_scan_plan_root(source)
  let plan = ScanPlan::from_rules([recursive_bench_rule(8, "absent()")])
  it.bench(fn() {
    it.keep(apply_structural_scan_plan_to_node("bench.mbt", node, plan))
  })
}

///|
test "bench ordinary structural scan" (it : @bench.T) {
  let node = parse_scan_plan_root(recursive_bench_source())
  let rules = compile_scan_plan_rules([
    "id: ordinary\ndescription: Ordinary scan.\npatterns:\n  - shape: missing()\n",
  ])
  let plan = ScanPlan::from_rules(rules)
  it.bench(fn() {
    it.keep(apply_structural_scan_plan_to_node("bench.mbt", node, plan))
  })
}
