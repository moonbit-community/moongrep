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
fn assert_contains_unshadowed(
  source : String,
  id : String,
  expected : Bool,
) -> Unit raise {
  let actual = from_expr(parse_test_expr(source)).contains_unshadowed(id~)
  if actual != expected {
    fail(
      "expected contains_unshadowed(\{id}) for \{source} to be \{expected}, got \{actual}",
    )
  }
}

///|
fn node_test_child(node : Node, name : String) -> Node? {
  for entry in node.children {
    let (child_name, value) = entry
    if child_name == Some(name) {
      return Some(value)
    }
  }
  None
}

///|
fn node_test_leaf_string(node : Node) -> String? {
  match node.kind {
    Leaf(PString(value)) => Some(value)
    _ => None
  }
}

///|
fn node_test_leaf_string_child(node : Node, name : String) -> String? {
  if node_test_child(node, name) is Some(child) {
    node_test_leaf_string(child)
  } else {
    None
  }
}

///|
fn node_test_long_ident_name(node : Node) -> String? {
  match node.kind {
    LongIdent_Ident => node_test_leaf_string_child(node, "value")
    LongIdent_Dot =>
      match
        (
          node_test_leaf_string_child(node, "pkg"),
          node_test_leaf_string_child(node, "id"),
        ) {
        (Some(pkg), Some(id)) => Some("@\{pkg}.\{id}")
        _ => None
      }
    _ => None
  }
}

///|
fn node_test_expr_ident_name(node : Node) -> String? {
  guard node.kind == Expr_Ident else { return None }
  guard node_test_child(node, "id") is Some(var_node) else { return None }
  guard node_test_child(var_node, "name") is Some(long_ident) else {
    return None
  }
  node_test_long_ident_name(long_ident)
}

///|
fn scoped_expr_ident_shadow_sets(source : String) -> Array[String] raise {
  let exprs : Array[ScopedNodeExpr] = []
  collect_node_scoped_exprs(from_expr(parse_test_expr(source)), exprs)
  [
    for scoped in exprs if node_test_expr_ident_name(scoped.expr) is Some(name) => {
      "\{name}:\{scoped.shadowed_names.join(",")}"
    }
  ]
}

///|
fn test_is_expr_kind(kind : NodeKind) -> Bool {
  match kind {
    Expr_Apply
    | Expr_Array
    | Expr_ArrayAugmentedSet
    | Expr_ArrayGet
    | Expr_ArrayGetSlice
    | Expr_ArraySet
    | Expr_ArraySpread
    | Expr_As
    | Expr_Assign
    | Expr_Break
    | Expr_Constant
    | Expr_Constr
    | Expr_Constraint
    | Expr_Continue
    | Expr_Defer
    | Expr_DotApply
    | Expr_Field
    | Expr_For
    | Expr_ForEach
    | Expr_Function
    | Expr_Group
    | Expr_Guard
    | Expr_Hole
    | Expr_Ident
    | Expr_If
    | Expr_Implies
    | Expr_Infix
    | Expr_Interp
    | Expr_Is
    | Expr_IsLexmatch
    | Expr_Let
    | Expr_LetAnd
    | Expr_LetFn
    | Expr_LetMut
    | Expr_Lexmatch
    | Expr_ListComprehension
    | Expr_Map
    | Expr_Match
    | Expr_Method
    | Expr_MultilineString
    | Expr_Mutate
    | Expr_Pipe
    | Expr_ProofAssert
    | Expr_ProofLet
    | Expr_Quantifier
    | Expr_Raise
    | Expr_Record
    | Expr_RecordUpdate
    | Expr_RegexMatch
    | Expr_Return
    | Expr_RevPipe
    | Expr_Sequence
    | Expr_StaticAssert
    | Expr_TemplateWriting
    | Expr_Try
    | Expr_TryOperator
    | Expr_Tuple
    | Expr_Unary
    | Expr_Unit
    | Expr_While => true
    _ => false
  }
}

///|
fn test_loc() -> @basic.Location {
  @syntax.no_location
}

///|
fn test_var(name : @syntax.LongIdent) -> @syntax.Var {
  { name, loc: test_loc() }
}

///|
fn test_binder(name : String) -> @syntax.Binder {
  { name, loc: test_loc() }
}

///|
fn test_label(name : String) -> @syntax.Label {
  { name, loc: test_loc() }
}

///|
fn test_expr_ident(name : @syntax.LongIdent) -> Node {
  from_expr(@syntax.Expr::Ident(id=test_var(name), loc=test_loc()))
}

///|
fn test_pattern_var(name : String) -> Node {
  from_pattern(@syntax.Pattern::Var(test_binder(name)))
}

///|
fn require_test_child(node : Node, name : String) -> Node {
  match node_test_child(node, name) {
    Some(child) => child
    None => abort("expected child \{name}")
  }
}

