///|
struct LabelledTree {
  node : LabelledTreeNode
  loc : String
  mut hits : Int
}

///|
let dummy_loc : String = ""

///|
priv enum LabelledTreeNode {
  Node(label~ : String, children~ : ArrayView[LabelledTree])
  MetaVar(String)
}

///|
pub impl ToJson for LabelledTree with to_json(self) -> Json {
  match self.node {
    MetaVar(name) => Json::string("$\{name}")
    Node(label~, children~) =>
      if children.length() == 0 {
        Json::string(label)
      } else {
        [label, children]
      }
  }
}

///|
test {
  let tree = LabelledTree::node(dummy_loc, "f", [
    LabelledTree::node(dummy_loc, "g", [LabelledTree::node(dummy_loc, "x", [])]),
    LabelledTree::metavar("_"),
  ])
  json_inspect(tree, content=["f", [["g", ["x"]], "$_"]])
}

///|
fn LabelledTree::node(
  loc : String,
  label : String,
  children : ArrayView[LabelledTree],
) -> LabelledTree {
  LabelledTree::{ node: Node(label~, children~), loc, hits: 0 }
}

///|
fn LabelledTree::metavar(name : String) -> LabelledTree {
  LabelledTree::{
    node: MetaVar(name),
    loc: "meta variable no location",
    hits: 0,
  }
}

///|
fn LabelledTree::arity(self : LabelledTree) -> Int {
  match self.node {
    Node(children~, ..) => children.length()
    MetaVar(_) => 0
  }
}

///|
fn LabelledTree::child(self : LabelledTree, index : Int) -> LabelledTree {
  match self.node {
    Node(children~, ..) => children[index]
    MetaVar(_) => abort("impossible")
  }
}

///|
fn LabelledTree::label(self : LabelledTree) -> Symbol {
  match self.node {
    Node(label~, children~) => Label(label + children.length().to_string())
    MetaVar(_) => abort("impossible")
  }
}
