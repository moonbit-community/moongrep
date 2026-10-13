# Windows scan behavior

## Scan-root normalization

Windows scan roots accept both separator styles. Repeated separators and dot
components are normalized lexically, and the normalized relative path is used
in the finding.

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern 'target()' '.\..\testdata//exclude-dirs\ignored\..\.\hit.mbt'
..\testdata\exclude-dirs\hit.mbt:1:13-1:21
rule: target()
description:
  Anonymous CLI pattern.
source:
1 > fn sample { target() }
```

## Native recursive paths

Recursive scanning joins child paths with the native separator. Sorted
depth-first traversal reports the nested file before the next entry in the
parent directory.

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern 'target()' ../testdata/stream-order
..\testdata\stream-order\a\hit.mbt:2:3-2:11
rule: target()
description:
  Anonymous CLI pattern.
source:
1 | fn nested {
2 >   target()
3 | }

..\testdata\stream-order\a.mbt:2:3-2:11
rule: target()
description:
  Anonymous CLI pattern.
source:
1 | fn flat {
2 >   target()
3 | }
```

## Case-insensitive exclusions

Windows path exclusions use Unicode-aware case folding and normalized native
paths. Name, normalized relative-path, Unicode directory, and file exclusions
with different casing remove their entries. The default `target` exclusion
also removes the uppercase `TARGET` directory, leaving only the expected source
file.

```mooncram moonbit-community/moongrep
$ moongrep scan -r ../rules/structural --pattern 'unicode_marker()' --exclude IGNORED/ --exclude '.\..\testdata//exclude-dirs\generated\..\GENERATED\\' --exclude 'über' --exclude EXCLUDED.MBT ../testdata/exclude-dirs
..\testdata\exclude-dirs\hit.mbt:1:13-1:21
rule: example
description:
  Target call.
source:
1 > fn sample { target() }
```

## Explicit scan root

An exclusion applies only to entries found below a directory. It does not
remove an explicitly selected scan root with the same name.

```mooncram moonbit-community/moongrep
$ moongrep scan -r ../rules/structural --exclude hit.mbt ../testdata/exclude-dirs/hit.mbt
..\testdata\exclude-dirs\hit.mbt:1:13-1:21
rule: example
description:
  Target call.
source:
1 > fn sample { target() }
```
