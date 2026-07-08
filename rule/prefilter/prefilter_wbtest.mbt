///|
using @compile {compile_rules}

///|
fn compile_prefilter_rule_source(source : String) -> CompiledRule raise {
  let rules = compile_rules([
    @model.RawRuleSpec::from_str(
      "/tmp/rules/example.yaml", "/tmp/rules", source,
    ),
  ])
  guard rules is [rule] else { fail("expected one compiled rule") }
  rule
}

///|
test "prefilter keeps structural rule when required literal exists" {
  let source =
    #|id: example
    #|description: Target call.
    #|patterns:
    #|  - shape: target()
    #|
  let rule = compile_prefilter_rule_source(source)
  assert_true(rule_is_relevant_to_source(rule, "fn sample { target() }\n"))
  assert_false(rule_is_relevant_to_source(rule, "fn sample { other() }\n"))
}

///|
test "prefilter treats structural patterns as alternatives" {
  let source =
    #|id: example
    #|description: Lifecycle calls.
    #|patterns:
    #|  - shape: read_request()
    #|  - shape: end_request()
    #|
  let rule = compile_prefilter_rule_source(source)
  assert_true(
    rule_is_relevant_to_source(rule, "fn sample { read_request() }\n"),
  )
  assert_true(rule_is_relevant_to_source(rule, "fn sample { end_request() }\n"))
  assert_false(rule_is_relevant_to_source(rule, "fn sample { noop() }\n"))
}

///|
test "prefilter keeps unfilterable structural rule relevant" {
  let source =
    #|id: example
    #|description: Any expression.
    #|patterns:
    #|  - shape: $(_expr:exp)
    #|
  let rule = compile_prefilter_rule_source(source)
  assert_true(rule_is_relevant_to_source(rule, "fn sample { anything() }\n"))
  assert_true(rule_is_relevant_to_source(rule, "fn sample {\n"))
}

///|
test "prefilter treats inline expression metavars as placeholders" {
  let source =
    #|id: example
    #|description: Target call.
    #|patterns:
    #|  - shape: sink($(value:exp))
    #|
  let rule = compile_prefilter_rule_source(source)
  assert_true(rule_is_relevant_to_source(rule, "fn sample { sink(actual) }\n"))
  assert_false(
    rule_is_relevant_to_source(rule, "fn sample { other(actual) }\n"),
  )
}

///|
test "prefilter treats metavars as placeholders" {
  let source =
    #|id: example
    #|description: Target call.
    #|patterns:
    #|  - shape: sink($(value:exp), label=$(name:id))
    #|
  let rule = compile_prefilter_rule_source(source)
  assert_true(
    rule_is_relevant_to_source(rule, "fn sample { sink(actual, label=user) }\n"),
  )
  assert_false(
    rule_is_relevant_to_source(
      rule, "fn sample { other(actual, label=user) }\n",
    ),
  )
}

///|
test "prefilter treats inline constant metavars as placeholders" {
  let source =
    #|id: example
    #|description: Target call.
    #|patterns:
    #|  - shape: sink($(value:const))
    #|
  let rule = compile_prefilter_rule_source(source)
  assert_true(rule_is_relevant_to_source(rule, "fn sample { sink(42) }\n"))
  assert_false(rule_is_relevant_to_source(rule, "fn sample { other(42) }\n"))
}

///|
test "prefilter treats inline argument metavars as placeholders" {
  let source =
    #|id: example
    #|description: Target call.
    #|patterns:
    #|  - shape: sink($(arg:arg))
    #|
  let rule = compile_prefilter_rule_source(source)
  assert_true(
    rule_is_relevant_to_source(rule, "fn sample { sink(label=actual) }\n"),
  )
  assert_false(
    rule_is_relevant_to_source(rule, "fn sample { other(label=actual) }\n"),
  )
}

///|
test "prefilter treats inline type metavars as placeholders" {
  let source =
    #|id: example
    #|description: Typed let.
    #|patterns:
    #|  - shape: |
    #|      let value : $(T:type) = input
    #|
  let rule = compile_prefilter_rule_source(source)
  assert_true(
    rule_is_relevant_to_source(rule, "fn sample { let value : Int = input }\n"),
  )
  assert_false(
    rule_is_relevant_to_source(rule, "fn sample { let other : Int = source }\n"),
  )
}

