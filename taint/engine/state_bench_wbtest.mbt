///|
let state_bench_entry_count = 256

///|
let state_bench_root_count = 16

///|
fn state_bench_path(index : Int) -> StoragePath {
  {
    root: "root-\{index % state_bench_root_count}",
    segments: [Field("field-\{index}")],
  }
}

///|
fn state_bench_tree(index : Int) -> TaintTree {
  [
    {
      path: [],
      origins: [
        {
          rule_id: "bench",
          origin_id: "origin-\{index}",
          site: Synthetic("origin-\{index}"),
          note: None,
        },
      ],
    },
  ]
}

///|
fn state_bench_make_state(start : Int, count : Int) -> TaintState {
  let mut state = empty_state()
  for index in start..<(start + count) {
    state = state_write_path(
      state,
      state_bench_path(index),
      state_bench_tree(index),
    )
  }
  state
}

///|
test "bench taint state read entries=256 lookups=256" (it : @bench.T) {
  let state = state_bench_make_state(0, state_bench_entry_count)
  it.bench(fn() {
    let mut found = 0
    for index in 0..<state_bench_entry_count {
      found += state_read_path(state, state_bench_path(index)).length()
    }
    it.keep(found)
  })
}

///|
test "bench taint state merge overlap=128 entries=256+256" (it : @bench.T) {
  let left = state_bench_make_state(0, state_bench_entry_count)
  let right = state_bench_make_state(
    state_bench_entry_count / 2,
    state_bench_entry_count,
  )
  it.bench(fn() { it.keep(state_merge(left, right).entries.length()) })
}

///|
test "bench taint state merge and equiv entries=256+256" (it : @bench.T) {
  let left = state_bench_make_state(0, state_bench_entry_count)
  let right = state_bench_make_state(
    state_bench_entry_count / 2,
    state_bench_entry_count,
  )
  let expected = state_merge(right, left)
  it.bench(fn() {
    let merged = state_merge(left, right)
    it.keep(state_equiv(merged, expected))
  })
}
