///|
test "build infix expr pattern" {
  let pattern = "1 + 3 * ___"
  let tokens = @lexer.tokens_from_string(pattern, comment=true).tokens
  let (pattern, _) = @handrolled_parser.parse_expr(tokens)
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
      "lhs": {
        "kind": "Expr::Constant",
        "loc": null,
        "childs": {
          "constant": {
            "kind": "Constant::Int",
            "loc": null,
            "childs": { "0": "1" },
          },
        },
      },
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
          "lhs": {
            "kind": "Expr::Constant",
            "loc": null,
            "childs": {
              "constant": {
                "kind": "Constant::Int",
                "loc": null,
                "childs": { "0": "3" },
              },
            },
          },
          "rhs": { "kind": "MetaVariable", "name": "___" },
        },
      },
    },
  }
  @json.inspect(LabelledTree::from_json_repr(pattern), content=[
    "Expr::Infix()",
    [
      ["Var()", ["LongIdent::Ident(0=\"+\",)"]],
      ["Expr::Constant()", ["Constant::Int(0=\"1\",)"]],
      [
        "Expr::Infix()",
        [
          ["Var()", ["LongIdent::Ident(0=\"*\",)"]],
          ["Expr::Constant()", ["Constant::Int(0=\"3\",)"]],
          "$_",
        ],
      ],
    ],
  ])
}
