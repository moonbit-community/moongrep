# moongrep

`moongrep` is an experimental MoonBit structural search and taint-analysis tool.
Matching rules are declared as YAML files. 

## Scan

Run the scanner with a rule directory and an optional scan target directory or
`.mbt` file:

```bash
moon runwasm moonbit-community/moongrep -- scan --rules path/to/rules path/to/src
moon runwasm moonbit-community/moongrep -- scan --pattern 'target()' path/to/src
```

Synopsis:

```text
moon runwasm moonbit-community/moongrep -- scan [--verbose] ((--rules <rules-root> | --rules=<rules-root> | -r <rules-root>) | --pattern <pattern>)... [scan-root]
```

The scanner is available through the `scan` subcommand. `--rules` / `-r` is
optional when at least one `--pattern <pattern>` is supplied. The long rules
option accepts both `--rules <rules-root>` and `--rules=<rules-root>` forms.
Inline patterns are treated as anonymous structural rules whose rule id is the
pattern string itself, with the CLI placeholder description and no declared
metavars. One optional positional `scan-root` may appear in the `scan` argument
list and defaults to `.`. If the rules option appears multiple times, the last
value wins. Repeated `--pattern` values are appended as separate anonymous
rules. Usage errors print a message and exit with code 2: missing `scan`
command, missing both rules and pattern options, missing option value,
unknown options, or more than one scan root. Non-usage errors, including
unreadable paths, an empty rules directory, invalid YAML/schema/shape, or source
read failures, abort the run; the CLI prints the error and exits with code 1.
Pass `--verbose` to print the directory traversal progress before warnings and
match results.

If `scan-root` is omitted, `moongrep` scans the current directory:

```bash
moon runwasm moonbit-community/moongrep -- scan --rules path/to/rules
moon runwasm moonbit-community/moongrep -- scan -r path/to/rules
moon runwasm moonbit-community/moongrep -- scan --pattern 'target()'
```

The scanner recursively reads `.mbt` files. When descending from `scan-root`,
child entries named `.git`, `_build`, `.mooncakes`, or `target` are skipped; if
one of those directories is passed explicitly as `scan-root`, it is scanned.
Symbolic links encountered during recursive source or rule traversal are
followed. Files that fail to parse are reported as warnings and skipped; other
files continue to be scanned.

## Document

Embedded documentation is available through the `docs` subcommand:

```bash
moon runwasm moonbit-community/moongrep -- docs --list
moon runwasm moonbit-community/moongrep -- docs RuleSpec
```
