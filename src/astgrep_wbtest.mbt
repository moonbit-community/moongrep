///|
test "searching $_ + ($_ * $_)" {
  let program =
    #|fn foo() -> Int {
    #|  let foo = 5 + 8 * (220 << 1)
    #|  let bar = foo / 4
    #|  bar + foo * 42
    #|}
  @basic.show_loc.val = Json
  let (program, _) = @lexer.tokens_from_string(
      program,
      comment=true,
      name="function foo",
    ).tokens
    |> @handrolled_parser.parse()
  let program = match program {
    More(p, tail=Empty) => p
    _ => fail("parse failed")
  }
  let program = LabelledTree::from_json_repr(program.json_repr())
  let pattern = "___ + ___ * ___"
  let (pattern, _) = @lexer.tokens_from_string(pattern, comment=true).tokens
    |> @handrolled_parser.parse_expr()
  ignore(pattern)
  let pattern : Json = {
    "kind": "Expr::Infix",
    "loc": null,
    "childs": {
      "op": {
        "kind": "Var",
        "loc": null,
        "childs": {
          "name": {
            "kind": "LongIdent::Ident",
            "loc": null,
            "childs": { "0": "+" },
          },
        },
      },
      "lhs": { "kind": "MetaVariable", "name": "___" },
      "rhs": {
        "kind": "Expr::Infix",
        "loc": null,
        "childs": {
          "op": {
            "kind": "Var",
            "loc": null,
            "childs": {
              "name": {
                "kind": "LongIdent::Ident",
                "loc": null,
                "childs": { "0": "*" },
              },
            },
          },
          "lhs": { "kind": "MetaVariable", "name": "___" },
          "rhs": { "kind": "MetaVariable", "name": "___" },
        },
      },
    },
  }
  let pattern = LabelledTree::from_json_repr(pattern)
    |> build_pattern_from_labelled_tree
  let locs = AstGrepEnv::new().grep(pattern, program)
  @json.inspect(locs, content=[
    {
      "file": "function foo",
      "start": { "line": 2, "column": 13 },
      "end": { "line": 2, "column": 31 },
    },
    {
      "file": "function foo",
      "start": { "line": 4, "column": 3 },
      "end": { "line": 4, "column": 17 },
    },
  ])
}
