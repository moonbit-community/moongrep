///|
pub fn LabelledTree::from_json_repr(
  ast : Json,
) -> LabelledTree raise MoonGrepError {
  match ast {
    Object({ "kind": String("MetaVariable"), "name": String(metavar_name), .. }) =>
      LabelledTree::metavar(metavar_name)
    Object(
      { "kind": String(kind), "loc": String(loc), "children": children, .. } as node
    ) =>
      if node.length() == 3 {
        let original_children = match children {
          Object(children) => children.iter().collect()
          Array(children) =>
            children
            .iter2()
            .iter()
            .map(pair => (pair.0.to_string(radix=10), pair.1))
            .collect()
          _ =>
            raise AstConvertError(
              children,
              message="weird children in AST Node",
            )
        }
        let children = []
        let prefix_buf = StringBuilder::new()
        prefix_buf.write_string(kind)
        prefix_buf.write_char('(')
        for pair in original_children {
          match pair.1 {
            // TODO: remove String(_) && Number(_), only allow children: { "value": (String(_) | Number(_)) }
            Null | True | False | String(_) | Number(_) as json => {
              prefix_buf.write_string(pair.0)
              prefix_buf.write_char('=')
              prefix_buf.write_string(json.stringify())
              prefix_buf.write_char(',')
            }
            otherwise => children.push(LabelledTree::from_json_repr(otherwise))
          }
        }
        prefix_buf.write_char(')')
        LabelledTree::node(loc, prefix_buf.to_string(), children)
      } else {
        raise AstConvertError(ast, message="AST Node but have extra field")
      }
    otherwise => raise AstConvertError(otherwise, message="catch all case")
  }
}
