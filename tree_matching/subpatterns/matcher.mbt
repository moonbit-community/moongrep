///|
/// Subject and pattern node symbol.
///
/// The arity is part of the key so labels do not need to be encoded with
/// string concatenation. This prevents collisions such as `"a" + "10"` versus
/// `"a1" + "0"` and mirrors the paper's ranked alphabet.
priv struct NodeSymbol {
  label : String
  arity : Int
} derive(Eq, Hash)

///|
/// Structural key used to deduplicate non-wildcard pattern subtrees.
///
/// Children are already registered subpattern ids. Because child ids are
/// assigned from structural keys too, this key represents the whole subtree.
priv struct SubpatternKey {
  label : String
  children : Array[Int]
} derive(Eq, Hash)

///|
/// Numbered non-v pattern subtree.
///
/// The array contains child subpattern ids, where id `0` is `v`. A `Subpattern`
/// is stored at index `id - 1` in `CompileState::subpatterns`.
priv struct Subpattern {
  symbol : NodeSymbol
  children : Array[Int]
}

///|
/// Path from a complete pattern root to one capture occurrence.
///
/// Paths are stored as child indexes. During result construction we replay the
/// path against the matched subject node to recover the captured location.
priv struct CapturePath {
  name : String
  path : Array[Int]
}

///|
/// Memo key for `Father_i(M)`.
///
/// `pos` identifies `i`; `bits` is a copy of the child match set. The copy is
/// required because `Bitset` is mutable and map keys must remain stable.
priv struct FatherMemoKey {
  pos : Int
  bits : Array[UInt64]
} derive(Eq, Hash)

///|
/// Mutable state used only while compiling one matcher.
priv struct CompileState {
  key_to_id : Map[SubpatternKey, Int]
  subpatterns : Array[Subpattern]
}

///|
/// Result of matching one subject subtree.
///
/// `bits` is the subtree's bottom-up match set. `matches` contains complete
/// pattern matches in subject preorder for this subtree.
priv struct MatchState[Loc] {
  bits : Bitset
  matches : Array[Match[Loc]]
}

///|
/// Compiled bottom-up matcher for a fixed pattern forest.
///
/// The implementation follows the Section 10 bit-string formulation:
///
///   Match(a(t0..t{q-1})) =
///     (U_a & Father_0(Match(t0)) & ... & Father_{q-1}(Match(t{q-1}))) | {v}
///
/// Arrays are indexed by subpattern id. Id `0` is the distinguished wildcard
/// `v`; every other id is a unique non-wildcard subtree from the pattern
/// forest.
struct Matcher {
  // Number of UInt64 words in every bitset.
  word_count : Int
  // U_by_symbol[s] contains all subpattern roots with symbol s, plus v.
  u_by_symbol : Map[NodeSymbol, Bitset]
  // father_by_pos_child[i][child_id] contains every parent subpattern whose
  // i-th child is child_id. Unions over a child match set compute Father_i(M).
  father_by_pos_child : Array[Map[Int, Bitset]]
  // complete_patterns_by_root_id[root_id] gives all user pattern indexes whose
  // compiled root is root_id. Multiple top-level wildcards/captures share id 0.
  complete_patterns_by_root_id : Array[Array[Int]]
  // Capture paths are kept per user pattern, not per deduplicated subtree,
  // because two patterns can share structure but use different capture names.
  capture_paths_by_pattern : Array[Array[CapturePath]]
}

