## Builtin rules

This fixture contains one hit for each embedded rule. The scan checks the
stable rule order, the selected inner and outer ranges, and the explanatory
diagnostic shown with each match.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --enable-builtin-rules testdata/builtin-rules-all
testdata/builtin-rules-all/catch_all.mbt:3:3-5:4
rule: moonbitlang/catch_all
outer_loc: testdata/builtin-rules-all/catch_all.mbt:2:1-6:2
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

testdata/builtin-rules-all/cstyle_forward_simple_forloop.mbt:3:3-5:4
rule: moonbitlang/cstyle_forward_simple_forloop
outer_loc: testdata/builtin-rules-all/cstyle_forward_simple_forloop.mbt:3:3-5:4
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
outer_loc: testdata/builtin-rules-all/cstyle_backward_simple_forloop.mbt:3:3-5:4
description:
  C-style backward for loops that can be rewritten as simple for-in loops.
source:
1 | ///|
2 | fn backward_simple_loop(limit : Int) -> Unit {
3 >   for i = limit; i > 0; i = i - 1 {
4 >     tick_back()
5 >   }
6 | }

testdata/builtin-rules-all/cstyle_forward_array_iteration.mbt:4:18-4:21
rule: moonbitlang/cstyle_forward_array_iteration
outer_loc: testdata/builtin-rules-all/cstyle_forward_array_iteration.mbt:3:3-5:4
description:
  C-style forward array iteration that can be rewritten as simple for-in loops.
source:
2 | fn forward_array_loop(items : Array[Int]) -> Unit {
3 |   for i = 0; i < items.length(); i = i + 1 {
4 >     consume(items[i])
5 |   }
6 | }

testdata/builtin-rules-all/cstyle_backward_array_iteration.mbt:4:26-4:29
rule: moonbitlang/cstyle_backward_array_iteration
outer_loc: testdata/builtin-rules-all/cstyle_backward_array_iteration.mbt:3:3-5:4
description:
  C-style backward array iteration that can be rewritten as simple for-in loops.
