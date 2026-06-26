```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --verbose --pattern 'target()' testdata/symlink/scan-dir-link
moongrep scan: entering testdata/symlink/scan-dir-link
moongrep scan: file testdata/symlink/scan-dir-link/hit.mbt

testdata/symlink/scan-dir-link/hit.mbt:3:3-3:11
rule: target()
description:
  Anonymous CLI pattern.
source:
\x1b[90m1 | ///|\x1b[39m (escaped)
\x1b[90m2 | fn sample {\x1b[39m (escaped)
3 |   target()
\x1b[90m4 | }\x1b[39m (escaped)
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rules testdata/symlink/rules-dir-link testdata/symlink/scan-dir-link
testdata/symlink/scan-dir-link/hit.mbt:3:3-3:11
rule: example
description:
  Target call through symlinked rules.
source:
\x1b[90m1 | ///|\x1b[39m (escaped)
\x1b[90m2 | fn sample {\x1b[39m (escaped)
3 |   target()
\x1b[90m4 | }\x1b[39m (escaped)
```
