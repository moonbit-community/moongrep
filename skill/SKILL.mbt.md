---
name: moongrep
description: Create MoonBit AST matchers for structural search.
---

# Moongrep

## Overview

Use moongrep to search MoonBit source by matching AST JSON patterns. Follow the template -> JSON -> pattern -> traversal workflow in this guide.

## Workflow

### 1. Write a pattern template

Write the expression you want to match as a MoonBit multiline string inside a `test` block.

- Name the string `<pattern>`.
- Save it in `<path/to/pattern.mbt>`.
- Use `src/traverse_ast_test.mbt` as the reference for how to format patterns
  (e.g., `_ARRAY.push(_VALUE)`, `match _VALUE { Some(_ITEM) => _SOME_BODY ... }`,
  or the C99-style `for` loop).

### 2. Dump JSON from the template

Call `json_inspect(@moongrep.dump_expr_json_repr(<pattern>))` in the same test block, then run:

```bash
moon test <path/to/pattern.mbt> -u
moon fmt
```

Read the snapshot output to get the AST JSON for the template expression.

### 3. Convert JSON into a match pattern

Turn the JSON into a MoonBit pattern used in `match` expression:

- Keep the `kind` checks you care about.
- Replace literal meta names (e.g., `_ARRAY`) with pattern binds, usually `String(name)` for identifiers.
- Use `..` to ignore extra fields and `children` you do not need.
- Use `Null` to match JSON nulls (do not write `null`, which becomes a variable bind).
- Capture `loc` if you want to return locations.

Compare the dumped JSON and the hand-written JSON patterns in
`src/traverse_ast_test.mbt` to see the exact deltas. Typical edits shown there:

- Convert concrete names like `_ARRAY` into pattern binds:
  `LongIdent::Ident.value: String(array_name)` for identifiers.
- Bind repeated placeholders and enforce equality in code
  (e.g., `count_1 == count_2 == count_3 == count_4` for the C99 loop).
- Use helper predicates for reusable sub-patterns (e.g., `is_option_some_case`,
  `is_option_none_case`) and allow either order of cases.

### 4. Implement the matcher

Use the traversal helpers to walk AST JSON and match your pattern:

- Use `@moongrep.traverse_top_impls(name~, source, callback)` to parse a source
  string and traverse each top-level impl.
- Use `@moongrep.traverse_ast_json_repr(ast, callback)` when you already have a
  JSON tree.
- Return `true` from the callback to keep traversing, `false` to stop descent
  into that subtree.

Within the callback, match on the JSON object and push `loc` into your results
when it matches (see `identify_c99style_for_loop`, `identify_match_option_some_none`,
and `identify_array_push_call` in [example](./traverse_ast_test.mbt)).

## Notes

- Use `json_inspect` snapshots as the source of truth for AST structure
- re-run with `-u` whenever the template changes.
