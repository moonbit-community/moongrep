## Builtin rules

This fixture contains one hit for each embedded rule. The lint command checks
the stable rule order, each selected report range, and the explanatory
diagnostic shown with each match.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- lint testdata/builtin-rules-all
testdata/builtin-rules-all/catch_all.mbt:3:3-5:4
rule: moonbitlang/catch_all
description:
  Single catch arm handles every error, which can hide unexpected failures.
  Prefer matching only the specific error cases that can be recovered from.
source:
1 | ///|
2 | async fn catches_everything(_) -> Unit {
3 >   try risky() catch {
4 >     _ => recover()
5 >   }
6 | }

testdata/builtin-rules-all/match_option.mbt:3:3-11:4
rule: moonbitlang/match_option
description:
  Found an Option value handled with match over Some and None.
  Prefer if + is for simple Option checks.
source:
 1 | ///|
 2 | fn option_match(value : Int?) -> Bool {
 3 >   match value {
 4 >     Some(inner) => {
 5 >       let prepared = prepare(inner)
 . >       line 6-8: 3 matched lines omitted
 9 >     }
10 >     None => false
11 >   }
12 | }

testdata/builtin-rules-all/inspect_number.mbt:3:3-3:26
rule: moonbitlang/inspect_number
description:
  Found inspect() snapshots whose expected value is a plain number.
  Prefer numeric assertions for numeric checks.
source:
1 | ///|
2 | fn number_snapshot() -> Unit {
3 >   inspect(1, content="1")
4 | }

testdata/builtin-rules-all/unnessary_else.mbt:3:3-6:12
rule: moonbitlang/unnessary_else
description:
  Found an if expression whose else branch is empty or only returns ().
  Prefer omitting the unnecessary else branch.
source:
1 | ///|
2 | fn unnecessary_empty_else(flag : Bool) -> Unit {
3 >   if flag {
4 >     prepare()
5 >     finish()
6 >   } else {}
7 | }
8 | ///|

testdata/builtin-rules-all/inspect_boolean.mbt:3:3-3:32
rule: moonbitlang/inspect_boolean
description:
  Found inspect(), debug_inspect(), or json_inspect() snapshots whose expected value is true or false.
  Prefer assert_true(...) or assert_false(...) for boolean checks.
source:
1 | ///|
2 | fn boolean_snapshot(flag : Bool) -> Unit {
3 >   inspect(flag, content="true")
4 | }

testdata/builtin-rules-all/simplifiable_assignment.mbt:4:3-4:19
rule: moonbitlang/simplifiable_assignment
description:
  Assignment repeats its target as the operand of a binary expression.
  Prefer the corresponding augmented assignment, such as foo += 1, foo.bar += 1, foo[i] +=1.
  Note: Apply this rewrite only when the target expression and any index expression
  are free of side effects. Augmented assignment may evaluate them a different
  number of times.
source:
2 | fn simplifiable_assignment(step : Int) -> Int {
3 |   let mut foo = 0
4 >   foo = foo + step
5 |   foo
6 | }

testdata/builtin-rules-all/cstyle_forward_simple_forloop.mbt:3:3-5:4
rule: moonbitlang/cstyle_forward_simple_forloop
description:
  C-style forward for loops that can be rewritten as simple for-in loops.
source:
1 | ///|
2 | fn forward_simple_loop(limit : Int) -> Unit {
3 >   for i = 0; i < limit; i = i + 1 {
4 >     tick()
5 >   }
6 | }

testdata/builtin-rules-all/cstyle_backward_simple_forloop.mbt:3:3-5:4
rule: moonbitlang/cstyle_backward_simple_forloop
description:
  C-style backward for loops that can be rewritten as simple for-in loops.
source:
1 | ///|
2 | fn backward_simple_loop(limit : Int) -> Unit {
3 >   for i = limit; i > 0; i = i - 1 {
4 >     tick_back()
5 >   }
6 | }

testdata/builtin-rules-all/cstyle_forward_array_iteration.mbt:3:3-5:4
rule: moonbitlang/cstyle_forward_array_iteration
description:
  C-style forward array iteration that can be rewritten as simple for-in loops.
