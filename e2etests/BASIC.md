## moongrep help

```mooncram
$ moonrun "$TESTDIR"/moongrep.wasm -- help
Usage: moongrep <command>

Scan MoonBit source files with structural and taint rules.

Commands:
  scan  Scan MoonBit source files with structural and taint rules.
  docs  Print embedded moongrep documentation.
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

