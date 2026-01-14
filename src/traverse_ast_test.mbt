///|
fn identify_c99style_for_loop(
  ast : Json,
  locations : Array[Json],
) -> Unit raise {
  // pattern:
  // for _COUNT = 0; _COUNT < n; _COUNT = _COUNT + 1 {
  //   _BODY
  // }
  traverse_ast_json_repr(ast, ast => match ast {
    {
      "kind": "Expr::For",
      ..
    } => {
      ...
    }
    _ => ()
  })
}

///|
test {
  let program =
    #|fn foo() -> Unit {
    #| for i in 0..<10 {
    #|   println(i)
    #| }
    #| let arr = [9, 4, 8, 10]
    #| for i = 0; i < arr.length(); i = i + 1 {
    #|   println(arr[i])
    #| }
    #|}
  let (program, _) = @lexer.tokens_from_string(
      program,
      comment=true,
      name="function foo",
    ).tokens
    |> @handrolled_parser.parse()
  let program = match program {
    More(p, tail=Empty) => p.json_repr()
    _ => fail("parse failed")
  }
  let locations = []
  traverse_ast_json_repr(program, ast => identify_c99style_for_loop(
    ast, locations,
  ))
  @json.inspect(locations, content=[])
}
