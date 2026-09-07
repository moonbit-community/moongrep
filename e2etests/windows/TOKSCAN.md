# Windows token search

Repeated patterns preserve separate, overlapping results in start and pattern order.

```mooncram
$ Set-Location "$env:TESTDIR/../.."; moonrun e2etests/moongrep.wasm -- tokscan --pattern 'a a' --pattern='a a a' --pattern 'a a' testdata/tokscan/overlap.mbt
testdata\tokscan\overlap.mbt:1:1-1:4
pattern:
  a a
source:
1 > a a a

testdata\tokscan\overlap.mbt:1:1-1:6
pattern:
  a a a
source:
1 > a a a

testdata\tokscan\overlap.mbt:1:1-1:4
pattern:
  a a
source:
1 > a a a

testdata\tokscan\overlap.mbt:1:3-1:6
pattern:
  a a
source:
1 > a a a

testdata\tokscan\overlap.mbt:1:3-1:6
pattern:
  a a
source:
1 > a a a
```

Traversal is sorted depth-first and uses native path separators.

```mooncram
$ Set-Location "$env:TESTDIR/../.."; moonrun e2etests/moongrep.wasm -- tokscan --pattern 'target()' testdata/stream-order
testdata\stream-order\a\hit.mbt:2:3-2:11
pattern:
  target()
source:
1 | fn nested {
2 >   target()
3 | }

testdata\stream-order\a.mbt:2:3-2:11
pattern:
  target()
source:
1 | fn flat {
2 >   target()
3 | }
```

Matches cannot cross source blocks.

```mooncram
$ Set-Location "$env:TESTDIR/../.."; moonrun e2etests/moongrep.wasm -- tokscan --pattern 'a;b' testdata/tokscan/blocks.mbt
no match hits
```

Skip attributes remain searchable; Unicode columns and dot prefixes are preserved.

```mooncram
$ Set-Location "$env:TESTDIR/../.."; moonrun e2etests/moongrep.wasm -- tokscan --pattern 'target(1)' --pattern '#moongrep.skip' --pattern '.field' testdata/tokscan/blocks.mbt
testdata\tokscan\blocks.mbt:5:1-5:15
pattern:
  #moongrep.skip
source:
3 | b
4 | ///|
5 > #moongrep.skip
6 | target(1)
7 | ///|

testdata\tokscan\blocks.mbt:6:1-6:10
pattern:
  target(1)
source:
4 | ///|
5 | #moongrep.skip
6 > target(1)
7 | ///|
8 | "😀".field

testdata\tokscan\blocks.mbt:8:4-8:10
pattern:
  .field
source:
6 | target(1)
7 | ///|
8 > "😀".field
```

Lexical errors skip entire blocks; later blocks remain searchable despite invalid syntax.

```mooncram
$ Set-Location "$env:TESTDIR/../.."; moonrun e2etests/moongrep.wasm -- tokscan --pattern 'target(1)' --pattern 'let = + )' testdata/tokscan/warnings.mbt
testdata\tokscan\warnings.mbt:10:1-10:10
pattern:
  let = + )
source:
 8 | "\{$bad}"
 9 | ///|
10 > let = + )
11 | target ( 1 )

testdata\tokscan\warnings.mbt:11:1-11:13
pattern:
  target(1)
source:
 9 | ///|
10 | let = + )
11 > target ( 1 )
```

All patterns are validated before file access, in input order.

```mooncram
$ Set-Location "$env:TESTDIR/../.."; $tokOutput = @(moonrun e2etests/moongrep.wasm -- tokscan --pattern a --pattern '#tag($bad)' --pattern= missing-root 2>&1); $tokStatus = $LASTEXITCODE; $tokOutput | ForEach-Object { [Console]::Out.WriteLine([string]$_) }; $global:LASTEXITCODE = $tokStatus
error: invalid tokscan pattern 2
  source: --pattern 2
  pattern:
    #tag($bad)
  reason: attribute #tag: line 1, column 2: unrecognized character u32: $
[2]
```

An empty pattern is a usage error.

```mooncram
$ $tokOutput = @(moonrun "$env:TESTDIR/../moongrep.wasm" -- tokscan --pattern= 2>&1); $tokStatus = $LASTEXITCODE; $tokOutput | ForEach-Object { [Console]::Out.WriteLine([string]$_) }; $global:LASTEXITCODE = $tokStatus
error: invalid tokscan pattern 1
  source: --pattern 1
  pattern:
  reason: pattern contains no tokens
[2]
```

