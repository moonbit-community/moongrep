## Rule loading

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rules testdata/recursive-rule-discovery-rules testdata/recursive-rule-discovery-src
testdata/recursive-rule-discovery-src/hits.mbt:2:14-2:28
rule: example
description:
  Repeated equality.
source:
\x1b[90m1 | fn sample {\x1b[39m (escaped)
2 |   let same = value == value
\x1b[90m3 |   let x = get_user_input()\x1b[39m (escaped)
\x1b[90m4 |   sink(x)\x1b[39m (escaped)

testdata/recursive-rule-discovery-src/hits.mbt:4:8-4:9
rule: nested/example
description:
  User input reaches sink.
source:
\x1b[90m2 |   let same = value == value\x1b[39m (escaped)
\x1b[90m3 |   let x = get_user_input()\x1b[39m (escaped)
4 |   sink(x)
\x1b[90m5 | }\x1b[39m (escaped)
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rule testdata/recursive-rule-discovery-rules/nested/b.yml testdata/recursive-rule-discovery-src
testdata/recursive-rule-discovery-src/hits.mbt:4:8-4:9
rule: example
description:
  User input reaches sink.
source:
\x1b[90m2 |   let same = value == value\x1b[39m (escaped)
\x1b[90m3 |   let x = get_user_input()\x1b[39m (escaped)
4 |   sink(x)
\x1b[90m5 | }\x1b[39m (escaped)
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rules testdata/empty-rule-root testdata/recursive-rule-discovery-src
InvalidRule(
  path="testdata/empty-rule-root",
  info="no YAML rule files found",
)
[1]
```
