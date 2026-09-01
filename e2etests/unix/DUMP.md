# Dump command on Unix

## moongrep dump --expr

Dumping an infix expression produces an untyped CST whose root contains the
expected `Expr_Infix` node kind.

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- dump --expr 'x + 1' | grep 'kind: Expr_Infix'
  kind: Expr_Infix,
```

## moongrep dump --exit-code

Exit-code mode performs the same parse validation without writing CST output.
A valid expression therefore exits successfully with both output streams empty.

```mooncram
$ bash -c 'output=$(moonrun "$1" -- dump --exit-code --expr "x + 1" 2>&1); status=$?; test "$status" -eq 0 && test -z "$output"' _ "$TESTDIR"/../moongrep.wasm
```
