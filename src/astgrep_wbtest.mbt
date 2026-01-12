///|
fn test_search(
  program : String,
  pattern : Json,
) -> Map[String, Map[String, Array[String]]] raise {
  @basic.show_loc.val = String
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
  let pattern = LabelledTree::from_json_repr(pattern)
    |> build_pattern_from_labelled_tree
  AstGrepEnv::new().grep(pattern, program)
}

///|
test "searching $A + $B * $C" {
  let program =
    #|fn foo() -> Int {
    #|  let foo = 5 + 8 * (220 << 1)
    #|  let bar = foo / 4
    #|  bar + foo * 42
    #|}

  // $A + $B * $C 
  let pattern : Json = {
    "kind": "Expr::Infix",
    "loc": "",
    "childs": {
      "op": {
        "kind": "Var",
        "loc": "",
        "childs": {
          "name": {
            "kind": "LongIdent::Ident",
            "loc": "",
            "childs": { "0": "+" },
          },
        },
      },
      "lhs": { "kind": "MetaVariable", "name": "A" },
      "rhs": {
        "kind": "Expr::Infix",
        "loc": "",
        "childs": {
          "op": {
            "kind": "Var",
            "loc": "",
            "childs": {
              "name": {
                "kind": "LongIdent::Ident",
                "loc": "",
                "childs": { "0": "*" },
              },
            },
          },
          "lhs": { "kind": "MetaVariable", "name": "B" },
          "rhs": { "kind": "MetaVariable", "name": "C" },
        },
      },
    },
  }
  let locs = test_search(program, pattern)
  @json.inspect(locs, content={
    "2:13-2:31": { "A": ["2:13-2:14"], "B": ["2:17-2:18"], "C": ["2:21-2:31"] },
    "4:3-4:17": { "A": ["4:3-4:6"], "B": ["4:9-4:12"], "C": ["4:15-4:17"] },
  })
}

///|
test "C99 style forloop" {
  // let pattern =
  //   #|for _COUNT = 0; _COUNT < n; _COUNT = _COUNT + 1 {
  //   #|  _BODY
  //   #|}
  // let (pattern, _) = @lexer.tokens_from_string(
  //     pattern,
  //     comment=true,
  //     name="",
  //   ).tokens
  //   |> @handrolled_parser.parse_expr
  let program =
    #|fn foo(n : Int) -> Unit {
    #| for i in 0..<n {
    #|   println(i)
    #| }
    #| for i = 0; i < n; i = i + 1 {
    #|   println(i)
    #| }
    #|}
  let pattern : Json = {
    "kind": "Expr::For",
    "loc": "",
    "childs": {
      "binders": {
        "kind": "Expr::For::BindingList",
        "loc": "",
        "childs": [
          {
            "kind": "For::Binding",
            "loc": "",
            "childs": {
              "binder": { "kind": "MetaVariable", "name": "COUNT" },
              "expr": {
                "kind": "Expr::Constant",
                "loc": "",
                "childs": {
                  "constant": {
                    "kind": "Constant::Int",
                    "loc": "",
                    "childs": { "0": "0" },
                  },
                },
              },
            },
          },
        ],
      },
      "condition": {
        "kind": "Expr::Infix",
        "loc": "",
        "childs": {
          "op": {
            "kind": "Var",
            "loc": "",
            "childs": {
              "name": {
                "kind": "LongIdent::Ident",
                "loc": "",
                "childs": { "0": "<" },
              },
            },
          },
          "lhs": {
            "kind": "Expr::Ident",
            "loc": "",
            "childs": {
              "id": {
                "kind": "Var",
                "loc": "",
                "childs": {
                  "name": { "kind": "MetaVariable", "name": "COUNT" },
                },
              },
            },
          },
          "rhs": { "kind": "MetaVariable", "name": "N" },
        },
      },
      "continue_block": {
        "kind": "Expr::For::ContBindingList",
        "loc": "",
        "childs": [
          {
            "kind": "For::ContBinding",
            "loc": "",
            "childs": {
              "binder": { "kind": "MetaVariable", "name": "COUNT" },
              "expr": {
                "kind": "Expr::Infix",
                "loc": "",
                "childs": {
                  "op": {
                    "kind": "Var",
                    "loc": "",
                    "childs": {
                      "name": {
                        "kind": "LongIdent::Ident",
                        "loc": "",
                        "childs": { "0": "+" },
                      },
                    },
                  },
                  "lhs": {
                    "kind": "Expr::Ident",
                    "loc": "",
                    "childs": {
                      "id": {
                        "kind": "Var",
                        "loc": "",
                        "childs": {
                          "name": { "kind": "MetaVariable", "name": "COUNT" },
                        },
                      },
                    },
                  },
                  "rhs": {
                    "kind": "Expr::Constant",
                    "loc": "",
                    "childs": {
                      "constant": {
                        "kind": "Constant::Int",
                        "loc": "",
                        "childs": { "0": "1" },
                      },
                    },
                  },
                },
              },
            },
          },
        ],
      },
      "body": { "kind": "MetaVariable", "name": "BODY" },
      "for_else": null,
      "label": null,
    },
  }
  @json.inspect(test_search(program, pattern), content={
    "5:2-7:3": {
      "COUNT": ["5:6-5:7", "5:13-5:14", "5:20-5:21", "5:24-5:25"],
      "N": ["5:17-5:18"],
      "BODY": ["6:4-6:14"],
    },
  })
}
