///|
test {
  let c99style_for_loop =
    #| for _COUNT = _N; _COUNT < _ARRAY.length(); _COUNT = _COUNT + 1 {
    #|   _BODY
    #| }
  json_inspect(@moongrep.dump_expr_json_repr(c99style_for_loop), content={
    "kind": "Expr::For",
    "loc": null,
    "children": {
      "binders": {
        "kind": "Expr::For::BindingList",
        "loc": null,
        "children": [
          {
            "kind": "For::Binding",
            "loc": null,
            "children": {
              "binder": {
                "kind": "Binder",
                "loc": null,
                "children": { "name": "_COUNT" },
              },
              "expr": {
                "kind": "Expr::Ident",
                "loc": null,
                "children": {
                  "id": {
                    "kind": "Var",
                    "loc": null,
                    "children": {
                      "name": {
                        "kind": "LongIdent::Ident",
                        "loc": null,
                        "children": { "value": "_N" },
                      },
                    },
                  },
                },
              },
            },
          },
        ],
      },
      "condition": {
        "kind": "Expr::Infix",
        "loc": null,
        "children": {
          "op": {
            "kind": "Var",
            "loc": null,
            "children": {
              "name": {
                "kind": "LongIdent::Ident",
                "loc": null,
                "children": { "value": "<" },
              },
            },
          },
          "lhs": {
            "kind": "Expr::Ident",
            "loc": null,
            "children": {
              "id": {
                "kind": "Var",
                "loc": null,
                "children": {
                  "name": {
                    "kind": "LongIdent::Ident",
                    "loc": null,
                    "children": { "value": "_COUNT" },
                  },
                },
              },
            },
          },
          "rhs": {
            "kind": "Expr::DotApply",
            "loc": null,
            "children": {
              "self": {
                "kind": "Expr::Ident",
                "loc": null,
                "children": {
                  "id": {
                    "kind": "Var",
                    "loc": null,
                    "children": {
                      "name": {
                        "kind": "LongIdent::Ident",
                        "loc": null,
                        "children": { "value": "_ARRAY" },
                      },
                    },
                  },
                },
              },
              "method_name": {
                "kind": "Label",
                "loc": null,
                "children": { "name": "length" },
              },
              "args": {
                "kind": "Expr::DotApply::ArgList",
                "loc": null,
                "children": [],
              },
              "return_self": false,
              "attr": {
                "kind": "ApplyAttr::NoAttr",
                "loc": null,
                "children": {},
              },
            },
          },
        },
      },
      "continue_block": {
        "kind": "Expr::For::ContBindingList",
        "loc": null,
        "children": [
          {
            "kind": "For::ContBinding",
            "loc": null,
            "children": {
              "binder": {
                "kind": "Binder",
                "loc": null,
                "children": { "name": "_COUNT" },
              },
              "expr": {
                "kind": "Expr::Infix",
                "loc": null,
                "children": {
                  "op": {
                    "kind": "Var",
                    "loc": null,
                    "children": {
                      "name": {
                        "kind": "LongIdent::Ident",
                        "loc": null,
                        "children": { "value": "+" },
                      },
                    },
                  },
                  "lhs": {
                    "kind": "Expr::Ident",
                    "loc": null,
                    "children": {
                      "id": {
                        "kind": "Var",
                        "loc": null,
                        "children": {
                          "name": {
                            "kind": "LongIdent::Ident",
                            "loc": null,
                            "children": { "value": "_COUNT" },
                          },
                        },
                      },
                    },
                  },
                  "rhs": {
                    "kind": "Expr::Constant",
                    "loc": null,
                    "children": {
                      "constant": {
                        "kind": "Constant::Int",
                        "loc": null,
                        "children": { "value": "1" },
                      },
                    },
                  },
                },
              },
            },
          },
        ],
      },
      "body": {
        "kind": "Expr::Ident",
        "loc": null,
        "children": {
          "id": {
            "kind": "Var",
            "loc": null,
            "children": {
              "name": {
                "kind": "LongIdent::Ident",
                "loc": null,
                "children": { "value": "_BODY" },
              },
            },
          },
        },
      },
      "for_else": null,
      "label": null,
    },
  })
}

