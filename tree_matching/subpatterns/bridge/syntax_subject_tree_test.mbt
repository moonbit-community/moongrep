///|
fn parse_one_impl(source : String) -> @syntax.Impl raise {
  let (impls, reports) = @parser.parse_string(source, name="bridge_test.mbt")
  if !reports.is_empty() {
    fail("parse reports: \{to_repr(reports)}")
  }
  impls.head().unwrap()
}

///|
fn parse_one_expr_from_top_expr(source : String) -> @syntax.Expr raise {
  let (impls, reports) = @parser.parse_string(source, name="bridge_test.mbt")
  if reports.is_empty() {
    match impls.head().unwrap() {
      TopExpr(expr~, ..) => return expr
      _ => ()
    }
  }
  let wrapped = "fn __bridge_expr() -> Unit { \{source} }"
  match parse_one_impl(wrapped) {
    TopFuncDef(decl_body=DeclBody(expr~), ..) => expr
    _ => fail("expected expression wrapper function")
  }
}

///|
fn pnode(
  label : String,
  children : ArrayView[@subpatterns.Pattern],
) -> @subpatterns.Pattern {
  @subpatterns.Pattern::node(label, children)
}

///|
fn wildcard() -> @subpatterns.Pattern {
  @subpatterns.Pattern::wildcard()
}

///|
fn matches(
  subject : @subpatterns.SubjectTree[@basic.Location],
  pattern : @subpatterns.Pattern,
) -> Array[@subpatterns.Match[@basic.Location]] {
  @subpatterns.Matcher::compile([pattern]).find_all(subject)
}

///|
fn ident_pattern(name : String) -> @subpatterns.Pattern {
  pnode("Expr::Ident", [
    pnode("field:id", [
      pnode("Var", [
        pnode("field:name", [
          pnode("LongIdent::Ident", [
            pnode("field:value", [pnode("string:\{name}", [])]),
          ]),
        ]),
      ]),
    ]),
  ])
}

///|
fn binder_pattern(name : String) -> @subpatterns.Pattern {
  pnode("Binder", [pnode("field:name", [pnode("string:\{name}", [])])])
}

///|
fn label_pattern(name : String) -> @subpatterns.Pattern {
  pnode("Label", [pnode("field:name", [pnode("string:\{name}", [])])])
}

///|
fn int_constant_pattern(value : String) -> @subpatterns.Pattern {
  pnode("Expr::Constant", [
    pnode("field:constant", [
      pnode("Constant::Int", [
        pnode("field:value", [pnode("string:\{value}", [])]),
      ]),
    ]),
  ])
}

///|
fn bool_constant_pattern(value : Bool) -> @subpatterns.Pattern {
  pnode("Expr::Constant", [
    pnode("field:constant", [
      pnode("Constant::Bool", [
        pnode("field:value", [
          pnode(if value { "bool:true" } else { "bool:false" }, []),
        ]),
      ]),
    ]),
  ])
}

///|
fn type_name_pattern(name : String) -> @subpatterns.Pattern {
  pnode("Type::Name", [
    pnode("field:constr_id", [
      pnode("ConstrId", [
        pnode("field:id", [
          pnode("LongIdent::Ident", [
            pnode("field:value", [pnode("string:\{name}", [])]),
          ]),
        ]),
      ]),
    ]),
    wildcard(),
  ])
}

///|
fn positional_arg_pattern(value : @subpatterns.Pattern) -> @subpatterns.Pattern {
  pnode("Argument", [
    pnode("field:value", [value]),
    pnode("field:kind", [pnode("ArgumentKind::Positional", [])]),
  ])
}

///|
fn field_def_pattern(
  name : String,
  expr : @subpatterns.Pattern,
) -> @subpatterns.Pattern {
  pnode("FieldDef", [
    pnode("field:label", [label_pattern(name)]),
    pnode("field:expr", [expr]),
    pnode("field:is_pun", [pnode("bool:false", [])]),
  ])
}

///|
fn loc_string(loc : @basic.Location) -> String {
  "\{loc.start.fname}-\{loc.start.lnum}:\{loc.start.column()}-\{loc.end.lnum}:\{loc.end.column()}"
}

///|
fn match_loc_strings(
  subject : @subpatterns.SubjectTree[@basic.Location],
  pattern : @subpatterns.Pattern,
) -> Array[String] {
  let locs = []
  matches(subject, pattern).each(fn(match_) {
    locs.push(loc_string(match_.loc))
  })
  locs
}

///|
test "expr ident exposes json style id and string value" {
  let expr = parse_one_expr_from_top_expr("main")
  let subject = expr_to_subject_tree(expr)
  let pattern = ident_pattern("main")
  assert_eq(matches(subject, pattern).length(), 1)
}

///|
test "expr int constant exposes constant value" {
  let subject = expr_to_subject_tree(parse_one_expr_from_top_expr("42"))
  let pattern = pnode("Expr::Constant", [
    pnode("field:constant", [
      pnode("Constant::Int", [pnode("field:value", [pnode("string:42", [])])]),
    ]),
  ])
  assert_eq(matches(subject, pattern).length(), 1)
}