///|
/// Compile a pattern forest into reusable bottom-up tables.
///
/// Compilation performs three independent precomputations:
///
/// 1. Deduplicate non-wildcard subtrees and assign compact ids.
/// 2. Build `U_by_symbol` and per-position child-to-parent tables for
///    `Father_i`.
/// 3. Record complete-pattern root ids and capture occurrence paths.
///
/// Empty pattern lists are valid and produce a matcher that returns no matches.
pub fn Matcher::compile(patterns : ArrayView[Pattern]) -> Matcher {
  let state = CompileState::{ key_to_id: Map::default(), subpatterns: [] }
  let root_ids = []
  let capture_paths_by_pattern = []
  for pattern in patterns {
    root_ids.push(state.register(pattern))
    let captures = []
    collect_capture_paths(pattern, [], captures)
    capture_paths_by_pattern.push(captures)
  }

  let subpattern_count = state.subpatterns.length() + 1
  let word_count = bitset_word_count(subpattern_count)
  let u_by_symbol = Map::default()
  let father_by_pos_child = []
  let complete_patterns_by_root_id = Array::makei(subpattern_count, _ => [])

  // Populate U_a and the single-child contribution tables for Father_i.
  // Wildcards and captures never appear in `subpatterns`; they are represented
  // by child id 0 wherever they occur.
  for id in 1..<subpattern_count {
    let subpattern = state.subpatterns[id - 1]
    let symbol = subpattern.symbol
    u_by_symbol.get_or_init(symbol, () => Bitset::new(word_count)).set(id)
    subpattern.children.eachi((pos, child_id) => {
      while father_by_pos_child.length() <= pos {
        father_by_pos_child.push(Map::default())
      }
      let by_child = father_by_pos_child[pos]
      by_child.get_or_init(child_id, () => Bitset::new(word_count)).set(id)
    })
  }

  // Known U_a entries include v; unknown subject symbols get {v} in u_for.
  u_by_symbol.each((_symbol, bits) => bits.set(0))
  root_ids.eachi((pattern_index, root_id) => {
    complete_patterns_by_root_id[root_id].push(pattern_index)
  })

  {
    word_count,
    u_by_symbol,
    father_by_pos_child,
    complete_patterns_by_root_id,
    capture_paths_by_pattern,
  }
}

///|
/// Register a pattern subtree and return its subpattern id.
///
/// Wildcards and captures both return id `0`. Only labelled nodes are
/// deduplicated and assigned positive ids.
fn CompileState::register(self : CompileState, pattern : Pattern) -> Int {
  match pattern.kind {
    Wildcard | Capture(_) => 0
    Node(label, children) => {
      let child_ids = children.map(child => self.register(child))
      let key = SubpatternKey::{ label, children: child_ids.copy() }
      match self.key_to_id.get(key) {
        Some(id) => id
        None => {
          let id = self.subpatterns.length() + 1
          self.key_to_id[key] = id
          self.subpatterns.push({
            symbol: { label, arity: child_ids.length() },
            children: child_ids,
          })
          id
        }
      }
    }
  }
}

///|
/// Collect capture occurrence paths for a complete user pattern.
///
/// Capture paths are separate from structural subpattern ids so captures remain
/// visible even when the structural matcher treats them as plain `v`.
fn collect_capture_paths(
  pattern : Pattern,
  path : Array[Int],
  out : Array[CapturePath],
) -> Unit {
  match pattern.kind {
    Wildcard => ()
    Capture(name) => out.push({ name, path: path.copy() })
    Node(_, children) =>
      children.eachi((pos, child) => {
        let child_path = path.copy()
        child_path.push(pos)
        collect_capture_paths(child, child_path, out)
      })
  }
}

///|
/// Find every compiled pattern occurrence in `subject`.
///
/// The returned matches are ordered by subject preorder. If multiple patterns
/// match the same subject node, they are emitted by increasing compiled root
/// subpattern id; patterns sharing that root id keep increasing `pattern_index`
/// order.
pub fn[Loc] Matcher::find_all(
  self : Matcher,
  subject : SubjectTree[Loc],
) -> Array[Match[Loc]] {
  let father_cache = Map::default()
  self.match_subject(subject, father_cache).matches
}