A root without any pattern is a usage error.

```mooncram
$ $tokOutput = @(moonrun "$env:TESTDIR/../moongrep.wasm" -- tokscan src 2>&1); $tokStatus = $LASTEXITCODE; $tokOutput | ForEach-Object { [Console]::Out.WriteLine([string]$_) }; $global:LASTEXITCODE = $tokStatus
error: tokscan requires at least one --pattern
[2]
```

Mixed separators and dot components are normalized in explicit roots.

```mooncram
$ Set-Location "$env:TESTDIR/../.."; moonrun e2etests/moongrep.wasm -- tokscan --pattern 'a a a' '.\testdata//tokscan\ignored\..\.\overlap.mbt'
testdata\tokscan\overlap.mbt:1:1-1:6
pattern:
  a a a
source:
1 > a a a
```

Warnings use stderr, no matches still use stdout, and completion returns 0.

```mooncram
$ Set-Location "$env:TESTDIR/../.."; $tokStreams = @(moonrun e2etests/moongrep.wasm -- tokscan --pattern absent testdata/tokscan/warnings.mbt 2>&1); $tokStatus = $LASTEXITCODE; $tokOutput = @($tokStreams | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }); $tokError = @($tokStreams | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }); "status: $tokStatus"; $tokOutput; $tokError | ForEach-Object { [Console]::Out.WriteLine([string]$_) }; $global:LASTEXITCODE = $tokStatus
status: 0
no match hits
warning: skipping testdata\tokscan\warnings.mbt block starting at line 1: lexing failed: line 2, column 1: unrecognized character u32: $
warning: skipping testdata\tokscan\warnings.mbt block starting at line 3: lexing failed: attribute #tag: line 1, column 2: unrecognized character u32: $
warning: skipping testdata\tokscan\warnings.mbt block starting at line 6: lexing failed: interpolation: line 1, column 1: unrecognized character u32: $
```

A missing root retains status 6.

```mooncram
$ Set-Location "$env:TESTDIR/../.."; $tokOutput = @(moonrun e2etests/moongrep.wasm -- tokscan --pattern a missing-tokscan-root 2>&1); $tokStatus = $LASTEXITCODE; "status: $tokStatus"; "diagnostic: $([bool]($tokOutput -match 'could not access scan path'))"; $global:LASTEXITCODE = $tokStatus
status: 6
diagnostic: True
[6]
```

No arguments prints the same help as --help, and an omitted root uses `.`.

```mooncram
$ $plain = @(moonrun "$env:TESTDIR/../moongrep.wasm" -- tokscan); $plainStatus = $LASTEXITCODE; $helpOutput = @(moonrun "$env:TESTDIR/../moongrep.wasm" -- tokscan --help); "status: $plainStatus"; "same help: $(($plain -join "`n") -eq ($helpOutput -join "`n"))"
status: 0
same help: True
```

```mooncram
$ Set-Location "$env:TESTDIR/../../testdata/stream-order"; $implicit = @(moonrun "$env:TESTDIR/../moongrep.wasm" -- tokscan --pattern 'target()'); $explicit = @(moonrun "$env:TESTDIR/../moongrep.wasm" -- tokscan --pattern 'target()' .); "same root: $(($implicit -join "`n") -eq ($explicit -join "`n"))"
same root: True
```

Default exclusions skip hidden names and build/dependency directories. Explicit
roots still search excluded names. A directory junction cycle is visited once.

