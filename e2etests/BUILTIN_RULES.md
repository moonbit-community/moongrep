## Builtin rules

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

testdata/builtin-rules-all/match_option.mbt:3:3-6:4
rule: moonbitlang/match_option
description:
  Found an Option value handled with match over Some and None.
  Prefer if + is for simple Option checks.
source:
1 | ///|
2 | fn option_match(value : Int?) -> Bool {
3 >   match value {
4 >     Some(inner) => inner > 0
5 >     None => false
6 >   }
7 | }

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
