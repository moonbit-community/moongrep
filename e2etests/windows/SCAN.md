# Windows scan behavior

## Scan-root normalization

Windows scan roots accept both separator styles. Repeated separators and dot
components are normalized lexically, and the normalized relative path is used
in the finding.

```mooncram
$ Set-Location "$env:TESTDIR/../.."; moonrun e2etests/moongrep.wasm -- scan --pattern 'target()' '.\testdata//exclude-dirs\ignored\..\.\hit.mbt'
testdata\exclude-dirs\hit.mbt:1:13-1:21
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

```mooncram
$ Set-Location "$env:TESTDIR/../.."; moonrun e2etests/moongrep.wasm -- scan --pattern 'target()' testdata/stream-order
testdata\stream-order\a\hit.mbt:2:3-2:11
rule: target()
description:
  Anonymous CLI pattern.
source:
1 | fn nested {
2 >   target()
3 | }

testdata\stream-order\a.mbt:2:3-2:11
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

```mooncram
$ Set-Location "$env:TESTDIR/../.."; moonrun e2etests/moongrep.wasm -- scan -r e2etests/rules/structural --pattern 'unicode_marker()' --exclude IGNORED/ --exclude '.\testdata//exclude-dirs\generated\..\GENERATED\\' --exclude "$([char]0x00FC)ber" --exclude EXCLUDED.MBT testdata/exclude-dirs
testdata\exclude-dirs\hit.mbt:1:13-1:21
rule: example
description:
  Target call.
source:
1 > fn sample { target() }
```

## Explicit scan root

An exclusion applies only to entries found below a directory. It does not
remove an explicitly selected scan root with the same name.

```mooncram
$ Set-Location "$env:TESTDIR/../.."; moonrun e2etests/moongrep.wasm -- scan -r e2etests/rules/structural --exclude hit.mbt testdata/exclude-dirs/hit.mbt
testdata\exclude-dirs\hit.mbt:1:13-1:21
rule: example
description:
  Target call.
source:
1 > fn sample { target() }
```

## Case-sensitive source suffix

Windows filesystem lookup is case-insensitive, but the source suffix check is
not. An explicitly selected `.MBT` file is not scanned as a lowercase `.mbt`
source file.

```mooncram
$ Set-Location "$env:TESTDIR/../.."; moonrun e2etests/moongrep.wasm -- scan --pattern 'target()' testdata/exclude-dirs/uppercase.MBT
no match hits
```

## Non-BMP source

Scanning a match whose range ends on a line containing non-BMP characters
completes successfully.

```mooncram
$ Set-Location "$env:TESTDIR/../.."; moonrun e2etests/moongrep.wasm -- scan --pattern 'let $(name:id) = $(value:exp)' testdata/scan-non-bmp/tmp.mbt > $null
```
