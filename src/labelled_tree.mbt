///|
struct LabelledTree {
  node : LabelledTreeNode
  loc : Json
  mut hits : Int
}

///|
let dummy_loc : Json = Json::null()

///|
priv enum LabelledTreeNode {
  Node(label~ : String, childs~ : ArrayView[LabelledTree])
  WildCard
}

///|
pub impl ToJson for LabelledTree with to_json(self) -> Json {
  match self.node {
    WildCard => Json::string("$_")
    Node(label~, childs~) =>
      if childs.length() == 0 {
        Json::string(label)
      } else {
        [label, childs]
      }
  }
}

///|
test {
  let tree = LabelledTree::node(dummy_loc, "f", [
    LabelledTree::node(dummy_loc, "g", [LabelledTree::node(dummy_loc, "x", [])]),
    LabelledTree::wildcard(),
  ])
  @json.inspect(tree, content=["f", [["g", ["x"]], "$_"]])
}

///|
fn LabelledTree::node(
  loc : Json,
  label : String,
  childs : ArrayView[LabelledTree],
) -> LabelledTree {
  LabelledTree::{ node: Node(label~, childs~), loc, hits: 0 }
}

///|
fn LabelledTree::wildcard() -> LabelledTree {
  LabelledTree::{ node: WildCard, loc: Json::null(), hits: 0 }
}

///|
fn LabelledTree::arity(self : LabelledTree) -> Int {
  match self.node {
    Node(childs~, ..) => childs.length()
    WildCard => 0
  }
}

///|
fn LabelledTree::child(self : LabelledTree, index : Int) -> LabelledTree {
  match self.node {
    Node(childs~, ..) => childs[index]
    WildCard => abort("impossible")
  }
}

///|
fn LabelledTree::label(self : LabelledTree) -> Symbol {
  match self.node {
    Node(label~, childs~) => Label(label + childs.length().to_string())
    WildCard => abort("impossible")
  }
}
