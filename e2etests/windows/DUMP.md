# Dump command on Windows

## Successful expression check

Exit-code mode validates an expression without writing CST output. The command
exits successfully and leaves both output streams empty.

```mooncram
$ $dumpOutput = @(moonrun "$env:TESTDIR/../moongrep.wasm" -- dump --exit-code --expr 'x + 1' 2>&1); $dumpStatus = $LASTEXITCODE; "status: $dumpStatus"; "output count: $($dumpOutput.Count)"
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