```mooncram
$ $root = Join-Path $env:TESTDIR 'tokscan-walk.tmp'; $cycle = Join-Path $root 'again'; try { $null = New-Item -ItemType Directory -Path $root; foreach ($name in @('.hidden', '_build', 'node_modules', 'TARGET')) { $null = New-Item -ItemType Directory -Path (Join-Path $root $name) }; foreach ($name in @('hit.mbt', '.hidden.mbt', '.hidden/hit.mbt', '_build/hit.mbt', 'node_modules/hit.mbt', 'TARGET/hit.mbt')) { [IO.File]::WriteAllText((Join-Path $root $name), "fn sample { target() }`n") }; $null = New-Item -ItemType Junction -Path $cycle -Target $root; foreach ($scanRoot in @($root, (Join-Path $root '.hidden.mbt'), (Join-Path $root 'TARGET'))) { $output = @(moonrun "$env:TESTDIR/../moongrep.wasm" -- tokscan --pattern 'target()' $scanRoot); "status: $LASTEXITCODE; hits: $(@($output | Where-Object { $_ -eq 'pattern:' }).Count)" } } finally { if (Test-Path -LiteralPath $cycle) { [IO.Directory]::Delete($cycle) }; if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force } }
status: 0; hits: 1
status: 0; hits: 1
status: 0; hits: 1
```

JSON output keeps duplicate and overlapping findings on separate lines.

```mooncram
$ Set-Location "$env:TESTDIR/../.."; $records = @(moonrun e2etests/moongrep.wasm -- tokscan --json --pattern 'a a' --pattern 'a a a' --pattern 'a a' testdata/tokscan/overlap.mbt); "status: $LASTEXITCODE"; foreach ($line in $records) { $record = $line | ConvertFrom-Json; "$($record.type): $($record.pattern); $($record.range.start.column)-$($record.range.end.column); $($record.matched_source)" }; "fields: $((($records[0] | ConvertFrom-Json).PSObject.Properties.Name | Sort-Object) -join ', ')"
status: 0
finding: a a; 1-4; a a
finding: a a a; 1-6; a a a
finding: a a; 1-4; a a
finding: a a; 3-6; a a
finding: a a; 3-6; a a
fields: file, matched_source, pattern, range, source_context, type
```

JSON locations use Unicode code point columns and native normalized paths.

```mooncram
$ Set-Location "$env:TESTDIR/../.."; moonrun e2etests/moongrep.wasm -- tokscan --json --pattern '.field' '.\testdata//tokscan\ignored\..\.\blocks.mbt'
{"type":"finding","file":"testdata\\tokscan\\blocks.mbt","pattern":".field","range":{"start":{"line":8,"column":4},"end":{"line":8,"column":10}},"matched_source":".field","source_context":[{"line":6,"text":"target(1)","is_match":false},{"line":7,"text":"///|","is_match":false},{"line":8,"text":"\"😀\".field","is_match":true}]}
```

Exclusions accept mixed separators, dot components, names, paths, and Unicode
case folding. Options may appear among patterns and the root.

```mooncram
$ Set-Location "$env:TESTDIR/../.."; moonrun e2etests/moongrep.wasm -- tokscan --exclude IGNORED/ --pattern 'target()' --pattern 'unicode_marker()' testdata/exclude-dirs --json --exclude='.\testdata//exclude-dirs\generated\..\GENERATED\\' --exclude "$([char]0x00FC)ber" --exclude=EXCLUDED.MBT
{"type":"finding","file":"testdata\\exclude-dirs\\hit.mbt","pattern":"target()","range":{"start":{"line":1,"column":13},"end":{"line":1,"column":21}},"matched_source":"target()","source_context":[{"line":1,"text":"fn sample { target() }","is_match":true}]}
```

Explicit roots are still scanned, while matching recursive entries are excluded.

```mooncram
$ Set-Location "$env:TESTDIR/../.."; foreach ($root in @('testdata/stream-order/a', 'testdata/stream-order/a.mbt', 'testdata/stream-order')) { $output = @(moonrun e2etests/moongrep.wasm -- tokscan --json --pattern 'target()' --exclude A --exclude=A.MBT $root); "status: $LASTEXITCODE; records: $($output.Count)" }
status: 0; records: 1
status: 0; records: 1
status: 0; records: 0
```

Warnings and findings use separate streams, with block recovery and success
status. Excluding the malformed file suppresses all warnings.

```mooncram
$ Set-Location "$env:TESTDIR/../.."; $tokStreams = @(moonrun e2etests/moongrep.wasm -- tokscan --json --pattern 'target(1)' testdata/tokscan/warnings.mbt 2>&1); $tokStatus = $LASTEXITCODE; $tokOutput = @($tokStreams | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }); $tokError = @($tokStreams | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }); "status: $tokStatus"; $tokOutput | ForEach-Object { $record = $_ | ConvertFrom-Json; "stdout: $($record.type); line: $($record.range.start.line); source: $($record.matched_source)" }; $tokError | ForEach-Object { $record = [string]$_ | ConvertFrom-Json; "stderr: $($record.type); category: $($record.category); block: $($record.block_start_line)" }; $global:LASTEXITCODE = $tokStatus
status: 0
stdout: finding; line: 11; source: target ( 1 )
stderr: warning; category: lexical; block: 1
stderr: warning; category: lexical; block: 3
stderr: warning; category: lexical; block: 6
```

```mooncram
$ Set-Location "$env:TESTDIR/../.."; $output = @(moonrun e2etests/moongrep.wasm -- tokscan --json --pattern absent --exclude WARNINGS.MBT testdata/tokscan 2>&1); "status: $LASTEXITCODE; records: $($output.Count)"
status: 0; records: 0
```

Usage and file access errors follow the shared JSON protocol. Invalid patterns
are validated before accessing a missing root.

```mooncram
$ $output = @(moonrun "$env:TESTDIR/../moongrep.wasm" -- tokscan --json 2>&1); $tokStatus = $LASTEXITCODE; $output | ForEach-Object { [Console]::Out.WriteLine([string]$_) }; $global:LASTEXITCODE = $tokStatus
{"type":"error","category":"usage","exit_code":2,"message":"tokscan requires at least one --pattern"}
[2]
```

```mooncram
$ $output = @(moonrun "$env:TESTDIR/../moongrep.wasm" -- tokscan --json --pattern a --pattern '$bad' missing-tokscan-root 2>&1); $tokStatus = $LASTEXITCODE; $record = ($output | ForEach-Object { [string]$_ }) -join "`n" | ConvertFrom-Json; "status: $tokStatus; category: $($record.category); pattern: $($record.pattern); source: $($record.source)"; $global:LASTEXITCODE = $tokStatus
status: 2; category: usage; pattern: $bad; source: --pattern 2
[2]
```

```mooncram
$ $output = @(moonrun "$env:TESTDIR/../moongrep.wasm" -- tokscan --unknown --json 2>&1); $tokStatus = $LASTEXITCODE; $record = ($output | ForEach-Object { [string]$_ }) -join "`n" | ConvertFrom-Json; "status: $tokStatus; type: $($record.type); category: $($record.category); diagnostic: $($record.message.Contains('unexpected argument'))"; $global:LASTEXITCODE = $tokStatus
status: 2; type: error; category: usage; diagnostic: True
[2]
```

```mooncram
$ $output = @(moonrun "$env:TESTDIR/../moongrep.wasm" -- tokscan --json --exclude 2>&1); $tokStatus = $LASTEXITCODE; $record = ($output | ForEach-Object { [string]$_ }) -join "`n" | ConvertFrom-Json; "status: $tokStatus; type: $($record.type); category: $($record.category)"; $global:LASTEXITCODE = $tokStatus
status: 2; type: error; category: usage
[2]
```

```mooncram
$ $output = @(moonrun "$env:TESTDIR/../moongrep.wasm" -- tokscan --json --pattern a missing-tokscan-root 2>&1); $tokStatus = $LASTEXITCODE; $record = ($output | ForEach-Object { [string]$_ }) -join "`n" | ConvertFrom-Json; "status: $tokStatus; type: $($record.type); category: $($record.category); source: $($record.source)"; $global:LASTEXITCODE = $tokStatus
status: 6; type: error; category: scan_input; source: missing-tokscan-root
[6]
```

Help remains ordinary text and --json after the terminator is not an option.

```mooncram
$ $plain = @(moonrun "$env:TESTDIR/../moongrep.wasm" -- tokscan --help); $jsonHelp = @(moonrun "$env:TESTDIR/../moongrep.wasm" -- tokscan --json --help); "status: $LASTEXITCODE; same help: $(($plain -join "`n") -eq ($jsonHelp -join "`n"))"
status: 0; same help: True
```

```mooncram
$ $output = @(moonrun "$env:TESTDIR/../moongrep.wasm" -- tokscan -- --json 2>&1); $tokStatus = $LASTEXITCODE; $output | ForEach-Object { [Console]::Out.WriteLine([string]$_) }; $global:LASTEXITCODE = $tokStatus
error: tokscan requires at least one --pattern
[2]
```
