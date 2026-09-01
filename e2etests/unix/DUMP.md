# Dump command on Unix

## moongrep dump --expr

Dumping an infix expression produces an untyped CST whose root contains the
expected `Expr_Infix` node kind.

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- dump --expr 'x + 1' | grep 'kind: Expr_Infix'
  kind: Expr_Infix,
```

## moongrep dump --output-json

JSON mode emits exactly one physical record. Expression and implementation
inputs use distinct `kind` values while retaining their CST debug content.

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- dump --output-json --expr 'x + 1' | node -e 'const fs=require("fs");const lines=fs.readFileSync(0,"utf8").trimEnd().split("\n");const record=JSON.parse(lines[0]);console.log(lines.length,record.type,record.kind,record.content.includes("Expr_Infix"))'
1 dump expr true
```

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- dump --impl 'fn answer { 42 }' --output-json | node -e 'const fs=require("fs");const lines=fs.readFileSync(0,"utf8").trimEnd().split("\n");const record=JSON.parse(lines[0]);console.log(lines.length,record.type,record.kind,record.content.includes("Impl_Function"))'
1 dump impl true
```

Successful dump records are written to standard output, leaving standard error
empty.

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- dump --output-json --expr 'x + 1' 2>&1 >/dev/null
```

Invalid input keeps the existing `dump_input` error schema on standard error
and exits with status 3. Its standard output remains empty.

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- dump --output-json --expr 'value +' 2>&1 >/dev/null
{"type":"error","category":"dump_input","exit_code":3,"message":"could not parse dump input","source":"dump --expr","reason":"Unexpected end of file, missing simple expression here.","help":"provide one valid MoonBit expression"}
[3]
```

```mooncram
$ bash -c 'stdout=$(moonrun "$1" -- dump --output-json --expr "value +" 2>/dev/null); status=$?; test "$status" -eq 3 && test -z "$stdout"' _ "$TESTDIR"/../moongrep.wasm
```

Providing JSON mode without a dump input is a usage error on standard error
with status 2.

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- dump --output-json 2>&1 >/dev/null
{"type":"error","category":"usage","exit_code":2,"message":"missing dump --impl or --expr"}
[2]
```

Help remains ordinary text even when JSON mode was requested, and it exposes
the new option.

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- dump --output-json --help | grep '^  --output-json'
  --output-json  Write one compact JSON dump record to stdout and diagnostics to stderr.
```

## moongrep dump --exit-code

Exit-code mode performs the same parse validation without writing CST output.
A valid expression therefore exits successfully with both output streams empty.

```mooncram
$ bash -c 'output=$(moonrun "$1" -- dump --exit-code --expr "x + 1" 2>&1); status=$?; test "$status" -eq 0 && test -z "$output"' _ "$TESTDIR"/../moongrep.wasm
```

The exit-code flag also takes precedence over JSON output.

```mooncram
$ bash -c 'output=$(moonrun "$1" -- dump --exit-code --output-json --expr "x + 1" 2>&1); status=$?; test "$status" -eq 0 && test -z "$output"' _ "$TESTDIR"/../moongrep.wasm
```