///|
/// Compute the match set and complete matches for one subject subtree.
///
/// Recursion first computes children, giving the bottom-up order required by
/// the formula. The output array is assembled as root matches followed by child
/// results, which produces preorder result ordering while keeping the match-set
/// computation bottom-up.
fn[Loc] Matcher::match_subject(
  self : Matcher,
  subject : SubjectTree[Loc],
  father_cache : Map[FatherMemoKey, Bitset],
) -> MatchState[Loc] {
  let child_states = subject.children.map(child => {
    self.match_subject(child, father_cache)
  })
  let bits = self.u_for(subject.label, subject.children.length()).copy()
  // Intersect U_a with every Father_i(M(child_i)).
  for pos in 0..<child_states.length() {
    let father = self.father_for(pos, child_states[pos].bits, father_cache)
    bits.intersect_in_place(father)
  }
  // v matches every subject subtree, including unknown labels and arities.
  bits.set(0)

  let matches = []
  self.push_matches_at(subject, bits, matches)
  for child_state in child_states {
    matches.append(child_state.matches)
  }
  { bits, matches }
}

///|
/// Return `U_a` for a subject symbol.
///
/// Unknown symbols still receive `{v}` so wildcard and capture patterns match
/// them, but no complete labelled pattern can be reported.
fn Matcher::u_for(self : Matcher, label : String, arity : Int) -> Bitset {
  let symbol = NodeSymbol::{ label, arity }
  match self.u_by_symbol.get(symbol) {
    Some(bits) => bits
    None => {
      let bits = Bitset::new(self.word_count)
      bits.set(0)
      bits
    }
  }
}

///|
/// Compute `Father_pos(child_bits)`, memoized per traversal.
///
/// The paper notes that `Father_i(M1 union M2)` is the union of the individual
/// father sets. This implementation stores the contribution for each child id
/// and unions only the ids present in the child bitset. The final result is
/// cached because many subject nodes often have identical child match sets.
fn Matcher::father_for(
  self : Matcher,
  pos : Int,
  child_bits : Bitset,
  father_cache : Map[FatherMemoKey, Bitset],
) -> Bitset {
  let key = FatherMemoKey::{ pos, bits: child_bits.words.copy() }
  match father_cache.get(key) {
    Some(bits) => bits
    None => {
      let result = Bitset::new(self.word_count)
      if self.father_by_pos_child.get(pos) is Some(by_child) {
        child_bits.each_set_bit(child_id => {
          if by_child.get(child_id) is Some(parent_bits) {
            result.union_in_place(parent_bits)
          }
        })
      }
      father_cache[key] = result
      result
    }
  }
}

///|
/// Append complete pattern matches whose root ids are present in `bits`.
fn[Loc] Matcher::push_matches_at(
  self : Matcher,
  subject : SubjectTree[Loc],
  bits : Bitset,
  matches : Array[Match[Loc]],
) -> Unit {
  bits.each_set_bit(root_id => {
    if root_id < self.complete_patterns_by_root_id.length() {
      for pattern_index in self.complete_patterns_by_root_id[root_id] {
        matches.push({
          pattern_index,
          loc: subject.loc,
          captures: self.collect_captures(subject, pattern_index),
        })
      }
    }
  })
}

///|
/// Materialize the capture map for a single complete match.
///
/// Repeated names use `get_or_init` and append every occurrence location. This
/// is the intended first-version behavior: no equality check is performed for
/// repeated metavariable names.
fn[Loc] Matcher::collect_captures(
  self : Matcher,
  subject : SubjectTree[Loc],
  pattern_index : Int,
) -> Map[String, Array[Loc]] {
  let captures = Map::default()
  for capture_path in self.capture_paths_by_pattern[pattern_index] {
    captures
    .get_or_init(capture_path.name, () => [])
    .push(subject.loc_at_path(capture_path.path))
  }
  captures
}

///|
/// Follow a capture path from the matched root and return the reached location.
///
/// Paths originate from the pattern that just matched, so the corresponding
/// subject children are guaranteed to exist.
fn[Loc] SubjectTree::loc_at_path(
  self : SubjectTree[Loc],
  path : Array[Int],
) -> Loc {
  let mut current = self
  for pos in path {
    current = current.children[pos]
  }
  current.loc
}
