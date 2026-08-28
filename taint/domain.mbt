///|
priv struct StateEntry {
  path : StoragePath
  origins : Array[TaintOrigin]
}

///|
// The abstract state maps storage paths, including summarized `AnyIndex` paths,
// to source origins. Expression values use `TaintTree`, which is relative to
// that expression, while state entries are rooted at locals or parameters.
priv struct TaintState {
  entries : Array[StateEntry]
}

///|
fn empty_state() -> TaintState {
  { entries: [], }
}

///|
fn copy_segments(segments : Array[PathSegment]) -> Array[PathSegment] {
  let copied : Array[PathSegment] = []
  for segment in segments {
    copied.push(segment)
  }
  copied
}

///|
fn copy_origins(origins : Array[TaintOrigin]) -> Array[TaintOrigin] {
  let copied : Array[TaintOrigin] = []
  for origin in origins {
    copied.push(origin)
  }
  copied
}

///|
fn copy_tree(tree : TaintTree) -> TaintTree {
  let copied : TaintTree = []
  for entry in tree {
    copied.push({
      path: copy_segments(entry.path),
      origins: copy_origins(entry.origins),
    })
  }
  copied
}

///|
fn segment_key(segment : PathSegment) -> String {
  match segment {
    Field(name) => "f:\{name}"
    TupleIndex(index) => "t:\{index}"
    ConstIndex(index) => "i:\{index}"
    AnyIndex => "i:*"
  }
}

///|
fn segments_key(segments : Array[PathSegment]) -> String {
  let parts : Array[String] = []
  for segment in segments {
    parts.push(segment_key(segment))
  }
  parts.join("/")
}

///|
fn storage_path_key(path : StoragePath) -> String {
  "\{path.root}/\{segments_key(path.segments)}"
}

///|
fn path_prefix_match_for_write(
  path_segments : Array[PathSegment],
  prefix_segments : Array[PathSegment],
) -> Bool {
  if prefix_segments.length() > path_segments.length() {
    return false
  }
  for index in 0..<prefix_segments.length() {
    if path_segments[index] != prefix_segments[index] {
      return false
    }
  }
  true
}

///|
fn segment_matches_for_read(query : PathSegment, actual : PathSegment) -> Bool {
  match query {
    // Reads through an unknown array index may observe any concrete index, and
    // reads through a concrete index may observe an `AnyIndex` summary entry.
    AnyIndex =>
      match actual {
        AnyIndex | ConstIndex(_) => true
        _ => false
      }
    ConstIndex(index) =>
      match actual {
        ConstIndex(found) => found == index
        AnyIndex => true
        _ => false
      }
    _ => query == actual
  }
}

///|
fn path_prefix_match_for_read(
  path_segments : Array[PathSegment],
  prefix_segments : Array[PathSegment],
) -> Bool {
  if prefix_segments.length() > path_segments.length() {
    return false
  }
  for index in 0..<prefix_segments.length() {
    if !segment_matches_for_read(prefix_segments[index], path_segments[index]) {
      return false
    }
  }
  true
}

///|
fn strip_segments_prefix(
  segments : Array[PathSegment],
  prefix : Array[PathSegment],
) -> Array[PathSegment] {
  let stripped : Array[PathSegment] = []
  for index in prefix.length()..<segments.length() {
    stripped.push(segments[index])
  }
  stripped
}

///|
fn append_segments(
  left : Array[PathSegment],
  right : Array[PathSegment],
) -> Array[PathSegment] {
  let result : Array[PathSegment] = []
  for segment in left {
    result.push(segment)
  }
  for segment in right {
    result.push(segment)
  }
  result
}

///|
fn add_origin_unique(
  origins : Array[TaintOrigin],
  origin : TaintOrigin,
) -> Unit {
  if !origins.contains(origin) {
    origins.push(origin)
  }
}

///|
fn merge_origin_lists(
  left : Array[TaintOrigin],
  right : Array[TaintOrigin],
) -> Array[TaintOrigin] {
  let merged = copy_origins(left)
  for origin in right {
    add_origin_unique(merged, origin)
  }
  merged
}

