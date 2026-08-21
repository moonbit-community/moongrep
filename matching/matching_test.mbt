///|
fn test_expr(
  source : String,
  name? : String = "matching test",
) -> @untyped_cst.CstNode raise {
  let parsed = @untyped_cst.parse_expression(source, name~)
  guard parsed.diagnostics_view().is_empty() else {
    fail("expected expression to parse: \{source}")
  }
  @cst.expression_root(parsed.root())
}

///|
fn test_impl(
  source : String,
  name? : String = "matching test",
) -> @untyped_cst.CstNode raise {
  let parsed = @untyped_cst.parse_structure(source, name~)
  guard parsed.diagnostics_view().is_empty() else {
    fail("expected implementation to parse: \{source}")
  }
  guard @cst.toplevel_nodes(parsed.root()) is [node] else {
    fail("expected one implementation")
  }
  node
}

///|
fn test_compiled(
  cst : @untyped_cst.CstNode,
  expr_metavars? : Array[String] = [],
  identifier_metavars? : Array[String] = [],
  constant_metavars? : Array[String] = [],
  arg_metavars? : Array[String] = [],
  type_metavars? : Array[String] = [],
  ellipsis_metavars? : Array[EllipsisMetavar] = [],
  ignored_fields? : Array[IgnoredPatternField] = [],
) -> CompiledExprPattern {
  {
    cst,
    expr_metavars,
    identifier_metavars,
    constant_metavars,
    arg_metavars,
    type_metavars,
    ellipsis_metavars,
    target_metavar: None,
    source_metavar: None,
    ignored_fields,
  }
}

///|
fn test_single_binding(
  result : ExprMatch?,
  name : String,
) -> @untyped_cst.CstNode raise {
  guard result is Some(result) else { fail("expected match") }
  match result.bindings.get(name) {
    Some(Single(node)) => node
    _ => fail("expected one binding for \{name}")
  }
}

///|
test "semantic equality ignores locations formatting comments and separators" {
  let compact = test_expr("f(1, label=x)", name="compact")
  let formatted = test_expr(
    "f(\n  // before\n  1,\n  label = x,\n)",
    name="formatted",
  )
  assert_true(expr_matches(compact, formatted))
  assert_false(expr_matches(compact, test_expr("g(1, label=x)")))
  assert_false(expr_matches(compact, test_expr("f(1, other=x)")))
}

///|
test "semantic equality preserves constant spelling and operators" {
  assert_true(expr_matches(test_expr("1000"), test_expr("1000")))
  assert_false(expr_matches(test_expr("1000"), test_expr("1_000")))
  assert_false(
    expr_matches(test_expr("left + right"), test_expr("left - right")),
  )
  assert_false(expr_matches(test_expr("true"), test_expr("false")))
}

///|
test "expression metavars capture any expression and repeat structurally" {
  let compiled = test_compiled(test_expr("pair(value, value)"), expr_metavars=[
    "value",
  ])
  assert_true(
    match_expr_pattern(compiled, test_expr("pair(a + 1, a + 1)")) is Some(_),
  )
  assert_false(
    match_expr_pattern(compiled, test_expr("pair(a + 1, a + 2)")) is Some(_),
  )
  let captured = test_single_binding(
    match_expr_pattern(compiled, test_expr("pair(call(), call())")),
    "value",
  )
  assert_true(captured.kind is @untyped_cst.Expr_Apply)
}

///|
test "internal uppercase expression and constant markers use logical names" {
  let exp = test_compiled(test_expr("__moongrep_exp_Value"), expr_metavars=[
    "Value",
  ])
  assert_true(match_expr_pattern(exp, test_expr("some_call()")) is Some(_))
  let constant = test_compiled(test_expr("__moongrep_const_Value"), constant_metavars=[
    "Value",
  ])
  let value = test_single_binding(
    match_expr_pattern(constant, test_expr("42")),
    "Value",
  )
  assert_true(value.kind.is_constant())
}

///|
test "identifier metavars normalize binder and expression names" {
  let compiled = test_compiled(test_expr("match subject { name => name }"), identifier_metavars=[
    "name",
  ])
  let captured = test_single_binding(
    match_expr_pattern(compiled, test_expr("match subject { item => item }")),
    "name",
  )
  debug_inspect(@cst.normalized_name(captured), content="Some(\"item\")")
  assert_false(
    match_expr_pattern(compiled, test_expr("match subject { item => other }"))
    is Some(_),
  )
}

///|
test "constant metavars work in expressions and patterns" {
  let expression = test_compiled(test_expr("check(value)"), constant_metavars=[
    "value",
  ])
  assert_true(
    match_expr_pattern(expression, test_expr("check(\"raw\")")) is Some(_),
  )
  assert_false(
    match_expr_pattern(expression, test_expr("check(name)")) is Some(_),
  )
  let pattern = test_compiled(test_expr("match input { value => body }"), constant_metavars=[
    "value",
  ])
  assert_true(
    match_expr_pattern(pattern, test_expr("match input { 7 => body }"))
    is Some(_),
  )
}