///|
fn identify_c99style_for_loop(
  source : String,
  name~ : String,
  locations : Array[Json],
) -> Unit raise {
  // pattern:
  // for $COUNT = $N; $COUNT < $ARRAY.length(); $COUNT = $COUNT + 1 {
  //   $BODY
  // }

  @moongrep.traverse_top_impls(name~, source, ast => match ast {
    {
      "kind": "Expr::For",
      "loc": loc,
      "children": {
        "binders": {
          "kind": "Expr::For::BindingList",
          "children": [
            {
              "kind": "For::Binding",
              "children": {
                "binder": {
                  "kind": "Binder",
                  "children": { "name": count_1, .. },
                  ..
                },
                "expr": start_idx,
                ..
              },
              ..
            },
          ],
          ..
        },
        "condition": {
          "kind": "Expr::Infix",
          "children": {
            "op": {
              "kind": "Var",
              "children": {
                "name": {
                  "kind": "LongIdent::Ident",
                  "children": { "value": "<", .. },
                  ..
                },
                ..
              },
              ..
            },
            "lhs": {
              "kind": "Expr::Ident",
              "children": {
                "id": {
                  "kind": "Var",
                  "children": {
                    "name": {
                      "kind": "LongIdent::Ident",
                      "children": { "value": count_2, .. },
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
              "kind": "Expr::DotApply",
              "children": {
                "self": {
                  "kind": "Expr::Ident",
                  "children": {
                    "id": {
                      "kind": "Var",
                      "children": {
                        "name": {
                          "kind": "LongIdent::Ident",
                          "children": { "value": String(array_name), .. },
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
                "method_name": {
                  "kind": "Label",
                  "children": { "name": "length", .. },
                  ..
                },
                "args": {
                  "kind": "Expr::DotApply::ArgList",
                  "children": [],
                  ..
                },
                "return_self": false,
                "attr": { "kind": "ApplyAttr::NoAttr", "children": { .. }, .. },
                ..
              },
              ..
            },
            ..
          },
          ..
        },
        "continue_block": {
          "kind": "Expr::For::ContBindingList",
          "children": [
            {
              "kind": "For::ContBinding",
              "children": {
                "binder": {
                  "kind": "Binder",
                  "children": { "name": count_3, .. },
                  ..
                },
                "expr": {
                  "kind": "Expr::Infix",
                  "children": {
                    "op": {
                      "kind": "Var",
                      "children": {
                        "name": {
                          "kind": "LongIdent::Ident",
                          "children": { "value": "+", .. },
                          ..
                        },
                        ..
                      },
                      ..
                    },
                    "lhs": {
                      "kind": "Expr::Ident",
                      "children": {
                        "id": {
                          "kind": "Var",
                          "children": {
                            "name": {
                              "kind": "LongIdent::Ident",
                              "children": { "value": count_4, .. },
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
                      "children": {
                        "constant": {
                          "kind": "Constant::Int",
                          "children": { "value": "1", .. },
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
      ignore(array_name)
      ignore(start_idx)
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
  let match_option_some_none =
    #| match _VALUE {
    #|   Some(_ITEM) => _SOME_BODY
    #|   None => _NONE_BODY
    #| }
  json_inspect(@moongrep.dump_expr_json_repr(match_option_some_none), content={
    "kind": "Expr::Match",
    "loc": null,
    "children": {
      "expr": {
        "kind": "Expr::Ident",
        "loc": null,
        "children": {
          "id": {
            "kind": "Var",
            "loc": null,
            "children": {
              "name": {
                "kind": "LongIdent::Ident",
                "loc": null,
                "children": { "value": "_VALUE" },
              },
            },
          },
        },
      },
      "cases": {
        "kind": "Expr::Match::CaseList",
        "loc": null,
        "children": [
          {
            "kind": "Case",
            "loc": null,
            "children": {
              "pattern": {
                "kind": "Pattern::Constr",
                "loc": null,
                "children": {
                  "constr": {
                    "kind": "Constructor",
                    "loc": null,
                    "children": {
                      "name": {
                        "kind": "ConstrName",
                        "loc": null,
                        "children": { "name": "Some" },
                      },
                      "extra_info": {
                        "kind": "ConstructorExtraInfo::NoExtraInfo",
                        "loc": null,
                        "children": {},
                      },
                    },
                  },
                  "args": {
                    "kind": "Pattern::Constr::ArgList",
                    "loc": null,
                    "children": [
                      {
                        "kind": "ConstrPatArg",
                        "loc": null,
                        "children": {
                          "pat": {
                            "kind": "Pattern::Var",
                            "loc": null,
                            "children": {
                              "value": {
                                "kind": "Binder",
                                "loc": null,
                                "children": { "name": "_ITEM" },
                              },
                            },
                          },
                          "kind": {
                            "kind": "ArgumentKind::Positional",
                            "loc": null,
                            "children": {},
                          },
                        },
                      },
                    ],
                  },
                  "is_open": false,
                },
              },
              "guard": null,
              "body": {
                "kind": "Expr::Ident",
                "loc": null,
                "children": {
                  "id": {
                    "kind": "Var",
                    "loc": null,
                    "children": {
                      "name": {
                        "kind": "LongIdent::Ident",
                        "loc": null,
                        "children": { "value": "_SOME_BODY" },
                      },
                    },
                  },
                },
              },
            },
          },
          {
            "kind": "Case",
            "loc": null,
            "children": {
              "pattern": {
                "kind": "Pattern::Constr",
                "loc": null,
                "children": {
                  "constr": {
                    "kind": "Constructor",
                    "loc": null,
                    "children": {
                      "name": {
                        "kind": "ConstrName",
                        "loc": null,
                        "children": { "name": "None" },
                      },
                      "extra_info": {
                        "kind": "ConstructorExtraInfo::NoExtraInfo",
                        "loc": null,
                        "children": {},
                      },
                    },
                  },
                  "args": null,
                  "is_open": false,
                },
              },
              "guard": null,
              "body": {
                "kind": "Expr::Ident",
                "loc": null,
                "children": {
                  "id": {
                    "kind": "Var",
                    "loc": null,
                    "children": {
                      "name": {
                        "kind": "LongIdent::Ident",
                        "loc": null,
                        "children": { "value": "_NONE_BODY" },
                      },
                    },
                  },
                },
              },
            },
          },
        ],
      },
    },
  })
}

///|
fn identify_match_option_some_none(
  name~ : String,
  source : String,
  locations : Array[Json],
) -> Unit raise {
  // pattern:
  // 
  // match $VALUE {
  //   Some($ITEM) => $SOME_BODY
  //   None => $NONE_BODY
  // }
  // 
  // or:
  // 
  // match $VALUE {
  //   None => $NONE_BODY
  //   Some($ITEM) => $SOME_BODY
  // }
  fn is_option_some_case(ast : Json) -> Bool {
    match ast {
      {
        "kind": "Case",
        "children": {
          "pattern": {
            "kind": "Pattern::Constr",
            "children": {
              "constr": {
                "kind": "Constructor",
                "children": {
                  "name": {
                    "kind": "ConstrName",
                    "children": { "name": "Some", .. },
                    ..
                  },
                  ..
                },
                ..
              },
              "args": {
                "kind": "Pattern::Constr::ArgList",
                "children": [
                  {
                    "kind": "ConstrPatArg",
                    "children": {
                      "pat": pat,
                      "kind": {
                        "kind": "ArgumentKind::Positional",
                        "children": { .. },
                        ..
                      },
                      ..
                    },
                    ..
                  },
                ],
                ..
              },
              "is_open": false,
              ..
            },
            ..
          },
          "guard": Null,
          "body": body,
          ..
        },
        ..
      } => {
        ignore(pat)
        ignore(body)
        true
      }
      _ => false
    }
  }

  fn is_option_none_case(ast : Json) -> Bool {
    match ast {
      {
        "kind": "Case",
        "children": {
          "pattern": {
            "kind": "Pattern::Constr",
            "children": {
              "constr": {
                "kind": "Constructor",
                "children": {
                  "name": {
                    "kind": "ConstrName",
                    "children": { "name": "None", .. },
                    ..
                  },
                  ..
                },
                ..
              },
              "args": Null,
              "is_open": false,
              ..
            },
            ..
          },
          "guard": Null,
          "body": body,
          ..
        },
        ..
      } => {
        ignore(body)
        true
      }
      _ => false
    }
  }

  @moongrep.traverse_top_impls(name~, source, ast => match ast {
    {
      "kind": "Expr::Match",
      "loc": loc,
      "children": {
        "expr": expr,
        "cases": {
          "kind": "Expr::Match::CaseList",
          "children": [case_1, case_2],
          ..
        },
        ..
      },
      ..
    } => {
      ignore(expr)
      if (is_option_some_case(case_1) && is_option_none_case(case_2)) ||
        (is_option_none_case(case_1) && is_option_some_case(case_2)) {
        locations.push(loc)
      }
      true
    }
    _ => true
  })
}

///|
test {
  let array_push_call =
    #| _ARRAY.push(_VALUE)
  json_inspect(@moongrep.dump_expr_json_repr(array_push_call), content={
    "kind": "Expr::DotApply",
    "loc": null,
    "children": {
      "self": {
        "kind": "Expr::Ident",
        "loc": null,
        "children": {
          "id": {
            "kind": "Var",
            "loc": null,
            "children": {
              "name": {
                "kind": "LongIdent::Ident",
                "loc": null,
                "children": { "value": "_ARRAY" },
              },
            },
          },
        },
      },
      "method_name": {
        "kind": "Label",
        "loc": null,
        "children": { "name": "push" },
      },
      "args": {
        "kind": "Expr::DotApply::ArgList",
        "loc": null,
        "children": [
          {
            "kind": "Argument",
            "loc": null,
            "children": {
              "value": {
                "kind": "Expr::Ident",
                "loc": null,
                "children": {
                  "id": {
                    "kind": "Var",
                    "loc": null,
                    "children": {
                      "name": {
                        "kind": "LongIdent::Ident",
                        "loc": null,
                        "children": { "value": "_VALUE" },
                      },
                    },
                  },
                },
              },
              "kind": {
                "kind": "ArgumentKind::Positional",
                "loc": null,
                "children": {},
              },
            },
          },
        ],
      },
      "return_self": false,
      "attr": { "kind": "ApplyAttr::NoAttr", "loc": null, "children": {} },
    },
  })
}

///|
fn identify_array_push_call(
  name~ : String,
  source : String,
  locations : Array[Json],
) -> Unit raise {
  // pattern:
  // $ARRAY.push($VALUE)
  @moongrep.traverse_top_impls(name~, source, ast => match ast {
    {
      "kind": "Expr::DotApply",
      "loc": loc,
      "children": {
        "self": self_expr,
        "method_name": {
          "kind": "Label",
          "children": { "name": "push", .. },
          ..
        },
        "args": {
          "kind": "Expr::DotApply::ArgList",
          "children": [
            {
              "kind": "Argument",
              "children": {
                "value": arg,
                "kind": {
                  "kind": "ArgumentKind::Positional",
                  "children": { .. },
                  ..
                },
                ..
              },
              ..
            },
          ],
          ..
        },
        ..
      },
      ..
    } => {
      ignore(self_expr)
      ignore(arg)
      locations.push(loc)
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
  let locations = []
  identify_c99style_for_loop(name="foo", program, locations)
  json_inspect(locations, content=[
    {
      "file": "foo",
      "start": { "line": 9, "column": 2 },
      "end": { "line": 11, "column": 3 },
    },
  ])
}

///|
test {
  let program =
    #|fn foo() -> Unit {
    #|
    #| let arr = [1, 2, 3]
    #| let other = [4, 5]
    #|
    #| for i = 0; i < arr.length(); i = i + 1 {
    #|   println(arr[i])
    #| }
    #|
    #| if true {
    #|   for j = 1; j < other.length(); j = j + 1 {
    #|     println(other[j])
    #|   }
    #| }
    #|
    #|}
  let locations = []
  identify_c99style_for_loop(name="nested", program, locations)
  json_inspect(locations, content=[
    {
      "file": "nested",
      "start": { "line": 6, "column": 2 },
      "end": { "line": 8, "column": 3 },
    },
    {
      "file": "nested",
      "start": { "line": 11, "column": 4 },
      "end": { "line": 13, "column": 5 },
    },
  ])
}

///|
test {
  let program =
    #|fn foo() -> Unit {
    #|
    #| let arr = [1, 2, 3]
    #|
    #| for i in 0..<10 {
    #|   println(i)
    #| }
    #|
    #| for i = 0; i <= arr.length(); i = i + 1 {
    #|   println(arr[i])
    #| }
    #|
    #| for i = 0; i < arr.length(); i = i + 2 {
    #|   println(arr[i])
    #| }
    #|
    #| for i = 0; i < arr.length() - 1; i = i + 1 {
    #|   println(arr[i])
    #| }
    #|
    #|}
  let locations = []
  identify_c99style_for_loop(name="non_match", program, locations)
  json_inspect(locations, content=[])
}

///|
test {
  let program =
    #|fn foo() -> Unit {
    #|
    #| let x : Int? = None
    #| let y : Int? = Some(1)
    #| let z : Result[Int, String] = Ok(1)
    #|
    #| let _ = match x {
    #|   Some(v) => v
    #|   None => 0
    #| }
    #|
    #| let _ = match y {
    #|   None => 1
    #|   Some(v) => v + 1
    #| }
    #|
    #| let _ = match z {
    #|   Ok(v) => v
    #|   Err(_) => 0
    #| }
    #|}
  let locations = []
  identify_match_option_some_none(name="match_option", program, locations)
  json_inspect(locations, content=[
    {
      "file": "match_option",
      "start": { "line": 7, "column": 10 },
      "end": { "line": 10, "column": 3 },
    },
    {
      "file": "match_option",
      "start": { "line": 12, "column": 10 },
      "end": { "line": 15, "column": 3 },
    },
  ])
}

///|
test {
  let program =
    #|fn foo() -> Unit {
    #|
    #| let arr = []
    #| arr.push(1)
    #| arr.push(2)
    #| arr.pop()
    #| let other = [3]
    #| other.push(4)
    #|
    #| let nested = [[1], [2]]
    #| nested[0].push(3)
    #|}
  let locations = []
  identify_array_push_call(name="array_push", program, locations)
  json_inspect(locations, content=[
    {
      "file": "array_push",
      "start": { "line": 4, "column": 2 },
      "end": { "line": 4, "column": 13 },
    },
    {
      "file": "array_push",
      "start": { "line": 5, "column": 2 },
      "end": { "line": 5, "column": 13 },
    },
    {
      "file": "array_push",
      "start": { "line": 8, "column": 2 },
      "end": { "line": 8, "column": 15 },
    },
    {
      "file": "array_push",
      "start": { "line": 11, "column": 2 },
      "end": { "line": 11, "column": 19 },
    },
  ])
}
