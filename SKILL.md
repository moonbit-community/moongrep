# moongrep

`moongrep` is an experimental MoonBit structural search and taint-analysis tool.
Matching rules are declared as YAML files. 

## Scan

Run the scanner with a rule directory and an optional scan target directory or
`.mbt` file:

```bash
moon runwasm moonbit-community/moongrep -- scan --rules path/to/rules path/to/src
```

Synopsis:

```text
moon runwasm moonbit-community/moongrep -- scan (--rules <rules-root> | --rules=<rules-root> | -r <rules-root>) [scan-root]
```

The scanner is available through the `scan` subcommand. `--rules` / `-r` is
required. The long option accepts both `--rules <rules-root>` and
`--rules=<rules-root>` forms. One optional positional `scan-root` may appear in
the `scan` argument list and defaults to `.`. If the rules option appears
multiple times, the last value wins. Usage errors print a message and exit with
code 2: missing `scan` command, missing rules option, missing rules value,
unknown options, or more than one scan root. Non-usage errors, including
unreadable paths, an empty rules directory, invalid YAML/schema/shape, or source
read failures, abort the run; the CLI prints the error and exits with code 1.

If `scan-root` is omitted, `moongrep` scans the current directory:

```bash
moon runwasm moonbit-community/moongrep -- scan --rules path/to/rules
moon runwasm moonbit-community/moongrep -- scan -r path/to/rules
```

The scanner recursively reads `.mbt` files. When descending from `scan-root`,
child entries named `.git`, `_build`, `.mooncakes`, or `target` are skipped; if
one of those directories is passed explicitly as `scan-root`, it is scanned.
Symbolic links encountered during recursive source or rule traversal are
skipped. Files that fail to parse are reported as warnings and skipped; other
files continue to be scanned.

## Document

Embedded documentation is available through the `docs` subcommand:

```bash
moon runwasm moonbit-community/moongrep -- docs --list
moon runwasm moonbit-community/moongrep -- docs RuleSpec
```