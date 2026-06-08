///|
enum Symbol {
  Label(String)
  Child(Int)
} derive(Eq, Hash, Debug)

///|
type RTLPath = ImmutArray[Symbol] // Root to Leaf Path

///|
type TreePattern = ArrayView[(RTLPath, String?)]

///|
pub fn[Loc] build_pattern_from_labelled_tree(
  t : LabelledTree[Loc],
) -> TreePattern {
  let paths = Array::new()
  fn go(acc : RTLPath, t : LabelledTree[Loc]) -> Unit {
    match t.node {
      Node(label~, children=[]) =>
        paths.push((acc.push(Label(label + "0")), None))
      Node(label~, children~) =>
        children.eachi((i, t) => {
          go(
            acc
            .push(Label(label + children.length().to_string()))
            .push(Child(i)),
            t,
          )
        })
      MetaVar(name) => paths.push((acc, Some(name)))
    }
  }

  go(@immutvector.new(), t)
  return paths
}
