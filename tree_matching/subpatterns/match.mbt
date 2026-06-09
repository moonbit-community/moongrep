///|
/// One complete pattern occurrence found in a subject tree.
///
/// `pattern_index` is the zero-based index in the array passed to
/// `Matcher::compile`. `loc` is the location of the subject node where the
/// complete pattern matched. `captures` maps each capture name to every subject
/// location collected for that name in the matched pattern occurrence.
pub(all) struct Match[Loc] {
  pattern_index : Int
  loc : Loc
  captures : Map[String, Array[Loc]]
} derive(Eq, Debug)
