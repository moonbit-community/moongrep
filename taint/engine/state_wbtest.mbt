///|
fn test_path(root : String, segments : Array[PathSegment]) -> StoragePath {
  { root, segments, }
}

///|
fn test_origin(id : String) -> TaintOrigin {
  { rule_id: "test", origin_id: id, site: Synthetic(id), note: None, }
}

///|
fn single_tree(id : String) -> TaintTree {
  [{ path: [], origins: [test_origin(id)], }]
}

///|
fn origin_ids(tree : TaintTree) -> Array[String] {
  let ids : Array[String] = []
  for entry in tree {
    for origin in entry.origins {
      if !ids.contains(origin.origin_id) {
        ids.push(origin.origin_id)
      }
    }
  }
  ids.sort()
  ids
}

///|
fn assert_state_indexes(state : TaintState) -> Unit raise {
  assert_eq(state.entry_indices.length(), state.entries.length())
  for index, entry in state.entries {
    assert_eq(state.entry_indices.get(entry.key), Some(index))
    guard state.root_indices.get(entry.path.root) is Some(indices) else {
      fail("missing root index for \{entry.path.root}")
    }
    assert_true(indices.contains(index))
  }
}

///|
test "domain write overwrites target subtree and keeps siblings" {
  let state = empty_state()
    |> state_write_path(test_path("x", [Field("a")]), single_tree("a"))
    |> state_write_path(
      test_path("x", [Field("a"), Field("b")]),
      single_tree("ab"),
    )
    |> state_write_path(test_path("x", [Field("b")]), single_tree("b"))
    |> state_write_path(test_path("x", [Field("a")]), single_tree("new"))
  debug_inspect(
    origin_ids(state_read_path(state, test_path("x", [Field("a")]))),
    content="[\"new\"]",
  )
  debug_inspect(
    origin_ids(state_read_path(state, test_path("x", [Field("b")]))),
    content="[\"b\"]",
  )
}

///|
test "domain kill removes exact subtree only" {
  let state = empty_state()
    |> state_write_path(test_path("x", [Field("a")]), single_tree("a"))
    |> state_write_path(
      test_path("x", [Field("a"), Field("b")]),
      single_tree("ab"),
    )
    |> state_write_path(test_path("x", [Field("b")]), single_tree("b"))
  let killed = state_kill_path(state, test_path("x", [Field("a")]))
  assert_eq(state_read_path(killed, test_path("x", [Field("a")])).length(), 0)
  debug_inspect(
    origin_ids(state_read_path(killed, test_path("x", [Field("b")]))),
    content="[\"b\"]",
  )
}

///|
test "domain dynamic read sees any and constant index taint" {
  let state = empty_state()
    |> state_write_path(
      test_path("arr", [ConstIndex("0")]),
      single_tree("zero"),
    )
    |> state_write_path(test_path("arr", [AnyIndex]), single_tree("any"))
  debug_inspect(
    origin_ids(state_read_path(state, test_path("arr", [AnyIndex]))),
    content="[\"any\", \"zero\"]",
  )
}

///|
test "domain branch join unions states" {
  let left = empty_state()
    |> state_write_path(test_path("x", []), single_tree("left"))
  let right = empty_state()
    |> state_write_path(test_path("x", []), single_tree("right"))
  let joined = state_merge(left, right)
  debug_inspect(
    origin_ids(state_read_path(joined, test_path("x", []))),
    content="[\"left\", \"right\"]",
  )
  assert_true(state_equiv(joined, state_merge(right, left)))
}

///|
test "domain state indexes stay consistent across writes kills and merges" {
  let written = empty_state()
    |> state_write_path(test_path("x", [Field("a")]), single_tree("xa"))
    |> state_write_path(test_path("y", [Field("b")]), single_tree("yb"))
    |> state_write_path(test_path("x", [Field("c")]), single_tree("xc"))
  let killed = state_kill_path(written, test_path("x", [Field("a")]))
  let merged = state_merge(
    killed,
    empty_state()
    |> state_write_path(test_path("z", [AnyIndex]), single_tree("z")),
  )
  assert_state_indexes(written)
  assert_state_indexes(killed)
  assert_state_indexes(merged)
}
