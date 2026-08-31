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
error: unknown document
  source: MissingDoc
  help: run `moongrep docs --list` to list embedded documents
[2]
```

Invalid dump input uses status 3.

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- dump --expr 'value +' 2>&1 > /dev/null
error: could not parse dump input
  source: dump --expr
  reason: Unexpected end of file, missing simple expression here.
  help: provide one valid MoonBit expression
[3]
```

An empty rule directory is a rule-source error with status 4.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rules testdata/empty-rule-root testdata/custom-rules 2>&1 > /dev/null
error: no rules found
  source: testdata/empty-rule-root
  reason: the directory contains no YAML rule files
  help: add a .yaml or .yml rule file or choose another --rules directory
[4]
```

An invalid anonymous pattern is a rule-content error with status 5.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --pattern '$$$items' testdata/ellipsis/sample.mbt 2>&1 > /dev/null
error: invalid anonymous pattern
  source: --pattern
  pattern:
    $$$items
  reason: the pattern uses ellipsis metavar $$$items outside a complete ordered CST list item
  help: fix the pattern passed to --pattern and try again
[5]
```

A qualified ignore placeholder is rejected with the same rule-content status.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --pattern '@html.$_' testdata/cli-pattern/hit.mbt 2>&1 > /dev/null
error: invalid anonymous pattern
  source: --pattern
  pattern:
    @html.$_
  reason: the pattern uses $_ in an unsupported qualified identifier position
  help: fix the pattern passed to --pattern and try again
[5]
```

Malformed rule YAML is in the same rule-content category.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rule testdata/exit-codes/invalid.yaml testdata/custom-rules 2>&1 > /dev/null
error: invalid rule
  source: testdata/exit-codes/invalid.yaml
  reason: line 2, column 1: while parsing a node, did not find expected node content
  help: fix the rule and try again
[5]
```

A missing scan root is a scan-input error with status 6.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rules e2etests/rules/structural testdata/does-not-exist 2>&1 > /dev/null
error: could not access scan path
  source: testdata/does-not-exist
  reason: No such file or directory
  help: check that the scan path exists and is readable
[6]
```

A broken standard-output pipe takes precedence and uses status 7.

```mooncram
$ bash -o pipefail -c 'moonrun "$1"/../moongrep.wasm -- docs CLISpec | head -n 0' _ "$TESTDIR" 2>&1 >/dev/null
error: could not write output
  source: standard output
  reason: Broken pipe
  help: check the output destination or downstream command
[7]
```
