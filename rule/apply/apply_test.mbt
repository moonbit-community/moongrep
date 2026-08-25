///|
using @compile {compile_rules}

///|
using @model {type CompiledRule, type RuleFinding}

///|
fn parse_root_node(source : String) -> @untyped_cst.CstNode raise {
  let parsed = @untyped_cst.parse_structure(source, name="apply test")
  guard parsed.diagnostics_view().is_empty() else {
    fail("expected source to parse")
  }
  parsed.root()
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
fn apply_structural_test_rules(
  file : String,
  root_node : @untyped_cst.CstNode,
  rules : Array[CompiledRule],
) -> Array[RuleFinding] {
  apply_structural_scan_plan_to_node(
    file,
    root_node,
    ScanPlan::from_rules(rules),
  )
}

///|
fn apply_taint_test_rules(
  file : String,
  root_node : @untyped_cst.CstNode,
  rules : Array[CompiledRule],
) -> Array[RuleFinding] raise {
  let hits : Array[RuleFinding] = []
  let plan = ScanPlan::from_rules(rules)
  if root_node.kind is @untyped_cst.Impls {
    for node in @cst.toplevel_nodes(root_node) {
      let node_hits = apply_taint_scan_plan_to_node(file, node, plan)
      for hit in node_hits {
        hits.push(hit)
      }
    }
  } else {
    let node_hits = apply_taint_scan_plan_to_node(file, root_node, plan)
    for hit in node_hits {
      hits.push(hit)
    }
  }
  hits
}

///|
fn location_signature(loc : @basic.Location) -> String {
  "\{loc.start.lnum}:\{loc.start.column()}-\{loc.end.lnum}:\{loc.end.column()}"
}

///|
fn finding_signature(finding : RuleFinding) -> String {
  "\{finding.file}|\{finding.rule_id}|\{finding.pattern_index}|\{location_signature(finding.loc)}"
}

///|
fn int_array_signature(values : Array[Int]) -> String {
  let parts : Array[String] = []
  for value in values {
    parts.push(value.to_string())
  }
  "[\{parts.join(", ")}]"
}

///|
fn apply_structural_rule_findings(
  source : String,
  rule_source : String,
) -> Array[RuleFinding] raise {
  let rules = compile_rule_source(rule_source)
  apply_structural_test_rules("sample.mbt", parse_root_node(source), rules)
}

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
test "apply inside expr and inner guards filter inherited bindings" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Guarded wrapper.
    #|inside-expr:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|patterns:
    #|  - shape: call($(name:id))
    #|    guard:
    #|      $name: "^safe_.*ok$"
    #|
  let source =
    #|fn sample {
    #|  wrapper(safe_ok, call(safe_ok));
    #|  wrapper(unsafe_ok, call(unsafe_ok));
    #|  wrapper(safe_bad, call(safe_bad))
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
test "apply inside expr guard filters outer context matches" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Guarded outer wrapper.
    #|inside-expr:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|    guard:
    #|      $name: "^safe_"
    #|patterns:
    #|  - shape: call()
    #|
  let source =
    #|fn sample {
    #|  wrapper(safe_ok, call());
    #|  wrapper(unsafe_ok, call());
    #|  wrapper(safe_bad, other())
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
test "apply structural rule matches guards inside expr" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Guarded wrapper.
    #|inside-expr:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|patterns:
    #|  - shape: call($(name:id), $(value:const))
    #|    guard:
    #|      $name: "^safe_.*ok$"
    #|      $value: "^(42|true)$"
    #|
  let source =
    #|fn sample {
    #|  wrapper(safe_ok, call(safe_ok, 42));
    #|  wrapper(unsafe_ok, call(unsafe_ok, 42));
    #|  wrapper(safe_bad, call(safe_bad, 42));
    #|  wrapper(safe_ok, call(safe_ok, false))
    #|}
    #|
  let rules = compile_rule_source(rule_source)
  let impls = parse_root_node(source)
  let hits = apply_structural_test_rules("sample.mbt", impls, rules)
  assert_eq(hits.length(), 1)
}

///|
test "inside expr reports the outer context location" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Nested target call.
    #|inside-expr:
    #|  - shape: wrapper(__TARGET__)
    #|patterns:
    #|  - shape: target(secret)
    #|
  let source =
    #|fn sample {
    #|  wrapper(holder(target(secret)))
    #|}
    #|
  let rules = compile_rule_source(rule_source)
  let impls = parse_root_node(source)
  let hits = apply_structural_test_rules("sample.mbt", impls, rules)
  assert_eq(hits.length(), 1)
  inspect(location_signature(hits[0].loc), content="2:3-2:34")
}

///|
test "inside expr merges inner hits and keeps the first pattern index" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped calls.
    #|inside-expr:
    #|  - shape: wrapper(__TARGET__)
    #|patterns:
    #|  - shape: second()
    #|  - shape: first()
    #|
  let source =
    #|fn sample {
    #|  wrapper({
    #|    first();
    #|    second()
    #|  })
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].pattern_index, 1)
  inspect(finding_signature(hits[0]), content="sample.mbt|example|1|2:3-5:5")
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
test "inside expr positive root ignores descendant patterns-not" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped holder positive wins before descendant negative.
    #|inside-expr:
    #|  - shape: wrapper(__TARGET__)
    #|patterns:
    #|  - shape: holder($(value:exp))
    #|patterns-not:
    #|  - shape: danger()
    #|
  let source =
    #|fn sample {
    #|  wrapper(holder(danger()))
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(finding_signature(hits[0]), content="sample.mbt|example|0|2:3-2:28")
}

