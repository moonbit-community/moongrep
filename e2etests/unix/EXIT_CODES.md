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

Failure diagnostics are written to standard error. Discarding standard error
therefore leaves standard output empty while preserving the failure status.

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- docs MissingDoc 2> /dev/null
[2]
```

Unknown documents are usage errors with status 2. Discarding standard output
exposes the diagnostic from standard error.

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- docs MissingDoc 2>&1 > /dev/null
unknown document: MissingDoc
[2]
```

Invalid dump input uses status 3.

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- dump --expr 'value +' 2>&1 > /dev/null
dump --expr parse failed: Unexpected end of file, missing simple expression here.
[3]
```

An empty rule directory is a rule-source error with status 4.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rules testdata/empty-rule-root testdata/custom-rules 2>&1 > /dev/null
testdata/empty-rule-root: no YAML rule files found
[4]
```

An invalid anonymous pattern is a rule-content error with status 5.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --pattern '$$$items' testdata/ellipsis/sample.mbt 2>&1 > /dev/null
$$$items: patterns[0].shape uses ellipsis metavar $$$items outside a complete ordered CST list item
[5]
```

Malformed rule YAML is in the same rule-content category.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rule testdata/exit-codes/invalid.yaml testdata/custom-rules 2>&1 > /dev/null
testdata/exit-codes/invalid.yaml: YamlError(
  mark={ index: 2, line: 2, col: 0 },
  info="while parsing a node, did not find expected node content",
)
[5]
```

A missing scan root is a scan-input error with status 6.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rules e2etests/rules/structural testdata/does-not-exist 2>&1 > /dev/null
OSError("@fs.kind(): \"testdata/does-not-exist\": No such file or directory")
[6]
```

A broken standard-output pipe takes precedence and uses status 7.

```mooncram
$ bash -o pipefail -c 'moonrun "$1"/../moongrep.wasm -- docs CLISpec | head -n 0' _ "$TESTDIR" 2>&1 >/dev/null
OSError("@stdio.Output::write(): Broken pipe")
[7]
```
