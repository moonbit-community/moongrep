///|
fn parse_impls(source : String) -> @list.List[@syntax.Impl] raise {
  let (impls, reports) = @parser.parse_string(source, name="apply test")
  guard reports is [] else { fail("expected source to parse") }
  impls
}

///|
fn compile_rule_source(source : String) -> Array[CompiledRule] raise {
  compile_rules([
    parse_rule_source("/tmp/rules/example.yaml", "/tmp/rules", source),
  ])
}

///|
test "apply structural rule matches repeated subtree once" {
  let rule_source =
    #|package: moonbitlang/core
    #|description: |
    #|  Repeated equality.
    #|patterns:
    #|  - shape: _expr == _expr
    #|    metavars:
    #|      subtree: [_expr]
    #|
  let source =
    #|fn sample {
    #|  x == x;
    #|  x == y
    #|}
    #|
  let hits = apply_structural_rules(
    "sample.mbt",
    parse_impls(source),
    compile_rule_source(rule_source),
  )
  inspect(hits.length(), content="1")
  inspect(hits[0].rule_id, content="example")
  inspect(hits[0].pattern_index, content="0")
}

///|
test "apply structural rule treats patterns as ordered alternatives" {
  let rule_source =
    #|package: moonbitlang/core
    #|description: |
    #|  Lifecycle calls.
    #|patterns:
    #|  - shape: read_request()
    #|  - shape: end_request()
    #|
  let source =
    #|fn sample {
    #|  read_request();
    #|  end_request()
    #|}
    #|
  let hits = apply_structural_rules(
    "sample.mbt",
    parse_impls(source),
    compile_rule_source(rule_source),
  )
  inspect(hits.length(), content="2")
  inspect(hits[0].pattern_index, content="0")
  inspect(hits[1].pattern_index, content="1")
}

///|
test "apply structural rule supports inside expr inherited bindings" {
  let rule_source =
    #|package: moonbitlang/core
    #|description: |
    #|  Wrapped target call.
    #|inside-expr:
    #|  shape: wrapper(prefix, __TARGET__)
    #|  metavars:
    #|    subtree: [prefix]
    #|patterns:
    #|  - shape: target.call(prefix)
    #|
  let source =
    #|fn sample {
    #|  wrapper(token, target.call(token));
    #|  wrapper(token, target.call(other))
    #|}
    #|
  let hits = apply_structural_rules(
    "sample.mbt",
    parse_impls(source),
    compile_rule_source(rule_source),
  )
  inspect(hits.length(), content="1")
  assert_true(hits[0].outer_loc is Some(_))
}

///|
test "apply structural rule visits top let definitions" {
  let rule_source =
    #|package: moonbitlang/core
    #|description: |
    #|  Read request.
    #|patterns:
    #|  - shape: read_request()
    #|
  let source =
    #|let value = read_request()
    #|
  let hits = apply_structural_rules(
    "sample.mbt",
    parse_impls(source),
    compile_rule_source(rule_source),
  )
  inspect(hits.length(), content="1")
}

///|
test "apply taint rule reports source reaching sink" {
  let rule_source =
    #|package: example/pkg
    #|description: |
    #|  User input reaches sink.
    #|taint:
    #|  sources:
    #|    - shape: get_user_input()
    #|  sinks:
    #|    - shape: sink(__SOURCE__)
    #|
  let source =
    #|fn sample {
    #|  let x = get_user_input();
    #|  sink(x)
    #|}
    #|
  let hits = apply_taint_rules(
    "sample.mbt",
    parse_impls(source),
    compile_rule_source(rule_source),
  )
  inspect(hits.length(), content="1")
  inspect(hits[0].rule_id, content="example")
  inspect(hits[0].pattern_index, content="0")
}

///|
test "apply taint rule sanitizer suppresses nested source sink" {
  let rule_source =
    #|package: example/pkg
    #|description: |
    #|  Sanitized input is safe.
    #|taint:
    #|  sources:
    #|    - shape: get_user_input()
    #|  sinks:
    #|    - shape: sink(__SOURCE__)
    #|  sanitizers:
    #|    - shape: sanitize(__SOURCE__)
    #|
  let source =
    #|fn sample {
    #|  sink(sanitize(get_user_input()))
    #|}
    #|
  let hits = apply_taint_rules(
    "sample.mbt",
    parse_impls(source),
    compile_rule_source(rule_source),
  )
  inspect(hits.length(), content="0")
}

///|
test "apply taint rule reports receiver and root call targets with sink indexes" {
  let rule_source =
    #|package: example/pkg
    #|description: |
    #|  User input reaches multiple sink shapes.
    #|taint:
    #|  sources:
    #|    - shape: get_user_input()
    #|  sinks:
    #|    - shape: receiver.method(__SOURCE__)
    #|    - shape: __SOURCE__.dangerous()
    #|    - shape: wrap(__SOURCE__)
    #|
  let source =
    #|fn sample(receiver) {
    #|  let x = get_user_input();
    #|  receiver.method(x);
    #|  x.dangerous();
    #|  wrap(x)
    #|}
    #|
  let hits = apply_taint_rules(
    "sample.mbt",
    parse_impls(source),
    compile_rule_source(rule_source),
  )
  inspect(hits.length(), content="3")
  inspect(hits[0].pattern_index, content="0")
  inspect(hits[1].pattern_index, content="1")
  inspect(hits[2].pattern_index, content="2")
}