source:
1 | ///|
2 | fn forward_array_loop(items : Array[Int]) -> Unit {
3 >   for i = 0; i < items.length(); i = i + 1 {
4 >     consume(items[i])
5 >   }
6 | }

testdata/builtin-rules-all/cstyle_backward_array_iteration.mbt:3:3-5:4
rule: moonbitlang/cstyle_backward_array_iteration
description:
  C-style backward array iteration that can be rewritten as simple for-in loops.
source:
1 | ///|
2 | fn backward_array_loop(items : Array[Int]) -> Unit {
3 >   for i = items.length() - 1; i >= 0; i = i - 1 {
4 >     consume_reverse(items[i])
5 >   }
6 | }
```

## Builtin rules JSON output

The same builtin matches can be streamed as one JSON object per line. Each
record preserves the rule description, report range, matched source, and
annotated source context from the human-readable result.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- lint --output-json testdata/builtin-rules-all
{"type":"finding","file":"testdata/builtin-rules-all/catch_all.mbt","rule_id":"moonbitlang/catch_all","description":"Single catch arm handles every error, which can hide unexpected failures.\nPrefer matching only the specific error cases that can be recovered from.","range":{"start":{"line":3,"column":3},"end":{"line":5,"column":4}},"matched_source":"try risky() catch {\n    _ => recover()\n  }","source_context":[{"line":1,"text":"///|","is_match":false},{"line":2,"text":"async fn catches_everything(_) -> Unit {","is_match":false},{"line":3,"text":"  try risky() catch {","is_match":true},{"line":4,"text":"    _ => recover()","is_match":true},{"line":5,"text":"  }","is_match":true},{"line":6,"text":"}","is_match":false}]}
{"type":"finding","file":"testdata/builtin-rules-all/match_option.mbt","rule_id":"moonbitlang/match_option","description":"Found an Option value handled with match over Some and None.\nPrefer if + is for simple Option checks.","range":{"start":{"line":3,"column":3},"end":{"line":11,"column":4}},"matched_source":"match value {\n    Some(inner) => {\n      let prepared = prepare(inner)\n      let validated = validate(prepared)\n      let normalized = normalize(validated)\n      finish(normalized)\n    }\n    None => false\n  }","source_context":[{"line":1,"text":"///|","is_match":false},{"line":2,"text":"fn option_match(value : Int?) -> Bool {","is_match":false},{"line":3,"text":"  match value {","is_match":true},{"line":4,"text":"    Some(inner) => {","is_match":true},{"line":5,"text":"      let prepared = prepare(inner)","is_match":true},{"line":6,"text":"      let validated = validate(prepared)","is_match":true},{"line":7,"text":"      let normalized = normalize(validated)","is_match":true},{"line":8,"text":"      finish(normalized)","is_match":true},{"line":9,"text":"    }","is_match":true},{"line":10,"text":"    None => false","is_match":true},{"line":11,"text":"  }","is_match":true},{"line":12,"text":"}","is_match":false}]}
{"type":"finding","file":"testdata/builtin-rules-all/inspect_number.mbt","rule_id":"moonbitlang/inspect_number","description":"Found inspect() snapshots whose expected value is a plain number.\nPrefer numeric assertions for numeric checks.","range":{"start":{"line":3,"column":3},"end":{"line":3,"column":26}},"matched_source":"inspect(1, content=\"1\")","source_context":[{"line":1,"text":"///|","is_match":false},{"line":2,"text":"fn number_snapshot() -> Unit {","is_match":false},{"line":3,"text":"  inspect(1, content=\"1\")","is_match":true},{"line":4,"text":"}","is_match":false}]}
{"type":"finding","file":"testdata/builtin-rules-all/unnessary_else.mbt","rule_id":"moonbitlang/unnessary_else","description":"Found an if expression whose else branch is empty or only returns ().\nPrefer omitting the unnecessary else branch.","range":{"start":{"line":3,"column":3},"end":{"line":6,"column":12}},"matched_source":"if flag {\n    prepare()\n    finish()\n  } else {}","source_context":[{"line":1,"text":"///|","is_match":false},{"line":2,"text":"fn unnecessary_empty_else(flag : Bool) -> Unit {","is_match":false},{"line":3,"text":"  if flag {","is_match":true},{"line":4,"text":"    prepare()","is_match":true},{"line":5,"text":"    finish()","is_match":true},{"line":6,"text":"  } else {}","is_match":true},{"line":7,"text":"}","is_match":false},{"line":8,"text":"///|","is_match":false}]}
{"type":"finding","file":"testdata/builtin-rules-all/inspect_boolean.mbt","rule_id":"moonbitlang/inspect_boolean","description":"Found inspect(), debug_inspect(), or json_inspect() snapshots whose expected value is true or false.\nPrefer assert_true(...) or assert_false(...) for boolean checks.","range":{"start":{"line":3,"column":3},"end":{"line":3,"column":32}},"matched_source":"inspect(flag, content=\"true\")","source_context":[{"line":1,"text":"///|","is_match":false},{"line":2,"text":"fn boolean_snapshot(flag : Bool) -> Unit {","is_match":false},{"line":3,"text":"  inspect(flag, content=\"true\")","is_match":true},{"line":4,"text":"}","is_match":false}]}
{"type":"finding","file":"testdata/builtin-rules-all/simplifiable_assignment.mbt","rule_id":"moonbitlang/simplifiable_assignment","description":"Assignment repeats its target as the operand of a binary expression.\nPrefer the corresponding augmented assignment, such as foo += 1, foo.bar += 1, foo[i] +=1.\nNote: Apply this rewrite only when the target expression and any index expression\nare free of side effects. Augmented assignment may evaluate them a different\nnumber of times.","range":{"start":{"line":4,"column":3},"end":{"line":4,"column":19}},"matched_source":"foo = foo + step","source_context":[{"line":2,"text":"fn simplifiable_assignment(step : Int) -> Int {","is_match":false},{"line":3,"text":"  let mut foo = 0","is_match":false},{"line":4,"text":"  foo = foo + step","is_match":true},{"line":5,"text":"  foo","is_match":false},{"line":6,"text":"}","is_match":false}]}
{"type":"finding","file":"testdata/builtin-rules-all/cstyle_forward_simple_forloop.mbt","rule_id":"moonbitlang/cstyle_forward_simple_forloop","description":"C-style forward for loops that can be rewritten as simple for-in loops.","range":{"start":{"line":3,"column":3},"end":{"line":5,"column":4}},"matched_source":"for i = 0; i < limit; i = i + 1 {\n    tick()\n  }","source_context":[{"line":1,"text":"///|","is_match":false},{"line":2,"text":"fn forward_simple_loop(limit : Int) -> Unit {","is_match":false},{"line":3,"text":"  for i = 0; i < limit; i = i + 1 {","is_match":true},{"line":4,"text":"    tick()","is_match":true},{"line":5,"text":"  }","is_match":true},{"line":6,"text":"}","is_match":false}]}
{"type":"finding","file":"testdata/builtin-rules-all/cstyle_backward_simple_forloop.mbt","rule_id":"moonbitlang/cstyle_backward_simple_forloop","description":"C-style backward for loops that can be rewritten as simple for-in loops.","range":{"start":{"line":3,"column":3},"end":{"line":5,"column":4}},"matched_source":"for i = limit; i > 0; i = i - 1 {\n    tick_back()\n  }","source_context":[{"line":1,"text":"///|","is_match":false},{"line":2,"text":"fn backward_simple_loop(limit : Int) -> Unit {","is_match":false},{"line":3,"text":"  for i = limit; i > 0; i = i - 1 {","is_match":true},{"line":4,"text":"    tick_back()","is_match":true},{"line":5,"text":"  }","is_match":true},{"line":6,"text":"}","is_match":false}]}
{"type":"finding","file":"testdata/builtin-rules-all/cstyle_forward_array_iteration.mbt","rule_id":"moonbitlang/cstyle_forward_array_iteration","description":"C-style forward array iteration that can be rewritten as simple for-in loops.","range":{"start":{"line":3,"column":3},"end":{"line":5,"column":4}},"matched_source":"for i = 0; i < items.length(); i = i + 1 {\n    consume(items[i])\n  }","source_context":[{"line":1,"text":"///|","is_match":false},{"line":2,"text":"fn forward_array_loop(items : Array[Int]) -> Unit {","is_match":false},{"line":3,"text":"  for i = 0; i < items.length(); i = i + 1 {","is_match":true},{"line":4,"text":"    consume(items[i])","is_match":true},{"line":5,"text":"  }","is_match":true},{"line":6,"text":"}","is_match":false}]}
{"type":"finding","file":"testdata/builtin-rules-all/cstyle_backward_array_iteration.mbt","rule_id":"moonbitlang/cstyle_backward_array_iteration","description":"C-style backward array iteration that can be rewritten as simple for-in loops.","range":{"start":{"line":3,"column":3},"end":{"line":5,"column":4}},"matched_source":"for i = items.length() - 1; i >= 0; i = i - 1 {\n    consume_reverse(items[i])\n  }","source_context":[{"line":1,"text":"///|","is_match":false},{"line":2,"text":"fn backward_array_loop(items : Array[Int]) -> Unit {","is_match":false},{"line":3,"text":"  for i = items.length() - 1; i >= 0; i = i - 1 {","is_match":true},{"line":4,"text":"    consume_reverse(items[i])","is_match":true},{"line":5,"text":"  }","is_match":true},{"line":6,"text":"}","is_match":false}]}
```

