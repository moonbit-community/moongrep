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
