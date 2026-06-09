///|
/// A labelled subject tree with a caller supplied location at every node.
///
/// The matcher never interprets `Loc`: it only copies locations into
/// `Match::loc` and capture arrays. This keeps the package independent from
/// any concrete AST or source span representation.
struct SubjectTree[Loc] {
  loc : Loc
  label : String
  children : Array[SubjectTree[Loc]]
}

///|
/// Build a subject node.
///
/// As with `Pattern::node`, labels are matched together with the number of
/// children. The children are copied from the view to make constructed subject
/// trees stable while matching.
pub fn[Loc] SubjectTree::node(
  loc : Loc,
  label : String,
  children : ArrayView[SubjectTree[Loc]],
) -> SubjectTree[Loc] {
  { loc, label, children: children.to_owned() }
}
