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
test "prefilter splits qualified identifier literals" {
  let source =
    #|id: example
    #|description: Qualified target call.
    #|patterns:
    #|  - shape: "@pkg.name()"
    #|
  let rule = compile_prefilter_rule_source(source)
  debug_inspect(rule.prefilter.alternatives, content="[[\"pkg\", \"name\"]]")
  assert_true(rule_is_relevant_to_source(rule, "fn sample { @pkg.name() }\n"))
  assert_true(rule_is_relevant_to_source(rule, "fn sample { @pkg .name() }\n"))
  assert_false(
    rule_is_relevant_to_source(rule, "fn sample { @other.name() }\n"),
  )
  assert_false(rule_is_relevant_to_source(rule, "fn sample { @pkg.other() }\n"))
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
test "prefilter treats $_ ignore placeholders as placeholders" {
  let source =
    #|id: example
    #|description: Ignore first argument.
    #|patterns:
    #|  - shape: inspect($_, content=$(str:const))
    #|
  let rule = compile_prefilter_rule_source(source)
  assert_true(
    rule_is_relevant_to_source(
      rule, "fn sample { inspect(1, content=\"1\") }\n",
    ),
  )
  assert_false(
    rule_is_relevant_to_source(rule, "fn sample { other(1, content=\"1\") }\n"),
  )
}

///|
test "prefilter keeps all-underscore identifiers literal" {
  let source =
    #|id: example
    #|description: Literal all-underscore identifier.
    #|patterns:
    #|  - shape: foo(__)
    #|
  let rule = compile_prefilter_rule_source(source)
  assert_true(rule_is_relevant_to_source(rule, "fn sample { foo(__) }\n"))
  assert_false(rule_is_relevant_to_source(rule, "fn sample { foo(value) }\n"))
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
test "prefilter ignores keyword metavar markers" {
  let source =
    #|id: example
    #|description: Keyword metavars.
    #|patterns:
    #|  - shape: sink($(else:exp), $(for:id), $(if:const), $(match:arg))
    #|
  let rule = compile_prefilter_rule_source(source)
  debug_inspect(rule.prefilter.alternatives, content="[[\"sink\"]]")
  assert_true(
    rule_is_relevant_to_source(
      rule, "fn sample { sink(actual(), name, 42, label=value) }\n",
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
test "prefilter keeps fixed package for qualified identifier metavars" {
  let source =
    #|id: example
    #|description: Qualified callee capture.
    #|patterns:
    #|  - shape: "@pkg.$(callee:id)()"
    #|
  let rule = compile_prefilter_rule_source(source)
  debug_inspect(rule.prefilter.alternatives, content="[[\"pkg\"]]")
  assert_true(
    rule_is_relevant_to_source(rule, "fn sample { @pkg .actual() }\n"),
  )
  assert_false(
    rule_is_relevant_to_source(rule, "fn sample { @other.actual() }\n"),
  )
}

///|
test "prefilter splits qualified type literals" {
  let source =
    #|id: example
    #|description: Qualified type annotation.
    #|patterns:
    #|  - shape: |
    #|      let value : @pkg.Type = input
    #|
  let rule = compile_prefilter_rule_source(source)
  assert_true(
    rule_is_relevant_to_source(
      rule, "fn sample { let value : @pkg.Type = input }\n",
    ),
  )
  assert_true(
    rule_is_relevant_to_source(
      rule, "fn sample { let value : @pkg .Type = input }\n",
    ),
  )
  assert_false(
    rule_is_relevant_to_source(
      rule, "fn sample { let value : @other.Type = input }\n",
    ),
  )
  assert_false(
    rule_is_relevant_to_source(
      rule, "fn sample { let value : @pkg.Other = input }\n",
    ),
  )
}

///|
test "prefilter ignores ellipsis spelling and keeps adjacent literals" {
  let source =
    #|id: example
    #|description: Variadic target call.
    #|patterns:
    #|  - shape: sink($$$args, marker)
    #|
  let rule = compile_prefilter_rule_source(source)
  assert_true(
    rule_is_relevant_to_source(rule, "fn sample { sink(value, marker) }\n"),
  )
  assert_false(
    rule_is_relevant_to_source(rule, "fn sample { other(value, marker) }\n"),
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
    #|  - shape: wrapper(__TARGET__)
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
    #|  - shape: fn safe_entry { __TARGET__ }
    #|patterns:
    #|  - shape: target()
    #|
  let rule = compile_prefilter_rule_source(source)
  assert_true(rule_is_relevant_to_source(rule, "fn safe_entry { target() }\n"))
  assert_false(rule_is_relevant_to_source(rule, "fn safe_entry { noop() }\n"))
  assert_false(rule_is_relevant_to_source(rule, "fn other { target() }\n"))
}

///|
test "prefilter skips omitted partial function fields" {
  let source =
    #|id: example
    #|description: Partial top-level function.
    #|inside-toplevel:
    #|  - shape: fn safe_entry { __TARGET__ }
    #|patterns:
    #|  - shape: target()
    #|
  let rule = compile_prefilter_rule_source(source)
  assert_true(
    rule_is_relevant_to_source(
      rule,
      (
        #|/// Documented entry.
        #|#custom.attribute
        #|pub async fn safe_entry(value : InputType) -> ResultType noraise {
        #|  target()
        #|}
        #|
      ),
    ),
  )
  assert_false(
    rule_is_relevant_to_source(
      rule, "pub async fn other(value : InputType) -> ResultType { target() }\n",
    ),
  )
}

///|
test "prefilter skips compiled ignored fields by parent and child name" {
  let source =
    #|id: example
    #|description: Partial top-level function.
    #|inside-toplevel:
    #|  - shape: fn safe_entry { __TARGET__ }
    #|patterns:
    #|  - shape: target()
    #|
  let rule = compile_prefilter_rule_source(source)
  guard rule.definition is Structural(structural) else {
    fail("expected structural rule")
  }
  let pattern = structural.inside_toplevel[0]
  let compiled = pattern.compiled
  assert_true(compiled.ignored_fields.length() > 0)
  assert_true(
    prefilter_ignores_field(compiled, compiled.cst.kind, "semantic_type_name"),
  )
  assert_false(prefilter_ignores_field(compiled, compiled.cst.kind, "doc"))
  assert_true(prefilter_ignores_field(compiled, compiled.cst.kind, "attrs"))
  let literals = required_literals_from_compiled_pattern(pattern)
  assert_true(contains_string(literals, "safe_entry"))
  debug_inspect(literals, content="[\"safe_entry\"]")
}

///|
test "prefilter never requires docstring text" {
  let source =
    #|id: example
    #|description: Documented exact top-level function.
    #|inside-toplevel:
    #|  - shape: |
    #|      /// PrefilterDocstringSentinel
    #|      fn safe_entry { __TARGET__ }
    #|    match-mode: exact
    #|patterns:
    #|  - shape: target()
    #|
  let rule = compile_prefilter_rule_source(source)
  guard rule.definition is Structural(structural) else {
    fail("expected structural rule")
  }
  let literals = required_literals_from_compiled_pattern(
    structural.inside_toplevel[0],
  )
  assert_false(contains_string(literals, "PrefilterDocstringSentinel"))
  assert_true(contains_string(literals, "safe_entry"))
  assert_true(rule_is_relevant_to_source(rule, "fn safe_entry { target() }\n"))
}

///|
test "prefilter keeps explicit partial function fields required" {
  let source =
    #|id: example
    #|description: Explicit partial function fields.
    #|inside-toplevel:
    #|  - shape: async fn safe_entry() -> RequiredType noraise { __TARGET__ }
    #|patterns:
    #|  - shape: target()
    #|
  let rule = compile_prefilter_rule_source(source)
  assert_true(
    rule_is_relevant_to_source(
      rule, "async fn safe_entry() -> RequiredType noraise { target() }\n",
    ),
  )
  assert_false(
    rule_is_relevant_to_source(
      rule, "async fn safe_entry() -> OtherType noraise { target() }\n",
    ),
  )
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
    #|  - shape: wrapper(__TARGET__)
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

///|
test "prefilter builds outer and positive pattern cartesian alternatives" {
  let source =
    #|id: example
    #|description: Multiple outer and inner alternatives.
    #|inside-expr:
    #|  - shape: wrapper(__TARGET__)
    #|  - shape: container(__TARGET__)
    #|patterns:
    #|  - shape: first_target()
    #|  - shape: second_target()
    #|
  let rule = compile_prefilter_rule_source(source)
  assert_eq(rule.prefilter.alternatives.length(), 4)
  assert_true(
    rule_is_relevant_to_source(rule, "fn sample { wrapper(first_target()) }\n"),
  )
  assert_true(
    rule_is_relevant_to_source(rule, "fn sample { wrapper(second_target()) }\n"),
  )
  assert_true(
    rule_is_relevant_to_source(
      rule, "fn sample { container(first_target()) }\n",
    ),
  )
  assert_true(
    rule_is_relevant_to_source(
      rule, "fn sample { container(second_target()) }\n",
    ),
  )
  assert_false(
    rule_is_relevant_to_source(rule, "fn sample { wrapper(noop()) }\n"),
  )
  assert_false(
    rule_is_relevant_to_source(rule, "fn sample { other(first_target()) }\n"),
  )
}

///|
test "prefilter gives each patterns-not-only outer its own alternative" {
  let source =
    #|id: example
    #|description: Multiple clean contexts.
    #|inside-expr:
    #|  - shape: wrapper(__TARGET__)
    #|  - shape: container(__TARGET__)
    #|patterns-not:
    #|  - shape: impossible_negative_literal()
    #|
  let rule = compile_prefilter_rule_source(source)
  assert_eq(rule.prefilter.alternatives.length(), 2)
  assert_true(rule_is_relevant_to_source(rule, "fn sample { wrapper(ok()) }\n"))
  assert_true(
    rule_is_relevant_to_source(rule, "fn sample { container(ok()) }\n"),
  )
  assert_false(
    rule_is_relevant_to_source(
      rule, "fn sample { impossible_negative_literal() }\n",
    ),
  )
}
