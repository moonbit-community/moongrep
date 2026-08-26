# Basic CLI behavior

## moongrep help

The top-level help introduces the command, lists every subcommand, and shows
the global help option.

```mooncram
$ moonrun "$TESTDIR/moongrep.wasm" -- help
Usage: moongrep <command>

Scan MoonBit source files with structural and taint rules.

Commands:
  scan  Scan MoonBit source files.
  lint  Scan MoonBit source files with embedded builtin rules.
  docs  Print embedded moongrep documentation.
  dump  Parse a MoonBit impl or expression and print untyped CST debug output.
  help  Print help for the subcommand(s).

Options:
  -h, --help  Show help information.
```

## moongrep docs

The docs registry lists the English rule and CLI specifications in that order.

```mooncram
$ moonrun "$TESTDIR/moongrep.wasm" -- docs --list
RuleSpec	YAML rule keys, validation, and matcher semantics.
CLISpec	Command-line parsing, scanning, output, diagnostics, and exit behavior.
```

## moongrep lint --help

The lint help lists the options accepted by `lint`.

```mooncram
$ moonrun "$TESTDIR/moongrep.wasm" -- lint --help
Usage: moongrep lint [options] [scan-root]

Scan MoonBit source files with embedded builtin rules.

Arguments:
  scan-root  Directory or .mbt file to scan.

Options:
  -h, --help           Show help information.
  --verbose            Write loaded rule ids and traversal progress to stderr.
  --output-json        Write each match as one JSON record to stdout.
  -r, --rules <rules>  Directory containing YAML rules.
  --rule <rule>        Single YAML rule file.
  --pattern <pattern>  Anonymous structural pattern to match.
  --guard <guard>      YAML guard map for the preceding anonymous pattern.
  --exclude <exclude>  File or directory name or path to skip while recursively scanning. May be repeated.
  --disable <disable>  Rule id to disable after loading rules. May be repeated.
```

## moongrep scan --help

The scan help documents the scan root together with every rule source,
filtering, output, and traversal option accepted by the scanner.

```mooncram
$ moonrun "$TESTDIR/moongrep.wasm" -- scan --help
Usage: moongrep scan [options] [scan-root]

Scan MoonBit source files.

Arguments:
  scan-root  Directory or .mbt file to scan.

Options:
  -h, --help           Show help information.
  --verbose            Write loaded rule ids and traversal progress to stderr.
  --output-json        Write each match as one JSON record to stdout.
  -r, --rules <rules>  Directory containing YAML rules. [default: ./.moongrep/rules]
  --rule <rule>        Single YAML rule file.
  --pattern <pattern>  Anonymous structural pattern to match.
  --guard <guard>      YAML guard map for the preceding anonymous pattern.
  --exclude <exclude>  File or directory name or path to skip while recursively scanning. May be repeated.
  --disable <disable>  Rule id to disable after loading rules. May be repeated.
```

## moongrep dump --help

The dump help exposes separate inputs for parsing a top-level implementation
item and a single expression.

```mooncram
$ moonrun "$TESTDIR/moongrep.wasm" -- dump --help
Usage: moongrep dump [options]

Parse a MoonBit impl or expression and print untyped CST debug output.

Options:
  -h, --help     Show help information.
  --impl <impl>  MoonBit top-level implementation item to parse.
  --expr <expr>  MoonBit expression to parse.
```
