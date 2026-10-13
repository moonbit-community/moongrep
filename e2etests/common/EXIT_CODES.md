# Exit status matrix

The success cases include help, findings, no findings, and recoverable source
warnings. Each command below exits with status 0.

```mooncram moonbit-community/moongrep
$ moongrep help
@STDOUT (ignore)
@STDERR (ignore)
```

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern 'target()' ../testdata/custom-rules
@STDOUT (ignore)
@STDERR (ignore)
```

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern 'missing()' ../testdata/custom-rules
@STDOUT (ignore)
@STDERR (ignore)
```

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern 'target()' ../testdata/parse-warning
@STDOUT (ignore)
@STDERR (ignore)
```

Status 1 is reserved for internal and otherwise unclassified failures, so it
has no user-input trigger. White-box tests cover its fixed mapping and the
unreachable command-state path.

Failure diagnostics are written to standard error. Discarding standard error
therefore leaves standard output empty while preserving the failure status.

```mooncram moonbit-community/moongrep
$ moongrep docs MissingDoc
[2]
```

For `scan --json`, mode selection happens before argparse rejects an
unknown option. Its complete multiline diagnostic is escaped inside one JSON
record on standard error.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --unknown
@STDOUT (ignore)
@STDERR
{"type":"error","category":"usage","exit_code":2,"message":"error: unexpected argument '--unknown' found\n\nUsage: moongrep scan [options] [scan-root]\n\nScan MoonBit source files.\n\nArguments:\n  scan-root  Directory or .mbt file to scan.\n\nOptions:\n  -h, --help           Show help information.\n  --verbose            Write loaded rule ids and traversal progress to stderr.\n  --json               Write JSON Lines findings to stdout and diagnostics to stderr.\n  -r, --rules <rules>  Directory containing YAML rules. [default: ./.moongrep/rules]\n  --rule <rule>        Single YAML rule file.\n  --pattern <pattern>  Anonymous structural pattern to match.\n  --guard <guard>      YAML guard map for the preceding anonymous pattern.\n  --exclude <exclude>  File or directory name or path to skip while recursively scanning. May be repeated.\n  --disable <disable>  Rule id to disable after loading rules. May be repeated.\n"}
[2]
```

Unknown documents are usage errors with status 2. Discarding standard output
exposes the diagnostic from standard error.

```mooncram moonbit-community/moongrep
$ moongrep docs MissingDoc
@STDOUT (ignore)
@STDERR
error: unknown document
  source: MissingDoc
  help: run `moongrep docs --list` to list embedded documents
[2]
```

Invalid dump input in exit-code mode still writes its diagnostic and uses
status 3.

```mooncram moonbit-community/moongrep
$ moongrep dump --exit-code --expr 'value +'
@STDOUT (ignore)
@STDERR
error: could not parse dump input
  source: dump --expr
  reason: Unexpected end of file, missing simple expression here.
  help: provide one valid MoonBit expression
[3]
```

An invalid anonymous pattern is a rule-content error with status 5.

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern '$$$items' ../testdata/ellipsis/sample.mbt
@STDOUT (ignore)
@STDERR
error: invalid anonymous pattern
  source: --pattern
  pattern:
    $$$items
  reason: the pattern uses ellipsis metavar $$$items outside a complete ordered CST list item
  help: fix the pattern passed to --pattern and try again
[5]
```

A qualified ignore placeholder is rejected with the same rule-content status.

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern '@html.$_' ../testdata/cli-pattern/hit.mbt
@STDOUT (ignore)
@STDERR
error: invalid anonymous pattern
  source: --pattern
  pattern:
    @html.$_
  reason: the pattern uses $_ in an unsupported qualified identifier position
  help: fix the pattern passed to --pattern and try again
[5]
```
