# Exit status matrix

The success cases include help, findings, no findings, and recoverable source
warnings. Each command below exits with status 0.

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- help > /dev/null
```

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --pattern 'target()' testdata/custom-rules > /dev/null
```

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --pattern 'missing()' testdata/custom-rules > /dev/null
```

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --pattern 'target()' testdata/parse-warning > /dev/null 2> /dev/null
```

Status 1 is reserved for internal and otherwise unclassified failures, so it
has no user-input trigger. White-box tests cover its fixed mapping and the
unreachable command-state path.

Unknown documents are usage errors with status 2.

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- docs MissingDoc > /dev/null
[2]
```

Invalid dump input uses status 3.

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- dump --expr 'value +' > /dev/null
[3]
```

An empty rule directory is a rule-source error with status 4.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rules testdata/empty-rule-root testdata/custom-rules > /dev/null
[4]
```

An invalid anonymous pattern is a rule-content error with status 5.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --pattern '$$$items' testdata/ellipsis/sample.mbt > /dev/null
[5]
```

Malformed rule YAML is in the same rule-content category.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rule testdata/exit-codes/invalid.yaml testdata/custom-rules > /dev/null
[5]
```

A missing scan root is a scan-input error with status 6.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rules e2etests/rules/structural testdata/does-not-exist > /dev/null
[6]
```

A broken standard-output pipe takes precedence and uses status 7.

```mooncram
$ bash -o pipefail -c 'moonrun "$1"/../moongrep.wasm -- docs CLISpec | head -n 0' _ "$TESTDIR"
[7]
```