///|
fn merge_relative_entry(
  tree : TaintTree,
  path : Array[PathSegment],
  origins : Array[TaintOrigin],
) -> Unit {
  let key = segments_key(path)
  for index in 0..<tree.length() {
    if segments_key(tree[index].path) == key {
      tree[index] = {
        path: copy_segments(tree[index].path),
        origins: merge_origin_lists(tree[index].origins, origins),
      }
      return
    }
  }
  tree.push({ path: copy_segments(path), origins: copy_origins(origins), })
}

///|
fn merge_state_entry(
  entries : Array[StateEntry],
  path : StoragePath,
  origins : Array[TaintOrigin],
) -> Unit {
  let key = storage_path_key(path)
  for index in 0..<entries.length() {
    if storage_path_key(entries[index].path) == key {
      entries[index] = {
        path: { root: path.root, segments: copy_segments(path.segments), },
        origins: merge_origin_lists(entries[index].origins, origins),
      }
      return
    }
  }
  entries.push({
    path: { root: path.root, segments: copy_segments(path.segments), },
    origins: copy_origins(origins),
  })
}

///|
fn tree_merge(left : TaintTree, right : TaintTree) -> TaintTree {
  let merged = copy_tree(left)
  for entry in right {
    merge_relative_entry(merged, entry.path, entry.origins)
  }
  merged
}

///|
fn tree_project(tree : TaintTree, prefix : Array[PathSegment]) -> TaintTree {
  let projected : TaintTree = []
  for entry in tree {
    if path_prefix_match_for_read(entry.path, prefix) {
      merge_relative_entry(
        projected,
        strip_segments_prefix(entry.path, prefix),
        entry.origins,
      )
    }
  }
  projected
}

///|
fn state_read_path(state : TaintState, path : StoragePath) -> TaintTree {
  let projected : TaintTree = []
  for entry in state.entries {
    if entry.path.root == path.root &&
      path_prefix_match_for_read(entry.path.segments, path.segments) {
      merge_relative_entry(
        projected,
        strip_segments_prefix(entry.path.segments, path.segments),
        entry.origins,
      )
    }
  }
  projected
}

///|
fn state_kill_path(state : TaintState, path : StoragePath) -> TaintState {
  let kept : Array[StateEntry] = []
  for entry in state.entries {
    let should_drop = entry.path.root == path.root &&
      path_prefix_match_for_write(entry.path.segments, path.segments)
    if !should_drop {
      kept.push(entry)
    }
  }
  { entries: kept, }
}

///|
fn state_write_path(
  state : TaintState,
  path : StoragePath,
  value : TaintTree,
) -> TaintState {
  let killed = state_kill_path(state, path)
  let entries : Array[StateEntry] = []
  for entry in killed.entries {
    merge_state_entry(entries, entry.path, entry.origins)
  }
  for entry in value {
    merge_state_entry(
      entries,
      { root: path.root, segments: append_segments(path.segments, entry.path), },
      entry.origins,
    )
  }
  { entries, }
}

///|
fn state_merge(left : TaintState, right : TaintState) -> TaintState {
  let entries : Array[StateEntry] = []
  for entry in left.entries {
    merge_state_entry(entries, entry.path, entry.origins)
  }
  for entry in right.entries {
    merge_state_entry(entries, entry.path, entry.origins)
  }
  { entries, }
}

///|
fn state_merge_all(states : Array[TaintState]) -> TaintState {
  let mut merged = empty_state()
  for state in states {
    merged = state_merge(merged, state)
  }
  merged
}

///|
fn same_origin_list(
  left : Array[TaintOrigin],
  right : Array[TaintOrigin],
) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for origin in left {
    if !right.contains(origin) {
      return false
    }
  }
  true
}

///|
fn state_equiv(left : TaintState, right : TaintState) -> Bool {
  if left.entries.length() != right.entries.length() {
    return false
  }
  for entry in left.entries {
    let mut found = false
    for other in right.entries {
      if storage_path_key(entry.path) == storage_path_key(other.path) &&
        same_origin_list(entry.origins, other.origins) {
        found = true
      }
    }
    if !found {
      return false
    }
  }
  true
}
