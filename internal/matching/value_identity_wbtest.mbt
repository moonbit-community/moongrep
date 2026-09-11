///|
test "interned identities agree with atomic capture equality" {
  let values : Array[BoundValue] = []
  for
    source in [
      "name", " other ", "name", "Ctor", "Type::Ctor", "()", "_", "{ () }", "f(name)",
      " f( name ) ", "f(other)", "42", "true", "false",
    ] {
    let parsed = @untyped_cst.parse_expression(source, name="identity")
    assert_true(parsed.diagnostics_view().is_empty())
    let node = @cst.expression_root(parsed.root())
    values.push(Single(node))
    values.push(Multiple([node]))
    if @cst.name_node(node) is Some(name) {
      values.push(Single(name))
    }
  }
  values.push(Multiple([]))
  let interner = ValueInterner::new()
  for left in values {
    for right in values {
      assert_eq(
        interner.intern(left) == interner.intern(right),
        bound_value_equal(left, right),
      )
    }
  }
}
