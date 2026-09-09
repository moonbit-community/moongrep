# CST capture regressions

Separate type and constructor captures remain addressable through
`inside-toplevel` and recursive `then`. This valid rule produces one finding.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rule testdata/capture-scope/constructor.yaml testdata/capture-scope/constructor.mbt
testdata/capture-scope/constructor.mbt:3:28-3:47
rule: split-constructor
description:
  Type and constructor captures remain separate across rule levels.
source:
1 | fn sample {
2 |   match input {
3 >     Option::Some(value) => middle(sink(value))
4 |   }
5 | }
```

Explicit `before` and `after` binders in `lexscan` and `=~` preserve their
binding identity across rule levels. Only the four functions with `let other`
produce findings; the four functions with `let item` shadow the capture.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rule testdata/capture-scope/regex.yaml testdata/capture-scope/regex.mbt
testdata/capture-scope/regex.mbt:10:29-10:73
rule: regex-origin
description:
  Explicit regex captures retain their declaration binding.
source:
 8 | fn lexscan_before_visible {
 9 |   lexscan input {
10 >     (re"a", before=item) => middle({ let other = source(); sink(item) })
11 |   }
12 | }

testdata/capture-scope/regex.mbt:22:28-22:72
rule: regex-origin
description:
  Explicit regex captures retain their declaration binding.
source:
20 | fn lexscan_after_visible {
21 |   lexscan input {
22 >     (re"a", after=item) => middle({ let other = source(); sink(item) })
23 |   }
24 | }

testdata/capture-scope/regex.mbt:34:5-34:49
rule: regex-origin
description:
  Explicit regex captures retain their declaration binding.
source:
32 | fn regex_before_visible {
33 |   if input =~ (re"a", before=item) {
34 >     middle({ let other = source(); sink(item) })
35 |   }
36 | }

testdata/capture-scope/regex.mbt:46:5-46:49
rule: regex-origin
description:
  Explicit regex captures retain their declaration binding.
source:
44 | fn regex_after_visible {
45 |   if input =~ (re"a", after=item) {
46 >     middle({ let other = source(); sink(item) })
47 |   }
48 | }
```
