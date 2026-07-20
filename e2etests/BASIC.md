## moongrep help

The top-level help introduces the command, lists every subcommand, and shows
the global help option.

```mooncram
$ moonrun "$TESTDIR"/moongrep.wasm -- help
Usage: moongrep <command>

Scan MoonBit source files with structural and taint rules.

Commands:
  scan  Scan MoonBit source files.
  docs  Print embedded moongrep documentation.
  dump  Parse a MoonBit impl or expression and print untyped_ast debug output.
  help  Print help for the subcommand(s).

Options:
  -h, --help  Show help information.
```

## moongrep subcommands without arguments

Each check verifies that invoking a subcommand without arguments succeeds and
prints exactly the same help text as invoking it with `--help`.

The scan subcommand falls back to its help when no scan root or rule input is
provided.

```mooncram
$ moonrun "$TESTDIR"/moongrep.wasm -- scan > /dev/null && diff -u <(moonrun "$TESTDIR"/moongrep.wasm -- scan --help) <(moonrun "$TESTDIR"/moongrep.wasm -- scan)
```

The docs subcommand uses the same no-argument help behavior.

```mooncram
$ moonrun "$TESTDIR"/moongrep.wasm -- docs > /dev/null && diff -u <(moonrun "$TESTDIR"/moongrep.wasm -- docs --help) <(moonrun "$TESTDIR"/moongrep.wasm -- docs)
```

The dump subcommand also prints help instead of attempting to parse an empty
input.

```mooncram
$ moonrun "$TESTDIR"/moongrep.wasm -- dump > /dev/null && diff -u <(moonrun "$TESTDIR"/moongrep.wasm -- dump --help) <(moonrun "$TESTDIR"/moongrep.wasm -- dump)
```

## moongrep scan --help

The scan help documents the scan root together with every rule source,
filtering, output, and traversal option accepted by the scanner.

```mooncram
$ moonrun "$TESTDIR"/moongrep.wasm -- scan --help
Usage: moongrep scan [options] [scan-root]

Scan MoonBit source files.

Arguments:
  scan-root  Directory to scan.

Options:
  -h, --help                       Show help information.
  --verbose                        Write loaded rule ids and traversal progress to stderr.
  --enable-builtin-rules           Enable embedded builtin rules.
  --output-json                    Write each match as one JSON record to stdout.
  -r, --rules <rules>              Directory containing YAML rules.
  --rule <rule>                    Single YAML rule file.
  --pattern <pattern>              Anonymous structural pattern to match.
  --guard <guard>                  YAML guard map for the preceding anonymous pattern.
  --exclude-dir <exclude-dir>      Directory name or path to skip while recursively scanning.
  --exclude-rules <exclude-rules>  Rule id to disable after loading rules.
```

## moongrep scan --enable-builtin-rules

Enabling builtin rules without a separate rule directory reports every
embedded rule that matches the fixture. The default human-readable output
includes locations, rule metadata, and source context.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --enable-builtin-rules testdata/builtin-rules
testdata/builtin-rules/hit.mbt:3:3-3:26
rule: moonbitlang/inspect_number
description:
  Found inspect() snapshots whose expected value is a plain number.
  Prefer numeric assertions for numeric checks.
source:
1 | ///|
2 | fn has_builtin_hits(value : Int?) -> Unit {
3 >   inspect(1, content="1")
4 |   assert_true(
5 |     match value {

testdata/builtin-rules/hit.mbt:5:5-8:6
rule: moonbitlang/match_option
description:
  Found an Option value handled with match over Some and None.
  Prefer if + is for simple Option checks.
source:
 3 |   inspect(1, content="1")
 4 |   assert_true(
 5 >     match value {
 6 >       Some(inner) => inner > 0
 7 >       None => false
 8 >     },
 9 |   )
10 | }
```

## moongrep dump --help

The dump help exposes separate inputs for parsing a top-level implementation
item and a single expression.

```mooncram
$ moonrun "$TESTDIR"/moongrep.wasm -- dump --help
Usage: moongrep dump [options]

Parse a MoonBit impl or expression and print untyped_ast debug output.

Options:
  -h, --help     Show help information.
  --impl <impl>  MoonBit top-level implementation item to parse.
  --expr <expr>  MoonBit expression to parse.
```

## moongrep dump --expr

Dumping an infix expression produces an untyped AST whose root contains the
expected `Expr_Infix` node kind.

```mooncram
$ moonrun "$TESTDIR"/moongrep.wasm -- dump --expr 'x + 1' | grep 'kind: Expr_Infix'
  kind: Expr_Infix,
```
