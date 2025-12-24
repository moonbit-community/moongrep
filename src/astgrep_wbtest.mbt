///|
test {
  let program =
    #|{
    #|  let foo = 5 + 8 * (220 << 1)
    #|  let bar = foo / 4
    #|  bar + foo * 42
    #|}
  let (program, _) = @lexer.tokens_from_string(
      program,
      comment=true,
      name="block_expr",
    ).tokens
    |> @handrolled_parser.parse_expr()
  let program = LabelledTree::from_expr(program)
  let pattern = "___ + ___ * ___"
  let (pattern, _) = @lexer.tokens_from_string(pattern, comment=true).tokens
    |> @handrolled_parser.parse_expr()
  current_convert_mode.val = Pattern
  let pattern = LabelledTree::from_expr(pattern)
    |> build_pattern_from_labelled_tree
  let locs = AstGrepEnv::new().grep(pattern, program)
  @basic.show_loc.val = @basic.Json
  @json.inspect(locs, content=[
    {
      "file": "block_expr",
      "start": { "line": 2, "column": 13 },
      "end": { "line": 2, "column": 31 },
    },
    {
      "file": "block_expr",
      "start": { "line": 4, "column": 3 },
      "end": { "line": 4, "column": 17 },
    },
  ])
}
