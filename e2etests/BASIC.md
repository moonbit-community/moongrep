```mooncram
$ moonrun "$TESTDIR"/moongrep.wasm -- scan -h
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
