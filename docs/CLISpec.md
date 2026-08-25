# Command-Line Interface Specification

This document specifies the current moongrep command-line interface. It covers
command selection, rule-source selection, scanning, output, diagnostics, and
process exit behavior.

[RuleSpec.md](RuleSpec.md) specifies the YAML rule format, rule validation, and
matcher semantics. Paths and rule ids are compared as case-sensitive strings
unless a section says otherwise.

## Invocation and Command Selection

### Invocation Forms

Run an installed executable directly:

```text
moongrep <command> [arguments]
```

Run the published WebAssembly executable through Moon:

```text
moonx moonbit-community/moongrep -- <command> [arguments]
```

Run a local WebAssembly artifact with `moonrun`:

```text
moonrun path/to/moongrep.wasm -- <command> [arguments]
```

In the WebAssembly forms, `--` separates runner arguments from moongrep
arguments. Arguments after the separator follow the direct executable's
behavior.

### Top-Level Commands

moongrep provides four commands:

- `scan` scans MoonBit source with explicitly selected or default rules.
- `lint` scans MoonBit source with embedded builtin rules enabled by default.
- `docs` lists or prints embedded documentation.
- `dump` parses one MoonBit implementation item or expression and prints CST
  debug output.

Running moongrep without a command prints a missing-subcommand diagnostic and
top-level help, then exits with status 2.

### Help and No-Argument Behavior

`-h` and `--help` print help for the selected command. The `help` command
prints top-level help, and `help <command>` prints help for that command. Each
form exits with status 0.

With no additional arguments, each command behaves as follows:

- `scan` starts a normal scan with scan root `.` and default rules directory
  `./.moongrep/rules`.
- `lint` starts a normal scan with scan root `.` and builtin rules enabled.
- `docs` prints `docs` help and exits with status 0.
- `dump` prints `dump` help and exits with status 0.

Help text is written to standard output.

## `scan` and `lint`

### Syntax

```text
moongrep scan [options] [scan-root]
moongrep lint [options] [scan-root]
```

At most one `scan-root` positional argument is accepted. It may appear before,
between, or after options. When it is absent, the value is `.`.

### Options

Both commands accept:

- `-r <dir>` or `--rules <dir>`: select a directory containing YAML rules.
- `--rule <file>`: select one YAML rule file.
- `--pattern <source>`: add one anonymous structural pattern.
- `--guard <yaml>`: attach a YAML guard map to a preceding anonymous pattern.
- `--exclude-dir <name-or-path>`: skip matching traversal entries.
- `--exclude-rule <rule-id>`: disable an exact loaded rule id.
- `--verbose`: write rule-loading and traversal events to standard error.
- `--output-json`: write findings as JSON Lines records.
- `-h` or `--help`: print command help.

`--enable-builtin-rules` is not accepted by either command. Embedded builtin
rules can only be selected through `lint`.

Long options that take values accept both `--option value` and
`--option=value`. Among these options, `--rules` also has a short form. The
`NO_COLOR` environment variable controls color as described below.

### Scan Root

`scan-root` may name a directory or one regular file. Directory targets are
traversed recursively. A regular target is scanned when its path ends in
lowercase `.mbt`.

Rendered child paths and finding locations retain the path spelling supplied
by the user.

### Rule Sources and Ordering

`scan` and `lint` may combine rule sources. Sources are loaded in this fixed
category order, independent of where their options appeared:

1. embedded builtin rules, for `lint`;
2. the effective `--rules` directory, when present;
3. the effective `--rule` file, when present;
4. anonymous `--pattern` rules, in command-line order.

For `scan`, `./.moongrep/rules` is the default rules directory when the command
does not include `--rules`, `--rule`, or `--pattern`. Specifying any of these
sources replaces the default directory. An explicit `--rules` directory
combines with the other selected sources.

For `lint`, builtin rules are always the first source. Explicit `--rules`,
`--rule`, and `--pattern` values add more sources after the builtin rules.

Rule-directory discovery, rule ids, YAML validation, source ordering within a
rule directory, and matcher compilation are specified by
[RuleSpec.md](RuleSpec.md).

### Repeated Options

Repeated options have these effective values:

