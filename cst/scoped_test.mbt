///|
fn scoped_names_at_call(
  source : String,
  callee : String,
) -> Array[String]? raise {
  let parsed = @untyped_cst.parse_expression(source, name="scoped-test")
  if !parsed.diagnostics_view().is_empty() {
    fail("unexpected parse diagnostics for `\{source}`")
  }
  let scoped : Array[ScopedExprNode] = []
  collect_scoped_exprs(expression_root(parsed.root()), scoped)
  for item in scoped {
    if item.expr.kind is @untyped_cst.Expr_Apply &&
      raw_child(item.expr, "func").bind(normalized_expr_identifier_name) ==
      Some(callee) {
      return Some(item.shadowed_names)
    }
  }
  None
}

///|
fn require_scoped_names(
  source : String,
  callee : String,
) -> Array[String] raise {
  if scoped_names_at_call(source, callee) is Some(names) {
    names
  } else {
    fail("expected call to `\{callee}` in `\{source}`")
  }
}

///|
fn parse_scoped_structure(source : String) -> @untyped_cst.CstNode raise {
  let parsed = @untyped_cst.parse_structure(
    source,
    name="scoped-candidate-test",
  )
  if !parsed.diagnostics_view().is_empty() {
    fail("unexpected parse diagnostics for `\{source}`")
  }
  parsed.root()
}

///|
fn direct_candidate_count(
  candidates : Array[ScopedExprMatchCandidate],
  expected : (@untyped_cst.NodeKind) -> Bool,
) -> Int {
  let mut count = 0
  for item in candidates {
    if item.candidate is Direct(node) && expected(node.kind) {
      count += 1
    }
  }
  count
}

///|
test "condition bindings follow groups and conjunctions only" {
  let source = "if (value is Some(bound)) && ready(bound) { target(bound) }"
  let rhs_names = require_scoped_names(source, "ready")
  let body_names = require_scoped_names(source, "target")
  assert_true(rhs_names.contains("bound"))
  assert_true(body_names.contains("bound"))
  let disjunction_names = require_scoped_names(
    "if (value is Some(bound)) || ready() { target(bound) }", "target",
  )
  assert_true(!disjunction_names.contains("bound"))
}

///|
test "if traversal visits the semantic else branch after the else keyword" {
  let then_names = require_scoped_names(
    "if ready() { then_call() } else { else_call() }", "then_call",
  )
  let else_names = require_scoped_names(
    "if ready() { then_call() } else { else_call() }", "else_call",
  )
  assert_true(then_names.is_empty())
  assert_true(else_names.is_empty())
}

///|
test "match patterns and guards shadow names in case bodies" {
  let names = require_scoped_names(
    "match input { Some(value) as whole if value is Some(inner) => target(value, whole, inner) }",
    "target",
  )
  assert_true(names.contains("value"))
  assert_true(names.contains("whole"))
  assert_true(names.contains("inner"))
  let record_names = require_scoped_names(
    "match input { { field } => target(field) }", "target",
  )
  assert_true(record_names.contains("field"))
}

///|
test "loop and comprehension binders shadow their bodies" {
  let foreach_names = require_scoped_names(
    "for item in items { target(item) }", "target",
  )
  assert_true(foreach_names.contains("item"))
  let comprehension_names = require_scoped_names(
    "[ for item in items => target(item) ]", "target",
  )
  assert_true(comprehension_names.contains("item"))
  let loop_source = "for index = 0; index < limit; index = next(index) { body(index) } nobreak { after(index) } where { invariant: proof(index) }"
  assert_true(require_scoped_names(loop_source, "body").contains("index"))
  assert_true(require_scoped_names(loop_source, "after").contains("index"))
  assert_true(require_scoped_names(loop_source, "proof").contains("index"))
}

///|
test "try, lex, regex, and quantifier binders shadow nested expressions" {
  let catch_names = require_scoped_names(
    "try source() catch { error => target(error) }", "target",
  )
  assert_true(catch_names.contains("error"))
  let lex_names = require_scoped_names(
    "lexmatch source { (re\"a\" as piece) => target(piece) }", "target",
  )
  assert_true(lex_names.contains("piece"))
  let scan_names = require_scoped_names(
    "lexscan source { (re\"a\", before=head) => target(head) }", "target",
  )
  assert_true(scan_names.contains("head"))
  let regex_names = require_scoped_names(
    "if source =~ (re\"a\" as piece, before=head) { target(piece, head) }", "target",
  )
  assert_true(regex_names.contains("piece"))
  assert_true(regex_names.contains("head"))
  let quantified_names = require_scoped_names(
    "∀ item : Int, target(item)", "target",
  )
  assert_true(quantified_names.contains("item"))
}

///|
test "function bodies are sequences while nested blocks stay direct" {
  let plain : Array[ScopedExprMatchCandidate] = []
  collect_scoped_expr_match_candidate_roots(
    parse_scoped_structure("fn sample { first(); second() }"),
    plain,
  )
  guard plain is [{ candidate: Sequence(body), .. }, ..] else {
    fail("expected function body sequence")
  }
  assert_eq(body.length(), 2)
  assert_eq(
    direct_candidate_count(plain, kind => kind is @untyped_cst.Expr_Block),
    0,
  )
  let nested : Array[ScopedExprMatchCandidate] = []
  collect_scoped_expr_match_candidate_roots(
    parse_scoped_structure("fn sample { { first(); second() } }"),
    nested,
  )
  assert_eq(
    direct_candidate_count(nested, kind => kind is @untyped_cst.Expr_Block),
    1,
  )
  let mut nested_sequence_count = 0
  for item in nested {
    if item.candidate is Sequence(items) && items.length() == 2 {
      nested_sequence_count += 1
    }
  }
  assert_eq(nested_sequence_count, 1)
}

///|
test "continuation owners expose suffixes instead of header-only candidates" {
  let source = "fn sample { before(); let mut value = source(); body(value); defer cleanup(); after(); proof_let witness = fact(); finish(witness) }"
  let candidates : Array[ScopedExprMatchCandidate] = []
  collect_scoped_expr_match_candidate_roots(
    parse_scoped_structure(source),
    candidates,
  )
  assert_eq(
    direct_candidate_count(candidates, kind => kind is @untyped_cst.Expr_LetMut),
    0,
  )
  assert_eq(
    direct_candidate_count(candidates, kind => kind is @untyped_cst.Expr_Defer),
    0,
  )
  assert_eq(
    direct_candidate_count(candidates, kind => {
      kind is @untyped_cst.Expr_ProofLet
    }),
    1,
  )
  let mut let_suffix = false
  let mut defer_suffix = false
  for item in candidates {
    match item.candidate {
      Sequence([first, ..]) if first.kind is @untyped_cst.Expr_LetMut =>
        let_suffix = true
      Sequence([first, ..]) if first.kind is @untyped_cst.Expr_Defer =>
        defer_suffix = true
      _ => ()
    }
  }
  assert_true(let_suffix)
  assert_true(defer_suffix)
}

///|
test "sequence continuations apply bindings to later candidates" {
  let candidates : Array[ScopedExprMatchCandidate] = []
  collect_scoped_expr_match_candidate_roots(
    parse_scoped_structure("fn sample { let value = source(); target(value) }"),
    candidates,
  )
  let mut found = false
  for item in candidates {
    if item.candidate is Direct(expr) &&
      expr.kind is @untyped_cst.Expr_Apply &&
      raw_child(expr, "func").bind(normalized_expr_identifier_name) ==
      Some("target") {
      assert_true(item.shadowed_names.contains("value"))
      found = true
    }
  }
  assert_true(found)
}