///|
test "let binding exposes pattern expr and body" {
  let subject = expr_to_subject_tree(
    parse_one_expr_from_top_expr("let x = 1; x"),
  )
  let pattern = pnode("Expr::Let", [
    pnode("field:pattern", [
      pnode("Pattern::Var", [pnode("field:value", [binder_pattern("x")])]),
    ]),
    pnode("field:expr", [int_constant_pattern("1")]),
    pnode("field:body", [ident_pattern("x")]),
  ])
  assert_eq(matches(subject, pattern).length(), 1)
}

///|
test "typed function parameter exposes direct option values" {
  let subject = impl_to_subject_tree(
    parse_one_impl("fn add(a : Int) -> Int { a }"),
  )
  let pattern = pnode("Impl::TopFuncDef", [
    pnode("field:fun_decl", [
      pnode("FunDecl", [
        wildcard(),
        pnode("field:name", [binder_pattern("add")]),
        wildcard(),
        wildcard(),
        pnode("field:decl_params", [
          pnode("FunDecl::ParameterList", [
            pnode("Parameter::Positional", [
              pnode("field:binder", [binder_pattern("a")]),
              pnode("field:ty", [type_name_pattern("Int")]),
            ]),
          ]),
        ]),
        wildcard(),
        wildcard(),
        wildcard(),
        wildcard(),
        wildcard(),
        wildcard(),
      ]),
    ]),
    wildcard(),
    wildcard(),
  ])
  assert_eq(matches(subject, pattern).length(), 1)
}

///|
test "conditional exposes cond ifso and ifnot" {
  let subject = expr_to_subject_tree(
    parse_one_expr_from_top_expr("if flag { 1 } else { 2 }"),
  )
  let pattern = pnode("Expr::If", [
    pnode("field:cond", [ident_pattern("flag")]),
    pnode("field:ifso", [wildcard()]),
    pnode("field:ifnot", [wildcard()]),
  ])
  assert_eq(matches(subject, pattern).length(), 1)
}

///|
test "match expression exposes cases" {
  let subject = expr_to_subject_tree(
    parse_one_expr_from_top_expr("match x { 1 => true; _ => false }"),
  )
  let pattern = pnode("Expr::Match", [
    pnode("field:expr", [ident_pattern("x")]),
    pnode("field:cases", [
      pnode("Expr::Match::CaseList", [
        pnode("Case", [
          pnode("field:pattern", [
            pnode("Pattern::Constant", [
              pnode("field:constant", [
                pnode("Constant::Int", [
                  pnode("field:value", [pnode("string:1", [])]),
                ]),
              ]),
            ]),
          ]),
          pnode("field:guard", [pnode("none", [])]),
          pnode("field:body", [bool_constant_pattern(true)]),
        ]),
        pnode("Case", [
          pnode("field:pattern", [pnode("Pattern::Any", [])]),
          pnode("field:guard", [pnode("none", [])]),
          pnode("field:body", [bool_constant_pattern(false)]),
        ]),
      ]),
    ]),
  ])
  assert_eq(matches(subject, pattern).length(), 1)
}

///|
test "record expression exposes fields and trailing" {
  let subject = expr_to_subject_tree(
    parse_one_expr_from_top_expr("{ x: 1, y: 2 }"),
  )
  let pattern = pnode("Expr::Record", [
    pnode("field:type_name", [pnode("none", [])]),
    pnode("field:fields", [
      pnode("Expr::Record::FieldList", [
        field_def_pattern("x", int_constant_pattern("1")),
        field_def_pattern("y", int_constant_pattern("2")),
      ]),
    ]),
    pnode("field:trailing", [pnode("Trailing::None", [])]),
  ])
  assert_eq(matches(subject, pattern).length(), 1)
}

///|
test "for expression exposes all json style fields" {
  let source = "fn f() -> Unit { for i = 0; i < 3; i = i + 1 { i } }"
  let subject = impl_to_subject_tree(parse_one_impl(source))
  let pattern = pnode("Expr::For", [
    pnode("field:binders", [wildcard()]),
    pnode("field:condition", [wildcard()]),
    pnode("field:continue_block", [wildcard()]),
    pnode("field:body", [wildcard()]),
    pnode("field:for_else", [wildcard()]),
    pnode("field:where_clause", [wildcard()]),
    pnode("field:label", [wildcard()]),
  ])
  assert_eq(matches(subject, pattern).length(), 1)
}

///|
test "TopExpr exposes expr flags local types and async" {
  let expr = parse_one_expr_from_top_expr("1")
  let loc = expr.loc()
  let subject = impl_to_subject_tree(
    TopExpr(expr~, is_main=false, is_async=None, loc~),
  )
  let pattern = pnode("Impl::TopExpr", [
    pnode("field:expr", [int_constant_pattern("1")]),
    pnode("field:is_main", [pnode("bool:false", [])]),
    pnode("field:local_types", [pnode("Impl::TopExpr::LocalTypeList", [])]),
    pnode("field:is_async", [pnode("none", [])]),
  ])
  assert_eq(matches(subject, pattern).length(), 1)
}

