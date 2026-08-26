# Dump command on Unix

## moongrep dump --expr

Dumping an infix expression produces an untyped CST whose root contains the
expected `Expr_Infix` node kind.

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- dump --expr 'x + 1' | grep 'kind: Expr_Infix'
  kind: Expr_Infix,
```
