## Rule loading

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rules testdata/recursive-rule-discovery-rules testdata/recursive-rule-discovery-src
testdata/recursive-rule-discovery-src/hits.mbt:2:14-2:28
rule: example
description:
  Repeated equality.
source:
1 | fn sample {
2 >   let same = value == value
3 |   let x = get_user_input()
4 |   sink(x)

testdata/recursive-rule-discovery-src/hits.mbt:4:8-4:9
rule: nested/example
description:
  User input reaches sink.
source:
2 |   let same = value == value
3 |   let x = get_user_input()
4 >   sink(x)
5 | }
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rule testdata/recursive-rule-discovery-rules/nested/b.yml testdata/recursive-rule-discovery-src
testdata/recursive-rule-discovery-src/hits.mbt:4:8-4:9
rule: example
description:
  User input reaches sink.
source:
2 |   let same = value == value
3 |   let x = get_user_input()
4 >   sink(x)
5 | }
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rules testdata/empty-rule-root testdata/recursive-rule-discovery-src
InvalidRule(
  path="testdata/empty-rule-root",
  info="no YAML rule files found",
)
[1]
```