///|
fn require_test_first_child(node : Node) -> Node {
  guard node.children.length() > 0 else { abort("expected first child") }
  let (_, child) = node.children[0]
  child
}

///|
fn test_leaf_string(value : String) -> Node {
  { kind: Leaf(PString(value)), loc: test_loc(), children: [] }
}

///|
test "node normalized identifier methods return supported names" {
  let expr = test_expr_ident(Ident(name="target"))
  let var_node = require_test_child(expr, "id")
  let long_ident = require_test_child(var_node, "name")
  let pattern = test_pattern_var("binding")
  let binder = require_test_first_child(pattern)
  let label = from_expr(
      @syntax.Expr::Break(
        arg=None,
        label=Some(test_label("exit")),
        loc=test_loc(),
      ),
    )
    |> fn(root) { require_test_child(root, "label") }

  debug_inspect(long_ident.normalized_long_ident(), content="Some(\"target\")")
  debug_inspect(var_node.normalized_var_name(), content="Some(\"target\")")
  debug_inspect(binder.normalized_binder_name(), content="Some(\"binding\")")
  debug_inspect(label.normalized_label_name(), content="Some(\"exit\")")
  debug_inspect(
    expr.normalized_expr_identifier_name(),
    content="Some(\"target\")",
  )
  debug_inspect(
    pattern.normalized_pattern_identifier_name(),
    content="Some(\"binding\")",
  )
}

///|
test "node normalized qualified identifiers include package qualifier" {
  let expr = test_expr_ident(Dot(pkg="pkg", id="target"))
  let var_node = require_test_child(expr, "id")
  let long_ident = require_test_child(var_node, "name")
  debug_inspect(
    long_ident.normalized_long_ident(),
    content="Some(\"@pkg.target\")",
  )
  debug_inspect(var_node.normalized_var_name(), content="Some(\"@pkg.target\")")
  debug_inspect(
    expr.normalized_expr_identifier_name(),
    content="Some(\"@pkg.target\")",
  )
}

