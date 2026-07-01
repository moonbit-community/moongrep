///|
pub(all) struct Node {
  kind : String
  loc : @basic.Location
  children : NodeChildren
}

///|
pub(all) enum NodeChildren {
  AstFields(FixedArray[(String, Value)])
  AstItems(FixedArray[Value])
}

///|
pub(all) enum Value {
  AstNode(Node)
  AstNull
  AstBool(Bool)
  AstString(String)
  AstNumber(Double, repr~ : String?)
}

///|
pub fn Node::to_json(self : Node) -> Json {
  if self.kind == "__LocationJson" {
    self.loc.to_json()
  } else {
    match self.children {
      AstFields(fields) => fields_node_to_json(self.kind, self.loc, fields)
      AstItems(items) => items_node_to_json(self.kind, self.loc, items)
    }
  }
}

///|
fn fields_node_to_json(
  kind : String,
  loc : @basic.Location,
  fields : FixedArray[(String, Value)],
) -> Json {
  let children : Map[String, Json] = {}
  fields.each(fn(field) {
    let (name, value) = field
    children[name] = value.to_json()
  })
  { "kind": kind, "loc": loc, "children": children }
}

///|
fn items_node_to_json(
  kind : String,
  loc : @basic.Location,
  items : FixedArray[Value],
) -> Json {
  let children : Array[Json] = []
  items.each(fn(item) { children.push(item.to_json()) })
  { "kind": kind, "loc": loc, "children": children }
}

///|
pub fn Value::to_json(self : Value) -> Json {
  match self {
    AstNode(node) => node.to_json()
    AstNull => Json::null()
    AstBool(value) => Json::boolean(value)
    AstString(value) => Json::string(value)
    AstNumber(value, repr~) => Json::number(value, repr?)
  }
}

///|
pub impl ToJson for Node with fn to_json(self) {
  Node::to_json(self)
}

///|
pub impl ToJson for Value with fn to_json(self) {
  Value::to_json(self)
}
