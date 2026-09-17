///|
test "query package can be called from another module" {
  let query = @query.ExprQuery::ExprQuery("println($(value:exp))")
  let source =
    #|fn main {
    #|  println("first")
    #|  println(compute())
    #|  ignore("not a match")
    #|}
    #|
  let captures = query.captures(source_name="sample.mbt", source)
  assert_eq(captures.length(), 2)
  for capture in captures {
    assert_true(capture.contains("value"))
  }
}