///|
test "inside expr positive root wins over same-root patterns-not" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target roots match before negative patterns run.
    #|inside-expr:
    #|  - shape: wrapper(__TARGET__)
    #|patterns:
    #|  - shape: target($(value:exp))
    #|patterns-not:
    #|  - shape: target(blocked)
    #|
  let source =
    #|fn sample {
    #|  wrapper(target(allowed));
    #|  wrapper(target(blocked))
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 2)
  inspect(finding_signature(hits[0]), content="sample.mbt|example|0|2:3-2:27")
  inspect(finding_signature(hits[1]), content="sample.mbt|example|0|3:3-3:27")
}

///|
test "inside expr patterns-not rejects outer on uncovered negative" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped targets outside blocked branches.
    #|inside-expr:
    #|  - shape: wrapper(__TARGET__)
    #|patterns:
    #|  - shape: target()
    #|patterns-not:
    #|  - shape: blocker($(value:exp))
    #|
  let source =
    #|fn sample {
    #|  wrapper({
    #|    blocker(target());
    #|    target()
    #|  });
    #|  wrapper({
    #|    target();
    #|    blocker(target())
    #|  });
    #|  wrapper(blocker(target()));
    #|  wrapper(target())
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(finding_signature(hits[0]), content="sample.mbt|example|0|11:3-11:20")
}

///|
test "inside expr positive array access wins over patterns-not identifier" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped array access.
    #|inside-expr:
    #|  - shape: wrapper(__TARGET__)
    #|patterns:
    #|  - shape: $(array:exp)[$(index:exp)]
    #|patterns-not:
    #|  - shape: $(counter:id)
    #|
  let source =
    #|fn sample {
    #|  wrapper(arr[i])
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(finding_signature(hits[0]), content="sample.mbt|example|0|2:3-2:18")
}

///|
test "inside expr rejects only uncovered negative and accepts covered array access" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Covered array index use.
    #|inside-expr:
    #|  - shape: wrapper($(counter:id), __TARGET__)
    #|patterns:
    #|  - shape: arr[$(counter:id)]
    #|patterns-not:
    #|  - shape: $(counter:id)
    #|
  let source =
    #|fn sample {
    #|  wrapper(i, arr[i])
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(finding_signature(hits[0]), content="sample.mbt|example|0|2:3-2:21")
}

///|
test "inside expr rejects uncovered inherited id outside positive coverage" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Uncovered index use rejects the wrapper.
    #|inside-expr:
    #|  - shape: wrapper($(counter:id), __TARGET__)
    #|patterns:
    #|  - shape: arr[$(counter:id)]
    #|patterns-not:
    #|  - shape: $(counter:id)
    #|
  let source =
    #|fn sample {
    #|  wrapper(i, {
    #|    arr[i];
    #|    println(i)
    #|  })
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 0)
}

///|
test "inside expr merges multiple covered positive hits" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Multiple covered index uses.
    #|inside-expr:
    #|  - shape: wrapper($(counter:id), __TARGET__)
    #|patterns:
    #|  - shape: arr[$(counter:id)]
    #|patterns-not:
    #|  - shape: $(counter:id)
    #|
  let source =
    #|fn sample {
    #|  wrapper(i, {
    #|    arr[i];
    #|    arr[i]
    #|  })
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(finding_signature(hits[0]), content="sample.mbt|example|0|2:3-5:5")
}

///|
test "inside expr reject-uncovered-negative respects shadowed inherited identifiers" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Shadowed index use belongs to inner binding.
    #|inside-expr:
    #|  - shape: wrapper($(counter:id), __TARGET__)
    #|patterns:
    #|  - shape: arr[$(counter:id)]
    #|patterns-not:
    #|  - shape: $(counter:id)
    #|
  let source =
    #|fn sample {
    #|  wrapper(i, {
    #|    arr[i];
    #|    let i = other;
    #|    println(i)
    #|  })
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(finding_signature(hits[0]), content="sample.mbt|example|0|2:3-6:5")
}

///|
test "inside expr accepts only loop counter uses covered by array access" {
  let rule_source =
    #|id: example
    #|description: |
    #|  C-style forward array iteration.
    #|inside-expr:
    #|  - shape: |
    #|      for $(counter:id) = 0; $(counter:id) < $(arr:id).length(); $(counter:id) = $(counter:id) + 1 {
    #|        __TARGET__
    #|      }
    #|patterns:
    #|  - shape: |
    #|      $(arr:id)[$(counter:id)]
    #|patterns-not:
    #|  - shape: $(counter:id)
    #|
  let source =
    #|fn sample(arr) {
    #|  for i = 0; i < arr.length(); i = i + 1 {
    #|    wrapper(arr[i])
    #|  }
    #|  for i = 0; i < arr.length(); i = i + 1 {
    #|    arr[i];
    #|    println(i)
    #|  }
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].loc.start.lnum, 2)
}

///|
test "inside expr with only patterns-not reports outer when target subtree is clean" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target without danger.
    #|inside-expr:
    #|  - shape: wrapper(__TARGET__)
    #|patterns-not:
    #|  - shape: danger()
    #|
  let source =
    #|fn sample {
    #|  wrapper(safe());
    #|  wrapper(danger());
    #|  wrapper(holder(danger()))
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(finding_signature(hits[0]), content="sample.mbt|example|0|2:3-2:18")
}

///|
test "inside expr only patterns-not respects shadowed inherited identifiers" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target without same-name target call.
    #|inside-expr:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|patterns-not:
    #|  - shape: target($(name:id))
    #|
  let source =
    #|fn sample {
    #|  wrapper(x, {
    #|    let x = other;
    #|    target(x)
    #|  });
    #|  wrapper(x, target(x))
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].loc.start.lnum, 2)
}

