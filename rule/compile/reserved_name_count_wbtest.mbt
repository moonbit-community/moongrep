///|
test "reserved name count counts supported names in node expressions" {
  let parsed = @untyped_cst.parse_expression(
    "(__TARGET__, wrap(__TARGET__), { field: __TARGET__ })",
    name="test",
  )
  assert_eq(
    count_supported_name_in_node(
      @cst.expression_root(parsed.root()),
      "__TARGET__",
    ),
    3,
  )
}

///|
test "reserved name count counts expression identifiers once" {
  let parsed = @untyped_cst.parse_expression("target", name="test")
  assert_eq(
    count_supported_name_in_node(@cst.expression_root(parsed.root()), "target"),
    1,
  )
}
