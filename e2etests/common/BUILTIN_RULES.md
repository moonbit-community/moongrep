# Builtin rules

```mooncram-import
jq : cli/jq@0.2.1
```

## Misspelled builtin rule ID

The former misspelled rule ID is rejected by `--disable`.

```mooncram moonbit-community/moongrep
$ moongrep lint --disable moonbitlang/unnessary_else ../testdata/builtin-rules-all/unnecessary_else.mbt
@STDOUT (ignore)
@STDERR
error: unknown rule id in --disable
  source: moonbitlang/unnessary_else
  help: use the exact id of a loaded rule
[2]
```

## Catch-all async function variants

This focused fixture checks several async signatures and includes a synchronous
function with the same catch expression to make sure it is not reported.

```mooncram moonbit-community/moongrep
$ moongrep lint --json ../testdata/builtin-catch-all-variants | jq -r '"\(.rule_id) \(.range.start.line):\(.range.start.column)"'
moonbitlang/catch_all 3:3
moonbitlang/catch_all 7:3
moonbitlang/catch_all 11:3
moonbitlang/catch_all 17:3
```

## Simplifiable assignment variants

All eighteen rule shapes are reported: local variables, fields, and indexed
values using `+`, `-`, `*`, or `/`, including both operand orders supported for
commutative operators and compound expressions in the other operand.

```mooncram moonbit-community/moongrep
$ moongrep lint --json ../testdata/builtin-simplifiable-assignment-variants/positive.mbt | jq -r 'select(.rule_id == "moonbitlang/simplifiable_assignment") | "\(.range.start.line):\(.range.start.column) \(.matched_source | @json | .[1:-1])"'
14:3 add_left = add_left + step * 2
16:3 add_right = step * 2 + add_right
18:3 subtract = subtract - step
20:3 multiply_left = multiply_left * (step + 1)
22:3 multiply_right = (step + 1) * multiply_right
24:3 divide = divide / step
32:3 target.add_left = target.add_left + step * 2
33:3 target.add_right = step * 2 + target.add_right
34:3 target.subtract = target.subtract - step
35:3 target.multiply_left = target.multiply_left * (step + 1)
36:3 target.multiply_right = (step + 1) * target.multiply_right
37:3 target.divide = target.divide / step
42:3 target[0] = target[0] + step * 2
43:3 target[1] = step * 2 + target[1]
44:3 target[2] = target[2] - step
45:3 target[3] = target[3] * (step + 1)
46:3 target[4] = (step + 1) * target[4]
47:3 target[5] = target[5] / step
```

The negative fixture checks unsupported operators, different local, field, or
indexed targets, different field receivers or indexed collections, reversed
`-` and `/`, and existing augmented assignments. It produces no findings for
this rule.

```mooncram moonbit-community/moongrep
$ moongrep lint --json ../testdata/builtin-simplifiable-assignment-variants/negative.mbt | jq -s '[.[] | select(.rule_id == "moonbitlang/simplifiable_assignment")] | length'
0
```