///|
test "inside expr condition binders shadow inherited identifiers" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target call.
    #|inside-expr:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|patterns:
    #|  - shape: target($(name:id))
    #|
  let source =
    #|fn sample {
    #|  wrapper(x, if maybe is Some(x) { target(x) } else { fallback });
    #|  wrapper(x, if maybe is Some(x) && ready { target(x) } else { fallback });
    #|  wrapper(x, if maybe is Some(x) && target(x) { fallback } else { fallback });
    #|  wrapper(x, {
    #|    guard maybe is Some(x) else { fallback }
    #|    target(x)
    #|  });
    #|  wrapper(x, match value { _ if maybe is Some(x) => target(x) });
    #|  wrapper(x, while maybe is Some(x) { target(x) });
    #|  wrapper(x, for i = 0; maybe is Some(x); i = target(x) { target(x) });
    #|  wrapper(x, [for i = 0; maybe is Some(x); i = i + 1 => target(x)]);
    #|  wrapper(x, [for i = 0; i < 1; i = i + 1 if maybe is Some(x) => target(x)]);
    #|  wrapper(x, if ready { target(x) } else { fallback });
    #|  wrapper(x, if maybe is Some(y) { target(x) } else { fallback })
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 2)
  assert_eq(hits[0].loc.start.lnum, 14)
  assert_eq(hits[1].loc.start.lnum, 15)
}

///|
test "inside expr patterns-not ignores condition-shadowed inherited identifiers" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target without same-name target call.
    #|inside-expr:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|patterns-not:
    #|  - shape: target($(name:id))
    #|
  let source =
    #|fn sample {
    #|  wrapper(x, if maybe is Some(x) { target(x) } else { fallback });
    #|  wrapper(x, if maybe is Some(x) && target(x) { fallback } else { fallback });
    #|  wrapper(x, {
    #|    guard maybe is Some(x) else { fallback }
    #|    target(x)
    #|  });
    #|  wrapper(x, match value { _ if maybe is Some(x) => target(x) });
    #|  wrapper(x, while maybe is Some(x) { target(x) });
    #|  wrapper(x, for i = 0; maybe is Some(x); i = i + 1 { target(x) });
    #|  wrapper(x, [for i = 0; maybe is Some(x); i = i + 1 => target(x)]);
    #|  wrapper(x, [for i = 0; i < 1; i = i + 1 if maybe is Some(x) => target(x)]);
    #|  wrapper(x, if ready { target(x) } else { fallback });
    #|  wrapper(x, if maybe is Some(y) { target(x) } else { fallback })
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 8)
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
test "inside expr preserves source order of outer locations" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target call.
    #|inside-expr:
    #|  - shape: wrapper(__TARGET__)
    #|patterns:
    #|  - shape: target()
    #|
  let source =
    #|fn sample {
    #|  wrapper(holder(target()));
    #|  wrapper(holder(other()));
    #|  wrapper(holder(target()))
    #|}
    #|
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 2)
  assert_eq(hits[0].pattern_index, 0)
  assert_eq(hits[1].pattern_index, 0)
  assert_true(hits[0].loc.start.lnum < hits[1].loc.start.lnum)
  assert_eq(hits[0].loc.start.column(), 3)
  assert_eq(hits[1].loc.start.column(), 3)
}

///|
test "inside toplevel matches functions and inherits bindings" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Guarded top-level function.
    #|inside-toplevel:
    #|  - shape: |
    #|      fn $(name:id)($(param:id) : Int) -> Int { __TARGET__ }
    #|    guard:
    #|      $name: "^safe_"
    #|patterns:
    #|  - shape: call($(param:id))
    #|
  let source =
    #|fn safe_run(value : Int) -> Int { call(value) }
    #|fn unsafe_run(value : Int) -> Int { call(value) }
    #|fn safe_other(value : Int) -> Int { call(other) }
    #|
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
  inspect(hits[0].rule_id, content="example")
  inspect(location_signature(hits[0].loc), content="1:35-1:46")
}

///|
test "inside toplevel defaults function shapes to partial matching" {
  let rule_source =
    #|id: example
    #|description: Broad function context.
    #|inside-toplevel:
    #|  - shape: fn $_ { __TARGET__ }
    #|patterns:
    #|  - shape: marker()
    #|
  let source =
    #|fn plain { marker() }
    #|pub fn parameters(value : Int) -> String { marker() }
    #|priv async fn[T] generic(value : T) -> T noraise { marker() }
    #|/// Documented function.
    #|#custom.attribute
    #|fn documented { marker() }
    #|fn[T] Box::map(value : T) -> T { marker() }
    #|fn fallible(value : Int) -> Int raise { marker() }
    #|fn constrained where { requirement: required() } { marker() }
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 7)
}

///|
test "inside toplevel partial matching keeps explicit function fields exact" {
  let rule_source =
    #|id: example
    #|description: Explicit function header.
    #|inside-toplevel:
    #|  - shape: |
    #|      /// Required documentation.
    #|      #custom.attribute
    #|      pub async fn[T] Box::run() -> Int noraise { __TARGET__ }
    #|    match-mode: partial
    #|patterns:
    #|  - shape: marker()
    #|
  let source =
    #|/// Required documentation.
    #|#custom.attribute
    #|pub async fn[T] Box::run() -> Int noraise { marker() }
    #|#custom.attribute
    #|pub async fn[T] Box::run() -> Int noraise { marker() }
    #|/// Required documentation.
    #|pub async fn[T] Box::run() -> Int noraise { marker() }
    #|/// Required documentation.
    #|#custom.attribute
    #|priv async fn[T] Box::run() -> Int noraise { marker() }
    #|/// Required documentation.
    #|#custom.attribute
    #|pub fn[T] Box::run() -> Int noraise { marker() }
    #|/// Required documentation.
    #|#custom.attribute
    #|pub async fn[U] Box::run() -> Int noraise { marker() }
    #|/// Required documentation.
    #|#custom.attribute
    #|pub async fn[T] Other::run() -> Int noraise { marker() }
    #|/// Required documentation.
    #|#custom.attribute
    #|pub async fn[T] Box::run -> Int noraise { marker() }
    #|/// Required documentation.
    #|#custom.attribute
    #|pub async fn[T] Box::run() -> String noraise { marker() }
    #|/// Required documentation.
    #|#custom.attribute
    #|pub async fn[T] Box::run() -> Int { marker() }
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 2)
}

