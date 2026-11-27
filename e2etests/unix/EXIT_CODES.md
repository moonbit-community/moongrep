# Exit diagnostics on Unix

An empty rule directory is a rule-source error with status 4.

```mooncram moonbit-community/moongrep
$ moonx moonbit-community/moongrep scan --rules ../testdata/empty-rule-root ../testdata/custom-rules
@STDOUT (ignore)
@STDERR
error: no rules found
  source: ../testdata/empty-rule-root
  reason: the directory contains no YAML rule files
  help: add a .yaml or .yml rule file or choose another --rules directory
[4]
```

A missing rule file keeps the OS reason separate from the path and operation.

```mooncram moonbit-community/moongrep
$ moonx moonbit-community/moongrep scan --rule ../testdata/missing-rule.yaml ../testdata/custom-rules
@STDOUT (empty)
@STDERR
error: could not read rule file
  source: ../testdata/missing-rule.yaml
  reason: No such file or directory
  help: check that the rule path exists and is readable
[4]
```

JSON output preserves the rule-source category and status 4.

```mooncram moonbit-community/moongrep
$ moonx moonbit-community/moongrep scan --json --rule ../testdata/missing-rule.yaml ../testdata/custom-rules
@STDOUT (empty)
@STDERR
{"type":"error","category":"rule_source","exit_code":4,"message":"could not read rule file","source":"../testdata/missing-rule.yaml","reason":"No such file or directory","help":"check that the rule path exists and is readable"}
[4]
```

Passing a directory to `--rule` exercises a read failure after opening. Its
diagnostic contains the OS reason without reader or filesystem internals.

```mooncram moonbit-community/moongrep
$ moonx moonbit-community/moongrep scan --rule ../testdata/custom-rules ../testdata/custom-rules
@STDOUT (empty)
@STDERR
error: could not read rule file
  source: ../testdata/custom-rules
  reason: Is a directory
  help: check that the rule path exists and is readable
[4]
```

The same read failure remains a rule-source error in JSON output.

```mooncram moonbit-community/moongrep
$ moonx moonbit-community/moongrep scan --json --rule ../testdata/custom-rules ../testdata/custom-rules
@STDOUT (empty)
@STDERR
{"type":"error","category":"rule_source","exit_code":4,"message":"could not read rule file","source":"../testdata/custom-rules","reason":"Is a directory","help":"check that the rule path exists and is readable"}
[4]
```

Malformed rule YAML produces a structured rule-content error with status 5
when JSON output is requested.

```mooncram moonbit-community/moongrep
$ moonx moonbit-community/moongrep scan --json --rule ../testdata/exit-codes/invalid.yaml ../testdata/custom-rules
@STDOUT (ignore)
@STDERR
{"type":"error","category":"rule_content","exit_code":5,"message":"invalid rule","source":"../testdata/exit-codes/invalid.yaml","reason":"line 2, column 1: while parsing a node, did not find expected node content","help":"fix the rule and try again"}
[5]
```

The same malformed YAML also produces a text diagnostic.

```mooncram moonbit-community/moongrep
$ moonx moonbit-community/moongrep scan --rule ../testdata/exit-codes/invalid.yaml ../testdata/custom-rules
@STDOUT (ignore)
@STDERR
error: invalid rule
  source: ../testdata/exit-codes/invalid.yaml
  reason: line 2, column 1: while parsing a node, did not find expected node content
  help: fix the rule and try again
[5]
```

A missing scan root is a scan-input error with status 6.

```mooncram moonbit-community/moongrep
$ moonx moonbit-community/moongrep scan --rules ../rules/structural ../testdata/does-not-exist
@STDOUT (ignore)
@STDERR
error: could not access scan path
  source: ../testdata/does-not-exist
  reason: No such file or directory
  help: check that the scan path exists and is readable
[6]
```

JSON mode also keeps scan-input failures on standard error and preserves status
6.

```mooncram moonbit-community/moongrep
$ moonx moonbit-community/moongrep scan --json --rules ../rules/structural ../testdata/does-not-exist
@STDOUT (ignore)
@STDERR
{"type":"error","category":"scan_input","exit_code":6,"message":"could not access scan path","source":"../testdata/does-not-exist","reason":"No such file or directory","help":"check that the scan path exists and is readable"}
[6]
```
