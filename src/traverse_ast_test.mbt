///|
fn identify_c99style_for_loop(
  ast : Json,
  locations : Array[Json],
) -> Unit raise {
  // pattern:
  // for _COUNT = 0; _COUNT < _N; _COUNT = _COUNT + 1 {
  //   _BODY
  // }
  traverse_ast_json_repr(ast, ast => match ast {
    {
      "kind": "Expr::For",
      "loc": loc,
      "childs": {
        "binders": {
          "kind": "Expr::For::BindingList",
          "childs": [
            {
              "kind": "For::Binding",
              "childs": {
                "binder": {
                  "kind": "Binder",
                  "childs": { "name": count_1, .. },
                  ..
                },
                "expr": {
                  "kind": "Expr::Constant",
                  "childs": {
                    "constant": {
                      "kind": "Constant::Int",
                      "childs": { "0": "0", .. },
                      ..
                    },
                    ..
                  },
                  ..
                },
                ..
              },
              ..
            },
          ],
          ..
        },
        "condition": {
          "kind": "Expr::Infix",
          "childs": {
            "op": {
              "kind": "Var",
              "childs": {
                "name": {
                  "kind": "LongIdent::Ident",
                  "childs": { "0": "<", .. },
                  ..
                },
                ..
              },
              ..
            },
            "lhs": {
              "kind": "Expr::Ident",
              "childs": {
                "id": {
                  "kind": "Var",
                  "childs": {
                    "name": {
                      "kind": "LongIdent::Ident",
                      "childs": { "0": count_2, .. },
                      ..
                    },
                    ..
                  },
                  ..
                },
                ..
              },
              ..
            },
            "rhs": rhs,
            ..
          },
          ..
        },
        "continue_block": {
          "kind": "Expr::For::ContBindingList",
          "childs": [
            {
              "kind": "For::ContBinding",
              "childs": {
                "binder": {
                  "kind": "Binder",
                  "childs": { "name": count_3, .. },
                  ..
                },
                "expr": {
                  "kind": "Expr::Infix",
                  "childs": {
                    "op": {
                      "kind": "Var",
                      "childs": {
                        "name": {
                          "kind": "LongIdent::Ident",
                          "childs": { "0": "+", .. },
                          ..
                        },
                        ..
                      },
                      ..
                    },
                    "lhs": {
                      "kind": "Expr::Ident",
                      "childs": {
                        "id": {
                          "kind": "Var",
                          "childs": {
                            "name": {
                              "kind": "LongIdent::Ident",
                              "childs": { "0": count_4, .. },
                              ..
                            },
                            ..
                          },
                          ..
                        },
                        ..
                      },
                      ..
                    },
                    "rhs": {
                      "kind": "Expr::Constant",
                      "childs": {
                        "constant": {
                          "kind": "Constant::Int",
                          "childs": { "0": "1", .. },
                          ..
                        },
                        ..
                      },
                      ..
                    },
                    ..
                  },
                  ..
                },
                ..
              },
              ..
            },
          ],
          ..
        },
        "body": body,
        "for_else": for_else,
        "label": label,
        ..
      },
      ..
    } => {
      ignore(rhs)
      ignore(body)
      ignore(for_else)
      ignore(label)
      if count_1 == count_2 && count_2 == count_3 && count_3 == count_4 {
        locations.push(loc)
      }
      true
    }
    _ => true
  })
}

///|
test {
  let program =
    #|fn foo() -> Unit {
    #|
    #| for i in 0..<10 {
    #|   println(i)
    #| }
    #|
    #| let arr = [9, 4, 8, 10]
    #|
    #| for i = 0; i < arr.length(); i = i + 1 {
    #|   println(arr[i])
    #| }
    #|
    #| // not typical c99 style forloop that can be replace with for in
    #| for j = 0; j < arr.length(); j = j + 2 {
    #|   println(arr[j])
    #| }
    #|
    #|}
  @basic.show_loc.val = Json
  let (program, _) = @lexer.tokens_from_string(
      program,
      comment=true,
      name="foo",
    ).tokens
    |> @handrolled_parser.parse()
  let program = match program {
    More(p, tail=Empty) => p.json_repr()
    _ => fail("parse failed")
  }
  let locations = []
  identify_c99style_for_loop(program, locations)
  @json.inspect(locations, content=[
    {
      "file": "foo",
      "start": { "line": 9, "column": 2 },
      "end": { "line": 11, "column": 3 },
    },
  ])
}
