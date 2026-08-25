## moongrep help

The top-level help introduces the command, lists every subcommand, and shows
the global help option.

```mooncram
$ moonrun "$TESTDIR"/moongrep.wasm -- help
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

## moongrep subcommands without arguments

The `docs` and `dump` subcommands print their help when invoked without
arguments. `scan` and `lint` instead treat an omitted scan root as the current
directory. `scan` uses its default rules directory, while `lint` enables
builtin rules automatically.

The docs subcommand uses the same no-argument help behavior.

```mooncram
$ moonrun "$TESTDIR"/moongrep.wasm -- docs > /dev/null && diff -u <(moonrun "$TESTDIR"/moongrep.wasm -- docs --help) <(moonrun "$TESTDIR"/moongrep.wasm -- docs)
```

The dump subcommand also prints help instead of attempting to parse an empty
input.

```mooncram
$ moonrun "$TESTDIR"/moongrep.wasm -- dump > /dev/null && diff -u <(moonrun "$TESTDIR"/moongrep.wasm -- dump --help) <(moonrun "$TESTDIR"/moongrep.wasm -- dump)
```

## moongrep docs

The docs registry lists the English rule and CLI specifications in that order.

```mooncram
$ moonrun "$TESTDIR"/moongrep.wasm -- docs --list
RuleSpec	YAML rule keys, validation, and matcher semantics.
CLISpec	Command-line parsing, scanning, output, diagnostics, and exit behavior.
```

The named CLI document prints the embedded source.

```mooncram
$ moonrun "$TESTDIR"/moongrep.wasm -- docs CLISpec | grep -E '^# Command-Line Interface Specification$|^## (`scan` and `lint`|JSON Lines Output|Diagnostics and Exit Status)$'
# Command-Line Interface Specification
## `scan` and `lint`
## JSON Lines Output
## Diagnostics and Exit Status
```

Running bare `lint` from a fixture directory produces the same output as an
explicit current-directory lint target.

```mooncram
$ cd "$TESTDIR"/../testdata/builtin-rules && diff -u <(moonrun "$TESTDIR"/moongrep.wasm -- lint) <(moonrun "$TESTDIR"/moongrep.wasm -- lint .)
```

## moongrep lint --help

The lint help lists the options accepted by `lint`.

```mooncram
$ moonrun "$TESTDIR"/moongrep.wasm -- lint --help
Usage: moongrep lint [options] [scan-root]

Scan MoonBit source files with embedded builtin rules.

Arguments:
  scan-root  Directory to scan.

Options:
  -h, --help                     Show help information.
  --verbose                      Write loaded rule ids and traversal progress to stderr.
  --output-json                  Write each match as one JSON record to stdout.
  -r, --rules <rules>            Directory containing YAML rules.
  --rule <rule>                  Single YAML rule file.
  --pattern <pattern>            Anonymous structural pattern to match.
  --guard <guard>                YAML guard map for the preceding anonymous pattern.
  --exclude-dir <exclude-dir>    Directory name or path to skip while recursively scanning. May be repeated.
  --exclude-rule <exclude-rule>  Rule id to disable after loading rules. May be repeated.
```

## moongrep scan --help

The scan help documents the scan root together with every rule source,
filtering, output, and traversal option accepted by the scanner.

```mooncram
$ moonrun "$TESTDIR"/moongrep.wasm -- scan --help
Usage: moongrep scan [options] [scan-root]

Scan MoonBit source files.

Arguments:
  scan-root  Directory to scan.

Options:
  -h, --help                     Show help information.
  --verbose                      Write loaded rule ids and traversal progress to stderr.
  --output-json                  Write each match as one JSON record to stdout.
  -r, --rules <rules>            Directory containing YAML rules. [default: ./.moongrep/rules]
  --rule <rule>                  Single YAML rule file.
  --pattern <pattern>            Anonymous structural pattern to match.
  --guard <guard>                YAML guard map for the preceding anonymous pattern.
  --exclude-dir <exclude-dir>    Directory name or path to skip while recursively scanning. May be repeated.
  --exclude-rule <exclude-rule>  Rule id to disable after loading rules. May be repeated.
```

## moongrep lint builtin rules

Linting without a separate rule directory reports every embedded rule that
matches the fixture. The default human-readable output includes locations,
rule metadata, and source context.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- lint testdata/builtin-rules
testdata/builtin-rules/hit.mbt:3:3-3:26
rule: moonbitlang/inspect_number
description:
  Found inspect() snapshots whose expected value is a plain number.
  Prefer numeric assertions for numeric checks.
source:
1 | ///|
2 | fn has_builtin_hits(value : Int?) -> Unit {
3 >   inspect(1, content="1")
4 |   assert_true(
5 |     match value {

testdata/builtin-rules/hit.mbt:5:5-8:6
rule: moonbitlang/match_option
description:
  Found an Option value handled with match over Some and None.
  Prefer if + is for simple Option checks.
source:
 3 |   inspect(1, content="1")
 4 |   assert_true(
 5 >     match value {
 6 >       Some(inner) => inner > 0
 7 >       None => false
 8 >     },
 9 |   )
10 | }
```

## moongrep scan rejects the removed builtin option

Builtin rules are only available through `lint`. The former scan option is an
unknown option and returns exit status 2.

```mooncram
$ moonrun "$TESTDIR"/moongrep.wasm -- scan --enable-builtin-rules
error: unexpected argument '--enable-builtin-rules' found

Usage: moongrep scan [options] [scan-root]

Scan MoonBit source files.

Arguments:
  scan-root  Directory to scan.

Options:
  -h, --help                     Show help information.
  --verbose                      Write loaded rule ids and traversal progress to stderr.
  --output-json                  Write each match as one JSON record to stdout.
  -r, --rules <rules>            Directory containing YAML rules. [default: ./.moongrep/rules]
  --rule <rule>                  Single YAML rule file.
  --pattern <pattern>            Anonymous structural pattern to match.
  --guard <guard>                YAML guard map for the preceding anonymous pattern.
  --exclude-dir <exclude-dir>    Directory name or path to skip while recursively scanning. May be repeated.
  --exclude-rule <exclude-rule>  Rule id to disable after loading rules. May be repeated.
[2]
```

## moongrep dump --help

The dump help exposes separate inputs for parsing a top-level implementation
item and a single expression.

```mooncram
$ moonrun "$TESTDIR"/moongrep.wasm -- dump --help
Usage: moongrep dump [options]

Parse a MoonBit impl or expression and print untyped CST debug output.

Options:
  -h, --help     Show help information.
  --impl <impl>  MoonBit top-level implementation item to parse.
  --expr <expr>  MoonBit expression to parse.
```

## moongrep dump --expr

Dumping an infix expression produces an untyped CST whose root contains the
expected `Expr_Infix` node kind.

```mooncram
$ moonrun "$TESTDIR"/moongrep.wasm -- dump --expr 'x + 1' | grep 'kind: Expr_Infix'
  kind: Expr_Infix,
```
