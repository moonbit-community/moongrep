///|
using @compile {compile_rules}

///|
using @model {type CompiledRule, type RuleFinding}

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
fn location_signature(loc : @basic.Location) -> String {
  "\{loc.start.lnum}:\{loc.start.column()}-\{loc.end.lnum}:\{loc.end.column()}"
}

///|
fn finding_signature(finding : RuleFinding) -> String {
  let outer = if finding.outer_loc is Some(loc) {
    location_signature(loc)
  } else {
    "none"
  }
  "\{finding.file}|\{finding.rule_id}|\{finding.pattern_index}|\{location_signature(finding.loc)}|\{outer}"
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
fn assert_same_findings(
  expected : Array[RuleFinding],
  actual : Array[RuleFinding],
) -> Unit raise {
  assert_eq(actual.length(), expected.length())
  for index in 0..<expected.length() {
    inspect(
      finding_signature(actual[index]),
      content=finding_signature(expected[index]),
    )
  }
}

///|
fn assert_same_ast_json_findings(
  source : String,
  rule_source : String,
) -> Array[RuleFinding] raise {
  let rules = compile_rule_source(rule_source)
  let impls = parse_impls(source)
  let ast_hits = apply_structural_rules_with_backend(
    "sample.mbt",
    impls,
    rules,
    @model.MatcherBackend::AstMatcher,
  )
  let json_hits = apply_structural_rules_with_backend(
    "sample.mbt",
    impls,
    rules,
    @model.MatcherBackend::JsonMatcher,
  )
  assert_same_findings(ast_hits, json_hits)
  ast_hits
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
  let hits = apply_structural_rules(
    "sample.mbt",
    parse_impls(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
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
  let hits = apply_structural_rules(
    "sample.mbt",
    parse_impls(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
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
  assert_eq(hits.length(), 1)
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
    #|      callee: "^safe_"
    #|
  let source =
    #|fn sample {
    #|  safe_call();
    #|  unsafe_call()
    #|}
    #|
  let hits = apply_structural_rules(
    "sample.mbt",
    parse_impls(source),
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
    #|      value: "^(danger|42|true)$"
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
  let hits = apply_structural_rules(
    "sample.mbt",
    parse_impls(source),
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
    #|      callee: "^safe_"
    #|      value: "^ok$"
    #|
  let source =
    #|fn sample {
    #|  safe_call("ok");
    #|  safe_call("bad");
    #|  danger_call("ok")
    #|}
    #|
  let hits = apply_structural_rules(
    "sample.mbt",
    parse_impls(source),
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
    #|inside-expr: wrapper($(name:id), __TARGET__)
    #|patterns:
    #|  - shape: call($(name:id))
    #|    guard:
    #|      name: "^safe_.*ok$"
    #|
  let source =
    #|fn sample {
    #|  wrapper(safe_ok, call(safe_ok));
    #|  wrapper(unsafe_ok, call(unsafe_ok));
    #|  wrapper(safe_bad, call(safe_bad))
    #|}
    #|
  let hits = apply_structural_rules(
    "sample.mbt",
    parse_impls(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
  assert_true(hits[0].outer_loc is Some(_))
}

///|
test "backend-aware structural apply matches JSON and AST with guards inside expr" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Guarded wrapper.
    #|inside-expr: wrapper($(name:id), __TARGET__)
    #|patterns:
    #|  - shape: call($(name:id), $(value:const))
    #|    guard:
    #|      name: "^safe_.*ok$"
    #|      value: "^(42|true)$"
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
  let impls = parse_impls(source)
  let legacy_hits = apply_structural_rules("sample.mbt", impls, rules)
  let ast_hits = apply_structural_rules_with_backend(
    "sample.mbt",
    impls,
    rules,
    @model.MatcherBackend::AstMatcher,
  )
  let json_hits = apply_structural_rules_with_backend(
    "sample.mbt",
    impls,
    rules,
    @model.MatcherBackend::JsonMatcher,
  )
  assert_same_findings(legacy_hits, ast_hits)
  assert_same_findings(ast_hits, json_hits)
  assert_eq(json_hits.length(), 1)
  assert_true(json_hits[0].outer_loc is Some(_))
}

///|
test "JSON inside expr reports nested target locations without AST recovery" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Nested target call.
    #|inside-expr: wrapper(__TARGET__)
    #|patterns:
    #|  - shape: target(secret)
    #|
  let source =
    #|fn sample {
    #|  wrapper(holder(target(secret)))
    #|}
    #|
  let rules = compile_rule_source(rule_source)
  let impls = parse_impls(source)
  let ast_hits = apply_structural_rules_with_backend(
    "sample.mbt",
    impls,
    rules,
    @model.MatcherBackend::AstMatcher,
  )
  let json_hits = apply_structural_rules_with_backend(
    "sample.mbt",
    impls,
    rules,
    @model.MatcherBackend::JsonMatcher,
  )
  assert_eq(json_hits.length(), 1)
  assert_same_findings(ast_hits, json_hits)
  assert_true(json_hits[0].outer_loc is Some(_))
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
  let hits = apply_structural_rules(
    "sample.mbt",
    parse_impls(source),
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
    #|  - shape: sink(safe(__))
    #|
  let source =
    #|fn sample {
    #|  sink(danger);
    #|  sink(safe(raw))
    #|}
    #|
  let hits = assert_same_ast_json_findings(source, rule_source)
  assert_eq(hits.length(), 2)
  inspect(
    finding_signature(hits[0]),
    content="sample.mbt|example|0|2:3-2:15|none",
  )
  inspect(
    finding_signature(hits[1]),
    content="sample.mbt|example|0|3:3-3:18|none",
  )
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
  let hits = assert_same_ast_json_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(
    finding_signature(hits[0]),
    content="sample.mbt|example|1|3:3-3:11|none",
  )
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
  let hits = assert_same_ast_json_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(
    finding_signature(hits[0]),
    content="sample.mbt|example|0|2:3-2:20|none",
  )
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
  let hits = assert_same_ast_json_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(
    finding_signature(hits[0]),
    content="sample.mbt|example|0|3:3-3:11|none",
  )
}

///|
test "inside expr positive root ignores descendant patterns-not" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped holder positive wins before descendant negative.
    #|inside-expr: wrapper(__TARGET__)
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
  let hits = assert_same_ast_json_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(
    finding_signature(hits[0]),
    content="sample.mbt|example|0|2:11-2:27|2:3-2:28",
  )
}

///|
test "inside expr positive root wins over same-root patterns-not" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target roots match before negative patterns run.
    #|inside-expr: wrapper(__TARGET__)
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
  let hits = assert_same_ast_json_findings(source, rule_source)
  assert_eq(hits.length(), 2)
  inspect(
    finding_signature(hits[0]),
    content="sample.mbt|example|0|2:11-2:26|2:3-2:27",
  )
  inspect(
    finding_signature(hits[1]),
    content="sample.mbt|example|0|3:11-3:26|3:3-3:27",
  )
}

///|
test "inside expr patterns-not rejects outer on uncovered negative" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped targets outside blocked branches.
    #|inside-expr: wrapper(__TARGET__)
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
  let hits = assert_same_ast_json_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(
    finding_signature(hits[0]),
    content="sample.mbt|example|0|11:11-11:19|11:3-11:20",
  )
}

///|
test "inside expr positive array access wins over patterns-not identifier" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped array access.
    #|inside-expr: wrapper(__TARGET__)
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
  let hits = assert_same_ast_json_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  guard hits[0].outer_loc is Some(_) else { fail("expected outer location") }
  inspect(
    finding_signature(hits[0]),
    content="sample.mbt|example|0|2:14-2:17|2:3-2:18",
  )
}

///|
test "inside expr rejects only uncovered negative and accepts covered array access" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Covered array index use.
    #|inside-expr: wrapper($(counter:id), __TARGET__)
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
  let hits = assert_same_ast_json_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(
    finding_signature(hits[0]),
    content="sample.mbt|example|0|2:17-2:20|2:3-2:21",
  )
}

///|
test "inside expr rejects uncovered inherited id outside positive coverage" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Uncovered index use rejects the wrapper.
    #|inside-expr: wrapper($(counter:id), __TARGET__)
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
  let hits = assert_same_ast_json_findings(source, rule_source)
  assert_eq(hits.length(), 0)
}

///|
test "inside expr reports multiple covered positive hits" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Multiple covered index uses.
    #|inside-expr: wrapper($(counter:id), __TARGET__)
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
  let hits = assert_same_ast_json_findings(source, rule_source)
  assert_eq(hits.length(), 2)
  inspect(
    finding_signature(hits[0]),
    content="sample.mbt|example|0|3:8-3:11|2:3-5:5",
  )
  inspect(
    finding_signature(hits[1]),
    content="sample.mbt|example|0|4:8-4:11|2:3-5:5",
  )
}

///|
test "inside expr reject-uncovered-negative respects shadowed inherited identifiers" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Shadowed index use belongs to inner binding.
    #|inside-expr: wrapper($(counter:id), __TARGET__)
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
  let hits = assert_same_ast_json_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  inspect(
    finding_signature(hits[0]),
    content="sample.mbt|example|0|3:8-3:11|2:3-6:5",
  )
}

///|
test "inside expr accepts only loop counter uses covered by array access" {
  let rule_source =
    #|id: example
    #|description: |
    #|  C-style forward array iteration.
    #|inside-expr: |
    #|  for $(counter:id) = 0; $(counter:id) < $(arr:id).length(); $(counter:id) = $(counter:id) + 1 {
    #|    __TARGET__
    #|  }
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
  let hits = assert_same_ast_json_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].loc.start.lnum, 3)
  guard hits[0].outer_loc is Some(outer) else {
    fail("expected outer location")
  }
  assert_eq(outer.start.lnum, 2)
}

