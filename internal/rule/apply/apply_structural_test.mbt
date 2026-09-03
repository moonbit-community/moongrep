///|
test "apply structural rules accepts untyped CST roots" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Any expression.
    #|patterns:
    #|  - shape: $(value:exp)
    #|
  let source =
    #|fn sample {
    #|  target()
    #|}
    #|
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
  inspect(hits[0].rule_id, content="example")
  assert_true(hits[0].loc.start.lnum > 0)
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
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
  inspect(hits[0].rule_id, content="example")
  assert_eq(hits[0].pattern_index, 0)
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
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
  inspect(hits[0].rule_id, content="example")
}

///|
test "apply structural rule supports metavars in string and bytes interpolation" {
  let rule_source =
    #|id: example
    #|description: Interpolation captures.
    #|patterns:
    #|  - shape: |
    #|      "hello \{$(value:exp)}"
    #|  - shape: |
    #|      b"hello \{$(value:exp)}"
    #|
  let source =
    #|fn sample {
    #|  "hello \{name}";
    #|  "hello \{make()}";
    #|  b"hello \{name}";
    #|  b"hello \{make()}"
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 4)
  inspect(
    int_array_signature(hits.map(hit => hit.pattern_index)),
    content="[0, 0, 1, 1]",
  )
}

///|
test "apply structural rule visits an if else branch" {
  let rule_source =
    #|id: example
    #|description: Infix in else.
    #|patterns:
    #|  - shape: $(left:exp) + $(right:exp)
    #|
  let source =
    #|fn sample {
    #|  if clean() { () } else { left() + right() }
    #|}
    #|
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
}

///|
test "apply structural rule matches keyword metavariables" {
  let rule_source =
    #|id: example
    #|description: Keyword metavars.
    #|patterns:
    #|  - shape: if $(condition:exp) { $(then:exp) } else { $(else:exp) }
    #|
  let source =
    #|fn sample {
    #|  if ready() { accepted() } else { rejected() }
    #|}
    #|
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
}

///|
test "apply structural rule supports inline argument metavars" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Single complete argument.
    #|patterns:
    #|  - shape: sink($(arg:arg))
    #|
  let source =
    #|fn sample {
    #|  sink(value);
    #|  sink(label=value);
    #|  sink(label~);
    #|  sink(label?=value);
    #|  sink(label?);
    #|  sink(value, other)
    #|}
    #|
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 5)
  inspect(hits[0].rule_id, content="example")
}

///|
test "apply structural rule supports inline type metavars" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Typed let annotations.
    #|patterns:
    #|  - shape: |
    #|      let value : $(T:type) = input
    #|
  let source =
    #|fn sample_int {
    #|  let value : Int = input;
    #|}
    #|fn sample_user {
    #|  let value : User = input;
    #|}
    #|fn sample_array {
    #|  let value : Array[String] = input
    #|}
    #|
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 3)
  inspect(hits[0].rule_id, content="example")
}

///|
test "apply structural rule supports bare expression metavars" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Repeated call value.
    #|patterns:
    #|  - shape: $value + $value
    #|
  let source =
    #|fn sample {
    #|  make() + make();
    #|  make() + other()
    #|}
    #|
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
  inspect(hits[0].rule_id, content="example")
}

///|
test "apply structural rule rewrites field access metavars recursively" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Repeated field mutation target.
    #|patterns:
    #|  - shape: $object.$field = $object.$field + $_
    #|
  let source =
    #|fn sample {
    #|  foo.bar.baz = foo.bar.baz + 1;
    #|  foo.bar.baz = foo.bar.other + 1;
    #|  foo.bar.baz = other.bar.baz + 1
    #|}
    #|
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
  inspect(hits[0].rule_id, content="example")
}

///|
test "apply structural rule treats $_ as independent ignore placeholder" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Ignore call arguments.
    #|patterns:
    #|  - shape: pair($_, $_)
    #|
  let source =
    #|fn sample {
    #|  pair(left, right);
    #|  pair(left, left);
    #|  pair()
    #|}
    #|
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 2)
  inspect(hits[0].rule_id, content="example")
}