- The last `--rules` or `-r` value wins.
- The last `--rule` value wins.
- Every `--pattern` is retained in order.
- Every `--exclude-dir` and `--exclude-rule` is retained in order.
- Repeated Boolean flags are equivalent to one occurrence.

Usage errors include multiple scan-root positionals, missing option values,
unknown options, and unknown commands.

### Anonymous Patterns and Guards

Each `--pattern` becomes a structural rule with one positive pattern. Its rule
id is the pattern source itself and its description is `Anonymous CLI
pattern.`. Anonymous rules use the default match mode.

A `--guard` attaches to the most recent preceding pattern without a guard.
Each pattern accepts at most one guard. Providing a guard without an eligible
preceding pattern is a usage error.

The command-line guard value must contain exactly one YAML document. That
document must be a mapping whose keys are nonempty `$`-prefixed names and
whose values are strings. Malformed YAML, another top-level YAML kind,
multiple documents, an invalid key, or a non-string value is a usage error.

Whether a key names a compatible capture, whether a regular expression is
valid, and how a guard matches are rule-compilation concerns specified by
[RuleSpec.md](RuleSpec.md).

### Rule Exclusion

All selected sources are loaded before `--exclude-rule` is applied. Each
excluded id is compared exactly against the combined loaded rule ids. Every
requested id must exist; the first unknown id is a usage error with status 2.

All rules with an excluded id are removed before rule compilation and scan
planning. Repeated excluded ids are treated as one. Verbose loaded-rule events
describe the rules that remain enabled.

## File Traversal

### File and Directory Targets

For a directory target, moongrep examines child entries recursively. It parses
regular files whose path ends in lowercase `.mbt` and ignores other entries.

A missing or unreadable target is a runtime failure. An existing regular file
whose path has another suffix completes successfully with no findings.

### Traversal Order and Symbolic Links

Directory entries are sorted, then visited with depth-first traversal. The
scanner completely traverses one entry before visiting the next sibling.
Findings, warnings, and verbose events use this traversal order as their final
streaming order.

Filesystem kind checks follow symbolic links, both at the scan root and below
it. Rendered paths retain the symbolic-link path. Traversal treats each path
independently, so multiple paths can scan the same target and a recursive
symbolic-link cycle can keep traversal running.

### Default Directory Exclusions

When considering a child entry, moongrep skips these exact names at every
depth:

- `.git`
- `_build`
- `.mooncakes`
- `target`

The comparison uses the complete, case-sensitive entry name. These exclusions
apply to children during traversal. An explicitly selected scan root is still
inspected when its final path component has one of these names.

### `--exclude-dir`

Each `--exclude-dir` value is normalized by removing trailing `/` characters
while preserving a lone `/`, then removing every leading `./`. For example,
`./vendor/` becomes `vendor` and `./src/generated///` becomes
`src/generated`.

Before visiting a child, the normalized exclusions are compared exactly
against both:

- the child's entry name; and
- the constructed child path after the same normalization.

Matching either complete string skips the entry. Comparison treats glob
characters and `..` literally, retains filesystem spelling, and preserves
case. Because entry-name matching is performed at every depth, excluding
`vendor` skips every child named `vendor`. A path such as `src/generated`
matches a child only when its constructed path has that exact spelling.

## Source Processing

### Prefiltering

Compiled rules produce a scan plan with source-text prefilters. moongrep first
filters the complete file and skips splitting and parsing when every enabled
rule is filtered out. It then filters each source block independently and
parses the blocks that still have candidate rules.

Only source retained by the file and block prefilters can produce parse or
attribute warnings.

### Source Blocks and Parse Warnings

A source line beginning with `///|` in column 1 starts a source block. The
delimiter line belongs to the following block. Indented `///|` text stays in
the current block. A file with no later delimiter is parsed as one block.

Each relevant block is parsed as MoonBit top-level structure. If parsing
reports a diagnostic or leaves a recovery node, that block is skipped and one
warning is written to standard error. Other relevant blocks in the same file
continue to scan.

For a multi-block file, the warning identifies the original line at which the
skipped block starts. For a single-block file, it identifies only the file.
Parser messages are compacted onto one warning line. The exit status remains
0 after parse warnings.

