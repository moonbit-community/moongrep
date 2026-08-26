# Subcommands without arguments

## moongrep subcommands without arguments

The `docs` and `dump` subcommands print their help when invoked without
arguments. `scan` and `lint` instead treat an omitted scan root as the current
directory. `scan` uses its default rules directory, while `lint` enables
builtin rules automatically.

The docs subcommand uses the same no-argument help behavior.

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- docs > /dev/null && diff -u <(moonrun "$TESTDIR"/../moongrep.wasm -- docs --help) <(moonrun "$TESTDIR"/../moongrep.wasm -- docs)
```

The dump subcommand also prints help instead of attempting to parse an empty
input.

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- dump > /dev/null && diff -u <(moonrun "$TESTDIR"/../moongrep.wasm -- dump --help) <(moonrun "$TESTDIR"/../moongrep.wasm -- dump)
```

Running bare `lint` from a fixture directory produces the same output as an
explicit current-directory lint target.

```mooncram
$ cd "$TESTDIR"/../../testdata/builtin-rules && diff -u <(moonrun "$TESTDIR"/../moongrep.wasm -- lint) <(moonrun "$TESTDIR"/../moongrep.wasm -- lint .)
```
