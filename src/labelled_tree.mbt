///|
pub struct LabelledTree {
  node : LabelledTreeNode
  loc : Location
  mut hits : Int
}

///|
let dummy_loc : Location = Location::{
  start: { fname: "", lnum: -1, bol: -1, cnum: -1 },
  end: { fname: "", lnum: -1, bol: -1, cnum: -1 },
}

///|
pub enum LabelledTreeNode {
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
    LabelledTree::wildcard(dummy_loc),
  ])
  @json.inspect(tree, content=["f", [["g", ["x"]], "$_"]])
}

///|
fn LabelledTree::node(
  loc : Location,
  label : String,
  childs : ArrayView[LabelledTree],
) -> LabelledTree {
  LabelledTree::{ node: Node(label~, childs~), loc, hits: 0 }
}

///|
fn LabelledTree::wildcard(loc : Location) -> LabelledTree {
  LabelledTree::{ node: WildCard, loc, hits: 0 }
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
