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
  inspect(hits[0].outer_loc is Some(_), content="true")
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
