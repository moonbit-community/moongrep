# Windows scan behavior

## Case-insensitive exclusions

Windows path exclusions are case-insensitive. Name, relative-path, and file
exclusions with different casing leave only the expected source file.

```mooncram
$ Set-Location "$env:TESTDIR/../.."; moonrun e2etests/moongrep.wasm -- scan -r e2etests/rules/structural --exclude IGNORED/ --exclude testdata/exclude-dirs/GENERATED/ --exclude EXCLUDED.MBT testdata/exclude-dirs
testdata\exclude-dirs\hit.mbt:1:13-1:21
rule: example
description:
  Target call.
source:
1 > fn sample { target() }
```

## Known non-BMP source crash

This is an intentionally failing regression test. The current implementation
crashes while extracting the matched source because the range ends on a line
containing non-BMP characters. Once that crash is fixed, the scan should
complete successfully.

```mooncram
$ Set-Location "$env:TESTDIR/../.."; moonrun e2etests/moongrep.wasm -- scan --pattern 'let $(name:id) = $(value:exp)' testdata/scan-non-bmp/tmp.mbt > $null
```
