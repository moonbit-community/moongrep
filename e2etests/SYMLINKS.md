```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --verbose --pattern 'target()' testdata/symlink/scan-dir-link
moongrep scan: loaded rule target()
moongrep scan: entering testdata/symlink/scan-dir-link
moongrep scan: file testdata/symlink/scan-dir-link/hit.mbt

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

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rules testdata/symlink/rules-dir-link testdata/symlink/scan-dir-link
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