///|
test "apply structural rule keeps underscore identifiers literal unless declared" {
  let literal_rule_source =
    #|id: literal
    #|description: |
    #|  Literal all-underscore identifier.
    #|patterns:
    #|  - shape: foo(__)
    #|
  let literal_source =
    #|fn sample {
    #|  foo(value);
    #|  foo(__)
    #|}
    #|
  let literal_hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(literal_source),
    compile_rule_source(literal_rule_source),
  )
  assert_eq(literal_hits.length(), 1)
  inspect(literal_hits[0].rule_id, content="literal")

  let metavar_rule_source =
    #|id: metavar
    #|description: |
    #|  Repeated all-underscore metavar.
    #|patterns:
    #|  - shape: $__ + $__
    #|
  let metavar_source =
    #|fn sample {
    #|  same + same;
    #|  left + right
    #|}
    #|
  let metavar_hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(metavar_source),
    compile_rule_source(metavar_rule_source),
  )
  assert_eq(metavar_hits.length(), 1)
  inspect(metavar_hits[0].rule_id, content="metavar")
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
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
  inspect(hits[0].rule_id, content="example")
}

///|
test "apply structural rule infers bare loop counter as identifier" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Consistent loop counter.
    #|patterns:
    #|  - shape: |
    #|      for $counter = 0; $counter < $limit; $counter = $counter + 1 {
    #|        $body
    #|      }
    #|
  let source =
    #|fn sample {
    #|  for i = 0; i < n; i = i + 1 { println(i) }
    #|  for i = 0; j < n; i = i + 1 { println(i) }
    #|}
    #|
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
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
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
  inspect(hits[0].rule_id, content="example")
}

///|
test "apply structural rule requires qualified identifier metavar prefixes" {
  let source =
    #|fn sample {
    #|  local();
    #|  @pkg.remote();
    #|  @other.wrong()
    #|}
    #|
  for shape in ["@pkg.$(callee:id)()", "@pkg.$callee()"] {
    let rule_source =
      $|id: example
      $|description: Qualified identifier prefix.
      $|patterns:
      $|  - shape: "\{shape}"
      $|
    let hits = apply_structural_rule_findings(source, rule_source)
    assert_eq(hits.length(), 1)
    inspect(location_signature(hits[0].loc), content="3:3-3:16")
  }
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
    #|  Actual(Actual);
    #|  @pkg.Actual(@pkg.Actual);
    #|  Type::Actual(Type::Actual);
    #|  @pkg.Type::Actual(@pkg.Type::Actual);
    #|  @pkg.Type::@other.Actual(@pkg.Type::@other.Actual);
    #|  @pkg.Type::Actual(@other.Type::Actual)
    #|}
    #|
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 5)
  inspect(hits[0].rule_id, content="example")
}

///|
test "constructor identity metavars repeat across patterns and expressions" {
  let rule_source =
    #|id: example
    #|description: Constructor pattern identity.
    #|patterns:
    #|  - shape: match $_ { $(Ctor:id)($(item:id)) => $(Ctor:id)($(item:id)) }
    #|
  let source =
    #|fn sample {
    #|  match input { @pkg.Type::Ctor(item) => @pkg.Type::Ctor(item) };
    #|  match input { @pkg.Type::Ctor(item) => @other.Type::Ctor(item) }
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
}

///|
test "identifier guards receive the complete constructor identity" {
  let rule_source =
    #|id: example
    #|description: Qualified constructor.
    #|patterns:
    #|  - shape: $(Ctor:id)($_)
    #|    guard:
    #|      $Ctor: "^@pkg[.]Type::Ctor$"
    #|
  let source =
    #|fn sample {
    #|  @pkg.Type::Ctor(value);
    #|  @other.Type::Ctor(value);
    #|  Type::Ctor(value)
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
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
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
  inspect(hits[0].rule_id, content="example")
}

///|
test "apply structural id guard filters matches" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Safe call.
    #|patterns:
    #|  - shape: $(callee:id)()
    #|    guard:
    #|      $callee: "^safe_"
    #|
  let source =
    #|fn sample {
    #|  safe_call();
    #|  unsafe_call()
    #|}
    #|
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
  inspect(hits[0].rule_id, content="example")
}

///|
test "apply structural const guard filters strings numbers and bools" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Selected constants.
    #|patterns:
    #|  - shape: sink($(value:const))
    #|    guard:
    #|      $value: "^(danger|42|true)$"
    #|
  let source =
    #|fn sample {
    #|  sink("danger");
    #|  sink(42);
    #|  sink(true);
    #|  sink("safe");
    #|  sink(false)
    #|}
    #|
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 3)
}