///|
test "inside expr with only patterns-not reports outer when target subtree is clean" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target without danger.
    #|inside-expr: wrapper(__TARGET__)
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
  let hits = assert_same_ast_json_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  guard hits[0].outer_loc is Some(outer) else {
    fail("expected outer location")
  }
  assert_eq(hits[0].loc.start.lnum, outer.start.lnum)
  assert_eq(hits[0].loc.start.column(), outer.start.column())
  assert_eq(hits[0].loc.end.lnum, outer.end.lnum)
  assert_eq(hits[0].loc.end.column(), outer.end.column())
  inspect(
    finding_signature(hits[0]),
    content="sample.mbt|example|0|2:3-2:18|2:3-2:18",
  )
}

///|
test "inside expr only patterns-not respects shadowed inherited identifiers" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target without same-name target call.
    #|inside-expr: wrapper($(name:id), __TARGET__)
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
  let hits = assert_same_ast_json_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].loc.start.lnum, 2)
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
  let hits = apply_structural_rules(
    "sample.mbt",
    parse_impls(source),
    compile_rule_source(rule_source),
  )
  let pattern_indices : Array[Int] = []
  for hit in hits {
    pattern_indices.push(hit.pattern_index)
  }
  inspect(int_array_signature(pattern_indices), content="[0, 1, 2]")
}