///|
test "inside toplevel partial matching keeps an explicit where clause exact" {
  let rule_source =
    #|id: example
    #|description: Explicit function where clause.
    #|inside-toplevel:
    #|  - shape: |
    #|      fn $_ where { requirement: required() } { __TARGET__ }
    #|patterns:
    #|  - shape: marker()
    #|
  let source =
    #|fn exact where { requirement: required() } { marker() }
    #|fn missing { marker() }
    #|fn different where { requirement: other() } { marker() }
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].loc.start.lnum, 1)
}

///|
test "inside toplevel explicit async excludes synchronous functions" {
  let rule_source =
    #|id: example
    #|description: Async function context.
    #|inside-toplevel:
    #|  - shape: async fn $_ { __TARGET__ }
    #|patterns:
    #|  - shape: marker()
    #|
  let source =
    #|async fn asynchronous(value : Int) -> Int { marker() }
    #|fn synchronous(value : Int) -> Int { marker() }
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].loc.start.lnum, 1)
}

///|
test "inside toplevel exact mode preserves complete function matching" {
  let rule_source =
    #|id: example
    #|description: Exact function context.
    #|inside-toplevel:
    #|  - shape: |
    #|      /// Rule documentation.
    #|      fn $_ { __TARGET__ }
    #|    match-mode: exact
    #|patterns:
    #|  - shape: marker()
    #|
  let source =
    #|fn exact { marker() }
    #|/// Rule documentation.
    #|fn documented { marker() }
    #|/// Different documentation.
    #|fn changed_documentation { marker() }
    #|pub fn public { marker() }
    #|fn parameters() { marker() }
    #|async fn asynchronous { marker() }
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 3)
  assert_eq(hits[0].loc.start.lnum, 1)
}

///|
test "inside toplevel rule order is independent of same-location docstrings" {
  let aaa_rule =
    #|id: doc-aaa
    #|description: AAA documentation shape.
    #|inside-toplevel:
    #|  - shape: |
    #|      /// AAA
    #|      fn same { __TARGET__ }
    #|    match-mode: exact
    #|patterns:
    #|  - shape: marker()
    #|
  let bbb_rule =
    #|id: doc-bbb
    #|description: BBB documentation shape.
    #|inside-toplevel:
    #|  - shape: |
    #|      /// BBB
    #|      fn same { __TARGET__ }
    #|    match-mode: exact
    #|patterns:
    #|  - shape: marker()
    #|
  let source = "/// AAA\nfn same { marker() }\n"
  let root = parse_root_node(source)
  let rules_ab = compile_rules([
    @model.RawRuleSpec::from_str("/tmp/rules/aaa.yaml", "/tmp/rules", aaa_rule),
    @model.RawRuleSpec::from_str("/tmp/rules/bbb.yaml", "/tmp/rules", bbb_rule),
  ])
  let rules_ba = compile_rules([
    @model.RawRuleSpec::from_str("/tmp/rules/bbb.yaml", "/tmp/rules", bbb_rule),
    @model.RawRuleSpec::from_str("/tmp/rules/aaa.yaml", "/tmp/rules", aaa_rule),
  ])
  let hits_ab = apply_structural_test_rules("sample.mbt", root, rules_ab)
  let hits_ba = apply_structural_test_rules("sample.mbt", root, rules_ba)
  assert_eq(hits_ab.length(), 2)
  assert_eq(hits_ba.length(), 2)
  let mut ab_has_aaa = false
  let mut ab_has_bbb = false
  let mut ba_has_aaa = false
  let mut ba_has_bbb = false
  for hit in hits_ab {
    ab_has_aaa = ab_has_aaa || hit.rule_id == "doc-aaa"
    ab_has_bbb = ab_has_bbb || hit.rule_id == "doc-bbb"
  }
  for hit in hits_ba {
    ba_has_aaa = ba_has_aaa || hit.rule_id == "doc-aaa"
    ba_has_bbb = ba_has_bbb || hit.rule_id == "doc-bbb"
  }
  assert_true(ab_has_aaa && ab_has_bbb)
  assert_true(ba_has_aaa && ba_has_bbb)
}

///|
test "inside toplevel keeps non-function defaults exact" {
  let rule_source =
    #|id: example
    #|description: Exact top-level let context.
    #|inside-toplevel:
    #|  - shape: let value = __TARGET__
    #|patterns:
    #|  - shape: marker()
    #|
  let source =
    #|let value = marker()
    #|pub let value = marker()
    #|let value : Int = marker()
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].loc.start.lnum, 1)
}

///|
test "inside toplevel matches top-level const initializers" {
  let rule_source =
    #|id: example
    #|description: Exact top-level const context.
    #|inside-toplevel:
    #|  - shape: const MATCHED = __TARGET__
    #|patterns:
    #|  - shape: marker()
    #|
  let source =
    #|const MATCHED = wrapper(marker())
    #|const OTHER = wrapper(marker())
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].loc.start.lnum, 1)
}

///|
test "inside toplevel with only patterns-not reports clean top-level let" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Clean top-level binding.
    #|inside-toplevel:
    #|  - shape: let $(name:id) = wrapper(__TARGET__)
    #|patterns-not:
    #|  - shape: forbidden($(name:id))
    #|
  let source =
    #|let clean = wrapper(ok(clean))
    #|let dirty = wrapper(forbidden(dirty))
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(location_signature(hits[0].loc), content="1:1-1:31")
}

