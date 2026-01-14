///|
pub suberror AstTraverseError {
  InvalidNode(Json)
  InvalidChilds(Json)
}

///|
pub fn traverse_ast_json_repr(
  ast : Json,
  callback : (Json) -> Unit raise?,
) -> Unit raise {
  match ast {
    Object({ "kind": _, "loc": _, "childs": childs, .. } as object) =>
      if object.length() == 3 {
        match childs {
          Object(childs) =>
            for _, subtree in childs.iter2() {
              traverse_ast_json_repr(subtree, callback)
            }
          Array(childs) =>
            for subtree in childs {
              traverse_ast_json_repr(subtree, callback)
            }
          childs => raise InvalidChilds(childs)
        }
        callback(ast)
      } else {
        raise InvalidNode(ast)
      }
    _ => ()
  }
}
