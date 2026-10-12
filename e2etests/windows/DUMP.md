# Dump command on Windows

```mooncram-import
jq : cli/jq@0.2.1
grep : cli/grep@0.2.0
```

## Structured dump records

JSON expression and implementation dumps each occupy one physical stdout line
and carry the corresponding `kind`. Successful commands leave stderr empty.

```mooncram moonbit-community/moongrep
$ moongrep dump --json --strict-check --expr 'x + 1' | jq -R -s -c 'rtrimstr("\n") | split("\n") | [length, (.[0] | fromjson | .type), (.[0] | fromjson | .kind), (.[0] | fromjson | .content | contains("Expr_Infix"))]'
@STDOUT
[1,"dump","expr",true]
@STDERR (empty)
```

```mooncram moonbit-community/moongrep
$ moongrep dump --impl 'fn answer { 42 }' --json | jq -R -s -c 'rtrimstr("\n") | split("\n") | [length, (.[0] | fromjson | .type), (.[0] | fromjson | .kind), (.[0] | fromjson | .content | contains("Impl_Function"))]'
@STDOUT
[1,"dump","impl",true]
@STDERR (empty)
```

## Structured dump failures

Invalid input writes one `dump_input` record to stderr, leaves stdout empty,
and exits with status 3.

```mooncram moonbit-community/moongrep
$ moongrep dump --json --strict-check --expr 'value +'
@STDOUT (empty)
@STDERR
{"type":"error","category":"dump_input","exit_code":3,"message":"could not parse dump input","source":"dump --expr","reason":"Unexpected end of file, missing simple expression here.","help":"provide one valid MoonBit expression"}
[3]
```

Strict pattern failures retain the original input in a `rule_content` JSON
diagnostic and exit with status 5.

```mooncram moonbit-community/moongrep
$ moongrep dump --json --strict-check --impl 'fn answer { 42 }'
@STDOUT (empty)
@STDERR
{"type":"error","category":"rule_content","exit_code":5,"message":"invalid dump pattern","source":"dump --impl","pattern":"fn answer { 42 }","reason":"the pattern must contain exactly one __TARGET__ placeholder in a supported expression position","help":"fix the pattern passed to --impl and try again"}
[5]
```

Missing input uses the shared JSON usage schema and status 2.

```mooncram moonbit-community/moongrep
$ moongrep dump --json
@STDOUT (empty)
@STDERR
{"type":"error","category":"usage","exit_code":2,"message":"missing dump --impl or --expr"}
[2]
```

Help stays textual and includes the new option.

```mooncram moonbit-community/moongrep
$ moongrep dump --json --help | grep '^  --strict-check'
  --strict-check  Apply scan's additional pattern validation to the dump input.
```

## Successful expression check

Exit-code mode validates an expression without writing CST output. The command
exits successfully and leaves both output streams empty.

```mooncram moonbit-community/moongrep
$ moongrep dump --exit-code --strict-check --expr 'x + 1'
@STDOUT (empty)
@STDERR (empty)
```

JSON mode remains silent when combined with exit-code mode.

```mooncram moonbit-community/moongrep
$ moongrep dump --exit-code --json --expr 'x + 1'
@STDOUT (empty)
@STDERR (empty)
```

## Successful implementation check

The flag also accepts a valid top-level implementation item when it appears
after the input option.

```mooncram moonbit-community/moongrep
$ moongrep dump --impl 'fn answer { __TARGET__ }' --strict-check --exit-code
@STDOUT (empty)
@STDERR (empty)
```

## Invalid expression check

Invalid input still writes its diagnostic and exits with dump-input status 3.

```mooncram moonbit-community/moongrep
$ moongrep dump --exit-code --strict-check --expr 'value +'
@STDOUT (empty)
@STDERR
error: could not parse dump input
  source: dump --expr
  reason: Unexpected end of file, missing simple expression here.
  help: provide one valid MoonBit expression
[3]
```