### `#moongrep.skip`

On a parsed top-level item, a bare `#moongrep.skip` suppresses every structural
rule for that complete item. Taint rules still run on the item.

Payload forms such as `#moongrep.skip()` are invalid. Each invalid attribute
emits a source-located warning. Structural rules continue to run unless the
same item also has a bare `#moongrep.skip`; the bare attribute suppresses the
structural rules while each invalid payload still emits a warning. Only the
exact bare `#moongrep.skip` form suppresses structural rules.

Attribute inspection runs after prefiltering and successful parsing. Warnings
therefore come from parsed blocks retained by the prefilters.

## Output Streams and Ordering

### Standard Output

During `scan` and `lint`, findings are written to standard output as they are
found. Human mode writes `no match hits` for a scan with zero findings. JSON
mode leaves standard output empty for the same scan.

Help, embedded documentation, and dump output are also written to standard
output. Command-line usage diagnostics, unknown-document diagnostics, dump
parse diagnostics, and propagated rule-loading, rule-compilation, filesystem,
or other runtime diagnostics are rendered as ordinary command text on standard
output by the current native and WebAssembly frontends.

### Standard Error and Verbose Events

Scan parse warnings and invalid-`#moongrep.skip` warnings are always written to
standard error. `--verbose` adds these standard-error events:

- `moongrep scan: loaded rule <id>` for each enabled compiled rule, before
  traversal starts;
- `moongrep scan: entering <path>` when a directory is entered;
- `moongrep scan: skipping <path>` when a default or requested exclusion
  skips a child;
- `moongrep scan: file <path>` before an eligible `.mbt` file is processed.

Verbose events stay on standard error and outside the JSON record stream.

### Streaming Order

One complete finding is written before traversal resumes. In human mode, a
blank line separates consecutive findings. In JSON mode, every finding is one
newline-terminated record without an extra blank line.

Warnings and verbose events remain interleaved on standard error at the point
where traversal produces them. Combining standard output and standard error
therefore exposes traversal order, subject to the shell or caller's normal
handling of two streams.

## Human-Readable Output

### Finding Layout

Each finding has this structure:

```text
<file>:<start-line>:<start-column>-<end-line>:<end-column>
rule: <rule-id>
description:
  <description line 1>
  <description line 2>
source:
<number> <marker> <source line>
```

Trailing newline characters are removed from the description, and every
remaining description line is indented by two spaces. An empty description
still produces one indented empty line.

Locations use 1-based line and UTF-16 column numbers. The start is inclusive
and the end is exclusive.

### Source Context and Long Matches

Source context contains up to two lines before the first matched line, every
displayed matched line, and up to two lines after the last matched line. Line
numbers are padded to the widest number in that finding.

When a match spans at most six lines, all matched lines are displayed. When it
spans seven or more lines, human output retains the first three and last three
matched lines and replaces the matched interior with one line that reports the
omitted line range and count. JSON `matched_source` and `source_context` always
retain all lines.

### Color

Color is enabled by default. The exact environment value `NO_COLOR=1` disables
it. An unset value and every other value, including the empty string and
`true`, keep color enabled.

With color enabled, the matched source slice is bright yellow and nonmatching
context and omission rows are bright black; rows use ` | ` as the separator.
With `NO_COLOR=1`, output is plain text. Matched or omitted rows use ` > `,
while nonmatching context rows use ` | `.

## JSON Lines Output

### Record Schema

`--output-json` writes one compact JSON object per finding, with fields in this
structure:

```text
{
  "file": string,
  "rule_id": string,
  "description": string,
  "range": {
    "start": { "line": integer, "column": integer },
    "end": { "line": integer, "column": integer }
  },
  "matched_source": string,
  "source_context": [
    { "line": integer, "text": string, "is_match": boolean }
  ]
}
```

The record contains exactly the fields shown above. Trailing newline
characters are removed from `description`.

### Coordinates and Source Text

JSON range coordinates are the same 1-based UTF-16 coordinates used by human
output. `range.start` is inclusive and `range.end` is exclusive.