///|
test "inside expr preserves source order and outer locations" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target call.
    #|inside-expr: wrapper(__TARGET__)
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
  let hits = apply_structural_rules(
    "sample.mbt",
    parse_impls(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 2)
  assert_eq(hits[0].pattern_index, 0)
  assert_eq(hits[1].pattern_index, 0)
  guard hits[0].outer_loc is Some(first_outer) else {
    fail("expected first outer location")
  }
  guard hits[1].outer_loc is Some(second_outer) else {
    fail("expected second outer location")
  }
  assert_true(hits[0].loc.start.lnum < hits[1].loc.start.lnum)
  assert_true(first_outer.start.lnum < second_outer.start.lnum)
}

///|
test "apply structural rule supports inside expr inherited bindings" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target call.
    #|inside-expr: wrapper($(prefix:exp), __TARGET__)
    #|patterns:
    #|  - shape: target.call($(prefix:exp))
    #|
  let source =
    #|fn sample {
    #|  wrapper(make(), target.call(make()));
    #|  wrapper(make(), target.call(other))
    #|}
    #|
  let hits = apply_structural_rules(
    "sample.mbt",
    parse_impls(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
  assert_true(hits[0].outer_loc is Some(_))
}

///|
test "inside expr plain names do not reference inherited bindings" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Plain names remain literal.
    #|inside-expr: wrapper($(prefix:exp), __TARGET__)
    #|patterns:
    #|  - shape: target.call(prefix)
    #|
  let source =
    #|fn sample {
    #|  wrapper(token, target.call(token))
    #|}
    #|
  let hits = apply_structural_rules(
    "sample.mbt",
    parse_impls(source),
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
    #|inside-expr: wrapper($(prefix:id), __TARGET__)
    #|patterns:
    #|  - shape: target.call($(prefix:id))
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
  assert_eq(hits.length(), 1)
  assert_true(hits[0].outer_loc is Some(_))
}

///|
test "inside expr inherited id is blocked after lexical let shadow" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target call.
    #|inside-expr: wrapper($(name:id), __TARGET__)
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
  let hits = assert_same_ast_json_findings(source, rule_source)
  assert_eq(hits.length(), 0)
}

