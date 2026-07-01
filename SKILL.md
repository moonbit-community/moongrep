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
moon runwasm moonbit-community/moongrep -- scan [--verbose] [--exclude-dir <dir>...] ((--rules <rules-root> | --rules=<rules-root> | -r <rules-root> | --rule <rule-file>) | --pattern <pattern>)... [scan-root]
```

The scanner is available through the `scan` subcommand. `--rules` / `-r` is
optional when `--rule <rule-file>` or at least one `--pattern <pattern>` is
supplied. The long rules option accepts both `--rules <rules-root>` and
`--rules=<rules-root>` forms. Use `--rule <rule-file>` to load exactly one YAML
rule file. Inline patterns are treated as anonymous structural rules whose rule
id is the pattern string itself. One optional positional `scan-root` may appear
in the `scan` argument list and defaults to `.`. If the rules or rule option
appears multiple times, the last value wins. Repeated `--pattern` values are
appended as separate anonymous rules.

Use `--exclude-dir <dir>...` to skip directory names or paths while recursively
scanning the source tree. When passing multiple excluded directories after one
flag, put `scan-root` before `--exclude-dir`; repeated `--exclude-dir <dir>` and
`--exclude-dir=<dir>` forms are also accepted.

Usage errors print a message and exit with code 2: missing `scan` command,
missing both rules and pattern options, missing option value, unknown options,
or more than one scan root. Non-usage errors, including unreadable paths, an
empty rules directory, invalid YAML/schema/shape, or source read failures,
abort the run; the CLI prints the error and exits with code 1.

Pass `--verbose` to print loaded rule ids and the directory traversal progress
before warnings and match results.

Each match result prints the source line covered by the finding plus up to two
lines of surrounding source context. Surrounding context lines are rendered in
gray; matched source lines are rendered without gray styling. Set `NO_COLOR=1`
to disable gray context styling and render matched source lines with `>` instead
of `|`.

If `scan-root` is omitted, `moongrep` scans the current directory:

```bash
moon runwasm moonbit-community/moongrep -- scan --rules path/to/rules
moon runwasm moonbit-community/moongrep -- scan -r path/to/rules
moon runwasm moonbit-community/moongrep -- scan --rule path/to/rule.yaml
moon runwasm moonbit-community/moongrep -- scan --pattern 'target()'
```

The scanner recursively reads `.mbt` files. When descending from `scan-root`,
child entries named `.git`, `_build`, `.mooncakes`, or `target` are skipped; if
one of those directories is passed explicitly as `scan-root`, it is scanned.
Directories supplied through `--exclude-dir` are skipped by entry name anywhere
below `scan-root`, or by exact child path.

Symbolic links encountered during recursive source or rule traversal are
followed. Files that fail to parse are reported as warnings and skipped; other
files continue to be scanned.

## Dump

MoonBit AST JSON dumps are available through the `dump` subcommand:

```bash
moon runwasm moonbit-community/moongrep -- dump --impl 'fn answer { 42 }'
moon runwasm moonbit-community/moongrep -- dump --expr 'x + 1'
```

Synopsis:

```text
moon runwasm moonbit-community/moongrep -- dump (--impl <impl> | --expr <expr>)
```

Use `--impl <impl>` to parse exactly one MoonBit top-level implementation item
and print its AST JSON. Use `--expr <expr>` to parse a MoonBit expression and
print its AST JSON. The options are mutually exclusive, and one of them is
required.

Usage errors, including missing both dump modes or combining `--impl` with
`--expr`, print a message and exit with code 2. Parse or lexical failures print
a message and exit with code 1.

## Document

Embedded documentation is available through the `docs` subcommand:

```bash
moon runwasm moonbit-community/moongrep -- docs --list
moon runwasm moonbit-community/moongrep -- docs RuleSpec
```
