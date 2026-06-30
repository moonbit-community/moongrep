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
