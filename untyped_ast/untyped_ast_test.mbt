///|
fn parse_test_expr(source : String) -> @syntax.Expr raise {
  let lex_result = @lexer.tokens_from_string(
    source,
    comment=true,
    name="untyped ast expr test",
  )
  guard lex_result.errors.length() == 0 else {
    fail("expected expression to lex: \{source}")
  }
  let (expr, reports) = @handrolled_parser.parse_expr(lex_result.tokens)
  guard reports is [] else { fail("expected expression to parse: \{source}") }
  expr
}

///|
fn parse_test_impl(source : String) -> @syntax.Impl raise {
  let (impls, reports) = @parser.parse_string(
    source,
    name="untyped ast impl test",
  )
  guard reports is [] else { fail("expected impl to parse: \{source}") }
  let nodes = impls.to_array()
  guard nodes.length() == 1 else { fail("expected one impl: \{source}") }
  nodes[0]
}

///|
fn assert_expr_json_matches_parser(source : String) -> Unit raise {
  let expr = parse_test_expr(source)
  assert_true(from_expr(expr).to_json() == expr.to_json())
}

///|
fn assert_expr_kind_json_matches_parser(
  source : String,
  expected_kind : NodeKind,
) -> Unit raise {
  let expr = parse_test_expr(source)
  let root = from_expr(expr)
  if root.kind != expected_kind {
    fail(
      "expected \{source} to parse as \{expected_kind.to_string()}, got \{root.kind.to_string()}",
    )
  }
  if root.to_json() != expr.to_json() {
    fail("expected untyped ast json to match parser json: \{source}")
  }
}

///|
fn assert_impl_json_matches_parser(source : String) -> Unit raise {
  let item = parse_test_impl(source)
  assert_true(from_impl(item).to_json() == item.to_json())
}

///|
test "untyped ast expression json matches parser json" {
  assert_expr_json_matches_parser("x + 1")
  assert_expr_json_matches_parser("try f() catch { _ => fallback }")
  assert_expr_json_matches_parser(
    "[for item in items if allow(item) => target(item)]",
  )
}

///|
test "untyped ast covers expression root variants" {
  let cases : Array[(String, NodeKind)] = [
    ("f(x)", Expr_Apply),
    ("[a, b]", Expr_Array),
    ("arr[0] += value", Expr_ArrayAugmentedSet),
    ("arr[0]", Expr_ArrayGet),
    ("arr[1:3]", Expr_ArrayGetSlice),
    ("arr[0] = value", Expr_ArraySet),
    ("[..xs, y]", Expr_ArraySpread),
    ("value as Show", Expr_As),
    ("x = y", Expr_Assign),
    ("break value", Expr_Break),
    ("42", Expr_Constant),
    ("Some", Expr_Constr),
    ("(value : Int)", Expr_Constraint),
    ("continue value", Expr_Continue),
    ("defer cleanup(); body", Expr_Defer),
    ("receiver.method(arg)", Expr_DotApply),
    ("record.field", Expr_Field),
    ("for i = 0; i < n; i = i + 1 { i }", Expr_For),
    ("for item in items { item }", Expr_ForEach),
    ("fn(x) { x }", Expr_Function),
    ("{ a; b }", Expr_Group),
    ("guard cond else { fallback }; body", Expr_Guard),
    ("_", Expr_Hole),
    ("x", Expr_Ident),
    ("if cond { a } else { b }", Expr_If),
    ("a → b", Expr_Implies),
    ("a + b", Expr_Infix),
    ("\"hello \\{name}\"", Expr_Interp),
    ("value is Some(x)", Expr_Is),
    ("value lexmatch? _", Expr_IsLexmatch),
    ("let x = 1; x", Expr_Let),
    ("letrec f = fn(x) { x } and g = fn(y) { y }; f(1)", Expr_LetAnd),
    ("fn helper(x) { x }; helper(1)", Expr_LetFn),
    ("let mut x = 1; x", Expr_LetMut),
    ("lexmatch input { _ => true }", Expr_Lexmatch),
    (
      "[for item in items if allow(item) => target(item)]",
      Expr_ListComprehension,
    ),
    ("[for i = 0; i < n; i = i + 1 => i]", Expr_ListComprehension),
    ("{ \"k\": value }", Expr_Map),
    ("match value { Some(x) => x; _ => fallback }", Expr_Match),
    ("Int::to_string", Expr_Method),
    ("#|hello", Expr_MultilineString),
    ("record.field = value", Expr_Mutate),
    ("value |> f", Expr_Pipe),
    ("proof_assert value", Expr_ProofAssert),
    ("proof_let x = value", Expr_ProofLet),
    ("∀ x : Int, x > 0", Expr_Quantifier),
    ("∃ x : Int, x > 0", Expr_Quantifier),
    ("raise err", Expr_Raise),
    ("{ field: value }", Expr_Record),
    ("{ ..record, field: value }", Expr_RecordUpdate),
    ("text =~ re\"abc\"", Expr_RegexMatch),
    ("return value", Expr_Return),
    ("f <| value", Expr_RevPipe),
    ("a; b", Expr_Sequence),
    // TODO: fix upstream json structure
    // ("writer <+ \"hello\"", Expr_TemplateWriting),
    ("try f() catch { _ => fallback }", Expr_Try),
    ("try! f()", Expr_TryOperator),
    ("try? f()", Expr_TryOperator),
    ("(a, b)", Expr_Tuple),
    ("-value", Expr_Unary),
    ("()", Expr_Unit),
    ("while cond { body } nobreak { done }", Expr_While),
  ]
  for item in cases {
    let (source, expected_kind) = item
    assert_expr_kind_json_matches_parser(source, expected_kind)
  }
}

