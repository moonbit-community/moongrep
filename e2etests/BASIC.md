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
  -h, --help           Show help information.
  --verbose            Print directory traversal progress.
  -r, --rules <rules>  Directory containing YAML rules.
  --pattern <pattern>  Anonymous structural pattern to match.
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