///|
test "argument metavars capture the complete argument kind" {
  let compiled = test_compiled(test_expr("sink(__moongrep_arg_item)"), arg_metavars=[
    "item",
  ])
  let labelled = test_single_binding(
    match_expr_pattern(compiled, test_expr("sink(label=value)")),
    "item",
  )
  assert_true(labelled.kind is @untyped_cst.Argument_Labelled)
  let optional = test_single_binding(
    match_expr_pattern(compiled, test_expr("sink(label?)")),
    "item",
  )
  assert_true(optional.kind is @untyped_cst.Argument_LabelledOptionPun)
}

///|
test "pattern metavars capture whole normalized patterns" {
  let compiled = test_compiled(
    test_expr("match input { __moongrep_pat_item => body }"),
  )
  let captured = test_single_binding(
    match_expr_pattern(
      compiled,
      test_expr("match input { Some(value) => body }"),
    ),
    "item",
  )
  assert_true(captured.kind is @untyped_cst.Pattern_Constr)
  assert_true(
    match_expr_pattern(
      compiled,
      test_expr("match input { (Some(value)) => body }"),
    )
    is Some(_),
  )
}

///|
test "type metavars decode internal markers and compare repeated captures" {
  let compiled = test_compiled(
    test_expr(
      "match input { (left : MoongrepType_ty, right : MoongrepType_ty) => body }",
    ),
    type_metavars=["ty"],
  )
  assert_true(
    match_expr_pattern(
      compiled,
      test_expr(
        "match input { (left : Array[Int], right : Array[Int]) => body }",
      ),
    )
    is Some(_),
  )
  assert_false(
    match_expr_pattern(
      compiled,
      test_expr(
        "match input { (left : Array[Int], right : Array[String]) => body }",
      ),
    )
    is Some(_),
  )
}

///|
test "ignore placeholder does not create a binding" {
  let compiled = test_compiled(test_expr("wrap(__moongrep_ignore)"))
  guard match_expr_pattern(compiled, test_expr("wrap(complex(1))"))
    is Some(result) else {
    fail("expected match")
  }
  assert_true(result.bindings.is_empty())
}

///|
test "ellipsis captures ordered argument spans including empty spans" {
  let compiled = test_compiled(
    test_expr("call(__moongrep_ellipsis_any_items, tail)"),
    ellipsis_metavars=[{ name: "items", kind: AnyItem }],
  )
  guard match_expr_pattern(compiled, test_expr("call(1, label=x, tail)"))
    is Some(result) else {
    fail("expected match")
  }
  match result.bindings.get("items") {
    Some(Multiple(items)) => assert_eq(items.length(), 2)
    _ => fail("expected ellipsis capture")
  }
  assert_true(match_expr_pattern(compiled, test_expr("call(tail)")) is Some(_))
}

///|
test "typed ellipsis constrains every captured item" {
  let compiled = test_compiled(
    test_expr("call(__moongrep_ellipsis_const_values)"),
    ellipsis_metavars=[{ name: "values", kind: ConstItem }],
  )
  assert_true(
    match_expr_pattern(compiled, test_expr("call(1, \"two\")")) is Some(_),
  )
  assert_false(
    match_expr_pattern(compiled, test_expr("call(1, name)")) is Some(_),
  )
}

///|
test "block matching handles parser sequence wrappers and lexical statements" {
  let same = test_compiled(test_expr("{ first(); second() }"))
  assert_true(
    match_expr_pattern(same, test_expr("{ first(); // gap\n second() }"))
    is Some(_),
  )
  let binding = test_compiled(test_expr("{ let value = source; sink(value) }"))
  assert_true(
    match_expr_pattern(binding, test_expr("{ let value=source; sink(value) }"))
    is Some(_),
  )
}

///|
test "an expression placeholder in an if body captures the complete block" {
  let compiled = test_compiled(
    test_expr("if __moongrep_ignore { __moongrep_ignore } else {}"),
  )
  assert_true(
    match_expr_pattern(
      compiled,
      test_expr("if flag { prepare(); finish() } else {}"),
    )
    is Some(_),
  )
}

///|
test "guard and let headers match their lexical CST continuation" {
  let guard_pattern = test_compiled(
    test_expr("guard ready() else { fallback() }"),
  )
  assert_true(
    match_expr_pattern(
      guard_pattern,
      test_expr("guard ready() else { fallback() }\ncontinue_work()"),
    )
    is Some(_),
  )
  let let_pattern = test_compiled(
    test_expr("let (__moongrep_ignore, __moongrep_ignore) = __moongrep_ignore"),
  )
  assert_true(
    match_expr_pattern(
      let_pattern,
      test_expr("let (fst, snd) = tuple\nconsume(fst)\nsnd"),
    )
    is Some(_),
  )
}

