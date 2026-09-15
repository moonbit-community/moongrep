# Dump command on Unix

## moongrep dump --expr

Dumping an infix expression produces an untyped CST whose root contains the
expected `Expr_Infix` node kind.

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- dump --strict-check --expr 'x + 1' | grep 'kind: Expr_Infix'
  kind: Expr_Infix,
```

A strict implementation pattern may place the flag after its input. The
rendered node is still the original dump CST.

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- dump --impl 'fn answer { __TARGET__ }' --strict-check | grep 'kind: Impl_Function'
  kind: Impl_Function,
```

## moongrep dump --json

JSON mode emits exactly one physical record. Expression and implementation
inputs use distinct `kind` values while retaining their CST debug content.

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- dump --json --expr 'x + 1' | node -e 'const fs=require("fs");const lines=fs.readFileSync(0,"utf8").trimEnd().split("\n");const record=JSON.parse(lines[0]);console.log(lines.length,record.type,record.kind,record.content.includes("Expr_Infix"))'
1 dump expr true
```

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- dump --impl 'fn answer { 42 }' --json | node -e 'const fs=require("fs");const lines=fs.readFileSync(0,"utf8").trimEnd().split("\n");const record=JSON.parse(lines[0]);console.log(lines.length,record.type,record.kind,record.content.includes("Impl_Function"))'
1 dump impl true
```

Successful dump records are written to standard output, leaving standard error
empty.

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- dump --json --expr 'x + 1' 2>&1 >/dev/null
```

Invalid input keeps the existing `dump_input` error schema on standard error
and exits with status 3. Its standard output remains empty.

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- dump --json --strict-check --expr 'value +' 2>&1 >/dev/null
{"type":"error","category":"dump_input","exit_code":3,"message":"could not parse dump input","source":"dump --expr","reason":"Unexpected end of file, missing simple expression here.","help":"provide one valid MoonBit expression"}
[3]
```

```mooncram
$ bash -c 'stdout=$(moonrun "$1" -- dump --json --strict-check --expr "value +" 2>/dev/null); status=$?; test "$status" -eq 3 && test -z "$stdout"' _ "$TESTDIR"/../moongrep.wasm
```

A pattern rejected by the additional check uses the `rule_content` schema and
status 5. The original input is retained in the `pattern` field.

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- dump --json --strict-check --impl 'fn answer { 42 }' 2>&1 >/dev/null
{"type":"error","category":"rule_content","exit_code":5,"message":"invalid dump pattern","source":"dump --impl","pattern":"fn answer { 42 }","reason":"the pattern must contain exactly one __TARGET__ placeholder in a supported expression position","help":"fix the pattern passed to --impl and try again"}
[5]
```

Providing JSON mode without a dump input is a usage error on standard error
with status 2.

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- dump --json 2>&1 >/dev/null
{"type":"error","category":"usage","exit_code":2,"message":"missing dump --impl or --expr"}
[2]
```

Help remains ordinary text even when JSON mode was requested, and it exposes
the new option.

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- dump --json --help | grep '^  --strict-check'
  --strict-check  Apply scan's additional pattern validation to the dump input.
```

## moongrep dump --exit-code

Exit-code mode performs the same parse validation without writing CST output.
A valid expression therefore exits successfully with both output streams empty.

```mooncram
$ bash -c 'output=$(moonrun "$1" -- dump --exit-code --strict-check --expr "x + 1" 2>&1); status=$?; test "$status" -eq 0 && test -z "$output"' _ "$TESTDIR"/../moongrep.wasm
```

The exit-code flag also takes precedence over JSON output.

```mooncram
$ bash -c 'output=$(moonrun "$1" -- dump --exit-code --json --expr "x + 1" 2>&1); status=$?; test "$status" -eq 0 && test -z "$output"' _ "$TESTDIR"/../moongrep.wasm
```
