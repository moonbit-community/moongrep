///|
test "flow join merges equal labels and keeps distinct labels partitioned" {
  let left_state = state_write_path(
    empty_state(),
    test_path("left", []),
    single_tree("left"),
  )
  let right_state = state_write_path(
    empty_state(),
    test_path("right", []),
    single_tree("right"),
  )
  let equal_breaks = flow_join(
    break_result(Some("same"), left_state, single_tree("left")),
    break_result(Some("same"), right_state, single_tree("right")),
  )
  assert_eq(equal_breaks.breaks.length(), 1)
  debug_inspect(
    origin_ids(equal_breaks.breaks[0].path.value),
    content="[\"left\", \"right\"]",
  )

  let labelled = flow_join(
    flow_join(
      break_result(Some("inner"), left_state, single_tree("inner-break")),
      break_result(Some("outer"), right_state, single_tree("outer-break")),
    ),
    flow_join(
      flow_normal_to_continue(
        normal_result(left_state, single_tree("inner-continue")),
        Some("inner"),
      ),
      flow_normal_to_continue(
        normal_result(right_state, single_tree("outer-continue")),
        Some("outer"),
      ),
    ),
  )
  let consumed = consume_loop_control(labelled, Some("inner"))
  guard consumed.break_exit is Some(inner_break) &&
    consumed.back_edge is Some(inner_continue) else {
    fail("expected matching inner exits")
  }
  debug_inspect(
    (
      origin_ids(inner_break.value),
      origin_ids(inner_continue.value),
      [
        for entry in consumed.exits.breaks => entry.label
      ],
      [
        for entry in consumed.exits.continues => entry.label
      ],
    ),
    content=(
      #|(
      #|  ["inner-break"],
      #|  ["inner-continue"],
      #|  [Some("outer")],
      #|  [Some("outer")],
      #|)
    ),
  )
}
