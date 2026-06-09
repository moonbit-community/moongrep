///|
/// Shorthand for leaf subjects used throughout the behavior tests.
fn leaf(loc : Int, label : String) -> @subpatterns.SubjectTree[Int] {
  @subpatterns.SubjectTree::node(loc, label, [])
}

///|
/// Shorthand for non-leaf subjects.
fn node(
  loc : Int,
  label : String,
  children : ArrayView[@subpatterns.SubjectTree[Int]],
) -> @subpatterns.SubjectTree[Int] {
  @subpatterns.SubjectTree::node(loc, label, children)
}

///|
/// Shorthand for labelled pattern nodes.
fn pnode(
  label : String,
  children : ArrayView[@subpatterns.Pattern],
) -> @subpatterns.Pattern {
  @subpatterns.Pattern::node(label, children)
}

///|
/// Shorthand for the distinguished wildcard `v`.
fn wildcard() -> @subpatterns.Pattern {
  @subpatterns.Pattern::wildcard()
}

///|
/// Shorthand for a named wildcard capture.
fn capture(name : String) -> @subpatterns.Pattern {
  @subpatterns.Pattern::capture(name)
}

///|
/// Reduce matches to the fields relevant for ordering assertions.
fn pair_locs(matches : Array[@subpatterns.Match[Int]]) -> Array[(Int, Int)] {
  matches.map(m => (m.pattern_index, m.loc))
}

///|
/// Covers the paper-style bottom-up formula with two patterns that match
/// different subject nodes. The expected order is subject preorder, even though
/// match sets are computed bottom-up.
test "paper style subpatterns match in subject preorder" {
  let patterns = [
    pnode("a", [pnode("a", [wildcard(), wildcard()]), pnode("b", [])]),
    pnode("a", [pnode("b", []), wildcard()]),
  ]
  let subject = node(0, "root", [
    node(1, "a", [node(2, "a", [leaf(3, "x"), leaf(4, "y")]), leaf(5, "b")]),
    node(6, "a", [leaf(7, "b"), leaf(8, "c")]),
  ])
  let matches = @subpatterns.Matcher::compile(patterns).find_all(subject)
  debug_inspect(
    pair_locs(matches),
    content=(
      #|[(0, 1), (1, 6)]
    ),
  )
}

///|
/// Demonstrates that this package is not restricted to simple pattern forests:
/// both overlapping patterns can match the same `a(b, b)` root.
test "non simple forest patterns can both match the same node" {
  let patterns = [
    pnode("a", [pnode("b", []), capture("x")]),
    pnode("a", [capture("y"), pnode("b", [])]),
  ]
  let subject = node(0, "a", [leaf(1, "b"), leaf(2, "b")])
  let matches = @subpatterns.Matcher::compile(patterns).find_all(subject)
  assert_eq(matches.length(), 2)
  debug_inspect(
    [
      (matches[0].pattern_index, matches[0].loc, matches[0].captures["x"]),
      (matches[1].pattern_index, matches[1].loc, matches[1].captures["y"]),
    ],
    content=(
      #|[(0, 0, [2]), (1, 0, [1])]
    ),
  )
}

///|
/// Checks ast-grep-like captures: a capture records the subject location at the
/// capture occurrence path while the complete match location remains the root.
test "named captures return subject locations for each match" {
  let pattern = pnode("call", [
    capture("callee"),
    pnode("arg", [capture("value")]),
  ])
  let subject = node(0, "root", [
    node(10, "call", [leaf(11, "f"), node(12, "arg", [leaf(13, "x")])]),
    node(20, "call", [
      leaf(21, "g"),
      node(22, "arg", [node(23, "pair", [leaf(24, "y"), leaf(25, "z")])]),
    ]),
  ])
  let matches = @subpatterns.Matcher::compile([pattern]).find_all(subject)
  assert_eq(matches.length(), 2)
  debug_inspect(
    [
      (
        matches[0].pattern_index,
        matches[0].loc,
        matches[0].captures["callee"],
        matches[0].captures["value"],
      ),
      (
        matches[1].pattern_index,
        matches[1].loc,
        matches[1].captures["callee"],
        matches[1].captures["value"],
      ),
    ],
    content=(
      #|[(0, 10, [11], [13]), (0, 20, [21], [23])]
    ),
  )
}

///|
/// Locks in the first-version repeated-name semantics. Repeated captures are
/// independent wildcard occurrences; the matcher returns both locations and
/// does not compare their captured subtrees.
test "repeated capture names are independent wildcards" {
  let pattern = pnode("pair", [capture("x"), capture("x")])
  let subject = node(0, "pair", [leaf(1, "a"), leaf(2, "b")])
  let matches = @subpatterns.Matcher::compile([pattern]).find_all(subject)
  assert_eq(matches.length(), 1)
  debug_inspect(
    matches[0].captures["x"],
    content=(
      #|[1, 2]
    ),
  )
}

///|
/// Covers boundary behavior that is easy to regress when changing bitset
/// initialization: empty pattern forests, top-level `v`, top-level captures,
/// and unknown labelled symbols.
test "edge cases for empty patterns wildcards captures and unknown labels" {
  let subject = node(0, "root", [leaf(1, "a"), leaf(2, "b")])
  assert_eq(@subpatterns.Matcher::compile([]).find_all(subject).length(), 0)

  let top_matches = @subpatterns.Matcher::compile([wildcard(), capture("whole")]).find_all(
    subject,
  )
  assert_eq(top_matches.length(), 6)
  debug_inspect(
    top_matches.map(m => {
      (m.pattern_index, m.loc, m.captures.get_or_default("whole", []))
    }),
    content=(
      #|[
      #|  (0, 0, []),
      #|  (1, 0, [0]),
      #|  (0, 1, []),
      #|  (1, 1, [1]),
      #|  (0, 2, []),
      #|  (1, 2, [2]),
      #|]
    ),
  )

  let unknown = @subpatterns.Matcher::compile([pnode("known", [])])
  assert_eq(unknown.find_all(leaf(3, "other")).length(), 0)
}
