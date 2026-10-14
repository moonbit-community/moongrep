# Windows junction traversal

```mooncram-import
grep : cli/grep@0.2.0
wc : cli/wc@0.2.0
```

## Scan-directory cycle

The setup script prepares a directory junction back to the scan root.
Source traversal follows the junction, reports the cycle as
skipped, and scans the source only once.

```mooncram moonbit-community/moongrep
$ moongrep scan --verbose --pattern 'target()' fs-walk-scan.tmp | grep -x 'rule: target()' | wc -l
1
```

The same traversal exposes its entering, skipping, and file events on stderr.

```mooncram moonbit-community/moongrep
$ moongrep scan --verbose --pattern 'target()' fs-walk-scan.tmp 1>/dev/null 2>&1 | grep -E '^moongrep scan: (entering|skipping|file) '
moongrep scan: entering fs-walk-scan.tmp
moongrep scan: skipping fs-walk-scan.tmp\again
moongrep scan: file fs-walk-scan.tmp\hit.mbt
```

## Rule-directory cycle

The setup script also prepares a rule directory with a junction back to itself.
Rule discovery follows the junction, stops at the already visited directory,
and reports one finding with no stderr output.

```mooncram moonbit-community/moongrep
$ moongrep scan --rules fs-walk-rules.tmp ../testdata/symlink/scan-dir-target/hit.mbt | grep -x 'rule: example' | wc -l
@STDOUT
1
@STDERR (empty)
```
