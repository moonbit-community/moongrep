///|
test "BoundValue variants support pattern matching" {
  let parsed = @untyped_cst.parse_structure("let x = 1", name="test.mbt")
  let node = parsed.root()
  let values : Array[@model.BoundValue] = [Single(node), Multiple([node])]
  guard values is [Single(_), Multiple([_])] else {
    fail("expected Single and Multiple captures")
  }
}
