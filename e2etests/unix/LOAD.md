## Rule loading

Loading a rule directory discovers YAML files recursively. Rules at the root
keep their declared id, while rules below a subdirectory receive the relative
directory prefix, so both structural and taint matches are reported here.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rules testdata/recursive-rule-discovery-rules testdata/recursive-rule-discovery-src
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

Loading one YAML file with `--rule` runs only that rule and keeps its declared
id without the directory-derived prefix.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rule testdata/recursive-rule-discovery-rules/nested/b.yml testdata/recursive-rule-discovery-src
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

An existing rule directory with no YAML files is rejected before scanning and
returns rule-source status 4 with a direct diagnostic.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rules testdata/empty-rule-root testdata/recursive-rule-discovery-src 2>&1 >/dev/null
error: no rules found
  source: testdata/empty-rule-root
  reason: the directory contains no YAML rule files
  help: add a .yaml or .yml rule file or choose another --rules directory
[4]
```
