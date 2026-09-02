# Windows junction traversal

## Scan-directory cycle

Windows directory junctions are followed during source traversal. A junction
back to the scan root is reported as skipped, and the source is scanned only
once.

```mooncram
$ $root = Join-Path $env:TESTDIR 'fs-walk-scan.tmp'; $cycle = Join-Path $root 'again'; if (Test-Path -LiteralPath $root) { if (Test-Path -LiteralPath $cycle) { [IO.Directory]::Delete($cycle) }; Remove-Item -LiteralPath $root -Recurse -Force }; $scanStatus = 1; try { $null = New-Item -ItemType Directory -Path $root; [IO.File]::WriteAllText((Join-Path $root 'hit.mbt'), "///|`nfn sample {`n  target()`n}`n"); $null = New-Item -ItemType Junction -Path $cycle -Target $root; Set-Location "$env:TESTDIR/../.."; $stdoutPath = Join-Path $root 'stdout.txt'; $stderrPath = Join-Path $root 'stderr.txt'; moonrun e2etests/moongrep.wasm -- scan --verbose --pattern 'target()' e2etests/windows/fs-walk-scan.tmp 1>$stdoutPath 2>$stderrPath; $scanStatus = $LASTEXITCODE; $scanOutput = @(Get-Content -LiteralPath $stdoutPath); "status: $scanStatus"; "hit count: $(@($scanOutput | Where-Object { $_ -eq 'rule: target()' }).Count)"; Get-Content -LiteralPath $stderrPath | Where-Object { $_ -match '^moongrep scan: (entering|skipping|file) ' } } finally { if (Test-Path -LiteralPath $cycle) { [IO.Directory]::Delete($cycle) }; if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force } }; $global:LASTEXITCODE = $scanStatus
status: 0
hit count: 1
moongrep scan: entering e2etests\windows\fs-walk-scan.tmp
moongrep scan: skipping e2etests\windows\fs-walk-scan.tmp\again
moongrep scan: file e2etests\windows\fs-walk-scan.tmp\hit.mbt
```

## Rule-directory cycle

Rule discovery also follows Windows directory junctions and stops when a
junction resolves to an already visited rule directory.

```mooncram
$ $root = Join-Path $env:TESTDIR 'fs-walk-rules.tmp'; $cycle = Join-Path $root 'again'; if (Test-Path -LiteralPath $root) { if (Test-Path -LiteralPath $cycle) { [IO.Directory]::Delete($cycle) }; Remove-Item -LiteralPath $root -Recurse -Force }; $scanStatus = 1; try { $null = New-Item -ItemType Directory -Path $root; [IO.File]::WriteAllText((Join-Path $root 'example.yaml'), "id: example`ndescription: Windows junction rule.`npatterns:`n  - shape: target()`n"); $null = New-Item -ItemType Junction -Path $cycle -Target $root; Set-Location "$env:TESTDIR/../.."; $stdoutPath = Join-Path $root 'stdout.txt'; $stderrPath = Join-Path $root 'stderr.txt'; moonrun e2etests/moongrep.wasm -- scan --rules e2etests/windows/fs-walk-rules.tmp testdata/symlink/scan-dir-target/hit.mbt 1>$stdoutPath 2>$stderrPath; $scanStatus = $LASTEXITCODE; $scanOutput = @(Get-Content -LiteralPath $stdoutPath); $scanError = @(Get-Content -LiteralPath $stderrPath); "status: $scanStatus"; "hit count: $(@($scanOutput | Where-Object { $_ -eq 'rule: example' }).Count)"; "stderr count: $($scanError.Count)" } finally { if (Test-Path -LiteralPath $cycle) { [IO.Directory]::Delete($cycle) }; if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force } }; $global:LASTEXITCODE = $scanStatus
status: 0
hit count: 1
stderr count: 0
```