///|
test "inside toplevel patterns-not rejects uncovered negative" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Only covered names are allowed.
    #|inside-toplevel:
    #|  - shape: fn $(name:id) { __TARGET__ }
    #|patterns:
    #|  - shape: arr[$(name:id)]
    #|patterns-not:
    #|  - shape: $(name:id)
    #|
  let source =
    #|fn x { arr[x] }
    #|fn y { y; arr[y] }
    #|fn z { arr[z]; z }
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(
    location_signature(hits[0].loc),
    content=(
      #|1:8-1:14
    ),
  )
}

///|
test "apply structural rule supports inside expr inherited bindings" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target call.
    #|inside-expr:
    #|  - shape: wrapper($(prefix:exp), __TARGET__)
    #|patterns:
    #|  - shape: target.call($(prefix:exp))
    #|
  let source =
    #|fn sample {
    #|  wrapper(make(), target.call(make()));
    #|  wrapper(make(), target.call(other))
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
test "apply inside expr inherits ellipsis sequence bindings" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Reuse an outer argument prefix inside the target.
    #|inside-expr:
    #|  - shape: wrapper($$$args, __TARGET__)
    #|patterns:
    #|  - shape: target($$$args)
    #|
  let source =
    #|fn sample {
    #|  wrapper(a, b, target(a, b));
    #|  wrapper(a, b, target(a, other))
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
test "inside expr plain names do not reference inherited bindings" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Plain names remain literal.
    #|inside-expr:
    #|  - shape: wrapper($(prefix:exp), __TARGET__)
    #|patterns:
    #|  - shape: target.call(prefix)
    #|
  let source =
    #|fn sample {
    #|  wrapper(token, target.call(token))
    #|}
    #|
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 0)
}

///|
test "apply structural rule inherits inside expr identifier bindings" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target call.
    #|inside-expr:
    #|  - shape: wrapper($(prefix:id), __TARGET__)
    #|patterns:
    #|  - shape: target.call($(prefix:id))
    #|
  let source =
    #|fn sample {
    #|  wrapper(token, target.call(token));
    #|  wrapper(token, target.call(other))
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
test "inside expr inherited id is blocked after lexical let shadow" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target call.
    #|inside-expr:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|patterns:
    #|  - shape: target($(name:id))
    #|
  let source =
    #|fn sample {
    #|  wrapper(x, {
    #|    let x = y;
    #|    target(x)
    #|  })
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 0)
}

///|
test "inside expr inherited id still matches without shadow" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target call.
    #|inside-expr:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|patterns:
    #|  - shape: target($(name:id))
    #|
  let source =
    #|fn sample {
    #|  wrapper(x, target(x))
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
}

///|
test "inside expr later shadow does not block earlier candidate" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target call.
    #|inside-expr:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|patterns:
    #|  - shape: target($(name:id))
    #|
  let source =
    #|fn sample {
    #|  wrapper(x, {
    #|    target(x);
    #|    let x = y;
    #|    done
    #|  })
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
}

///|
test "inside expr only blocks patterns referencing shadowed outer id" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target call.
    #|inside-expr:
    #|  - shape: wrapper($(left:id), $(right:id), __TARGET__)
    #|patterns:
    #|  - shape: target($(right:id))
    #|  - shape: target($(left:id))
    #|
  let source =
    #|fn sample {
    #|  wrapper(x, y, {
    #|    let x = other;
    #|    target(y);
    #|    target(x)
    #|  })
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].pattern_index, 0)
}

///|
test "inside expr traverses guard target children" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Guard target call.
    #|inside-expr:
    #|  - shape: wrapper(__TARGET__)
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
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
}

///|
test "inside expr traverses reverse pipe target children" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Reverse pipe target call.
    #|inside-expr:
    #|  - shape: wrapper(__TARGET__)
    #|patterns:
    #|  - shape: target()
    #|
  let source =
    #|fn sample {
    #|  wrapper(sink <| target())
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
test "inside expr traverses list comprehension target children" {
  let rule_source =
    #|id: example
    #|description: |
    #|  List comprehension target call.
    #|inside-expr:
    #|  - shape: wrapper(__TARGET__)
    #|patterns:
    #|  - shape: target(item)
    #|
  let source =
    #|fn sample {
    #|  wrapper([for item in items if allow(item) => target(item)])
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
test "default structural matcher carries inside target bindings" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target using same expression.
    #|inside-expr:
    #|  - shape: wrapper($(prefix:exp), __TARGET__)
    #|patterns:
    #|  - shape: target($(prefix:exp))
    #|
  let source =
    #|fn sample {
    #|  wrapper(if ready { a } else { b }, target(if ready { a } else { b }));
    #|  wrapper(if ready { a } else { b }, target(if ready { a } else { c }))
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
}

///|
test "default structural matcher respects shadowed inherited identifiers" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target call.
    #|inside-expr:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|patterns:
    #|  - shape: target($(name:id))
    #|
  let source =
    #|fn sample {
    #|  wrapper(x, {
    #|    let x = y;
    #|    target(x)
    #|  });
    #|  wrapper(x, target(x))
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
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
  let hits = apply_taint_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
  inspect(hits[0].rule_id, content="example")
}

///|
test "apply structural rule matches let pattern header with omitted body" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Tuple let header.
    #|patterns:
    #|  - shape: let ($_, $_) = $_
    #|
  let source =
    #|fn sample {
    #|  let (fst, snd) = tuple; consume(fst); snd
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
test "apply structural rule matches guard header with omitted body" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Guard header.
    #|patterns:
    #|  - shape: guard ready() else { fallback() }
    #|
  let source =
    #|fn sample {
    #|  guard ready() else { fallback() }
    #|  { continue_work(); finish_work() }
    #|}
    #|
  let hits = apply_structural_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
  inspect(location_signature(hits[0].loc), content="2:3-3:37")
}

