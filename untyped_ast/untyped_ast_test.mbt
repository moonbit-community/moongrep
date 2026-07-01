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
  expected_kind : String,
) -> Unit raise {
  let expr = parse_test_expr(source)
  let root = from_expr(expr)
  if root.kind != expected_kind {
    fail("expected \{source} to parse as \{expected_kind}, got \{root.kind}")
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
  let cases : Array[(String, String)] = [
    ("f(x)", "Expr::Apply"),
    ("[a, b]", "Expr::Array"),
    ("arr[0] += value", "Expr::ArrayAugmentedSet"),
    ("arr[0]", "Expr::ArrayGet"),
    ("arr[1:3]", "Expr::ArrayGetSlice"),
    ("arr[0] = value", "Expr::ArraySet"),
    ("[..xs, y]", "Expr::ArraySpread"),
    ("value as Show", "Expr::As"),
    ("x = y", "Expr::Assign"),
    ("break value", "Expr::Break"),
    ("42", "Expr::Constant"),
    ("Some", "Expr::Constr"),
    ("(value : Int)", "Expr::Constraint"),
    ("continue value", "Expr::Continue"),
    ("defer cleanup(); body", "Expr::Defer"),
    ("receiver.method(arg)", "Expr::DotApply"),
    ("record.field", "Expr::Field"),
    ("for i = 0; i < n; i = i + 1 { i }", "Expr::For"),
    ("for item in items { item }", "Expr::ForEach"),
    ("fn(x) { x }", "Expr::Function"),
    ("{ a; b }", "Expr::Group"),
    ("guard cond else { fallback }; body", "Expr::Guard"),
    ("_", "Expr::Hole"),
    ("x", "Expr::Ident"),
    ("if cond { a } else { b }", "Expr::If"),
    ("a → b", "Expr::Implies"),
    ("a + b", "Expr::Infix"),
    ("\"hello \\{name}\"", "Expr::Interp"),
    ("value is Some(x)", "Expr::Is"),
    ("value lexmatch? _", "Expr::IsLexmatch"),
    ("let x = 1; x", "Expr::Let"),
    ("letrec f = fn(x) { x } and g = fn(y) { y }; f(1)", "Expr::LetAnd"),
    ("fn helper(x) { x }; helper(1)", "Expr::LetFn"),
    ("let mut x = 1; x", "Expr::LetMut"),
    ("lexmatch input { _ => true }", "Expr::Lexmatch"),
    (
      "[for item in items if allow(item) => target(item)]", "Expr::ListComprehension",
    ),
    ("[for i = 0; i < n; i = i + 1 => i]", "Expr::ListComprehension"),
    ("{ \"k\": value }", "Expr::Map"),
    ("match value { Some(x) => x; _ => fallback }", "Expr::Match"),
    ("Int::to_string", "Expr::Method"),
    ("#|hello", "Expr::MultilineString"),
    ("record.field = value", "Expr::Mutate"),
    ("value |> f", "Expr::Pipe"),
    ("proof_assert value", "Expr::ProofAssert"),
    ("proof_let x = value", "Expr::ProofLet"),
    ("∀ x : Int, x > 0", "Expr::Quantifier"),
    ("∃ x : Int, x > 0", "Expr::Quantifier"),
    ("raise err", "Expr::Raise"),
    ("{ field: value }", "Expr::Record"),
    ("{ ..record, field: value }", "Expr::RecordUpdate"),
    ("text =~ re\"abc\"", "Expr::RegexMatch"),
    ("return value", "Expr::Return"),
    ("f <| value", "Expr::RevPipe"),
    ("a; b", "Expr::Sequence"),
    ("writer <+ \"hello\"", "Expr::TemplateWriting"),
    ("try f() catch { _ => fallback }", "Expr::Try"),
    ("try! f()", "Expr::TryOperator"),
    ("try? f()", "Expr::TryOperator"),
    ("(a, b)", "Expr::Tuple"),
    ("-value", "Expr::Unary"),
    ("()", "Expr::Unit"),
    ("while cond { body } nobreak { done }", "Expr::While"),
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
    assert_expr_kind_json_matches_parser(source, "Expr::Constant")
  }
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
  assert_eq(root.kind, "Expr::StaticAssert")
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
  match root.children {
    AstFields(fields) => {
      assert_eq(fields.length(), 3)
      match fields[0] {
        ("op", AstNode(op)) => {
          assert_eq(op.kind, "Var")
          match op.children {
            AstFields(op_fields) => assert_eq(op_fields.length(), 1)
            AstItems(_) => fail("expected operator node to expose named fields")
          }
        }
        _ => fail("expected first child to be operator node")
      }
    }
    AstItems(_) => fail("expected expression node to expose named fields")
  }
}

///|
test "untyped ast impl list uses direct item children" {
  let first = parse_test_impl("fn answer { 42 }")
  let second = parse_test_impl("let answer = 42")
  let list = from_impls(@list.from_array([first, second]))
  assert_eq(list.kind, "ImplList")
  match list.children {
    AstItems(items) => {
      assert_eq(items.length(), 2)
      match items[0] {
        AstNode(node) => assert_eq(node.kind, "Impl::TopFuncDef")
        _ => fail("expected first impl item")
      }
    }
    AstFields(_) => fail("expected impl list to expose direct item children")
  }
}
