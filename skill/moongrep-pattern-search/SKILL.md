---
name: moongrep-pattern-search
description: Build and validate AST-grep pattern searches for the moongrep library using JSON AST patterns, labelled trees, and metavariables. Use when writing or debugging pattern JSON, compiling patterns from MoonBit source snippets, or interpreting grep match locations in tests.
---

# AstGrep Pattern Search (moongrep)

Use this skill to construct JSON AST patterns, compile patterns from source snippets, and run searches against parsed programs in this repo's astgrep engine.

## Core workflow

1) Parse program source into a labelled tree, then grep with a compiled pattern.
2) Build patterns as JSON AST with `MetaVariable` nodes for captures.
3) Read results as a map: match location -> capture name -> list of locations.

## Canonical search flow (from tests)

```mbt
///|
fn test_search(program : String, pattern : Json)
  -> Map[String, Map[String, Array[String]]] raise {
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
```

## Pattern construction rules

- Patterns are JSON ASTs that mirror parser output.
- Use `MetaVariable` nodes to capture subtrees, with a `name` field.
- For operators and identifiers, follow the `Var` + `LongIdent::Ident` structure.

### Example: `$A + $B * $C`

```mbt
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
```

### Example: C99-style for-loop

Capture the counter name, loop bound, and body:

```mbt
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
```

## Reading match output

- Output is `Map[String, Map[String, Array[String]]]`.
- Outer key: matched span location (e.g., `"2:13-2:31"`).
- Inner map: capture name to list of span locations.
- A capture can appear multiple times per match (e.g., `COUNT` in a for-loop).

## Optional: compile a pattern from source snippet

If you want to generate the JSON pattern from MoonBit source, parse the snippet and call `json_repr()`:

```mbt
///|
fn compile_pattern(pattern : String) -> Json {
  @basic.show_loc.val = String
  let (pattern, _) = @lexer.tokens_from_string(
      pattern,
      comment=true,
      name="pattern",
    ).tokens
    |> @handrolled_parser.parse_expr
  pattern.json_repr()
}
```