///|
test "apply reports ordinary let continuation without function braces" {
  let rule_source =
    #|id: example
    #|description: Let header.
    #|patterns:
    #|  - shape: let $(name:id) = source()
    #|
  let source =
    #|fn sample {
    #|  let value = source()
    #|  consume(value)
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(location_signature(hits[0].loc), content="2:3-3:17")
}

///|
test "inside expr continuation target matches a complete multi-statement sequence" {
  let rule_source =
    #|id: example
    #|description: Matching continuation sequence.
    #|inside-expr:
    #|  - shape: let $(name:id) = source(); __TARGET__
    #|patterns:
    #|  - shape: consume($(name:id)); finish($(name:id))
    #|
  let source =
    #|fn sample {
    #|  let item = source()
    #|  consume(item)
    #|  finish(item)
    #|}
    #|fn ignored {
    #|  let other = source()
    #|  consume(other)
    #|  finish(item)
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].pattern_index, 0)
  inspect(location_signature(hits[0].loc), content="2:3-4:15")
}

///|
test "inside expr continuation target matches inside a nested block" {
  let rule_source =
    #|id: example
    #|description: Matching a nested continuation sequence.
    #|inside-expr:
    #|  - shape: wrapper({ let $(name:id) = source(); __TARGET__ })
    #|patterns:
    #|  - shape: consume($(name:id)); finish($(name:id))
    #|
  let source =
    #|fn sample {
    #|  wrapper({
    #|    let item = source()
    #|    consume(item)
    #|    finish(item)
    #|  })
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].pattern_index, 0)
  inspect(location_signature(hits[0].loc), content="2:3-6:5")
}

///|
test "inside expr multi-statement continuation targets traverse expressions" {
  let cases = [
    (
      "let mut $(name:id) = source(); __TARGET__", "target($(name:id))", "fn sample {\n  let mut item = source()\n  skip()\n  target(item)\n}\n",
      "2:3-4:15",
    ),
    (
      "guard ready() else { fallback() }; __TARGET__", "target()", "fn sample {\n  guard ready() else { fallback() }\n  skip()\n  target()\n}\n",
      "2:3-4:11",
    ),
  ]
  for case in cases {
    let (inside_shape, pattern_shape, source, expected_loc) = case
    let rule_source =
      $|id: example
      $|description: Traversing a continuation target.
      $|inside-expr:
      $|  - shape: \{inside_shape}
      $|patterns:
      $|  - shape: \{pattern_shape}
      $|
    let hits = apply_structural_rule_findings(source, rule_source)
    assert_eq(hits.length(), 1)
    assert_eq(location_signature(hits[0].loc), expected_loc)
  }
}

///|
test "inside expr empty continuation target supports patterns-not only" {
  let rule_source =
    #|id: example
    #|description: Empty clean continuation.
    #|inside-expr:
    #|  - shape: let $(name:id) = source(); __TARGET__
    #|patterns-not:
    #|  - shape: danger($(name:id))
    #|
  let source =
    #|fn sample {
    #|  prepare()
    #|  let item = source()
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].pattern_index, 0)
  assert_eq(hits[0].loc.start.lnum, 3)
  assert_eq(hits[0].loc.start.column(), 3)
}

///|
test "inside expr single-statement continuation target preserves location" {
  let rule_source =
    #|id: example
    #|description: Single continuation expression.
    #|inside-expr:
    #|  - shape: let $(name:id) = source(); __TARGET__
    #|patterns:
    #|  - shape: target($(name:id))
    #|
  let source =
    #|fn sample {
    #|  let item = source()
    #|  target(item)
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].pattern_index, 0)
  inspect(location_signature(hits[0].loc), content="2:3-3:15")
}

///|
test "apply rejects header-only non-shortcut continuations" {
  let cases = [
    (
      "let mut value = source()", "fn sample { let mut value = source(); consume(value) }",
    ),
    (
      "letrec recur = fn(value) { value }", "fn sample { letrec recur = fn(value) { value }; recur(source()) }",
    ),
    ("defer cleanup()", "fn sample { defer cleanup(); continue_work() }"),
  ]
  for case in cases {
    let (shape, source) = case
    let rule_source =
      $|id: example
      $|description: Header only.
      $|patterns:
      $|  - shape: \{shape}
      $|
    assert_eq(apply_structural_rule_findings(source, rule_source).length(), 0)
  }
}

///|
test "apply accepts complete non-shortcut continuation shapes" {
  let cases = [
    "let mut value = source(); consume(value)", "letrec recur = fn(value) { value }; recur(source())",
    "defer cleanup(); continue_work()",
  ]
  for shape in cases {
    let rule_source =
      $|id: example
      $|description: Complete continuation.
      $|patterns:
      $|  - shape: \{shape}
      $|
    let source = "fn sample { \{shape} }"
    assert_eq(apply_structural_rule_findings(source, rule_source).length(), 1)
  }
}

///|
test "proof let matches only its header and leaves its continuation visible" {
  let proof_rule =
    #|id: example
    #|description: Proof header.
    #|patterns:
    #|  - shape: proof_let witness = fact()
    #|
  let continuation_rule =
    #|id: example
    #|description: Continuation.
    #|patterns:
    #|  - shape: finish(witness)
    #|
  let source =
    #|fn sample {
    #|  proof_let witness = fact()
    #|  finish(witness)
    #|}
    #|
  let proof_hits = apply_structural_rule_findings(source, proof_rule)
  assert_eq(proof_hits.length(), 1)
  inspect(location_signature(proof_hits[0].loc), content="2:3-2:29")
  let continuation_hits = apply_structural_rule_findings(
    source, continuation_rule,
  )
  assert_eq(continuation_hits.length(), 1)
  inspect(location_signature(continuation_hits[0].loc), content="3:3-3:18")
}

