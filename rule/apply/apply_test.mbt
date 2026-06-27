///|
using @compile {compile_rules}

///|
using @model {type CompiledRule}

///|
fn parse_impls(source : String) -> @list.List[@syntax.Impl] raise {
  let (impls, reports) = @parser.parse_string(source, name="apply test")
  guard reports is [] else { fail("expected source to parse") }
  impls
}

///|
fn compile_rule_source(source : String) -> Array[CompiledRule] raise {
  compile_rules([
    @model.RawRuleSpec::from_str(
      "/tmp/rules/example.yaml", "/tmp/rules", source,
    ),
  ])
}

///|
test "apply structural rule matches repeated subtree once" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Repeated equality.
    #|patterns:
    #|  - shape: $(_expr:exp) == $(_expr:exp)
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
test "apply structural rule supports inline expression metavars" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Repeated call value.
    #|patterns:
    #|  - shape: $(value:exp) + $(value:exp)
    #|
  let source =
    #|fn sample {
    #|  make() + make();
    #|  make() + other()
    #|}
    #|
  let hits = apply_structural_rules(
    "sample.mbt",
    parse_impls(source),
    compile_rule_source(rule_source),
  )
  inspect(hits.length(), content="1")
  inspect(hits[0].rule_id, content="example")
}

///|
test "apply structural rule supports inline identifier metavars" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Consistent loop counter.
    #|patterns:
    #|  - shape: |
    #|      for $(counter:id) = 0; $(counter:id) < $(limit:exp); $(counter:id) = $(counter:id) + 1 {
    #|        $(body:exp)
    #|      }
    #|
  let source =
    #|fn sample {
    #|  for i = 0; i < n; i = i + 1 { println(i) }
    #|  for i = 0; j < n; i = i + 1 { println(i) }
    #|}
    #|
  let hits = apply_structural_rules(
    "sample.mbt",
    parse_impls(source),
    compile_rule_source(rule_source),
  )
  inspect(hits.length(), content="1")
  inspect(hits[0].rule_id, content="example")
}

///|
test "apply structural rule supports qualified inline identifier metavars" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Qualified callee.
    #|patterns:
    #|  - shape: $(callee:id)($(callee:id))
    #|
  let source =
    #|fn sample {
    #|  @int.abs(@int.abs);
    #|  @int.abs(abs)
    #|}
    #|
  let hits = apply_structural_rules(
    "sample.mbt",
    parse_impls(source),
    compile_rule_source(rule_source),
  )
  inspect(hits.length(), content="1")
  inspect(hits[0].rule_id, content="example")
}

///|
test "apply structural rule supports constructor identity metavars" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Constructor identity.
    #|patterns:
    #|  - shape: $(Ctor:id)($(Ctor:id))
    #|
  let source =
    #|fn sample {
    #|  @pkg.Actual(@pkg.Actual);
    #|  @pkg.Actual(Actual);
    #|  @pkg.Actual(@other.Actual)
    #|}
    #|
  let hits = apply_structural_rules(
    "sample.mbt",
    parse_impls(source),
    compile_rule_source(rule_source),
  )
  inspect(hits.length(), content="1")
  inspect(hits[0].rule_id, content="example")
}

///|
test "apply structural rule supports inline constant metavars" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Repeated constant value.
    #|patterns:
    #|  - shape: $(value:const) + $(value:const)
    #|
  let source =
    #|fn sample {
    #|  1 + 1;
    #|  1 + 2;
    #|  x + x
    #|}
    #|
  let hits = apply_structural_rules(
    "sample.mbt",
    parse_impls(source),
    compile_rule_source(rule_source),
  )
  inspect(hits.length(), content="1")
  inspect(hits[0].rule_id, content="example")
}

///|
test "apply structural rule supports inline pattern metavars" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Repeated pattern shape.
    #|patterns:
    #|  - shape: match $(value:exp) { ($(item:pat), $(item:pat)) => $(body:exp) }
    #|
  let source =
    #|fn sample {
    #|  match value { (Some(actual), Some(actual)) => ok };
    #|  match value { (Some(actual), Some(other)) => ok }
    #|}
    #|
  let hits = apply_structural_rules(
    "sample.mbt",
    parse_impls(source),
    compile_rule_source(rule_source),
  )
  inspect(hits.length(), content="1")
  inspect(hits[0].rule_id, content="example")
}

///|
test "apply structural rule treats patterns as ordered alternatives" {
  let rule_source =
    #|id: example
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
    #|id: example
    #|description: |
    #|  Wrapped target call.
    #|inside-expr:
    #|  shape: wrapper($(prefix:exp), __TARGET__)
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
test "apply structural rule inherits inside expr identifier bindings" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target call.
    #|inside-expr:
    #|  shape: wrapper($(prefix:id), __TARGET__)
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
test "inside expr traverses guard target children" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Guard target call.
    #|inside-expr:
    #|  shape: wrapper(__TARGET__)
    #|patterns:
    #|  - shape: target()
    #|
  let source =
    #|fn sample {
    #|  wrapper({
    #|    guard ready() else { fallback() }
    #|    target()
    #|  })
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
test "inside expr traverses reverse pipe target children" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Reverse pipe target call.
    #|inside-expr:
    #|  shape: wrapper(__TARGET__)
    #|patterns:
    #|  - shape: target()
    #|
  let source =
    #|fn sample {
    #|  wrapper(sink <| target())
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
test "inside expr traverses list comprehension target children" {
  let rule_source =
    #|id: example
    #|description: |
    #|  List comprehension target call.
    #|inside-expr:
    #|  shape: wrapper(__TARGET__)
    #|patterns:
    #|  - shape: target(item)
    #|
  let source =
    #|fn sample {
    #|  wrapper([for item in items if allow(item) => target(item)])
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
    #|id: example
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
test "apply taint rule supports inline constant metavars" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Constant-tagged sink.
    #|taint:
    #|  sources:
    #|    - shape: get_user_input()
    #|  sinks:
    #|    - shape: sink($(tag:const), __SOURCE__)
    #|
  let source =
    #|fn sample {
    #|  let x = get_user_input();
    #|  sink(1, x);
    #|  sink(tag, x)
    #|}
    #|
  let hits = apply_taint_rules(
    "sample.mbt",
    parse_impls(source),
    compile_rule_source(rule_source),
  )
  inspect(hits.length(), content="1")
  inspect(hits[0].rule_id, content="example")
}

///|
test "apply structural rule matches let pattern header with omitted body" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Tuple let header.
    #|patterns:
    #|  - shape: let (__, __) = __
    #|
  let source =
    #|fn sample {
    #|  let (fst, snd) = tuple; consume(fst); snd
    #|}
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
    #|id: example
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
test "apply taint rule supports inline identifier metavars" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Repeated tagged source reaches matching sink.
    #|taint:
    #|  sources:
    #|    - shape: tagged_source($(tag:id), $(tag:id))
    #|  sinks:
    #|    - shape: tagged_sink($(tag:id), $(tag:id), __SOURCE__)
    #|
  let source =
    #|fn sample {
    #|  let ignored = tagged_source(user, other);
    #|  let x = tagged_source(user, user);
    #|  tagged_sink(user, other, x);
    #|  tagged_sink(user, user, x)
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
    #|id: example
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
    #|id: example
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
