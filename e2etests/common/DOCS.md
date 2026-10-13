# Docs command

```mooncram-import
grep : cli/grep@0.2.0
cmp : cli/cmp@0.2.0
```

## Embedded CLI document headings

The named CLI document prints the embedded source.

```mooncram moonbit-community/moongrep
$ moongrep docs CLISpec | grep -E '^# Command-Line Interface Specification$|^## (`scan` and `lint`|JSON Lines Output|Diagnostics and Exit Status)$'
# Command-Line Interface Specification
## `scan` and `lint`
## JSON Lines Output
## Diagnostics and Exit Status
```

The embedded rule specification stays synchronized with its source.

```mooncram moonbit-community/moongrep
$ moongrep docs RuleSpec | cmp ../../internal/docs/RuleSpec.md -
```