///|
test "apply broad expressions skip function body wrapper braces" {
  let ignore_rule =
    #|id: example
    #|description: Any expression.
    #|patterns:
    #|  - shape: $_
    #|
  let capture_rule =
    #|id: example
    #|description: Any captured expression.
    #|patterns:
    #|  - shape: $(root:exp)
    #|
  let source =
    #|fn sample {
    #|  f <| value
    #|}
    #|
  let ignore_hits = apply_structural_rule_findings(source, ignore_rule)
  let capture_hits = apply_structural_rule_findings(source, capture_rule)
  assert_eq(ignore_hits.length(), 1)
  assert_eq(capture_hits.length(), 1)
  inspect(location_signature(ignore_hits[0].loc), content="2:3-2:13")
  inspect(location_signature(capture_hits[0].loc), content="2:3-2:13")
}

///|
test "apply explicit block shapes do not match function body wrappers" {
  let rule_source =
    #|id: example
    #|description: Explicit block.
    #|patterns:
    #|  - shape: "{ a; b }"
    #|
  let source =
    #|fn wrapper { a; b }
    #|fn nested { { a; b } }
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(location_signature(hits[0].loc), content="2:13-2:21")
}

///|
test "negative block patterns distinguish wrappers from explicit blocks" {
  let rule_source =
    #|id: example
    #|description: Target outside an explicit blocked block.
    #|patterns:
    #|  - shape: target()
    #|patterns-not:
    #|  - shape: "{ target(); other() }"
    #|
  let source =
    #|fn wrapper { target(); other() }
    #|fn nested { { target(); other() } }
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(location_signature(hits[0].loc), content="1:14-1:22")
}

///|
test "inside toplevel target traversal skips function body wrapper blocks" {
  let rule_source =
    #|id: example
    #|description: Inner expression.
    #|inside-toplevel:
    #|  - shape: fn sample { __TARGET__ }
    #|patterns:
    #|  - shape: $(root:exp)
    #|
  let source =
    #|fn sample {
    #|  target()
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(location_signature(hits[0].loc), content="2:3-2:11")
}

///|
test "inside expr target traversal distinguishes lambda bodies from blocks" {
  let rule_source =
    #|id: example
    #|description: Explicit block in a lambda.
    #|inside-expr:
    #|  - shape: wrapper(fn() { __TARGET__ })
    #|patterns:
    #|  - shape: "{ target(); other() }"
    #|
  let source =
    #|fn sample {
    #|  wrapper(fn() { target(); other() });
    #|  wrapper(fn() { { target(); other() } })
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].loc.start.lnum, 3)
}

///|
test "inside expr negative patterns use lambda body candidates" {
  let rule_source =
    #|id: example
    #|description: Lambda without an explicit blocked block.
    #|inside-expr:
    #|  - shape: wrapper(fn() { __TARGET__ })
    #|patterns-not:
    #|  - shape: "{ target(); other() }"
    #|
  let source =
    #|fn sample {
    #|  wrapper(fn() { target(); other() });
    #|  wrapper(fn() { { target(); other() } })
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].loc.start.lnum, 2)
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
  let hits = apply_taint_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
  inspect(hits[0].rule_id, content="example")
  assert_eq(hits[0].pattern_index, 0)
}

///|
test "apply taint rule covers migrated CST field mappings" {
  let rule_source =
    #|id: regression-probe
    #|description: Migrated CST taint fields.
    #|taint:
    #|  sources:
    #|    - shape: get_user_inputs()
    #|    - shape: get_user_input()
    #|  sinks:
    #|    - shape: sink(__SOURCE__)
    #|
  let source =
    #|fn foreach_case {
    #|  for item in get_user_inputs() { sink(item) }
    #|}
    #|fn try_case {
    #|  try get_user_input() catch {
    #|    _ => ()
    #|  } noraise {
    #|    result => sink(result)
    #|  }
    #|}
    #|fn array_get_case {
    #|  let values = [get_user_input()];
    #|  sink(values[0])
    #|}
    #|fn array_set_case {
    #|  values[0] = sink(get_user_input())
    #|}
    #|fn else_case {
    #|  if clean() { () } else { sink(get_user_input()) }
    #|}
    #|
  let hits = apply_taint_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 5)
}

///|
test "taint sink locates source argument after ellipsis captures" {
  let rule_source =
    #|id: example
    #|description: |
    #|  User input reaches a variadic sink slot.
    #|taint:
    #|  sources:
    #|    - shape: get_user_input()
    #|  sinks:
    #|    - shape: sink(prefix, $$$before, marker, __SOURCE__, $$$after)
    #|
  let source =
    #|fn sample {
    #|  let x = get_user_input();
    #|  sink(prefix, clean, also_clean, marker, x, trailing)
    #|}
    #|
  let hits = apply_taint_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
}