///|
test "apply structural multiple guards use and semantics" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Safe tagged call.
    #|patterns:
    #|  - shape: $(callee:id)($(value:const))
    #|    guard:
    #|      $callee: "^safe_"
    #|      $value: "^ok$"
    #|
  let source =
    #|fn sample {
    #|  safe_call("ok");
    #|  safe_call("bad");
    #|  danger_call("ok")
    #|}
    #|
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
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
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
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
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 2)
  assert_eq(hits[0].pattern_index, 0)
  assert_eq(hits[1].pattern_index, 1)
}

///|
test "apply structural patterns-not is ignored after positive root match" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Match every sink root before considering negative patterns.
    #|patterns:
    #|  - shape: sink($(value:exp))
    #|patterns-not:
    #|  - shape: sink(safe($_))
    #|
  let source =
    #|fn sample {
    #|  sink(danger);
    #|  sink(safe(raw))
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 2)
  inspect(finding_signature(hits[0]), content="sample.mbt|example|0|2:3-2:15")
  inspect(finding_signature(hits[1]), content="sample.mbt|example|0|3:3-3:18")
}

///|
test "apply structural patterns-not uses independent bindings after positives fail" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Block pair descendants only after positive pair matching fails.
    #|patterns:
    #|  - shape: pair($(value:exp), $(value:exp))
    #|  - shape: target()
    #|patterns-not:
    #|  - shape: pair($(prefix:exp), $(value:exp))
    #|
  let source =
    #|fn sample {
    #|  pair(a, target());
    #|  target()
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(finding_signature(hits[0]), content="sample.mbt|example|1|3:3-3:11")
}

///|
test "apply structural positive root prunes descendants" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Prefer the wrapper root over its target child.
    #|patterns:
    #|  - shape: wrapper($(value:exp))
    #|  - shape: target()
    #|
  let source =
    #|fn sample {
    #|  wrapper(target())
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(finding_signature(hits[0]), content="sample.mbt|example|0|2:3-2:20")
}

///|
test "apply structural patterns-not prunes descendants after positives fail" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Skip target calls hidden inside blocked wrappers.
    #|patterns:
    #|  - shape: target()
    #|patterns-not:
    #|  - shape: wrapper($(value:exp))
    #|
  let source =
    #|fn sample {
    #|  wrapper(target());
    #|  target()
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(finding_signature(hits[0]), content="sample.mbt|example|0|3:3-3:11")
}

///|
test "apply structural root patterns preserve pattern indexes" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Mixed root patterns.
    #|patterns:
    #|  - shape: sink($(value:exp))
    #|  - shape: $(name:id)
    #|  - shape: $(value:const)
    #|
  let source =
    #|fn sample {
    #|  sink(42);
    #|  token;
    #|  7
    #|}
    #|
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  let pattern_indices : Array[Int] = []
  for hit in hits {
    pattern_indices.push(hit.pattern_index)
  }
  inspect(int_array_signature(pattern_indices), content="[0, 1, 2]")
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
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
}

///|
test "default structural matcher matches repeated if expression" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Repeated branch expression.
    #|patterns:
    #|  - shape: $(value:exp) == $(value:exp)
    #|
  let source =
    #|fn sample {
    #|  (if ready { a } else { b }) == (if ready { a } else { b });
    #|  (if ready { a } else { b }) == (if ready { a } else { c })
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(hits[0].rule_id, content="example")
}

///|
test "default structural matcher prunes descendants with patterns-not" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Skip target calls in repeated wrappers.
    #|patterns:
    #|  - shape: target()
    #|patterns-not:
    #|  - shape: wrapper($(value:exp), $(value:exp), $(body:exp))
    #|
  let source =
    #|fn sample {
    #|  wrapper(if ready { a } else { b }, if ready { a } else { b }, target());
    #|  target()
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(finding_signature(hits[0]), content="sample.mbt|example|0|3:3-3:11")
}

///|
test "default structural matcher applies id and const guards" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Guarded calls.
    #|patterns:
    #|  - shape: $(callee:id)($(value:const))
    #|    guard:
    #|      $callee: "^safe_"
    #|      $value: "^ok$"
    #|
  let source =
    #|fn sample {
    #|  safe_call("ok");
    #|  safe_call("bad");
    #|  danger_call("ok")
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
}
