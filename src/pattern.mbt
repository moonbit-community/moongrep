///|
enum Symbol {
  Label(String)
  Child(Int)
} derive(Eq, Hash, Show)

///|
type RTLPath = ImmutArray[Symbol] // Root to Leaf Path

///|
type TreePattern = ArrayView[RTLPath]

///|
pub fn build_pattern_from_labelled_tree(t : LabelledTree) -> TreePattern {
  let paths = Array::new()
  fn go(acc : RTLPath, t : LabelledTree) -> Unit {
    match t.node {
      Node(label~, childs=[]) => paths.push(acc.push(Label(label + "0")))
      Node(label~, childs~) =>
        childs.eachi((i, t) => go(
          acc.push(Label(label + childs.length().to_string())).push(Child(i)),
          t,
        ))
      WildCard => paths.push(acc)
    }
  }

  go(@immut/array.new(), t)
  return paths
}