///|
test "default taint matcher applies source sink and sanitizer patterns" {
  let rule_source =
    #|id: example
    #|description: |
    #|  User input reaches sink unless sanitized.
    #|taint:
    #|  sources:
    #|    - shape: tagged_source($(tag:exp), $(tag:exp))
    #|  sinks:
    #|    - shape: tagged_sink($(tag:exp), $(tag:exp), __SOURCE__)
    #|  sanitizers:
    #|    - shape: clean($(tag:exp), $(tag:exp), __SOURCE__)
    #|
  let source =
    #|fn sample {
    #|  let dirty = tagged_source(if ready { a } else { b }, if ready { a } else { b });
    #|  tagged_sink(if ready { a } else { b }, if ready { a } else { b }, dirty);
    #|  tagged_sink(if ready { a } else { b }, if ready { a } else { b }, clean(if ready { a } else { b }, if ready { a } else { b }, dirty))
    #|}
    #|
  let hits = apply_taint_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
  inspect(hits[0].rule_id, content="example")
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
  let hits = apply_taint_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
  inspect(hits[0].rule_id, content="example")
  assert_eq(hits[0].pattern_index, 0)
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
  let hits = apply_taint_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 0)
}

///|
test "apply taint rule matches source sink sanitizer" {
  let rule_source =
    #|id: example
    #|description: |
    #|  User input reaches sink unless sanitized.
    #|taint:
    #|  sources:
    #|    - shape: get_user_input()
    #|  sinks:
    #|    - shape: sink(__SOURCE__)
    #|  sanitizers:
    #|    - shape: clean(__SOURCE__)
    #|
  let source =
    #|fn sample {
    #|  let dirty = get_user_input();
    #|  sink(dirty);
    #|  sink(clean(dirty))
    #|}
    #|
  let rules = compile_rule_source(rule_source)
  let impls = parse_root_node(source)
  let hits = apply_taint_test_rules("sample.mbt", impls, rules)
  assert_eq(hits.length(), 1)
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
  let hits = apply_taint_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 3)
  assert_eq(hits[0].pattern_index, 0)
  assert_eq(hits[1].pattern_index, 1)
  assert_eq(hits[2].pattern_index, 2)
}

///|
test "inside expr tries multiple outer shapes in yaml order" {
  let rule_source =
    #|id: example
    #|description: Multiple expression contexts.
    #|inside-expr:
    #|  - shape: wrapper(__TARGET__)
    #|  - shape: container(__TARGET__)
    #|patterns:
    #|  - shape: target()
    #|
  let source =
    #|fn sample {
    #|  wrapper(target());
    #|  container(target())
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 2)
  assert_eq(hits[0].loc.start.lnum, 2)
  assert_eq(hits[1].loc.start.lnum, 3)
}

///|
test "inside expr selects the first overlapping outer alternative" {
  let rule_source =
    #|id: example
    #|description: Ordered overlapping contexts.
    #|inside-expr:
    #|  - shape: wrapper($(name:id), $_, __TARGET__)
    #|  - shape: wrapper($_, $(name:id), __TARGET__)
    #|patterns:
    #|  - shape: target($(name:id))
    #|
  let source =
    #|fn sample {
    #|  wrapper(first, second, target(first));
    #|  wrapper(first, second, target(second))
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].loc.start.lnum, 2)
}

///|
test "inside expr falls through when an earlier outer guard fails" {
  let rule_source =
    #|id: example
    #|description: Guarded ordered contexts.
    #|inside-expr:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|    guard:
    #|      $name: "^primary$"
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|    guard:
    #|      $name: "^fallback$"
    #|patterns:
    #|  - shape: target($(name:id))
    #|
  let source =
    #|fn sample {
    #|  wrapper(fallback, target(fallback))
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].loc.start.lnum, 2)
}

///|
test "inside expr does not try later alternatives after inner matching fails" {
  let rule_source =
    #|id: example
    #|description: No fallback after outer selection.
    #|inside-expr:
    #|  - shape: wrapper($(name:id), $_, __TARGET__)
    #|  - shape: wrapper($_, $(name:id), __TARGET__)
    #|patterns:
    #|  - shape: target($(name:id))
    #|
  let source =
    #|fn sample {
    #|  wrapper(first, second, target(second))
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 0)
}

///|
test "inside expr alternatives support patterns-not only" {
  let rule_source =
    #|id: example
    #|description: Clean ordered contexts.
    #|inside-expr:
    #|  - shape: wrapper(__TARGET__)
    #|  - shape: container(__TARGET__)
    #|patterns-not:
    #|  - shape: danger()
    #|
  let source =
    #|fn sample {
    #|  wrapper(safe());
    #|  container(safe());
    #|  wrapper(danger());
    #|  container(holder(danger()))
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 2)
  assert_eq(hits[0].loc.start.lnum, 2)
  assert_eq(hits[1].loc.start.lnum, 3)
}

///|
test "inside expr alternatives preserve outer locations and inner pattern indexes" {
  let rule_source =
    #|id: example
    #|description: Ordered context metadata.
    #|inside-expr:
    #|  - shape: wrapper(__TARGET__)
    #|  - shape: container(__TARGET__)
    #|patterns:
    #|  - shape: first()
    #|  - shape: second()
    #|
  let source =
    #|fn sample {
    #|  container(holder(second()))
    #|}
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].pattern_index, 1)
  assert_eq(hits[0].loc.start.lnum, 2)
  assert_eq(hits[0].loc.start.column(), 3)
}

///|
test "inside toplevel tries multiple outer shapes and inherits bindings" {
  let rule_source =
    #|id: example
    #|description: Multiple top-level contexts.
    #|inside-toplevel:
    #|  - shape: fn $(name:id) { __TARGET__ }
    #|  - shape: let $(name:id) = wrapper(__TARGET__)
    #|patterns:
    #|  - shape: target($(name:id))
    #|
  let source =
    #|fn run { target(run) }
    #|let value = wrapper(target(value))
    #|
  let hits = apply_structural_rule_findings(source, rule_source)
  assert_eq(hits.length(), 2)
  assert_eq(hits[0].loc.start.lnum, 1)
  assert_eq(hits[1].loc.start.lnum, 2)
  assert_eq(hits[0].pattern_index, 0)
  assert_eq(hits[1].pattern_index, 0)
}
