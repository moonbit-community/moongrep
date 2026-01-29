///|
test "build infix expr pattern" {
  let pattern = "1 + 3 * ___"
  let tokens = @lexer.tokens_from_string(pattern, comment=true).tokens
  let (pattern, _) = @handrolled_parser.parse_expr(tokens)
  ignore(pattern)
  let pattern : Json = {
    "kind": "Expr::Infix",
    "loc": "",
    "children": {
      "op": {
        "kind": "Var",
        "loc": "",
        "children": {
          "name": {
            "kind": "LongIdent::Ident",
            "loc": "",
            "children": { "value": "+" },
          },
        },
      },
      "lhs": {
        "kind": "Expr::Constant",
        "loc": "",
        "children": {
          "constant": {
            "kind": "Constant::Int",
            "loc": "",
            "children": { "value": "1" },
          },
        },
      },
      "rhs": {
        "kind": "Expr::Infix",
        "loc": "",
        "children": {
          "op": {
            "kind": "Var",
            "loc": "",
            "children": {
              "name": {
                "kind": "LongIdent::Ident",
                "loc": "",
                "children": { "value": "*" },
              },
            },
          },
          "lhs": {
            "kind": "Expr::Constant",
            "loc": "",
            "children": {
              "constant": {
                "kind": "Constant::Int",
                "loc": "",
                "children": { "value": "3" },
              },
            },
          },
          "rhs": { "kind": "MetaVariable", "name": "___" },
        },
      },
    },
  }
  json_inspect(LabelledTree::from_json_repr(pattern), content=[
    "Expr::Infix()",
    [
      ["Var()", ["LongIdent::Ident(value=\"+\",)"]],
      ["Expr::Constant()", ["Constant::Int(value=\"1\",)"]],
      [
        "Expr::Infix()",
        [
          ["Var()", ["LongIdent::Ident(value=\"*\",)"]],
          ["Expr::Constant()", ["Constant::Int(value=\"3\",)"]],
          "$___",
        ],
      ],
    ],
  ])
}