`matched_source` is the exact source slice covered by that range.
`source_context` contains the same two-line-before and two-line-after window
used by human output. `is_match` is true for every physical line intersected
by the range, even when only part of the first or last line is matched.

### No-Match Behavior

Every JSON record ends with one newline. A scan with zero findings writes zero
bytes to standard output. Warnings and verbose events may still be written to
standard error.

## `docs`

The command accepts exactly one of these forms:

```text
moongrep docs --list
moongrep docs <document-name>
```

`--list` prints registered names and summaries in registry order, separated by
one tab:

```text
RuleSpec	YAML rule keys, validation, and matcher semantics.
CLISpec	Command-line parsing, scanning, output, diagnostics, and exit behavior.
```

The registry contains `RuleSpec` followed by `CLISpec` and embeds their English
sources. The repository also contains `_CN.md` translations.

Document lookup is exact and case-sensitive. An unknown name exits with status
2. Combining `--list` with a name, providing more than one name, or using an
unknown option is a usage error with status 2. Invoking `docs` without
arguments prints its help and exits with status 0.

## `dump`

The command accepts exactly one of these forms:

```text
moongrep dump --impl <source>
moongrep dump --expr <source>
```

`--impl` accepts one valid MoonBit top-level item. `--expr` accepts one valid
MoonBit expression. Both forms require a parse without diagnostics or recovery
nodes.

On success, `dump` writes the MoonBit `Repr` debug rendering of the resulting
untyped CST node to standard output in CST debug text format.

Providing both `--impl` and `--expr` is a usage error with status 2. Invoking
`dump` without either option prints help and exits with status 0. Lexical or
parse diagnostics, recovery nodes, and an `--impl` result containing zero or
multiple top-level items exit with status 3.

## Diagnostics and Exit Status

moongrep uses one fixed status for each actionable failure category:

| Status | Category |
|---:|---|
| 0 | Success |
| 1 | Internal or otherwise unclassified failure |
| 2 | Command-line usage failure |
| 3 | Invalid `dump` input |
| 4 | Rule-source failure |
| 5 | Invalid rule content |
| 6 | Scan-input failure |
| 7 | Output failure |

### Exit Status 0

Status 0 means the requested command completed successfully. It includes:

- help output;
- successful `docs` listing or lookup;
- a successful CST dump;
- scans with findings;
- scans with no findings; and
- scans that emitted source parse or invalid-attribute warnings.

`lint` returns status 0 for findings and source warnings.

### Exit Status 1

Status 1 is reserved for internal failures. It includes a damaged embedded
builtin rule, an unreachable command state, and any unexpected error that has
not been assigned to another category.

### Exit Status 2

Status 2 means command-line selection or validation failed. It includes:

- a missing or unknown top-level command;
- an unknown option, missing option value, or more than one scan root;
- a `--guard` that has no eligible preceding pattern, duplicates a guard, or
  is not a valid YAML string mapping;
- combining mutually exclusive `docs` or `dump` arguments;
- an unknown embedded document; and
- an unknown rule id requested by `--exclude-rule`.

### Exit Status 3

Status 3 means `dump` received invalid MoonBit input. Lexical or syntax
diagnostics, recovery nodes, and an `--impl` result containing anything other
than one top-level item use this status.

### Exit Status 4

Status 4 means a requested rule source could not be used. It covers a missing,
unreadable, or incorrectly typed rule path, directory traversal or rule-file
reading failures, and a rule directory containing no YAML files.

### Exit Status 5

Status 5 means rule content is invalid. It covers YAML parsing, schema and
duplicate-id validation, and pattern or guard validation and compilation. This
status also applies to invalid anonymous command-line patterns. A failure in
the embedded builtin rules instead uses status 1.

### Exit Status 6

Status 6 means scan input could not be read. It covers a missing scan root,
directory traversal failures, and MoonBit source-file reading failures. A
MoonBit source parse failure encountered during scanning remains a warning and
returns status 0.

### Exit Status 7

Status 7 means writing standard output or standard error failed, including a
broken pipe. If writing an original failure diagnostic also fails, status 7
takes precedence over that failure's normal status. Findings already written
by a streaming scan are not withdrawn when a later write or scan-input failure
occurs.
