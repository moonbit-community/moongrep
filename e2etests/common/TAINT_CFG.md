# Incomplete taint analysis

Unsupported executable syntax skips the affected function, warns, and keeps
scanning other functions. Strict mode finishes the scan and returns status 8.
The cases run from the fixture directory so filenames in both output streams
are independent of platform path separators.

```mooncram moonbit-community/moongrep
#cwd(../testdata/taint-cfg)
$ moonx moonbit-community/moongrep scan --rule rules.yaml --json unsupported.mbt
@STDOUT
{"type":"finding","file":"unsupported.mbt","rule_id":"cfg","description":"CFG analysis.","range":{"start":{"line":9,"column":8},"end":{"line":9,"column":16}},"matched_source":"source()","source_context":[{"line":7,"text":"///|","is_match":false},{"line":8,"text":"fn supported {","is_match":false},{"line":9,"text":"  sink(source())","is_match":true},{"line":10,"text":"}","is_match":false}]}
@STDERR
{"type":"warning","category":"taint_incomplete","message":"taint_incomplete: unsupported.mbt:3:16-3:34: rules cfg: unsupported executable syntax Expr_ListComprehension","file":"unsupported.mbt","range":{"start":{"line":3,"column":16},"end":{"line":3,"column":34}},"rule_ids":["cfg"],"reason":"unsupported executable syntax Expr_ListComprehension"}
```

```mooncram moonbit-community/moongrep
#cwd(../testdata/taint-cfg)
$ moonx moonbit-community/moongrep scan --rule rules.yaml --json --strict-taint unsupported.mbt
@STDOUT
{"type":"finding","file":"unsupported.mbt","rule_id":"cfg","description":"CFG analysis.","range":{"start":{"line":9,"column":8},"end":{"line":9,"column":16}},"matched_source":"source()","source_context":[{"line":7,"text":"///|","is_match":false},{"line":8,"text":"fn supported {","is_match":false},{"line":9,"text":"  sink(source())","is_match":true},{"line":10,"text":"}","is_match":false}]}
@STDERR
{"type":"warning","category":"taint_incomplete","message":"taint_incomplete: unsupported.mbt:3:16-3:34: rules cfg: unsupported executable syntax Expr_ListComprehension","file":"unsupported.mbt","range":{"start":{"line":3,"column":16},"end":{"line":3,"column":34}},"rule_ids":["cfg"],"reason":"unsupported executable syntax Expr_ListComprehension"}
{"type":"error","category":"taint_incomplete","exit_code":8,"message":"taint analysis incomplete","reason":"see taint_incomplete warnings for skipped functions and rules"}
[8]
```

A divergent SCC suppresses all findings for that function and rule, including
findings encountered before the SCC. Later functions still produce findings.

```mooncram moonbit-community/moongrep
#cwd(../testdata/taint-cfg)
$ moonx moonbit-community/moongrep scan --rule rules.yaml --json --strict-taint growth.mbt
@STDOUT (ignore)
@STDERR (ignore)
[8]
```

A parse failure that prevents taint analysis also counts toward strict mode.

```mooncram moonbit-community/moongrep
#cwd(../testdata/taint-cfg)
$ moonx moonbit-community/moongrep scan --rule rules.yaml --json --strict-taint parse.mbt
@STDOUT (ignore)
@STDERR (ignore)
[8]
```
