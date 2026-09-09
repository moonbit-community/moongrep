# Inherited identifier scopes

The four report examples produce 0, 0, 1, and 0 findings respectively. Only
the accessor case matches; the other three reuse a different variable binding.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rules testdata/capture-scope/rules testdata/capture-scope/report.mbt
testdata/capture-scope/report.mbt:18:3-21:5
rule: field-origin
description:
  Local variables do not shadow accessor names.
source:
16 | 
17 | fn field {
18 >   wrapper(object.field, {
19 >     let field = source()
20 >     sink(object.field)
21 >   })
22 | }
23 | 
```

An `inside-toplevel` parameter capture checks the occurrence after the local
declaration in a multi-statement candidate. Only the second function matches.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rule testdata/capture-scope/parameter.yaml testdata/capture-scope/parameter.mbt
testdata/capture-scope/parameter.mbt:7:3-8:13
rule: parameter-origin
description:
  A parameter binding survives only where it is still visible.
source:
5 | 
6 | fn visible(item : Int) {
7 >   let other = source()
8 >   sink(item)
9 | }
```

Alias and quantifier captures must not crash the index. Each declaration is
inherited through `inside-toplevel` and a recursive `then`; only the four
functions without a shadowing local variable match.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rule testdata/capture-scope/wrapped.yaml testdata/capture-scope/wrapped.mbt
testdata/capture-scope/wrapped.mbt:4:24-4:68
rule: wrapped-origin
description:
  Alias and quantifier captures retain their declaration binding.
source:
2 | fn alias_visible(item : Int) {
3 |   match input {
4 >     Some(_) as item => middle({ let other = source(); sink(item) })
5 |   }
6 | }

testdata/capture-scope/wrapped.mbt:16:24-16:68
rule: wrapped-origin
description:
  Alias and quantifier captures retain their declaration binding.
source:
14 | fn regex_visible(item : Int) {
15 |   lexmatch input {
16 >     (re"a" as item) => middle({ let other = source(); sink(item) })
17 |   }
18 | }

testdata/capture-scope/wrapped.mbt:27:17-27:61
rule: wrapped-origin
description:
  Alias and quantifier captures retain their declaration binding.
source:
25 | ///|
26 | fn forall_visible(item : Int) {
27 >   ∀ item : Int, middle({ let other = source(); sink(item) })
28 | }
29 | ///|

testdata/capture-scope/wrapped.mbt:35:17-35:61
rule: wrapped-origin
description:
  Alias and quantifier captures retain their declaration binding.
source:
33 | ///|
34 | fn exists_visible(item : Int) {
35 >   ∃ item : Int, middle({ let other = source(); sink(item) })
36 | }
37 | ///|
```

Assignments and augmented assignments resolve the left-hand variable at its
occurrence. Only the two functions that preserve the outer binding match.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rule testdata/capture-scope/assignment.yaml testdata/capture-scope/assignment.mbt
testdata/capture-scope/assignment.mbt:9:3-9:49
rule: assignment-origin
description:
  Assignments match only the captured variable binding.
source:
 7 | fn assign_visible {
 8 |   let mut item = 0
 9 >   wrapper(item, { let mut other = 0; item = 1 })
10 | }
11 | ///|

testdata/capture-scope/assignment.mbt:19:3-19:50
rule: assignment-origin
description:
  Assignments match only the captured variable binding.
source:
17 | fn augmented_visible {
18 |   let mut item = 0
19 >   wrapper(item, { let mut other = 0; item += 1 })
20 | }
```

A parameter captured by `inside-toplevel` remains visible in a later
parameter's default value. The call in the default produces one finding.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rule testdata/capture-scope/default.yaml testdata/capture-scope/default.mbt
testdata/capture-scope/default.mbt:1:37-1:47
rule: default-origin
description:
  A default value sees the preceding parameter.
source:
1 > fn sample(item : Int, next~ : Int = sink(item)) {
2 |   ignore(next)
3 | }
```

A `for` update target captures the loop variable. The local `let i` in the
first loop shadows it, so only the second loop produces a finding.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rule testdata/capture-scope/for-update.yaml testdata/capture-scope/for-update.mbt
testdata/capture-scope/for-update.mbt:9:3-12:4
rule: for-update-origin
description:
  An update target refers to the loop variable.
source:
 7 | ///|
 8 | fn visible {
 9 >   for i = 0; i < 10; i = i + 1 {
10 >     let other = source()
11 >     sink(i)
12 >   }
13 | }
```
