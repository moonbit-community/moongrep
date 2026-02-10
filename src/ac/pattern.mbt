///|
enum Symbol {
  Label(String)
  Child(Int)
} derive(Eq, Hash, Show)

///|
type RTLPath = ImmutArray[Symbol] // Root to Leaf Path

///|
type TreePattern = ArrayView[(RTLPath, String?)]

///|
pub fn build_pattern_from_labelled_tree(t : LabelledTree) -> TreePattern {
  let paths = Array::new()
  fn go(acc : RTLPath, t : LabelledTree) -> Unit {
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

  go(@immutarray.new(), t)
  return paths
}
