# Dump command on Windows

## Structured dump records

JSON expression and implementation dumps each occupy one physical stdout line
and carry the corresponding `kind`. Successful commands leave stderr empty.

```mooncram
$ $stdoutPath = Join-Path $env:TESTDIR 'dump-stdout.tmp'; $stderrPath = Join-Path $env:TESTDIR 'dump-stderr.tmp'; moonrun "$env:TESTDIR/../moongrep.wasm" -- dump --output-json --expr 'x + 1' 1>$stdoutPath 2>$stderrPath; $dumpStatus = $LASTEXITCODE; $dumpOutput = @(Get-Content $stdoutPath); $dumpError = @(Get-Content $stderrPath); $record = $dumpOutput[0] | ConvertFrom-Json; "status: $dumpStatus"; "stdout count: $($dumpOutput.Count)"; "stderr count: $($dumpError.Count)"; "record: $($record.type) $($record.kind) $($record.content.Contains('Expr_Infix'))"; Remove-Item $stdoutPath, $stderrPath; $global:LASTEXITCODE = $dumpStatus
status: 0
stdout count: 1
stderr count: 0
record: dump expr True
```

```mooncram
$ $stdoutPath = Join-Path $env:TESTDIR 'dump-stdout.tmp'; $stderrPath = Join-Path $env:TESTDIR 'dump-stderr.tmp'; moonrun "$env:TESTDIR/../moongrep.wasm" -- dump --impl 'fn answer { 42 }' --output-json 1>$stdoutPath 2>$stderrPath; $dumpStatus = $LASTEXITCODE; $dumpOutput = @(Get-Content $stdoutPath); $dumpError = @(Get-Content $stderrPath); $record = $dumpOutput[0] | ConvertFrom-Json; "status: $dumpStatus"; "stdout count: $($dumpOutput.Count)"; "stderr count: $($dumpError.Count)"; "record: $($record.type) $($record.kind) $($record.content.Contains('Impl_Function'))"; Remove-Item $stdoutPath, $stderrPath; $global:LASTEXITCODE = $dumpStatus
status: 0
stdout count: 1
stderr count: 0
record: dump impl True
```

## Structured dump failures

Invalid input writes one `dump_input` record to stderr, leaves stdout empty,
and exits with status 3.

```mooncram
$ $dumpStreams = @(moonrun "$env:TESTDIR/../moongrep.wasm" -- dump --output-json --expr 'value +' 2>&1); $dumpStatus = $LASTEXITCODE; $dumpOutput = @($dumpStreams | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }); $dumpError = @($dumpStreams | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }); "status: $dumpStatus"; "stdout count: $($dumpOutput.Count)"; "stderr count: $($dumpError.Count)"; $dumpError | ForEach-Object { [Console]::Out.WriteLine([string]$_) }; $global:LASTEXITCODE = $dumpStatus
status: 3
stdout count: 0
stderr count: 1
{"type":"error","category":"dump_input","exit_code":3,"message":"could not parse dump input","source":"dump --expr","reason":"Unexpected end of file, missing simple expression here.","help":"provide one valid MoonBit expression"}
[3]
```

Missing input uses the shared JSON usage schema and status 2.

```mooncram
$ $dumpStreams = @(moonrun "$env:TESTDIR/../moongrep.wasm" -- dump --output-json 2>&1); $dumpStatus = $LASTEXITCODE; $dumpOutput = @($dumpStreams | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }); $dumpError = @($dumpStreams | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }); "status: $dumpStatus"; "stdout count: $($dumpOutput.Count)"; "stderr count: $($dumpError.Count)"; $dumpError | ForEach-Object { [Console]::Out.WriteLine([string]$_) }; $global:LASTEXITCODE = $dumpStatus
status: 2
stdout count: 0
stderr count: 1
{"type":"error","category":"usage","exit_code":2,"message":"missing dump --impl or --expr"}
[2]
```

Help stays textual and includes the new option.

```mooncram
$ moonrun "$env:TESTDIR/../moongrep.wasm" -- dump --output-json --help | Where-Object { $_ -match '^  --output-json' }
  --output-json  Write one compact JSON dump record to stdout and diagnostics to stderr.
```

## Successful expression check

Exit-code mode validates an expression without writing CST output. The command
exits successfully and leaves both output streams empty.

```mooncram
$ $dumpOutput = @(moonrun "$env:TESTDIR/../moongrep.wasm" -- dump --exit-code --expr 'x + 1' 2>&1); $dumpStatus = $LASTEXITCODE; "status: $dumpStatus"; "output count: $($dumpOutput.Count)"
status: 0
output count: 0
```

JSON mode remains silent when combined with exit-code mode.

```mooncram
$ $dumpOutput = @(moonrun "$env:TESTDIR/../moongrep.wasm" -- dump --exit-code --output-json --expr 'x + 1' 2>&1); $dumpStatus = $LASTEXITCODE; "status: $dumpStatus"; "output count: $($dumpOutput.Count)"
status: 0
output count: 0
```

## Successful implementation check

The flag also accepts a valid top-level implementation item when it appears
after the input option.

```mooncram
$ $dumpOutput = @(moonrun "$env:TESTDIR/../moongrep.wasm" -- dump --impl 'fn answer { 42 }' --exit-code 2>&1); $dumpStatus = $LASTEXITCODE; "status: $dumpStatus"; "output count: $($dumpOutput.Count)"
status: 0
output count: 0
```

## Invalid expression check

Invalid input still writes its diagnostic and exits with dump-input status 3.

```mooncram
$ $dumpOutput = @(moonrun "$env:TESTDIR/../moongrep.wasm" -- dump --exit-code --expr 'value +' 2>&1); $dumpStatus = $LASTEXITCODE; $dumpOutput | ForEach-Object { [Console]::Out.WriteLine([string]$_) }; $global:LASTEXITCODE = $dumpStatus
error: could not parse dump input
  source: dump --expr
  reason: Unexpected end of file, missing simple expression here.
  help: provide one valid MoonBit expression
[3]
```