///|
test "inside expr inherited id still matches without shadow" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target call.
    #|inside-expr: wrapper($(name:id), __TARGET__)
    #|patterns:
    #|  - shape: target($(name:id))
    #|
  let source =
    #|fn sample {
    #|  wrapper(x, target(x))
    #|}
    #|
  let hits = assert_same_ast_json_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_true(hits[0].outer_loc is Some(_))
}

///|
test "inside expr later shadow does not block earlier candidate" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target call.
    #|inside-expr: wrapper($(name:id), __TARGET__)
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
  let hits = assert_same_ast_json_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_true(hits[0].outer_loc is Some(_))
}

///|
test "inside expr only blocks patterns referencing shadowed outer id" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Wrapped target call.
    #|inside-expr: wrapper($(left:id), $(right:id), __TARGET__)
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
  let hits = assert_same_ast_json_findings(source, rule_source)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].pattern_index, 0)
  assert_true(hits[0].outer_loc is Some(_))
}

///|
test "inside expr traverses guard target children" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Guard target call.
    #|inside-expr: wrapper(__TARGET__)
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
  assert_eq(hits.length(), 1)
  assert_true(hits[0].outer_loc is Some(_))
}

///|
test "inside expr traverses reverse pipe target children" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Reverse pipe target call.
    #|inside-expr: wrapper(__TARGET__)
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
  assert_eq(hits.length(), 1)
  assert_true(hits[0].outer_loc is Some(_))
}

///|
test "inside expr traverses list comprehension target children" {
  let rule_source =
    #|id: example
    #|description: |
    #|  List comprehension target call.
    #|inside-expr: wrapper(__TARGET__)
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
  assert_eq(hits.length(), 1)
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
  let hits = apply_taint_rules(
    "sample.mbt",
    parse_impls(source),
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
  assert_eq(hits.length(), 1)
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
  assert_eq(hits.length(), 1)
  inspect(hits[0].rule_id, content="example")
  assert_eq(hits[0].pattern_index, 0)
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
  let hits = apply_taint_rules(
    "sample.mbt",
    parse_impls(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 0)
}

///|
test "backend-aware taint apply matches JSON and AST for source sink sanitizer" {
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
  let impls = parse_impls(source)
  let legacy_hits = apply_taint_rules("sample.mbt", impls, rules)
  let ast_hits = apply_taint_rules_with_backend(
    "sample.mbt",
    impls,
    rules,
    @model.MatcherBackend::AstMatcher,
  )
  let json_hits = apply_taint_rules_with_backend(
    "sample.mbt",
    impls,
    rules,
    @model.MatcherBackend::JsonMatcher,
  )
  assert_same_findings(legacy_hits, ast_hits)
  assert_same_findings(ast_hits, json_hits)
  assert_eq(json_hits.length(), 1)
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
  assert_eq(hits.length(), 3)
  assert_eq(hits[0].pattern_index, 0)
  assert_eq(hits[1].pattern_index, 1)
  assert_eq(hits[2].pattern_index, 2)
}