///|
test "top-level exact matching ignores docstrings and compares attributes" {
  let documented = test_impl(
    "///| API\n/// detail\n#stable\nfn sample { body() }",
    name="pattern-doc",
  )
  let same = test_impl(
    "///| API\n/// detail\n#stable\nfn sample { body() }",
    name="candidate-doc",
  )
  let changed_doc = test_impl(
    "///| Changed\n#stable\nfn sample { body() }",
    name="changed-doc",
  )
  let changed_attr = test_impl(
    "///| API\n/// detail\n#other\nfn sample { body() }",
    name="changed-attr",
  )
  let without_doc = test_impl(
    "#stable\nfn sample { body() }",
    name="without-doc",
  )
  let without_attr = test_impl(
    "///| API\n/// detail\nfn sample { body() }",
    name="without-attr",
  )
  assert_true(expr_matches(documented, same))
  assert_true(expr_matches(documented, changed_doc))
  assert_true(expr_matches(documented, without_doc))
  assert_true(expr_matches(without_doc, documented))
  assert_false(expr_matches(documented, changed_attr))
  assert_false(expr_matches(documented, without_attr))
}

///|
test "nested declaration docstrings never affect exact matching" {
  let documented_field = test_impl(
    "struct Sample {\n  /// field docs\n  value : Int\n}",
    name="field-doc-pattern",
  )
  let changed_field = test_impl(
    "struct Sample {\n  /// changed docs\n  value : Int\n}",
    name="field-doc-changed",
  )
  let plain_field = test_impl(
    "struct Sample {\n  value : Int\n}",
    name="field-doc-missing",
  )
  assert_true(expr_matches(documented_field, changed_field))
  assert_true(expr_matches(documented_field, plain_field))
  assert_true(expr_matches(plain_field, documented_field))
  let documented_constructor = test_impl(
    "enum Sample {\n  /// constructor docs\n  Value(Int)\n}",
    name="constructor-doc-pattern",
  )
  let changed_constructor = test_impl(
    "enum Sample {\n  /// changed docs\n  Value(Int)\n}",
    name="constructor-doc-changed",
  )
  let plain_constructor = test_impl(
    "enum Sample {\n  Value(Int)\n}",
    name="constructor-doc-missing",
  )
  assert_true(expr_matches(documented_constructor, changed_constructor))
  assert_true(expr_matches(documented_constructor, plain_constructor))
  assert_true(expr_matches(plain_constructor, documented_constructor))
  let documented_method = test_impl(
    "trait Sample {\n  /// method docs\n  read(Self) -> Int\n}",
    name="trait-method-doc-pattern",
  )
  let changed_method = test_impl(
    "trait Sample {\n  /// changed docs\n  read(Self) -> Int\n}",
    name="trait-method-doc-changed",
  )
  let plain_method = test_impl(
    "trait Sample {\n  read(Self) -> Int\n}",
    name="trait-method-doc-missing",
  )
  assert_true(expr_matches(documented_method, changed_method))
  assert_true(expr_matches(documented_method, plain_method))
  assert_true(expr_matches(plain_method, documented_method))
}

///|
test "same-location docstrings do not introduce parse-order state" {
  let aaa_first = test_impl("/// AAA\nfn same { body() }", name="rule shape")
  let bbb_second = test_impl("/// BBB\nfn same { body() }", name="rule shape")
  let bbb_first = test_impl("/// BBB\nfn same { body() }", name="rule shape")
  let aaa_second = test_impl("/// AAA\nfn same { body() }", name="rule shape")
  let candidate = test_impl("/// AAA\nfn same { other() }", name="candidate")
  assert_true(expr_matches(aaa_first, bbb_second))
  assert_true(expr_matches(bbb_first, aaa_second))
  assert_false(expr_matches(aaa_first, candidate))
}

///|
test "ignored top-level fields implement partial matching" {
  let pattern = test_impl("fn sample { body() }", name="partial-pattern")
  let ignored : Array[IgnoredPatternField] = []
  let function_kind = pattern.kind
  for
    name in [
      "semantic_type_name", "async", "params", "quantifier", "clause", "vis", "attrs",
      "where_clause",
    ] {
    ignored.push({ parent_kind: function_kind, child_name: name })
  }
  let compiled = test_compiled(pattern, ignored_fields=ignored)
  let candidate = test_impl(
    "///| docs\npub async fn sample(value : Int) -> Int { body() }",
    name="partial-candidate",
  )
  assert_true(match_expr_pattern(compiled, candidate) is Some(_))
  assert_false(
    match_expr_pattern(
      compiled,
      test_impl("fn other { body() }", name="partial-other"),
    )
    is Some(_),
  )
}

///|
test "caller bindings are copied and repeated values ignore locations" {
  let compiled = test_compiled(test_expr("pair(value, value)"), expr_metavars=[
    "value",
  ])
  let initial : @hashmap.HashMap[String, BoundValue] = HashMap([])
  initial["existing"] = Single(test_expr("kept"))
  guard match_expr_pattern_with_bindings(
      compiled,
      test_expr("pair(item, item)", name="candidate-locations"),
      initial,
    )
    is Some(result) else {
    fail("expected match")
  }
  assert_true(result.bindings.contains("existing"))
  assert_false(initial.contains("value"))
}
