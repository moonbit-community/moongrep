///|
priv struct StateKey {
  path : StoragePath
  hash : Int
}

///|
impl Eq for StateKey with fn equal(self, other) {
  self.path == other.path
}

///|
impl Hash for StateKey with fn hash(self) {
  self.hash
}

///|
impl Hash for StateKey with fn hash_combine(self, hasher) {
  hasher.combine_int(self.hash)
}

///|
priv struct StateEntry {
  key : StateKey
  path : StoragePath
  origins : Array[TaintOrigin]
}

///|
// The abstract state keeps entries in insertion order for deterministic
// results. Exact paths and roots have private indexes so merge, equivalence,
// and reads do not repeatedly scan unrelated entries or build string keys.
priv struct TaintState {
  entries : Array[StateEntry]
  entry_indices : Map[StateKey, Int]
  root_indices : Map[String, Array[Int]]
}

///|
priv struct StateBuilder {
  entries : Array[StateEntry]
  entry_indices : Map[StateKey, Int]
  root_indices : Map[String, Array[Int]]
}

///|
fn new_state_builder() -> StateBuilder {
  { entries: [], entry_indices: {}, root_indices: {}, }
}

///|
fn empty_state() -> TaintState {
  { entries: [], entry_indices: {}, root_indices: {}, }
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
fn state_path_hash(path : StoragePath) -> Int {
  let hasher = Hasher()
  hasher.combine_string(path.root)
  hasher.combine_int(path.segments.length())
  for segment in path.segments {
    match segment {
      Field(name) => {
        hasher.combine_int(0)
        hasher.combine_string(name)
      }
      TupleIndex(index) => {
        hasher.combine_int(1)
        hasher.combine_int(index)
      }
      ConstIndex(index) => {
        hasher.combine_int(2)
        hasher.combine_string(index)
      }
      AnyIndex => hasher.combine_int(3)
    }
  }
  hasher.finalize()
}

///|
fn state_key(path : StoragePath) -> StateKey {
  { path, hash: state_path_hash(path), }
}

///|
fn copy_storage_path(path : StoragePath) -> StoragePath {
  { root: path.root, segments: copy_segments(path.segments), }
}

///|
fn StateBuilder::add_entry(self : StateBuilder, entry : StateEntry) -> Unit {
  let index = self.entries.length()
  self.entries.push(entry)
  self.entry_indices[entry.key] = index
  if self.root_indices.get(entry.path.root) is Some(indices) {
    indices.push(index)
  } else {
    self.root_indices[entry.path.root] = [index]
  }
}

///|
fn StateBuilder::merge_entry(self : StateBuilder, entry : StateEntry) -> Unit {
  if self.entry_indices.get(entry.key) is Some(index) {
    let previous = self.entries[index]
    self.entries[index] = {
      key: previous.key,
      path: previous.path,
      origins: merge_origin_lists(previous.origins, entry.origins),
    }
  } else {
    self.add_entry(entry)
  }
}

///|
fn StateBuilder::merge_path(
  self : StateBuilder,
  path : StoragePath,
  origins : Array[TaintOrigin],
) -> Unit {
  let query_key = state_key(path)
  if self.entry_indices.get(query_key) is Some(index) {
    let previous = self.entries[index]
    self.entries[index] = {
      key: previous.key,
      path: previous.path,
      origins: merge_origin_lists(previous.origins, origins),
    }
  } else {
    let stored_path = copy_storage_path(path)
    self.add_entry({
      key: state_key(stored_path),
      path: stored_path,
      origins: copy_origins(origins),
    })
  }
}

///|
fn StateBuilder::finish(self : StateBuilder) -> TaintState {
  {
    entries: self.entries,
    entry_indices: self.entry_indices,
    root_indices: self.root_indices,
  }
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
  for index in 0..<tree.length() {
    if tree[index].path == path {
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
  guard state.root_indices.get(path.root) is Some(indices) else {
    return projected
  }
  for index in indices {
    let entry = state.entries[index]
    if path_prefix_match_for_read(entry.path.segments, path.segments) {
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
  let builder = new_state_builder()
  for entry in state.entries {
    let should_drop = entry.path.root == path.root &&
      path_prefix_match_for_write(entry.path.segments, path.segments)
    if !should_drop {
      builder.add_entry(entry)
    }
  }
  builder.finish()
}

///|
fn state_write_path(
  state : TaintState,
  path : StoragePath,
  value : TaintTree,
) -> TaintState {
  let builder = new_state_builder()
  for entry in state.entries {
    let should_drop = entry.path.root == path.root &&
      path_prefix_match_for_write(entry.path.segments, path.segments)
    if !should_drop {
      builder.add_entry(entry)
    }
  }
  for entry in value {
    builder.merge_path(
      { root: path.root, segments: append_segments(path.segments, entry.path), },
      entry.origins,
    )
  }
  builder.finish()
}

///|
fn state_merge(left : TaintState, right : TaintState) -> TaintState {
  let builder = new_state_builder()
  for entry in left.entries {
    builder.merge_entry(entry)
  }
  for entry in right.entries {
    builder.merge_entry(entry)
  }
  builder.finish()
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
    if right.entry_indices.get(entry.key) is Some(index) {
      if !same_origin_list(entry.origins, right.entries[index].origins) {
        return false
      }
    } else {
      return false
    }
  }
  true
}
