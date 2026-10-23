# Builtin rules

## Misspelled builtin rule ID

The former misspelled rule ID is rejected by `--disable`.

```mooncram moonbit-community/moongrep
$ moonx moonbit-community/moongrep lint --disable moonbitlang/unnessary_else ../testdata/builtin-rules-all/unnecessary_else.mbt
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
$ moonx moonbit-community/moongrep lint --json ../testdata/builtin-catch-all-variants | moonx cli/jq@0.2.1 -r '"\(.rule_id) \(.range.start.line):\(.range.start.column)"'
moonbitlang/catch_all 3:3
moonbitlang/catch_all 7:3
moonbitlang/catch_all 11:3
moonbitlang/catch_all 17:3
```

## Single-case match variants

Constructor matches with explicit unit wildcard fallbacks suggest `if` + `is`.
Guards, side effects in the fallback, extra arms, aliases, and or-patterns are
outside this rule's scope. A bare `{}` fallback can be an empty Map and must not
be assumed to be unit.

```mooncram moonbit-community/moongrep
$ moonx moonbit-community/moongrep lint --json ../testdata/builtin-match-single-case-variants | moonx cli/jq@0.2.1 -r '"\(.rule_id) \(.range.start.line):\(.range.start.column)"'
moonbitlang/match_single_case 3:3
moonbitlang/match_single_case 7:3
moonbitlang/match_single_case 14:3
```

## Simplifiable assignment variants

All twelve rule shapes are reported: local variables, fields, and indexed
values using `+`, `-`, `*`, or `/`, with the repeated target as the left operand.
The fixture also covers compound expressions in the other operand and string
suffix concatenation for all three target forms.

```mooncram moonbit-community/moongrep
$ moonx moonbit-community/moongrep lint --json ../testdata/builtin-simplifiable-assignment-variants/positive.mbt | moonx cli/jq@0.2.1 -r 'select(.rule_id == "moonbitlang/simplifiable_assignment") | "\(.range.start.line):\(.range.start.column) \(.matched_source | @json | .[1:-1])"'
12:3 add_left = add_left + step * 2
14:3 subtract = subtract - step
16:3 multiply_left = multiply_left * (step + 1)
18:3 divide = divide / step
26:3 target.add_left = target.add_left + step * 2
27:3 target.subtract = target.subtract - step
28:3 target.multiply_left = target.multiply_left * (step + 1)
29:3 target.divide = target.divide / step
34:3 target[0] = target[0] + step * 2
35:3 target[1] = target[1] - step
36:3 target[2] = target[2] * (step + 1)
37:3 target[3] = target[3] / step
51:3 text = text + \" world\"
52:3 target.text = target.text + \" world\"
53:3 values[0] = values[0] + \" world\"
```

The negative fixture checks unsupported operators, different local, field, or
indexed targets, different field receivers or indexed collections, all four
operators with the repeated target as the right operand, and existing augmented
assignments. The reversed cases include string prefix concatenation,
noncommutative overloaded multiplication, and integer addition with side
effects. The fixture produces no findings for this rule.

```mooncram moonbit-community/moongrep
$ moonx moonbit-community/moongrep lint --json ../testdata/builtin-simplifiable-assignment-variants/negative.mbt | moonx cli/jq@0.2.1 -s '[.[] | select(.rule_id == "moonbitlang/simplifiable_assignment")] | length'
0
```
