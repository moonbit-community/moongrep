## moongrep help

```mooncram
$ moonrun "$TESTDIR"/moongrep.wasm -- help
Usage: moongrep <command>

Scan MoonBit source files with structural and taint rules.

Commands:
  scan  Scan MoonBit source files with structural and taint rules.
  docs  Print embedded moongrep documentation.
  dump  Parse a MoonBit impl or expression and print AST JSON.
  help  Print help for the subcommand(s).

Options:
  -h, --help  Show help information.
```

## moongrep scan --help

```mooncram
$ moonrun "$TESTDIR"/moongrep.wasm -- scan --help
Usage: moongrep scan [options] [scan-root]

Scan MoonBit source files with structural and taint rules.

Arguments:
  scan-root  Directory to scan.

Options:
  -h, --help                   Show help information.
  --verbose                    Print directory traversal progress.
  --enable-builtin-rules       Enable embedded builtin rules.
  -r, --rules <rules>          Directory containing YAML rules.
  --pattern <pattern>          Anonymous structural pattern to match.
  --exclude-dir <exclude-dir>  Directory name or path to skip while recursively scanning.
```

## moongrep scan --enable-builtin-rules

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --enable-builtin-rules testdata/builtin-rules
testdata/builtin-rules/hit.mbt:3:3-3:26
rule: moonbitlang/inspect_number
description:
  Found inspect() snapshots whose expected value is a plain number.
  Prefer numeric assertions for numeric checks.
source:
\x1b[90m1 | ///|\x1b[39m (escaped)
\x1b[90m2 | fn has_builtin_hits(value : Int?) -> Unit {\x1b[39m (escaped)
3 |   inspect(1, content="1")
\x1b[90m4 |   assert_true(\x1b[39m (escaped)
\x1b[90m5 |     match value {\x1b[39m (escaped)

testdata/builtin-rules/hit.mbt:5:5-8:6
rule: moonbitlang/match_option
description:
  Found an Option value handled with match over Some and None.
  Prefer if + is for simple Option checks.
source:
\x1b[90m3 |   inspect(1, content="1")\x1b[39m (escaped)
\x1b[90m4 |   assert_true(\x1b[39m (escaped)
5 |     match value {
6 |       Some(inner) => inner > 0
7 |       None => false
8 |     },
\x1b[90m9 |   )\x1b[39m (escaped)
\x1b[90m10 | }\x1b[39m (escaped)
```

## moongrep dump --help

```mooncram
$ moonrun "$TESTDIR"/moongrep.wasm -- dump --help
Usage: moongrep dump [options]

Parse a MoonBit impl or expression and print AST JSON.

Options:
  -h, --help     Show help information.
  --impl <impl>  MoonBit top-level implementation item to parse.
  --expr <expr>  MoonBit expression to parse.
```

## moongrep dump --expr

```mooncram
$ moonrun "$TESTDIR"/moongrep.wasm -- dump --expr 'x + 1' | grep '"kind": "Expr::Infix"'
  "kind": "Expr::Infix",
```
