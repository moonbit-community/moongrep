///|
pub suberror AstTraverseError {
  InvalidNode(Json)
  InvalidChilds(Json)
}

///|
pub fn traverse_ast_json_repr(
  ast : Json,
  callback : (Json) -> Bool raise,
) -> Unit raise {
  match ast {
    Object({ "kind": _, "loc": _, "children": children, .. } as object) =>
      if object.length() == 3 {
        if !callback(ast) {
          return
        }
        match children {
          Object(children) =>
            for _, subtree in children.iter2() {
              traverse_ast_json_repr(subtree, callback)
            }
          Array(children) =>
            for subtree in children {
              traverse_ast_json_repr(subtree, callback)
            }
          children => raise InvalidChilds(children)
        }
      } else {
        raise InvalidNode(ast)
      }
    _ => ()
  }
}

///|
pub fn traverse_top_impls(
  name~ : String,
  source : String,
  callback : (Json) -> Bool raise,
) -> Unit raise {
  @basic.show_loc.val = Json
  let (program, reports) = @lexer.tokens_from_string(
      source,
      comment=true,
      name~,
    ).tokens
    |> @handrolled_parser.parse()
  if reports is [err, ..] {
    fail(err.to_json().stringify(indent=2))
  } else {
    for impl_ in program.iter().map(impl_ => impl_.json_repr()) {
      traverse_ast_json_repr(impl_, callback)
    }
  }
}
