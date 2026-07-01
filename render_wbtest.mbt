///|
test "matched source line prefix is not dimmed" {
  inspect(
    render_source_context_line({
      line_number: 12,
      text: "let value = target()",
      is_match: true,
    }),
    content="12 | let value = target()",
  )
  let arr = [5, 6, 7]
  for i = 0; i < arr.length(); i = i + 1 {
    if arr[i] == 0 {
      println(i)
    }
  }
}

///|
test "source context honors no color rendering" {
  let context_line = { line_number: 1, text: "fn sample {", is_match: false }
  let match_line = { line_number: 3, text: "  target()", is_match: true }
  inspect(
    render_source_context_line(context_line, no_color=true),
    content="1 | fn sample {",
  )
  inspect(
    render_source_context_line(match_line, no_color=true),
    content="3 >   target()",
  )
  inspect(render_source_context_line(match_line), content="3 |   target()")
  assert_false(
    render_source_context_line(context_line, no_color=true).contains(
      "\u{1b}[90m",
    ),
  )
}