///|
test "TopLetDef exposes binder and doc string" {
  let subject = impl_to_subject_tree(
    parse_one_impl("/// doc\npub let answer = 42"),
  )
  let pattern = pnode("Impl::TopLetDef", [
    pnode("field:binder", [binder_pattern("answer")]),
    wildcard(),
    pnode("field:expr", [int_constant_pattern("42")]),
    wildcard(),
    wildcard(),
    wildcard(),
    wildcard(),
    pnode("field:doc", [pnode("string: doc", [])]),
  ])
  assert_eq(matches(subject, pattern).length(), 1)
}

///|
test "attributes use syntax raw attribute shape" {
  let subject = impl_to_subject_tree(
    parse_one_impl("#bridge\nlet attr_value = 1"),
  )
  let pattern = pnode("Impl::TopLetDef", [
    wildcard(),
    wildcard(),
    wildcard(),
    wildcard(),
    wildcard(),
    wildcard(),
    pnode("field:attrs", [
      pnode("Impl::TopLetDef::AttrList", [
        pnode("Attribute", [pnode("field:raw", [pnode("string:#bridge", [])])]),
      ]),
    ]),
    wildcard(),
  ])
  assert_eq(matches(subject, pattern).length(), 1)
}

///|
test "location root and nested expression locations" {
  let subject = expr_to_subject_tree(
    parse_one_expr_from_top_expr("foo(1, bar)"),
  )
  debug_inspect(
    match_loc_strings(
      subject,
      pnode("Expr::Apply", [
        pnode("field:func", [ident_pattern("foo")]),
        pnode("field:args", [wildcard()]),
        pnode("field:attr", [pnode("ApplyAttr::NoAttr", [])]),
      ]),
    ),
    content=(
      #|["bridge_test.mbt-1:30-1:41"]
    ),
  )
  debug_inspect(
    match_loc_strings(subject, ident_pattern("foo")),
    content=(
      #|["bridge_test.mbt-1:30-1:33"]
    ),
  )
  debug_inspect(
    match_loc_strings(
      subject,
      pnode("Constant::Int", [pnode("field:value", [pnode("string:1", [])])]),
    ),
    content=(
      #|["bridge_test.mbt-1:34-1:35"]
    ),
  )
  debug_inspect(
    match_loc_strings(subject, ident_pattern("bar")),
    content=(
      #|["bridge_test.mbt-1:37-1:40"]
    ),
  )
}

///|
test "location field and primitive inheritance" {
  let subject = impl_to_subject_tree(parse_one_impl("let answer = 42"))
  debug_inspect(
    match_loc_strings(subject, pnode("field:binder", [wildcard()])),
    content=(
      #|["bridge_test.mbt-1:1-1:16"]
    ),
  )
  debug_inspect(
    match_loc_strings(subject, pnode("string:answer", [])),
    content=(
      #|["bridge_test.mbt-1:5-1:11"]
    ),
  )
  debug_inspect(
    match_loc_strings(subject, pnode("field:expr", [wildcard()])),
    content=(
      #|["bridge_test.mbt-1:1-1:16"]
    ),
  )
  debug_inspect(
    match_loc_strings(subject, pnode("string:42", [])),
    content=(
      #|["bridge_test.mbt-1:14-1:16"]
    ),
  )
}

///|
test "expr string constant exposes constant value" {
  let subject = expr_to_subject_tree(parse_one_expr_from_top_expr("\"hi\""))
  let pattern = pnode("Expr::Constant", [
    pnode("field:constant", [
      pnode("Constant::String", [pnode("field:value", [pnode("string:hi", [])])]),
    ]),
  ])
  assert_eq(matches(subject, pattern).length(), 1)
}

///|
test "expr bool constant exposes bool leaf" {
  let subject = expr_to_subject_tree(parse_one_expr_from_top_expr("true"))
  let pattern = pnode("Expr::Constant", [
    pnode("field:constant", [
      pnode("Constant::Bool", [pnode("field:value", [pnode("bool:true", [])])]),
    ]),
  ])
  assert_eq(matches(subject, pattern).length(), 1)
}

///|
test "nested apply exposes function arguments and no attr" {
  let subject = expr_to_subject_tree(
    parse_one_expr_from_top_expr("foo(1, bar)"),
  )
  let pattern = pnode("Expr::Apply", [
    pnode("field:func", [ident_pattern("foo")]),
    pnode("field:args", [
      pnode("Expr::Apply::ArgumentList", [
        positional_arg_pattern(int_constant_pattern("1")),
        positional_arg_pattern(ident_pattern("bar")),
      ]),
    ]),
    pnode("field:attr", [pnode("ApplyAttr::NoAttr", [])]),
  ])
  assert_eq(matches(subject, pattern).length(), 1)
}
