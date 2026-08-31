///|
fn test_expr(
  source : String,
  name? : String = "matching test",
) -> @untyped_cst.CstNode raise {
  let parsed = @untyped_cst.parse_expression(source, name~, enable_metavar=true)
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
  let parsed = @untyped_cst.parse_structure(source, name~, enable_metavar=true)
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
  entries? : Array[MetavarEntry] = [],
  special_expr_placeholders? : Array[String] = [],
  ignored_fields? : Array[IgnoredPatternField] = [],
) -> CompiledExprPattern {
  let metavars = MetavarRegistry::new()
  for entry in entries {
    ignore(metavars.register(entry.name, entry.kind))
  }
  for placeholder in special_expr_placeholders {
    metavars.register_special_expr_placeholder(placeholder)
  }
  { cst, metavars, ignored_fields, }
}

///|
fn test_metavar_entry(name : String, kind : MetavarKind) -> MetavarEntry {
  { name, kind, }
}

///|
fn expr_matches(
  pattern : @untyped_cst.CstNode,
  candidate : @untyped_cst.CstNode,
) -> Bool {
  match_expr_pattern(test_compiled(pattern), candidate) is Some(_)
}

///|
fn test_candidate(source : String) -> @cst.ExprMatchCandidate raise {
  let node = test_expr(source)
  if node.kind is @untyped_cst.Expression {
    @cst.Sequence(@cst.expression_nodes(node))
  } else {
    @cst.Direct(node)
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
  let compiled = test_compiled(test_expr("pair($(value:exp), $(value:exp))"), entries=[
    test_metavar_entry("value", Expr),
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
test "raw expression and constant metavars use logical names" {
  let exp = test_compiled(test_expr("$(value:exp)"), entries=[
    test_metavar_entry("value", Expr),
  ])
  assert_true(match_expr_pattern(exp, test_expr("some_call()")) is Some(_))
  let constant = test_compiled(test_expr("$(value:const)"), entries=[
    test_metavar_entry("value", Constant),
  ])
  let value = test_single_binding(
    match_expr_pattern(constant, test_expr("42")),
    "value",
  )
  assert_true(value.kind.is_constant())
}

///|
test "identifier metavars normalize binder and expression names" {
  let compiled = test_compiled(
    test_expr("match subject { $(name:id) => $(name:id) }"),
    entries=[test_metavar_entry("name", Identifier)],
  )
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
test "qualified identifier metavars require the same prefix" {
  for pattern_source in ["@pkg.$(callee:id)()", "@pkg.$callee()"] {
    let compiled = test_compiled(test_expr(pattern_source), entries=[
      test_metavar_entry("callee", Identifier),
    ])
    for candidate_source in ["local()", "@other.wrong()"] {
      assert_false(
        match_expr_pattern(compiled, test_expr(candidate_source)) is Some(_),
      )
    }
    let captured = test_single_binding(
      match_expr_pattern(compiled, test_expr("@pkg.remote()")),
      "callee",
    )
    assert_eq(@cst.normalized_name(captured), Some("@pkg.remote"))
  }
}

///|
test "qualified wildcard does not match as an expression placeholder" {
  let compiled = test_compiled(test_expr("@html.$_"))
  assert_false(
    match_expr_pattern(compiled, test_expr("@html.render(value)")) is Some(_),
  )
  assert_false(
    match_expr_pattern(compiled, test_expr("render(value)")) is Some(_),
  )
}

///|
test "one identifier metavar captures a complete constructor identity" {
  let compiled = test_compiled(test_expr("$(Ctor:id)($(Ctor:id))"), entries=[
    test_metavar_entry("Ctor", Identifier),
  ])
  let cases = [
    ("Ctor(Ctor)", "Ctor"),
    ("@pkg.Ctor(@pkg.Ctor)", "@pkg.Ctor"),
    ("Type::Ctor(Type::Ctor)", "Type::Ctor"),
    ("@pkg.Type::Ctor(@pkg.Type::Ctor)", "@pkg.Type::Ctor"),
    ("@pkg.Type::@other.Ctor(@pkg.Type::@other.Ctor)", "@pkg.Type::@other.Ctor"),
  ]
  for case in cases {
    let (source, identity) = case
    let captured = test_single_binding(
      match_expr_pattern(compiled, test_expr(source)),
      "Ctor",
    )
    assert_eq(@cst.normalized_name(captured), Some(identity))
    assert_eq(@cst.source_text(captured, source), identity)
  }
  assert_false(
    match_expr_pattern(
      compiled,
      test_expr("@pkg.Type::Ctor(@other.Type::Ctor)"),
    )
    is Some(_),
  )
}

///|
test "constructor identity bindings compare across patterns and expressions" {
  let compiled = test_compiled(
    test_expr(
      "match input { $(Ctor:id)($(item:id)) => $(Ctor:id)($(item:id)) }",
    ),
    entries=[
      test_metavar_entry("Ctor", Identifier),
      test_metavar_entry("item", Identifier),
    ],
  )
  let matched = test_expr(
    "match input { @pkg.Type::Ctor(item) => @pkg.Type::Ctor(item) }",
  )
  let constructor_name = test_single_binding(
    match_expr_pattern(compiled, matched),
    "Ctor",
  )
  assert_eq(@cst.normalized_name(constructor_name), Some("@pkg.Type::Ctor"))
  assert_false(
    match_expr_pattern(
      compiled,
      test_expr(
        "match input { @pkg.Type::Ctor(item) => @other.Type::Ctor(item) }",
      ),
    )
    is Some(_),
  )
  assert_false(
    match_expr_pattern(
      compiled,
      test_expr(
        "match input { @pkg.Type::Ctor(left) => @pkg.Type::Ctor(right) }",
      ),
    )
    is Some(_),
  )
}

///|
test "explicit constructor identity parts remain separate captures" {
  let compiled = test_compiled(test_expr("$(Type:id)::$(Ctor:id)(value)"), entries=[
    test_metavar_entry("Type", Identifier),
    test_metavar_entry("Ctor", Identifier),
  ])
  guard match_expr_pattern(compiled, test_expr("@pkg.Type::Ctor(value)"))
    is Some(result) else {
    fail("expected split constructor identity match")
  }
  guard result.bindings.get("Type") is Some(Single(type_name)) &&
    result.bindings.get("Ctor") is Some(Single(constructor_name)) else {
    fail("expected split constructor identity captures")
  }
  assert_eq(@cst.normalized_name(type_name), Some("@pkg.Type"))
  assert_eq(@cst.normalized_name(constructor_name), Some("Ctor"))
  let pattern_compiled = test_compiled(
    test_expr("match input { $(Type:id)::$(Ctor:id)(value) => body }"),
    entries=[
      test_metavar_entry("Type", Identifier),
      test_metavar_entry("Ctor", Identifier),
    ],
  )
  guard match_expr_pattern(
      pattern_compiled,
      test_expr("match input { Type::Ctor(value) => body }"),
    )
    is Some(pattern_result) else {
    fail("expected split constructor pattern identity match")
  }
  guard pattern_result.bindings.get("Type") is Some(Single(pattern_type)) &&
    pattern_result.bindings.get("Ctor") is Some(Single(pattern_constructor)) else {
    fail("expected split constructor pattern captures")
  }
  assert_eq(@cst.normalized_name(pattern_type), Some("Type"))
  assert_eq(@cst.normalized_name(pattern_constructor), Some("Ctor"))
}

///|
test "constant metavars work in expressions and patterns" {
  let expression = test_compiled(test_expr("check($(value:const))"), entries=[
    test_metavar_entry("value", Constant),
  ])
  assert_true(
    match_expr_pattern(expression, test_expr("check(\"raw\")")) is Some(_),
  )
  assert_false(
    match_expr_pattern(expression, test_expr("check(name)")) is Some(_),
  )
  let pattern = test_compiled(
    test_expr("match input { $(value:const) => body }"),
    entries=[test_metavar_entry("value", Constant)],
  )
  assert_true(
    match_expr_pattern(pattern, test_expr("match input { 7 => body }"))
    is Some(_),
  )
}

///|
test "constant metavars reuse captures across patterns and expressions" {
  let compiled = test_compiled(
    test_expr("match input { $(lit:const) => $(lit:const) }"),
    entries=[test_metavar_entry("lit", Constant)],
  )
  assert_true(
    match_expr_pattern(compiled, test_expr("match input { 7 => 7 }")) is Some(_),
  )
  assert_false(
    match_expr_pattern(compiled, test_expr("match input { 7 => 8 }")) is Some(_),
  )
}

///|
test "argument metavars capture the complete argument kind" {
  let compiled = test_compiled(test_expr("sink($(item:arg))"), entries=[
    test_metavar_entry("item", Argument),
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
    test_expr("match input { $(item:pat) => body }"),
    entries=[test_metavar_entry("item", Pattern)],
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
test "type metavars compare repeated captures" {
  let compiled = test_compiled(
    test_expr("match input { (left : $(T:type), right : $(T:type)) => body }"),
    entries=[test_metavar_entry("T", Type)],
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
  let compiled = test_compiled(test_expr("wrap($_)"))
  guard match_expr_pattern(compiled, test_expr("wrap(complex(1))"))
    is Some(result) else {
    fail("expected match")
  }
  assert_true(result.bindings.is_empty())
}

///|
test "ellipsis captures ordered argument spans including empty spans" {
  let compiled = test_compiled(test_expr("call($$$items, tail)"), entries=[
    test_metavar_entry("items", Ellipsis(AnyItem)),
  ])
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
  let compiled = test_compiled(test_expr("call($$$(values:const))"), entries=[
    test_metavar_entry("values", Ellipsis(ConstItem)),
  ])
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
  let compiled = test_compiled(test_expr("if $_ { $_ } else {}"))
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
  let let_pattern = test_compiled(test_expr("let ($_, $_) = $_"))
  assert_true(
    match_expr_pattern(
      let_pattern,
      test_expr("let (fst, snd) = tuple\nconsume(fst)\nsnd"),
    )
    is Some(_),
  )
}

///|
test "only ordinary let and guard omit a sequence continuation" {
  let allowed = [
    ("let value = source()", "let value = source(); consume(value)"),
    (
      "guard ready() else { fallback() }", "guard ready() else { fallback() }; continue_work()",
    ),
  ]
  for case in allowed {
    let (pattern, candidate) = case
    assert_true(
      match_expr_pattern_candidate(
        test_compiled(test_expr(pattern)),
        test_candidate(candidate),
      )
      is Some(_),
    )
  }
  let rejected = [
    ("let mut value = source()", "let mut value = source(); consume(value)"),
    (
      "letrec recur = fn(value) { value }", "letrec recur = fn(value) { value }; recur(source())",
    ),
    ("defer cleanup()", "defer cleanup(); continue_work()"),
  ]
  for case in rejected {
    let (pattern, candidate) = case
    assert_false(
      match_expr_pattern_candidate(
        test_compiled(test_expr(pattern)),
        test_candidate(candidate),
      )
      is Some(_),
    )
  }
}

///|
test "complete statement shapes match sequence candidates" {
  for
    source in [
      "let mut value = source(); consume(value)", "letrec recur = fn(value) { value }; recur(source())",
      "defer cleanup(); continue_work()",
    ] {
    let compiled = test_compiled(test_expr(source))
    assert_true(
      match_expr_pattern_candidate(compiled, test_candidate(source)) is Some(_),
    )
  }
}

///|
test "explicit continuation metavars capture complete let and guard suffixes" {
  let cases = [
    ("let value = source(); $(body:exp)", "let value = source()", "", true),
    (
      "let value = source(); $(body:exp)", "let value = source(); consume(value)",
      "consume(value)", false,
    ),
    (
      "let value = source(); $(body:exp)", "let value = source(); consume(value); finish(value)",
      "consume(value); finish(value)", true,
    ),
    (
      "let mut value = source(); $(body:exp)", "let mut value = source()", "", true,
    ),
    (
      "let mut value = source(); $(body:exp)", "let mut value = source(); consume(value)",
      "consume(value)", false,
    ),
    (
      "let mut value = source(); $(body:exp)", "let mut value = source(); consume(value); finish(value)",
      "consume(value); finish(value)", true,
    ),
    (
      "guard ready() else { fallback() }; $(body:exp)", "guard ready() else { fallback() }",
      "", true,
    ),
    (
      "guard ready() else { fallback() }; $(body:exp)", "guard ready() else { fallback() }; continue_work()",
      "continue_work()", false,
    ),
    (
      "guard ready() else { fallback() }; $(body:exp)", "guard ready() else { fallback() }; continue_work(); finish()",
      "continue_work(); finish()", true,
    ),
  ]
  for case in cases {
    let (pattern, candidate, expected_body, expected_multiple) = case
    guard match_expr_pattern_candidate(
        test_compiled(test_expr(pattern), entries=[
          test_metavar_entry("body", Expr),
        ]),
        test_candidate(candidate),
      )
      is Some(result) else {
      fail("expected continuation match: \{candidate}")
    }
    let (actual_body, actual_multiple) = match result.bindings.get("body") {
      Some(Single(node)) => (@cst.source_text(node, candidate), false)
      Some(Multiple(nodes)) =>
        (
          [ for node in nodes => @cst.source_text(node, candidate) ].join("; "),
          true,
        )
      None => fail("expected body binding: \{candidate}")
    }
    assert_eq(actual_body, expected_body)
    assert_eq(actual_multiple, expected_multiple)
    assert_eq(result.loc.start.cnum, 0)
    assert_eq(result.loc.end.cnum, candidate.length())
  }
}

///|
test "direct continuation captures preserve explicit block candidates" {
  let compiled = test_compiled(test_expr("let value = source(); $(body:exp)"), entries=[
    test_metavar_entry("body", Expr),
  ])
  let cases = [
    ("{ let value = source() }", "", true),
    ("{ let value = source(); consume(value) }", "consume(value)", false),
    (
      "{ let value = source(); consume(value); finish(value) }", "consume(value); finish(value)",
      true,
    ),
  ]
  for case in cases {
    let (candidate, expected_body, expected_multiple) = case
    guard match_expr_pattern_candidate(compiled, test_candidate(candidate))
      is Some(result) else {
      fail("expected explicit block continuation match: \{candidate}")
    }
    assert_true(result.root.kind is @untyped_cst.Expr_Block)
    assert_eq(result.loc.start.cnum, 0)
    assert_eq(result.loc.end.cnum, candidate.length())
    let (actual_body, actual_multiple) = match result.bindings.get("body") {
      Some(Single(node)) => (@cst.source_text(node, candidate), false)
      Some(Multiple(nodes)) =>
        (
          [ for node in nodes => @cst.source_text(node, candidate) ].join("; "),
          true,
        )
      None => fail("expected body binding: \{candidate}")
    }
    assert_eq(actual_body, expected_body)
    assert_eq(actual_multiple, expected_multiple)
  }
  assert_false(
    match_expr_pattern_candidate(
      compiled,
      test_candidate("{ let mut value = source(); consume(value) }"),
    )
    is Some(_),
  )
  let ignore = test_compiled(test_expr("let value = source(); $_"))
  for
    candidate in [
      "{ let value = source() }", "{ let value = source(); consume(value) }", "{ let value = source(); consume(value); finish(value) }",
    ] {
    assert_true(
      match_expr_pattern_candidate(ignore, test_candidate(candidate)) is Some(_),
    )
  }
}

///|
test "nested expression containers capture complete continuation suffixes" {
  let cases = [
    (
      "wrapper({ let item = source(); $(body:exp) })", "wrapper({ let item = source() })",
      "", true,
    ),
    (
      "wrapper({ let item = source(); $(body:exp) })", "wrapper({ let item = source(); consume(item) })",
      "consume(item)", false,
    ),
    (
      "wrapper({ let item = source(); $(body:exp) })", "wrapper({ let item = source(); consume(item); finish(item) })",
      "consume(item); finish(item)", true,
    ),
    (
      "if ready() { let item = source(); $(body:exp) }", "if ready() { let item = source(); consume(item); finish(item) }",
      "consume(item); finish(item)", true,
    ),
  ]
  for case in cases {
    let (pattern, candidate, expected_body, expected_multiple) = case
    guard match_expr_pattern_candidate(
        test_compiled(test_expr(pattern), entries=[
          test_metavar_entry("body", Expr),
        ]),
        test_candidate(candidate),
      )
      is Some(result) else {
      fail("expected nested continuation match: \{candidate}")
    }
    let (actual_body, actual_multiple) = match result.bindings.get("body") {
      Some(Single(node)) => (@cst.source_text(node, candidate), false)
      Some(Multiple(nodes)) =>
        (
          [ for node in nodes => @cst.source_text(node, candidate) ].join("; "),
          true,
        )
      None => fail("expected nested body binding: \{candidate}")
    }
    assert_eq(actual_body, expected_body)
    assert_eq(actual_multiple, expected_multiple)
  }
}

///|
test "terminal ignore placeholder absorbs every continuation owner suffix" {
  let headers = [
    "let value = source()", "let mut value = source()", "fn helper(value) { value }",
    "letrec helper = fn(value) { value }", "guard ready() else { fallback() }", "defer cleanup()",
  ]
  let suffixes = ["", "; continue_work()", "; continue_work(); finish()"]
  for header in headers {
    let root = test_compiled(test_expr("\{header}; $_"))
    let nested = test_compiled(test_expr("wrapper({ \{header}; $_ })"))
    for suffix in suffixes {
      let candidate = "\{header}\{suffix}"
      guard match_expr_pattern_candidate(root, test_candidate(candidate))
        is Some(root_result) else {
        fail("expected terminal ignore continuation match: \{candidate}")
      }
      assert_true(root_result.bindings.get("$_") is None)
      assert_true(root_result.bindings.get("_") is None)
      let nested_candidate = "wrapper({ \{candidate} })"
      guard match_expr_pattern_candidate(
          nested,
          test_candidate(nested_candidate),
        )
        is Some(nested_result) else {
        fail(
          "expected nested terminal ignore continuation match: \{nested_candidate}",
        )
      }
      assert_true(nested_result.bindings.get("$_") is None)
      assert_true(nested_result.bindings.get("_") is None)
    }
  }
}

///|
test "terminal ignore placeholder commits header bindings without binding itself" {
  let compiled = test_compiled(test_expr("let $(name:id) = $(value:exp); $_"), entries=[
    test_metavar_entry("value", Expr),
    test_metavar_entry("name", Identifier),
  ])
  for
    candidate in [
      "let item = load()", "let item = load(); consume(item)", "let item = load(); consume(item); finish(item)",
    ] {
    guard match_expr_pattern_candidate(compiled, test_candidate(candidate))
      is Some(result) else {
      fail("expected continuation match with header bindings: \{candidate}")
    }
    guard result.bindings.get("name") is Some(Single(name)) else {
      fail("expected name binding: \{candidate}")
    }
    guard result.bindings.get("value") is Some(Single(value)) else {
      fail("expected value binding: \{candidate}")
    }
    assert_eq(@cst.source_text(name, candidate), "item")
    assert_eq(@cst.source_text(value, candidate), "load()")
    assert_true(result.bindings.get("$_") is None)
    assert_true(result.bindings.get("_") is None)
  }
}

///|
test "non-terminal and non-owner ignore placeholders match one expression" {
  let cases = [
    ("before(); $_", "before()", false),
    ("before(); $_", "before(); middle()", true),
    ("before(); $_", "before(); middle(); after()", false),
    ("proof_let witness = fact(); $_", "proof_let witness = fact()", false),
    (
      "proof_let witness = fact(); $_", "proof_let witness = fact(); use(witness)",
      true,
    ),
    (
      "proof_let witness = fact(); $_", "proof_let witness = fact(); use(witness); finish()",
      false,
    ),
    (
      "let value = source(); $_; finish()", "let value = source(); finish()", false,
    ),
    (
      "let value = source(); $_; finish()", "let value = source(); middle(); finish()",
      true,
    ),
    (
      "let value = source(); $_; finish()", "let value = source(); first(); second(); finish()",
      false,
    ),
  ]
  for case in cases {
    let (pattern, candidate, expected_match) = case
    assert_eq(
      match_expr_pattern_candidate(
        test_compiled(test_expr(pattern)),
        test_candidate(candidate),
      )
      is Some(_),
      expected_match,
    )
  }
}

///|
test "sequence candidates reject broad expressions and omit wrapper braces" {
  let broad = test_compiled(test_expr("$_"))
  assert_false(
    match_expr_pattern_candidate(broad, test_candidate("first(); second()"))
    is Some(_),
  )
  let source = "first(); second()"
  let exact = test_compiled(test_expr(source))
  guard match_expr_pattern_candidate(exact, test_candidate(source))
    is Some(result) else {
    fail("expected complete sequence match")
  }
  assert_eq(result.loc.start.cnum, 0)
  assert_eq(result.loc.end.cnum, source.length())
  let block_source = "{ first(); second() }"
  guard match_expr_pattern_candidate(
      test_compiled(test_expr(block_source)),
      test_candidate(block_source),
    )
    is Some(block_result) else {
    fail("expected explicit block match")
  }
  assert_eq(block_result.loc.start.cnum, 0)
  assert_eq(block_result.loc.end.cnum, block_source.length())
}

///|
test "proof let remains an independent direct candidate" {
  let sequence = test_candidate("proof_let witness = fact(); use(witness)")
  guard sequence is @cst.Sequence([header, ..]) else {
    fail("expected proof-let sequence")
  }
  assert_true(header.kind is @untyped_cst.Expr_ProofLet)
  assert_true(
    match_expr_pattern_candidate(
      test_compiled(test_expr("proof_let witness = fact()")),
      @cst.Direct(header),
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
    ignored.push({ parent_kind: function_kind, child_name: name, })
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
  let compiled = test_compiled(test_expr("pair($(value:exp), $(value:exp))"), entries=[
    test_metavar_entry("value", Expr),
  ])
  let initial : @hashmap.HashMap[String, BoundValue] = HashMap([])
  initial["existing"] = Single(test_expr("kept"))
  guard match_expr_pattern_candidate_with_bindings(
      compiled,
      @cst.Direct(test_expr("pair(item, item)", name="candidate-locations")),
      initial,
    )
    is Some(result) else {
    fail("expected match")
  }
  assert_true(result.bindings.contains("existing"))
  assert_false(initial.contains("value"))
}