///|
test "prefilter ignores one digit int literals" {
  let one_digit_source =
    #|id: example
    #|description: One digit int.
    #|patterns:
    #|  - shape: "1"
    #|
  let one_digit_rule = compile_prefilter_rule_source(one_digit_source)
  assert_true(
    rule_is_relevant_to_source(one_digit_rule, "fn sample { other() }\n"),
  )
  let two_digit_source =
    #|id: example
    #|description: Two digit int.
    #|patterns:
    #|  - shape: "12"
    #|
  let two_digit_rule = compile_prefilter_rule_source(two_digit_source)
  assert_true(
    rule_is_relevant_to_source(two_digit_rule, "fn sample { let x = 12 }\n"),
  )
  assert_false(
    rule_is_relevant_to_source(two_digit_rule, "fn sample { other() }\n"),
  )
}

///|
test "prefilter requires inside expr and inner pattern literals together" {
  let source =
    #|id: example
    #|description: Wrapped target call.
    #|inside-expr:
    #|  shape: wrapper(__TARGET__)
    #|patterns:
    #|  - shape: target()
    #|
  let rule = compile_prefilter_rule_source(source)
  assert_true(
    rule_is_relevant_to_source(rule, "fn sample { wrapper(target()) }\n"),
  )
  assert_false(
    rule_is_relevant_to_source(rule, "fn sample { wrapper(noop()) }\n"),
  )
  assert_false(rule_is_relevant_to_source(rule, "fn sample { target() }\n"))
}

///|
test "prefilter requires inside toplevel and inner pattern literals together" {
  let source =
    #|id: example
    #|description: Top-level target call.
    #|inside-toplevel:
    #|  shape: fn safe_entry { __TARGET__ }
    #|patterns:
    #|  - shape: target()
    #|
  let rule = compile_prefilter_rule_source(source)
  assert_true(rule_is_relevant_to_source(rule, "fn safe_entry { target() }\n"))
  assert_false(rule_is_relevant_to_source(rule, "fn safe_entry { noop() }\n"))
  assert_false(rule_is_relevant_to_source(rule, "fn other { target() }\n"))
}

///|
test "prefilter ignores patterns-not literals for structural rules" {
  let source =
    #|id: example
    #|description: Target unless ignored.
    #|patterns:
    #|  - shape: target()
    #|patterns-not:
    #|  - shape: impossible_negative_literal()
    #|
  let rule = compile_prefilter_rule_source(source)
  assert_true(rule_is_relevant_to_source(rule, "fn sample { target() }\n"))
  assert_false(rule_is_relevant_to_source(rule, "fn sample { other() }\n"))
}

///|
test "prefilter uses inside expr literals for patterns-not only rules" {
  let source =
    #|id: example
    #|description: Wrapped target unless ignored.
    #|inside-expr:
    #|  shape: wrapper(__TARGET__)
    #|patterns-not:
    #|  - shape: impossible_negative_literal()
    #|
  let rule = compile_prefilter_rule_source(source)
  assert_true(rule_is_relevant_to_source(rule, "fn sample { wrapper(ok()) }\n"))
  assert_false(
    rule_is_relevant_to_source(
      rule, "fn sample { impossible_negative_literal() }\n",
    ),
  )
}

///|
test "prefilter requires taint source and sink literals" {
  let source =
    #|id: example
    #|description: User input reaches sink.
    #|taint:
    #|  sources:
    #|    - shape: get_user_input()
    #|  sinks:
    #|    - shape: sink(__SOURCE__)
    #|
  let rule = compile_prefilter_rule_source(source)
  assert_true(
    rule_is_relevant_to_source(
      rule, "fn sample { let x = get_user_input(); sink(x) }\n",
    ),
  )
  assert_false(
    rule_is_relevant_to_source(rule, "fn sample { let x = get_user_input() }\n"),
  )
  assert_false(rule_is_relevant_to_source(rule, "fn sample { sink(x) }\n"))
}

///|
test "prefilter literal matching treats regex metacharacters literally" {
  assert_true(literal_matches_source("a+b(c)", "fn sample { a+b(c) }\n"))
  assert_false(literal_matches_source("a+b(c)", "fn sample { abcc }\n"))
  assert_true(literal_matches_source("target.name", "let _ = target.name\n"))
  assert_false(literal_matches_source("target.name", "let _ = targetxname\n"))
}
