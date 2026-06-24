///|
using @compile {compile_rules}

///|
using @load {parse_rule_source}

///|
fn compile_prefilter_rule_source(source : String) -> CompiledRule raise {
  let rules = compile_rules([
    parse_rule_source("/tmp/rules/example.yaml", "/tmp/rules", source),
  ])
  guard rules is [rule] else { fail("expected one compiled rule") }
  rule
}

///|
test "prefilter keeps structural rule when required literal exists" {
  let source =
    #|package: example/pkg
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
    #|package: example/pkg
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
    #|package: example/pkg
    #|description: Any expression.
    #|patterns:
    #|  - shape: _expr
    #|    metavars:
    #|      subtree: [_expr]
    #|
  let rule = compile_prefilter_rule_source(source)
  assert_true(rule_is_relevant_to_source(rule, "fn sample { anything() }\n"))
  assert_true(rule_is_relevant_to_source(rule, "fn sample {\n"))
}

///|
test "prefilter treats auto metavars as placeholders" {
  let source =
    #|package: example/pkg
    #|description: Target call.
    #|patterns:
    #|  - shape: sink(value)
    #|    metavars: [value]
    #|
  let rule = compile_prefilter_rule_source(source)
  assert_true(rule_is_relevant_to_source(rule, "fn sample { sink(actual) }\n"))
  assert_false(
    rule_is_relevant_to_source(rule, "fn sample { other(actual) }\n"),
  )
}

///|
test "prefilter ignores one digit int literals" {
  let one_digit_source =
    #|package: example/pkg
    #|description: One digit int.
    #|patterns:
    #|  - shape: "1"
    #|
  let one_digit_rule = compile_prefilter_rule_source(one_digit_source)
  assert_true(
    rule_is_relevant_to_source(one_digit_rule, "fn sample { other() }\n"),
  )
  let two_digit_source =
    #|package: example/pkg
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
    #|package: example/pkg
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
test "prefilter requires taint source and sink literals" {
  let source =
    #|package: example/pkg
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
