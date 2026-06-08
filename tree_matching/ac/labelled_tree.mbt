///|
struct LabelledTree[Loc] {
  node : LabelledTreeNode[Loc]
  loc : Loc?
  mut hits : Int
}

///|
let dummy_loc : String = ""

///|
priv enum LabelledTreeNode[Loc] {
  Node(label~ : String, children~ : ArrayView[LabelledTree[Loc]])
  MetaVar(String)
}

///|
pub impl[Loc] ToJson for LabelledTree[Loc] with fn to_json(self) -> Json {
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
pub fn[Loc] LabelledTree::node(
  loc : Loc,
  label : String,
  children : ArrayView[LabelledTree[Loc]],
) -> LabelledTree[Loc] {
  LabelledTree::{ node: Node(label~, children~), loc: Some(loc), hits: 0 }
}

///|
pub fn[Loc] LabelledTree::metavar(name : String) -> LabelledTree[Loc] {
  LabelledTree::{ node: MetaVar(name), loc: None, hits: 0 }
}

///|
fn[Loc] LabelledTree::arity(self : LabelledTree[Loc]) -> Int {
  match self.node {
    Node(children~, ..) => children.length()
    MetaVar(_) => 0
  }
}

///|
fn[Loc] LabelledTree::child(
  self : LabelledTree[Loc],
  index : Int,
) -> LabelledTree[Loc] {
  match self.node {
    Node(children~, ..) => children[index]
    MetaVar(_) => abort("impossible")
  }
}

///|
fn[Loc] LabelledTree::label(self : LabelledTree[Loc]) -> Symbol {
  match self.node {
    Node(label~, children~) => Label(label + children.length().to_string())
    MetaVar(_) => abort("impossible")
  }
}