///|
test "node normalized identifier methods reject unexpected shapes" {
  let wrong = test_expr_ident(Ident(name="target"))
  let malformed_long_ident : Node = {
    kind: LongIdent_Ident,
    loc: test_loc(),
    children: FixedArray::from_array([(Some("value"), wrong)]),
  }
  let malformed_var : Node = {
    kind: Var,
    loc: test_loc(),
    children: FixedArray::from_array([(Some("name"), malformed_long_ident)]),
  }
  let malformed_binder : Node = {
    kind: Binder,
    loc: test_loc(),
    children: FixedArray::from_array([(Some("name"), wrong)]),
  }
  let malformed_label : Node = {
    kind: Label,
    loc: test_loc(),
    children: FixedArray::from_array([(Some("name"), wrong)]),
  }

  debug_inspect(wrong.normalized_long_ident(), content="None")
  debug_inspect(wrong.normalized_var_name(), content="None")
  debug_inspect(wrong.normalized_binder_name(), content="None")
  debug_inspect(wrong.normalized_label_name(), content="None")
  debug_inspect(
    test_leaf_string("target").normalized_expr_identifier_name(),
    content="None",
  )
  debug_inspect(
    test_leaf_string("target").normalized_pattern_identifier_name(),
    content="None",
  )
  debug_inspect(malformed_long_ident.normalized_long_ident(), content="None")
  debug_inspect(malformed_var.normalized_var_name(), content="None")
  debug_inspect(malformed_binder.normalized_binder_name(), content="None")
  debug_inspect(malformed_label.normalized_label_name(), content="None")
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
test "node scoped traversal shadows let body but not initializer" {
  assert_eq(
    scoped_expr_ident_shadow_sets("let target = source; target").join("|"),
    "source:|target:target",
  )
}

///|
test "node scoped traversal shadows function parameters in body" {
  assert_eq(
    scoped_expr_ident_shadow_sets("fn(target) { target + source }").join("|"),
    "target:target|source:target",
  )
}

///|
test "node scoped traversal shadows match case guard and body" {
  assert_eq(
    scoped_expr_ident_shadow_sets(
      "match input { Some(target) if target > 0 => target + source }",
    ).join("|"),
    "input:|target:target|target:target|source:target",
  )
}

///|
test "node scoped traversal propagates condition binders through true branches" {
  assert_eq(
    scoped_expr_ident_shadow_sets(
      "if maybe is Some(target) && target > 0 { target } else { fallback }",
    ).join("|"),
    "maybe:|target:target|target:target|fallback:",
  )
  assert_eq(
    scoped_expr_ident_shadow_sets(
      "guard maybe is Some(target) else { fallback }; target",
    ).join("|"),
    "maybe:|fallback:|target:target",
  )
}

///|
test "node scoped traversal tracks list comprehension scopes" {
  assert_eq(
    scoped_expr_ident_shadow_sets(
      "[for item in items if maybe is Some(target) => item + target + source]",
    ).join("|"),
    "items:|maybe:item|item:item,target|target:item,target|source:item,target",
  )
}

///|
test "node scoped visitor prune skips children" {
  let visited : Array[String] = []
  visit_node_scoped_exprs(from_expr(parse_test_expr("target + source")), fn(
    scoped,
  ) {
    match node_test_expr_ident_name(scoped.expr) {
      Some(name) => visited.push(name)
      None => ()
    }
    NodeVisitPrune
  })
  assert_eq(visited.join("|"), "")
}

///|
test "node scoped root traversal skips non-expression roots" {
  let first = parse_test_impl("fn sample { target() }")
  let second = parse_test_impl("let answer = 42")
  let root = from_impls(@list.from_array([first, second]))
  let exprs : Array[ScopedNodeExpr] = []
  collect_node_scoped_expr_roots(root, exprs)
  assert_true(exprs.length() > 0)
  for scoped in exprs {
    if !test_is_expr_kind(scoped.expr.kind) {
      fail(
        "expected only expression nodes, got \{scoped.expr.kind.to_string()}",
      )
    }
  }
}

///|
test "node contains_unshadowed tracks identifier uses through local shadowing" {
  assert_true(
    from_expr(parse_test_expr("target + 1")).contains_unshadowed(id="target"),
  )
  assert_false(
    from_expr(parse_test_expr("let target = source; target")).contains_unshadowed(
      id="target",
    ),
  )
  assert_true(
    from_expr(parse_test_expr("let other = target; other")).contains_unshadowed(
      id="target",
    ),
  )
  assert_false(
    from_expr(parse_test_expr("let mut target = source; target")).contains_unshadowed(
      id="target",
    ),
  )
  assert_true(
    from_expr(parse_test_expr("let mut other = target; other")).contains_unshadowed(
      id="target",
    ),
  )
}

///|
test "node contains_unshadowed tracks identifier uses through function and match scopes" {
  assert_false(
    from_expr(parse_test_expr("fn(target) { target }")).contains_unshadowed(
      id="target",
    ),
  )
  assert_true(
    from_expr(parse_test_expr("fn(other) { target }")).contains_unshadowed(
      id="target",
    ),
  )
  assert_false(
    from_expr(parse_test_expr("match input { Some(target) => target }")).contains_unshadowed(
      id="target",
    ),
  )
  assert_true(
    from_expr(parse_test_expr("match target { Some(other) => other }")).contains_unshadowed(
      id="target",
    ),
  )
}

///|
test "node contains_unshadowed tracks conditional pattern scopes" {
  assert_contains_unshadowed(
    "if maybe is Some(target) { target }", "target", false,
  )
  assert_contains_unshadowed(
    "if (maybe is Some(target)) { target }", "target", false,
  )
  assert_contains_unshadowed(
    "if target is Some(other) { other }", "target", true,
  )
  assert_contains_unshadowed(
    "if maybe is Some(target) && target > 0 { target }", "target", false,
  )
  assert_contains_unshadowed(
    "if maybe is Some(target) || target > 0 { target }", "target", true,
  )
  assert_contains_unshadowed(
    "guard maybe is Some(target) else { fallback }; target", "target", false,
  )
  assert_contains_unshadowed(
    "guard maybe is Some(target) else { target }; fallback", "target", true,
  )
  assert_contains_unshadowed(
    "match x { _ if other is Some(target) => target }", "target", false,
  )
  assert_contains_unshadowed(
    "match x { _ if target is Some(other) => other }", "target", true,
  )
  assert_contains_unshadowed(
    "while maybe is Some(target) { target }", "target", false,
  )
  assert_contains_unshadowed(
    "while maybe is Some(target) { () } nobreak { target }", "target", true,
  )
  assert_contains_unshadowed(
    "if s lexmatch? (\"a\", target) { target }", "target", false,
  )
  assert_contains_unshadowed(
    "if s =~ (re\".\" as target) { target }", "target", false,
  )
  assert_contains_unshadowed(
    "if s =~ (re\".\", before=target) { target }", "target", false,
  )
  assert_contains_unshadowed(
    "for i = 0; maybe is Some(target); i = i + 1 { target }", "target", false,
  )
  assert_contains_unshadowed(
    "for i = 0; maybe is Some(target); i = target { () }", "target", false,
  )
  assert_contains_unshadowed(
    "for i = 0; maybe is Some(target); i = i + 1 { () } nobreak { target }", "target",
    true,
  )
  assert_contains_unshadowed(
    "[for i = 0; maybe is Some(target); i = i + 1 => target]", "target", false,
  )
  assert_contains_unshadowed(
    "[for i = 0; i < 1; i = i + 1 if maybe is Some(target) => target]", "target",
    false,
  )
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
