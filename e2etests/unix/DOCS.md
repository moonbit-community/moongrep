# Docs command on Unix

## Embedded CLI document headings

The named CLI document prints the embedded source.

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- docs CLISpec | grep -E '^# Command-Line Interface Specification$|^## (`scan` and `lint`|JSON Lines Output|Diagnostics and Exit Status)$'
# Command-Line Interface Specification
## `scan` and `lint`
## JSON Lines Output
## Diagnostics and Exit Status
```