## Catch-all async function variants

This focused fixture checks several async signatures and includes a synchronous
function with the same catch expression to make sure it is not reported.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- lint --output-json testdata/builtin-catch-all-variants | sed -n 's/.*"rule_id":"\([^"]*\)".*"range":{"start":{"line":\([0-9][0-9]*\),"column":\([0-9][0-9]*\)}.*/\1 \2:\3/p'
moonbitlang/catch_all 3:3
moonbitlang/catch_all 7:3
moonbitlang/catch_all 11:3
moonbitlang/catch_all 17:3
```

## Simplifiable assignment variants

All eighteen rule shapes are reported: local variables, fields, and indexed
values using `+`, `-`, `*`, or `/`, including both operand orders supported for
commutative operators and compound expressions in the other operand.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- lint --output-json testdata/builtin-simplifiable-assignment-variants/positive.mbt | sed -n 's#.*"rule_id":"moonbitlang/simplifiable_assignment".*"range":{"start":{"line":\([0-9][0-9]*\),"column":\([0-9][0-9]*\)}.*"matched_source":"\([^"]*\)".*#\1:\2 \3#p'
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

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- lint --output-json testdata/builtin-simplifiable-assignment-variants/negative.mbt | sed -n 's#"rule_id":"moonbitlang/simplifiable_assignment"#&#p' | wc -l
0
```

## moongrep lint builtin rules

Linting without a separate rule directory reports every embedded rule that
matches the fixture. The default human-readable output includes locations,
rule metadata, and source context.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- lint testdata/builtin-rules
testdata/builtin-rules/hit.mbt:3:3-3:26
rule: moonbitlang/inspect_number
description:
  Found inspect() snapshots whose expected value is a plain number.
  Prefer numeric assertions for numeric checks.
source:
1 | ///|
2 | fn has_builtin_hits(value : Int?) -> Unit {
3 >   inspect(1, content="1")
4 |   assert_true(
5 |     match value {

testdata/builtin-rules/hit.mbt:5:5-8:6
rule: moonbitlang/match_option
description:
  Found an Option value handled with match over Some and None.
  Prefer if + is for simple Option checks.
source:
 3 |   inspect(1, content="1")
 4 |   assert_true(
 5 >     match value {
 6 >       Some(inner) => inner > 0
 7 >       None => false
 8 >     },
 9 |   )
10 | }
```