source:
2 | fn backward_array_loop(items : Array[Int]) -> Unit {
3 |   for i = items.length() - 1; i >= 0; i = i - 1 {
4 >     consume_reverse(items[i])
5 |   }
6 | }
```

## Builtin rules JSON output

The same builtin matches can be streamed as one JSON object per line. Each
record preserves the rule description, matched source, optional outer range,
and annotated source context from the human-readable result.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --enable-builtin-rules testdata/builtin-rules-all
{"file":"testdata/builtin-rules-all/catch_all.mbt","rule_id":"moonbitlang/catch_all","description":"Single catch arm handles every error, which can hide unexpected failures.\nPrefer matching only the specific error cases that can be recovered from.","range":{"start":{"line":3,"column":3},"end":{"line":5,"column":4}},"outer_range":{"start":{"line":2,"column":1},"end":{"line":6,"column":2}},"matched_source":"try risky() catch {\n    _ => recover()\n  }","source_context":[{"line":1,"text":"///|","is_match":false},{"line":2,"text":"async fn catches_everything(_) -> Unit {","is_match":false},{"line":3,"text":"  try risky() catch {","is_match":true},{"line":4,"text":"    _ => recover()","is_match":true},{"line":5,"text":"  }","is_match":true},{"line":6,"text":"}","is_match":false}]}
{"file":"testdata/builtin-rules-all/match_option.mbt","rule_id":"moonbitlang/match_option","description":"Found an Option value handled with match over Some and None.\nPrefer if + is for simple Option checks.","range":{"start":{"line":3,"column":3},"end":{"line":11,"column":4}},"outer_range":null,"matched_source":"match value {\n    Some(inner) => {\n      let prepared = prepare(inner)\n      let validated = validate(prepared)\n      let normalized = normalize(validated)\n      finish(normalized)\n    }\n    None => false\n  }","source_context":[{"line":1,"text":"///|","is_match":false},{"line":2,"text":"fn option_match(value : Int?) -> Bool {","is_match":false},{"line":3,"text":"  match value {","is_match":true},{"line":4,"text":"    Some(inner) => {","is_match":true},{"line":5,"text":"      let prepared = prepare(inner)","is_match":true},{"line":6,"text":"      let validated = validate(prepared)","is_match":true},{"line":7,"text":"      let normalized = normalize(validated)","is_match":true},{"line":8,"text":"      finish(normalized)","is_match":true},{"line":9,"text":"    }","is_match":true},{"line":10,"text":"    None => false","is_match":true},{"line":11,"text":"  }","is_match":true},{"line":12,"text":"}","is_match":false}]}
{"file":"testdata/builtin-rules-all/inspect_number.mbt","rule_id":"moonbitlang/inspect_number","description":"Found inspect() snapshots whose expected value is a plain number.\nPrefer numeric assertions for numeric checks.","range":{"start":{"line":3,"column":3},"end":{"line":3,"column":26}},"outer_range":null,"matched_source":"inspect(1, content=\"1\")","source_context":[{"line":1,"text":"///|","is_match":false},{"line":2,"text":"fn number_snapshot() -> Unit {","is_match":false},{"line":3,"text":"  inspect(1, content=\"1\")","is_match":true},{"line":4,"text":"}","is_match":false}]}
{"file":"testdata/builtin-rules-all/inspect_boolean.mbt","rule_id":"moonbitlang/inspect_boolean","description":"Found inspect(), debug_inspect(), or json_inspect() snapshots whose expected value is true or false.\nPrefer assert_true(...) or assert_false(...) for boolean checks.","range":{"start":{"line":3,"column":3},"end":{"line":3,"column":32}},"outer_range":null,"matched_source":"inspect(flag, content=\"true\")","source_context":[{"line":1,"text":"///|","is_match":false},{"line":2,"text":"fn boolean_snapshot(flag : Bool) -> Unit {","is_match":false},{"line":3,"text":"  inspect(flag, content=\"true\")","is_match":true},{"line":4,"text":"}","is_match":false}]}
{"file":"testdata/builtin-rules-all/cstyle_forward_simple_forloop.mbt","rule_id":"moonbitlang/cstyle_forward_simple_forloop","description":"C-style forward for loops that can be rewritten as simple for-in loops.","range":{"start":{"line":3,"column":3},"end":{"line":5,"column":4}},"outer_range":{"start":{"line":3,"column":3},"end":{"line":5,"column":4}},"matched_source":"for i = 0; i < limit; i = i + 1 {\n    tick()\n  }","source_context":[{"line":1,"text":"///|","is_match":false},{"line":2,"text":"fn forward_simple_loop(limit : Int) -> Unit {","is_match":false},{"line":3,"text":"  for i = 0; i < limit; i = i + 1 {","is_match":true},{"line":4,"text":"    tick()","is_match":true},{"line":5,"text":"  }","is_match":true},{"line":6,"text":"}","is_match":false}]}
{"file":"testdata/builtin-rules-all/cstyle_backward_simple_forloop.mbt","rule_id":"moonbitlang/cstyle_backward_simple_forloop","description":"C-style backward for loops that can be rewritten as simple for-in loops.","range":{"start":{"line":3,"column":3},"end":{"line":5,"column":4}},"outer_range":{"start":{"line":3,"column":3},"end":{"line":5,"column":4}},"matched_source":"for i = limit; i > 0; i = i - 1 {\n    tick_back()\n  }","source_context":[{"line":1,"text":"///|","is_match":false},{"line":2,"text":"fn backward_simple_loop(limit : Int) -> Unit {","is_match":false},{"line":3,"text":"  for i = limit; i > 0; i = i - 1 {","is_match":true},{"line":4,"text":"    tick_back()","is_match":true},{"line":5,"text":"  }","is_match":true},{"line":6,"text":"}","is_match":false}]}
{"file":"testdata/builtin-rules-all/cstyle_forward_array_iteration.mbt","rule_id":"moonbitlang/cstyle_forward_array_iteration","description":"C-style forward array iteration that can be rewritten as simple for-in loops.","range":{"start":{"line":4,"column":18},"end":{"line":4,"column":21}},"outer_range":{"start":{"line":3,"column":3},"end":{"line":5,"column":4}},"matched_source":"[i]","source_context":[{"line":2,"text":"fn forward_array_loop(items : Array[Int]) -> Unit {","is_match":false},{"line":3,"text":"  for i = 0; i < items.length(); i = i + 1 {","is_match":false},{"line":4,"text":"    consume(items[i])","is_match":true},{"line":5,"text":"  }","is_match":false},{"line":6,"text":"}","is_match":false}]}
{"file":"testdata/builtin-rules-all/cstyle_backward_array_iteration.mbt","rule_id":"moonbitlang/cstyle_backward_array_iteration","description":"C-style backward array iteration that can be rewritten as simple for-in loops.","range":{"start":{"line":4,"column":26},"end":{"line":4,"column":29}},"outer_range":{"start":{"line":3,"column":3},"end":{"line":5,"column":4}},"matched_source":"[i]","source_context":[{"line":2,"text":"fn backward_array_loop(items : Array[Int]) -> Unit {","is_match":false},{"line":3,"text":"  for i = items.length() - 1; i >= 0; i = i - 1 {","is_match":false},{"line":4,"text":"    consume_reverse(items[i])","is_match":true},{"line":5,"text":"  }","is_match":false},{"line":6,"text":"}","is_match":false}]}
```
