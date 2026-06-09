# Subpatterns

This package implements a generic bottom-up tree matcher for a fixed forest of
patterns. It is intentionally independent from `tree_matching/ac` and from any
specific AST representation: callers provide labelled `SubjectTree` values with
their own location type, and the matcher returns those locations unchanged.

## Public API

- `Pattern::node(label, children)` builds a labelled pattern node.
- `Pattern::wildcard()` builds the anonymous wildcard `v`.
- `Pattern::capture(name)` builds a named wildcard and records the matched
  subject location under `name`.
- `SubjectTree::node(loc, label, children)` builds a subject node.
- `Matcher::compile(patterns)` preprocesses a pattern forest once.
- `Matcher::find_all(subject)` returns every complete pattern occurrence.

`Match::pattern_index` is the zero-based index in the array passed to
`Matcher::compile`. `Match::loc` is the location of the subject node where the
complete pattern matched. `Match::captures` maps capture names to all captured
locations for that match.

## Matching Semantics

Labels are matched together with arity, so a nullary `a` and a unary `a` are
different symbols. Wildcards and captures match every subject subtree. Repeated
capture names are treated as independent wildcard occurrences; all locations are
returned and no structural equality constraint is enforced.

Matches are returned in subject preorder. If several complete patterns match the
same subject node, they are emitted by increasing compiled root subpattern id;
patterns sharing that root id keep increasing `pattern_index` order.

## Implementation Notes

The implementation follows the Section 10 bit-string formulation from
`tree_matching.md`. Pattern subtree id `0` is reserved for the distinguished
wildcard `v`. Every labelled pattern subtree is deduplicated structurally and
receives a positive id. A match set is represented by `Bitset`, where a set bit
means the corresponding subpattern matches the current subject subtree.

Compilation builds three tables:

- `U_by_symbol`: for each known `(label, arity)`, the set of possible labelled
  subpattern roots for that symbol, plus `v`. Unknown subject symbols synthesize
  `{v}` during matching.
- `father_by_pos_child`: for each child position and child subpattern id, the
  set of parent subpatterns that can be inferred.
- `complete_patterns_by_root_id` and `capture_paths_by_pattern`: metadata used
  to turn bit hits into user-facing `Match` values.

Matching computes children first, then evaluates:

```text
Match(a(t0..t{q-1})) =
  (U_a
   & Father_0(Match(t0))
   & ...
   & Father_{q-1}(Match(t{q-1})))
  | {v}
```

`Father_i` is memoized per traversal by `(i, child_match_set)` because different
subject nodes often produce identical child match sets.
