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
