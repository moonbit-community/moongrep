## Symlink traversal

A symlink can be used as the scan root. The scanner follows the linked
directory and reports the matched file through the path supplied on the
command line. The target contains `again -> .`; traversal skips that cycle.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --verbose --pattern 'target()' testdata/symlink/scan-dir-link
testdata/symlink/scan-dir-link/hit.mbt:3:3-3:11
rule: target()
description:
  Anonymous CLI pattern.
source:
1 | ///|
2 | fn sample {
3 >   target()
4 | }
```

Verbose traversal reports the cycle through the existing skipped-path event.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --verbose --pattern 'target()' testdata/symlink/scan-dir-link 2>&1 >/dev/null
moongrep scan: loaded rule target()
moongrep scan: entering testdata/symlink/scan-dir-link
moongrep scan: skipping testdata/symlink/scan-dir-link/again
moongrep scan: file testdata/symlink/scan-dir-link/hit.mbt
```

A symlink can also be used as the rule directory. Rule discovery follows the
link while the scan root continues to use its own symlinked path. The rule
target also contains `again -> .`, which is skipped during discovery.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rules testdata/symlink/rules-dir-link testdata/symlink/scan-dir-link
testdata/symlink/scan-dir-link/hit.mbt:3:3-3:11
rule: example
description:
  Target call through symlinked rules.
source:
1 | ///|
2 | fn sample {
3 >   target()
4 | }
```
