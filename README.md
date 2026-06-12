# moongrep

`moongrep` is an experimental MoonBit structural search and taint-analysis tool.
Matching rules are declared as YAML files. See
[docs/WritingRules.md](docs/WritingRules.md) for the rule authoring guide and
[docs/RuleSpec.md](docs/RuleSpec.md) for the YAML rule format.

## Command Line

Run the scanner with a rule directory and an optional scan target directory or
`.mbt` file:

```bash
moon run . -- scan --rules path/to/rules path/to/src
```

Synopsis:

```text
moon run . -- scan (--rules <rules-root> | --rules=<rules-root> | -r <rules-root>) [scan-root]
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
moon run . -- scan --rules path/to/rules
moon run . -- scan -r path/to/rules
```

Embedded documentation is available through the `docs` subcommand:

```bash
moon run . -- docs --list
moon run . -- docs RuleSpec
```

The scanner recursively reads `.mbt` files. When descending from `scan-root`,
child entries named `.git`, `_build`, `.mooncakes`, or `target` are skipped; if
one of those directories is passed explicitly as `scan-root`, it is scanned.
Symbolic links encountered during recursive source or rule traversal are
skipped. Files that fail to parse are reported as warnings and skipped; other
files continue to be scanned.

Human-readable output starts with parse warnings, if any, followed by one block
per hit:

```text
warning: skipping src/broken.mbt: parse failed due to syntax error

src/example.mbt:10:3-10:24
rule: security/raw-html
outer_loc: src/example.mbt:8:1-12:2
description:
  User-controlled HTML reaches a raw HTML sink.
```

If there are no hits, the final output section is `no match hits`, after any
parse warnings. For `inside-expr` structural rules, hits include `outer_loc`
between `rule:` and `description:`; it points at the outer expression that
established the context.

## Current Limitations

- The stable user-facing entry point is the CLI; library APIs are still
  experimental.
- Matching is AST based and location preserving. Reported locations are exactly
  the locations supplied by the parser/tree builder.
- Rule `guard` keys are rejected in runtime AST mode.
- Taint analysis is intra-procedural. Cross-function behavior must be described
  with call models or matched directly by rule shapes.
- Unknown call handling depends on the selected `taint.UnknownCallPolicy`; YAML
  taint rules currently use a conservative no-effect policy except for explicit
  rule source, sink, and sanitizer shapes.