///|
test "untyped ast covers expression constants" {
  let constants = [
    "true", "\"text\"", "'a'", "b'a'", "b\"abc\"", "1.2", "1.2F", "123L", "123UL",
  ]
  for source in constants {
    assert_expr_kind_json_matches_parser(source, Expr_Constant)
  }
}

///|
test "node kind string conversion preserves json kind names" {
  let infix : NodeKind = Expr_Infix
  let type_name : NodeKind = Type_Name
  assert_eq(infix.to_string(), "Expr::Infix")
  assert_eq(type_name.to_string(), "Type::Name")
}

///|
test "untyped ast covers compiler generated static assert expression" {
  let body = parse_test_expr("body")
  let loc = body.loc()
  let constr_id : @syntax.ConstrId = {
    id: @syntax.LongIdent::Ident(name="Int"),
    loc,
  }
  let ty = @syntax.Type::Name(constr_id~, tys=@list.new(), loc~)
  let assertion : @syntax.StaticAssertion = {
    loc,
    msg: "static assertion",
    trait_: @syntax.LongIdent::Ident(name="Show"),
    ty,
  }
  let expr = @syntax.Expr::StaticAssert(
    asserts=@list.from_array([assertion]),
    body~,
  )
  let root = from_expr(expr)
  assert_true(root.kind == Expr_StaticAssert)
  assert_true(root.to_json() == expr.to_json())
}

///|
test "untyped ast impl json matches parser json" {
  assert_impl_json_matches_parser("fn answer { 42 }")
  assert_impl_json_matches_parser("let answer = 42")
  assert_impl_json_matches_parser("test { inspect(1) }")
}

///|
test "untyped ast exposes named fields children" {
  let expr = parse_test_expr("x + 1")
  let root = from_expr(expr)
  assert_eq(root.children.length(), 3)
  match root.children[0] {
    (Some("op"), op) => {
      assert_true(op.kind == Var)
      assert_eq(op.children.length(), 1)
      guard op.children[0] is (Some("name"), _) else {
        fail("expected operator node to expose named fields")
      }
    }
    _ => fail("expected first child to be operator node")
  }
}

///|
test "untyped ast impl list uses direct item children" {
  let first = parse_test_impl("fn answer { 42 }")
  let second = parse_test_impl("let answer = 42")
  let list = from_impls(@list.from_array([first, second]))
  assert_true(list.kind == ImplList)
  assert_eq(list.children.length(), 2)
  match list.children[0] {
    (None, item) => assert_true(item.kind == Impl_TopFuncDef)
    _ => fail("expected impl list to expose direct item children")
  }
}

///|
test "untyped ast scalar leaves serialize as raw json values" {
  let expr = parse_test_expr("true")
  let root = from_expr(expr)
  match root.children[0] {
    (Some("constant"), constant) =>
      match constant.children[0] {
        (Some("value"), leaf) => {
          assert_true(leaf.kind == Leaf(PBool(true)))
          assert_true(leaf.to_json() == Json::boolean(true))
          assert_true(root.to_json() == expr.to_json())
        }
        _ => fail("expected constant value leaf")
      }
    _ => fail("expected expression constant child")
  }
}
