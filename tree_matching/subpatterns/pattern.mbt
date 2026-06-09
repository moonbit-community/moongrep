///|
/// A tree pattern accepted by `Matcher`.
///
/// `Pattern` is intentionally abstract. Callers build values with the
/// constructors below, while the matcher compiles them into deduplicated
/// internal subpattern ids.
struct Pattern {
  kind : PatternKind
}

///|
/// Internal representation of a user pattern.
///
/// `Wildcard` is the paper variable `v` and matches every subject subtree.
/// `Capture(name)` has the same matching power as `Wildcard`, but records the
/// subject location reached by its occurrence path. `Node(label, children)`
/// is the only form that becomes a numbered non-v subpattern during compile.
priv enum PatternKind {
  Wildcard
  Capture(String)
  Node(String, Array[Pattern])
}

///|
/// Build an anonymous wildcard pattern.
///
/// A wildcard matches any subject subtree and does not add entries to the
/// capture map. Top-level wildcards are valid complete patterns and therefore
/// match every node in the subject tree.
pub fn Pattern::wildcard() -> Pattern {
  { kind: Wildcard }
}

///|
/// Build a named capture pattern.
///
/// Captures match any subject subtree. Their locations are returned under
/// `name` in `Match::captures`. Multiple occurrences of the same name are
/// deliberately treated as independent wildcards; all locations are appended in
/// pattern preorder, and no structural equality constraint is enforced.
pub fn Pattern::capture(name : String) -> Pattern {
  { kind: Capture(name) }
}

///|
/// Build a labelled tree pattern.
///
/// Labels are compared together with arity, so `node("a", [])` and
/// `node("a", [wildcard()])` are different symbols. The children are copied
/// from the view so later caller-side array mutation cannot change a compiled
/// or pending pattern.
pub fn Pattern::node(label : String, children : ArrayView[Pattern]) -> Pattern {
  { kind: Node(label, children.to_owned()) }
}
