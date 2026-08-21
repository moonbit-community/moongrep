///|
pub(all) struct AttributeInfo {
  qualifier : String?
  name : String
  raw_payload : String
  node : @untyped_cst.CstNode
}

///|
pub fn attribute_info(node : @untyped_cst.CstNode) -> AttributeInfo? {
  guard node.kind
    is (@untyped_cst.Attribute_Simple | @untyped_cst.Attribute_Qualified) else {
    return None
  }
  let qualifier = raw_child(node, "qualifier").bind(string_payload)
  let name = raw_child(node, "name").bind(string_payload).unwrap_or("")
  let raw_payload = raw_child(node, "raw_payload")
    .bind(string_payload)
    .unwrap_or("")
  Some({ qualifier, name, raw_payload, node })
}

///|
pub fn attributes(node : @untyped_cst.CstNode) -> Array[AttributeInfo] {
  let result : Array[AttributeInfo] = []
  for entry in node.children {
    if entry.1.kind is @untyped_cst.Syntax_Attribute {
      for child in entry.1.children {
        if attribute_info(child.1) is Some(info) {
          result.push(info)
        }
      }
    }
  }
  result
}

///|
pub fn has_bare_attribute(
  node : @untyped_cst.CstNode,
  qualifier : String,
  name : String,
) -> Bool {
  for attribute in attributes(node) {
    if attribute.qualifier == Some(qualifier) &&
      attribute.name == name &&
      attribute.raw_payload == "" {
      return true
    }
  }
  false
}

///|
pub fn attribute_payload(
  node : @untyped_cst.CstNode,
  qualifier : String,
  name : String,
) -> String? {
  for attribute in attributes(node) {
    if attribute.qualifier == Some(qualifier) && attribute.name == name {
      return Some(attribute.raw_payload)
    }
  }
  None
}
