# Command-Line Interface Specification

This document specifies how the `moongrep` CLI selects commands and rule
sources, traverses and scans MoonBit files, formats output and diagnostics, and
assigns exit codes.

For YAML rule syntax, validation, and matcher semantics, see
[RuleSpec.md](RuleSpec.md). Paths and rule IDs are compared as case-sensitive
strings unless a section explicitly states otherwise.

## Invocation and command selection

### Invocation forms

| Distribution | Command form |
| --- | --- |
| Installed binary | `moongrep <command> [arguments]` |
| Published Wasm CLI | `moonx moonbit-community/moongrep -- <command> [arguments]` |
| Local Wasm artifact | `moonrun path/to/moongrep.wasm -- <command> [arguments]` |

In the WebAssembly forms, `--` separates runner arguments from `moongrep`
arguments. Everything after `--` behaves identically to invoking the installed
executable directly.

### Top-level commands

| Command | Summary | Behavior with no extra arguments |
| --- | --- | --- |
| `scan` | Scan MoonBit source with explicit or default rules. | Scans `.` using `./.moongrep/rules`. |
| `lint` | Scan MoonBit source with embedded builtin rules enabled. | Scans `.` using builtin rules. |
| `docs` | List or print embedded documentation. | Prints `docs` help and exits `0`. |
| `dump` | Parse one top-level item or expression for CST debug output or validation. | Prints `dump` help and exits `0`. |

Running `moongrep` with no command prints a missing-subcommand diagnostic and
top-level help, then exits with status `2`.

### Version and help

- **Version**: `moongrep --version` and `moongrep -V` print the module version
  from `moon.mod` to standard output and exit `0` without requiring a
  subcommand.
- **Help**: `-h` and `--help` print help for the active command. `moongrep help`
  prints top-level help, and `moongrep help <command>` prints help for that
  command. All help forms write to standard output and exit `0`.

## `scan` and `lint`

### Syntax

```text
moongrep scan [options] [scan-root]
moongrep lint [options] [scan-root]
```

At most one `scan-root` positional argument is accepted. It may appear before,
between, or after options, and defaults to `.` when omitted.

### Options

| Option | Value | Purpose | Repeated behavior |
| --- | --- | --- | --- |
| `-r`, `--rules` | `<dir>` | Select a directory of YAML rules. | Last value wins. |
| `--rule` | `<file>` | Select one YAML rule file (lowercase `.yaml` or `.yml`). | Last value wins. |
| `--pattern` | `<source>` | Add an anonymous structural expression pattern. | All retained in order. |
| `--guard` | `<yaml>` | Attach a YAML guard map to the most recent unguarded `--pattern`. | At most one per pattern. |
| `--exclude` | `<name-or-path>` | Skip matching child file or directory entries. | All retained in order. |
| `--disable` | `<rule-id>` | Disable a loaded rule by exact ID. | All retained in order (duplicates deduplicated). |
| `--strict-taint` | flag | Exit with status `8` if taint analysis is incomplete (off by default). | Equivalent to one occurrence. |
| `--verbose` | flag | Write rule-loading and traversal trace events to stderr. | Equivalent to one occurrence. |
| `--json` | flag | Write findings and diagnostics as JSON Lines. | Equivalent to one occurrence. |
| `-h`, `--help` | flag | Print command help and exit `0`. | Equivalent to one occurrence. |

Additional option rules:

- Long options taking a value accept both `--option value` and
  `--option=value`. Among them, only `--rules` has a short form (`-r`).
- `--enable-builtin-rules` is not accepted by either command; embedded builtin
  rules are enabled only through `lint`.
- Color output is controlled by the `NO_COLOR` environment variable (see
  [Color](#color)).
- Multiple `scan-root` positionals, missing option values, unknown options, and
  unknown commands are usage errors (status `2`).

### Scan root and platform path rules

`scan-root` may be a directory or a single regular file:

- Directories are traversed recursively.
- A regular file is scanned only when its path ends in exact lowercase `.mbt`.
- Directory symlinks are followed. Each resolved directory identity (via
  `realpath`) is entered at most once, so symlink cycles and repeated aliases
  are skipped. Rendered findings and events keep the traversal (symlink) path.

Platform path handling:

- **Linux and macOS**: Retain the supplied `scan-root` spelling and join child
  paths with `/`.
- **Windows**: Lexically normalize `scan-root` before any filesystem call. Both
  `/` and `\` are accepted as separators, repeated separators are collapsed, and
  `.` / `..` components are normalized using Windows path rules (without turning
  a relative root into an absolute path). Child paths are joined with `\`. The
  same normalized native path is used for filesystem access, findings, warnings,
  verbose events, and JSON output. Directory identity checks resolve symlinks
  separately without altering the rendered path.

### Rule sources and loading order

`scan` and `lint` can combine multiple rule sources. Regardless of flag order on
the command line, sources are always loaded in this fixed category order:

1. Embedded builtin rules (`lint` only).
2. The effective `--rules` directory, if present.
3. The effective `--rule` file, if present.
4. Anonymous `--pattern` rules, in command-line order.

Default-source behavior:

- For `scan`, `./.moongrep/rules` is used when none of `--rules`, `--rule`, or
  `--pattern` is provided. Passing any of those options replaces the default
  directory; an explicit `--rules` directory combines with `--rule` and
  `--pattern`.
- For `lint`, builtin rules are always loaded first, and explicit `--rules`,
  `--rule`, and `--pattern` options append additional sources after them.

Single-file and path rules for rule sources:

- The suffix check for `--rule` is case-sensitive on all platforms (lowercase
  `.yaml` or `.yml`). A readable file with any other suffix is rejected as
  invalid rule content (status `5`).
- On Windows, effective `--rules` and `--rule` paths are lexically normalized
  before filesystem access; recursive rule discovery joins paths with `\` and
  the containing directory of `--rule` follows Windows path rules. Linux and
  macOS keep `/`-based path construction.
- Directory symlinks are followed during rule discovery, and each resolved rule
  directory is visited at most once.
- Rule-directory discovery, rule IDs, YAML validation, intra-directory ordering,
  and compilation are defined in [RuleSpec.md](RuleSpec.md).

### Anonymous patterns and guards

- Each `--pattern` creates a structural rule with one positive pattern, rule ID
  equal to the pattern source text, description `Anonymous CLI pattern.`, and
  default match mode.
- Each `--guard` attaches to the most recent preceding `--pattern` that does not
  already have a guard. Providing `--guard` with no eligible preceding pattern
  is a usage error (status `2`).
- The `--guard` argument must be a single YAML document containing a mapping
  whose keys are nonempty `$`-prefixed names and whose values are strings.
  Malformed YAML, multiple documents, non-mapping documents, invalid keys, or
  non-string values are usage errors (status `2`).
- Capture compatibility and regular-expression compilation are validated during
  rule compilation (status `5`); see [RuleSpec.md](RuleSpec.md).

### Rule disabling (`--disable`)

- All selected rule sources are loaded before `--disable` is applied.
- Disabled IDs are matched exactly and case-sensitively against the combined
  loaded rule IDs on every platform.
- Every requested ID must match a loaded rule; the first unknown ID causes a
  usage error (status `2`).
- Disabled rules are removed before rule compilation and scan planning. Repeated
  IDs are treated as one. Verbose `rule_loaded` events report only rules that
  remain enabled.

## File traversal

### Eligible files and traversal order

- Under a directory target, `moongrep` visits entries recursively, parsing only
  regular files whose path ends in exact lowercase `.mbt` (case-sensitive on
  every platform) and ignoring other entries.
- A missing or unreadable target fails the scan (status `6`). An existing
  regular file without a `.mbt` suffix succeeds with zero findings (status `0`).
- Directory entries are sorted and traversed depth-first, finishing each entry
  completely before moving to the next sibling. Findings, warnings, and verbose
  events stream in this exact traversal order.
- Filesystem kind checks follow symlinks at and below `scan-root`. Resolved
  directory identities (`realpath`) are visited at most once per scan; symlink
  cycles and later aliases are skipped.

### Default directory exclusions

At every depth below `scan-root`, child entries matching any of these names are
skipped:

- Any entry name starting with `.` (case-independent).
- `_build`
- `node_modules`
- `target`

Exact-name comparison is case-sensitive on Linux and macOS, and case-insensitive
(via per-character Unicode lowercase mapping) on Windows. Default exclusions
apply only to discovered children; an explicitly passed `scan-root` whose final
component matches one of these names is still scanned.

### Explicit exclusions (`--exclude`)

Normalization before comparison:

- **Linux and macOS**: Strip trailing `/` characters (keeping a lone `/`), then
  strip all leading `./` prefixes. For example, `./vendor/` becomes `vendor` and
  `./src/generated///` becomes `src/generated`. Other components such as `..`
  stay literal.
- **Windows**: Accept both `/` and `\`, collapse repeated separators, and
  normalize `.` / `..` with Windows path rules. Non-root trailing separators are
  removed, while roots such as `C:\` and `\\server\share\` keep their trailing
  separator. An empty exclusion stays empty.

Matching rules:

- Before visiting a child entry, each normalized exclusion is compared against
  both the child's entry name and the normalized constructed child path. A full
  string match on either skips the entry.
- Comparisons are case-sensitive on Linux and macOS, and case-insensitive
  (per-character Unicode lowercase) on Windows.
- Glob characters (`*`, `?`, `[`, etc.) are treated as ordinary literal
  characters on every platform.
- Because entry names are checked at every depth, `--exclude vendor` skips every
  entry named `vendor`, and `--exclude generated.mbt` skips every file named
  `generated.mbt`.
- A multi-component path such as `src/generated` matches only a child whose
  constructed path equals it under platform comparison rules. An absolute
  exclusion matches only an absolute constructed child path; a relative
  `scan-root` is not resolved just to match an absolute exclusion.
- Exclusions apply only to children discovered during directory traversal, not
  to `scan-root` itself.

## Source processing

### Prefiltering

Compiled rules produce a scan plan containing conservative source-text
prefilters:

1. `moongrep` first filters the entire file text; if every enabled rule is
   filtered out, block splitting and parsing are skipped completely.
2. Otherwise, each source block is filtered independently, and only blocks with
   at least one remaining candidate rule are parsed.

Because irrelevant files and blocks are never parsed, only source retained by
both prefilters can emit parse or attribute warnings.

### Source blocks and parse warnings

- Any line starting with `///|` at column 1 begins a new source block, and that
  delimiter line belongs to the new block. Indented `///|` text remains inside
  the current block. A file without later delimiters is parsed as one block.
- Each relevant block is parsed as MoonBit top-level structure. If parsing emits
  a diagnostic or leaves a recovery node, that block is skipped and one warning
  is written to stderr; other relevant blocks in the same file continue
  scanning.
- In a multi-block file, the warning reports the skipped block's original
  starting line. In a single-block file, it identifies only the file. Parser
  messages are compacted onto a single line. Parse warnings keep exit status `0`
  (unless taint analysis is affected under `--strict-taint`; see
  [Incomplete taint analysis](#incomplete-taint-analysis)).

### `#moongrep.skip`

- A bare `#moongrep.skip` attribute on a parsed top-level item suppresses all
  structural rules for that entire item. Taint rules still run on it.
- Payload forms such as `#moongrep.skip()` are invalid: each invalid attribute
  emits a source-located warning (`invalid_skip_payload`) and does not suppress
  structural rules. If the same item has both a bare `#moongrep.skip` and an
  invalid payload form, structural rules are suppressed while each invalid
  payload still emits its warning.
- Attribute checks run after prefiltering and successful parsing, so warnings
  only come from blocks retained by prefilters and parsed cleanly.

## Output streams and ordering

### Standard output vs. standard error

| Stream | Contents |
| --- | --- |
| `stdout` | `scan`/`lint` findings (`no match hits` in human mode when zero findings; empty in JSON mode), help text, `docs` output, and `dump` text/JSON output (empty for successful `dump --exit-code`). |
| `stderr` | All fatal error diagnostics (statuses `1`–`8`), parse warnings, invalid `#moongrep.skip` warnings, `taint_incomplete` warnings, and `--verbose` trace events. |

### Verbose events (`--verbose`)

When `--verbose` is enabled, `moongrep` emits four traversal events to stderr:

- `moongrep scan: loaded rule <id>` — once per enabled compiled rule, before
  traversal begins.
- `moongrep scan: entering <path>` — when entering a directory.
- `moongrep scan: skipping <path>` — when a path is skipped due to an exclusion
  or an already-visited directory.
- `moongrep scan: file <path>` — before processing an eligible `.mbt` file.

In JSON mode, stderr emits `trace`, `warning`, and `error` JSON Lines records
instead of plain text, while stdout emits only `finding` records.

### Streaming order

- Each finding is written in full before traversal continues. Human mode
  separates consecutive findings with a blank line; JSON mode writes one
  newline-terminated record per finding with no extra blank line.
- Warnings and verbose events appear on stderr at the point in traversal where
  they occur.
- A later fatal failure writes an error diagnostic to stderr without withdrawing
  findings already written to stdout.

## Human-readable output

### Finding layout and coordinates

```text
<file>:<start-line>:<start-column>-<end-line>:<end-column>
rule: <rule-id>
description:
  <description line 1>
  <description line 2>
source:
<number> <marker> <source line>
```

- Trailing newline characters are stripped from `description`, and each
  remaining line is indented by two spaces. An empty description still emits one
  indented empty line.
- Line and column numbers are 1-based; columns count Unicode code points. A
  non-BMP character (such as an emoji) counts as one column, and combining marks
  count individually rather than as grapheme clusters. Start is inclusive; end
  is exclusive.

### Source context and long matches

- Context includes up to two lines before the first matched line, the displayed
  matched lines, and up to two lines after the last matched line. Line numbers
  are right-aligned to the widest line number in that finding.
- Matches spanning `<= 6` lines show every matched line. Matches spanning `>= 7`
  lines show the first three and last three matched lines and replace the middle
  with one omission line stating the omitted line range and line count.
- JSON `matched_source` and `source_context` always include all lines without
  truncation.

### Color

- Color is enabled by default. Only the exact environment setting `NO_COLOR=1`
  disables it; an unset variable or any other value (including `""` or `true`)
  keeps color enabled.
- **Color enabled**: matched source slices are bright yellow, nonmatching
  context and omission rows are bright black, and all rows use ` | ` as the
  separator.
- **Color disabled (`NO_COLOR=1`)**: plain text output where matched and omitted
  rows use ` > ` and nonmatching context rows use ` | `.

## JSON Lines Output

### Protocol and mode detection

- `--json` enables structured JSON Lines output for `scan`, `lint`, and `dump`.
- `--json` must appear as a standalone argument before any `--` option
  terminator (for example, `scan -- --json` and `dump -- --json` do not enable
  JSON mode), and the initial command must be `scan`, `lint`, or `dump`.
- For `scan` and `lint`, every nonempty line written to stdout or stderr is one
  compact JSON object. For `dump`, a successful non-`--exit-code` run writes one
  compact JSON object to stdout.
- Successful help and `docs` output are outside this protocol; in particular,
  `dump --json --help` prints ordinary plain-text help.
- Mode detection runs before full argument parsing, so usage failures (unknown
  options, missing option values, etc.) emit a JSON `error` record whenever a
  qualifying `--json` is present.

### Record schemas

#### `finding` (stdout)

```text
{
  "type": "finding",
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

Contains exactly these fields. Trailing newline characters are stripped from
`description`.

#### `warning` (stderr)

```text
{ "type": "warning", "category": "parse", "message": string,
  "file": string, "reason": string, "block_start_line": integer? }

{ "type": "warning", "category": "invalid_skip_payload", "message": string,
  "file": string, "range": range }

{ "type": "warning", "category": "taint_incomplete", "message": string,
  "file": string, "range": range, "rule_ids": [string], "reason": string }
```

`block_start_line` is present on `parse` warnings only for multi-block files
where the skipped block's starting line is identified.

#### `trace` (stderr, with `--verbose`)

```text
{ "type": "trace", "event": "rule_loaded", "rule_id": string }
{ "type": "trace", "event": "directory_entered", "path": string }
{ "type": "trace", "event": "path_skipped", "path": string }
{ "type": "trace", "event": "file_started", "path": string }
```

#### `dump` (stdout)

```text
{ "type": "dump", "kind": "impl" | "expr", "content": string }
```

Written as a single line on successful `dump --json`, with fields in exact order
`type`, `kind`, `content`. `content` is the same CST `Repr` text printed in
human mode (JSON-escaped onto one physical line). `dump --exit-code --json`
stays silent when all requested checks pass.

#### `error` (stderr)

```text
{ "type": "error", "category": string, "exit_code": integer,
  "message": string, "source": string?, "pattern": string?,
  "reason": string?, "help": string? }
```

`category` is one of `internal`, `usage`, `dump_input`, `rule_source`,
`rule_content`, `scan_input`, `output`, or `taint_incomplete`.

- For structured diagnostics, `message` is the summary line.
- For argparse diagnostics, `message` is the full multiline parser message as
  one escaped JSON string.
- Empty optional fields are omitted.
- `pattern` line endings are normalized to LF with one trailing line ending
  removed, matching human mode.

### Coordinates, context, and no-match behavior

- `range` uses the same 1-based Unicode code-point columns as human output
  (start inclusive, end exclusive).
- `matched_source` is the exact source slice covered by `range`.
- `source_context` uses the same two-line-before and two-line-after window as
  human output (without truncating long matches). `is_match` is `true` for every
  physical line intersected by `range`, even when only part of the first or last
  line matches.
- Every JSON record ends with a single newline. A scan with zero findings writes
  zero bytes to stdout (stderr may still contain `warning`, `trace`, or `error`
  records).

## `docs`

```text
moongrep docs --list
moongrep docs <document-name>
```

- `--list` prints registered document names and summaries in registry order,
  separated by a single tab:

```text
RuleSpec	YAML rule keys, validation, and matcher semantics.
CLISpec	Command-line parsing, scanning, output, diagnostics, and exit behavior.
```

- The registry embeds the English sources of `RuleSpec` and `CLISpec` in that
  order (Chinese `_CN.md` translations live in the repository).
- Lookup is exact and case-sensitive. An unknown name, combining `--list` with a
  name, passing multiple names, or passing an unknown option exits with status
  `2`.
- Invoking `moongrep docs` without arguments prints `docs` help and exits `0`.

## `dump`

```text
moongrep dump [--exit-code] [--strict-check] [--json] --impl <source>
moongrep dump [--exit-code] [--strict-check] [--json] --expr <source>
```

- **Input options** (mutually exclusive, exactly one required):
  - `--impl <source>`: must parse as exactly one valid MoonBit top-level item
    with no diagnostics or recovery nodes.
  - `--expr <source>`: must parse as one valid MoonBit expression with no
    diagnostics or recovery nodes.
- **Strict pattern validation (`--strict-check`)**:
  - Runs only after the base dump parse succeeds.
  - `--expr` is compiled as an ordinary structural expression pattern.
  - `--impl` is compiled with default `inside-toplevel` semantics: it must
    contain exactly one `__TARGET__` in a supported expression position, and
    function shapes use the default `partial` match mode. Guards and explicit
    match-mode flags are not accepted.
  - Does not alter the CST printed on success (output always comes from the
    initial parse).
- **Output and `--exit-code`**:
  - On success without `--exit-code`, text mode prints the untyped CST's MoonBit
    `Repr` debug string to stdout, and `--json` wraps that same string in one
    `dump` record.
  - `--exit-code` suppresses all CST output and takes precedence over `--json`:
    a passing check writes nothing to stdout or stderr and exits `0`.
- **Failure statuses**:
  - Bare `dump` with no arguments prints help and exits `0`.
  - Providing both `--impl` and `--expr`, or passing `--exit-code`,
    `--strict-check`, or `--json` without an input option, exits `2` (`dump
    --json --help` prints ordinary help and exits `0`).
  - Lexical/parse diagnostics, recovery nodes, or an `--impl` input with zero or
    multiple top-level items fail before `--strict-check` with a `dump_input`
    error and exit `3`.
  - A `--strict-check` failure writes an `invalid dump pattern` diagnostic
    (`category: "rule_content"`, original input in `pattern`) and exits `5`.
  - With `--json`, all of these failures use the standard JSON `error` record.

## Diagnostics and Exit Status

### Human diagnostic layout

Fatal diagnostics for statuses `1` through `8` use plain English text without
color:

```text
error: <summary>
  source: <relevant path or input>
  pattern:
    <pattern line 1>
    <pattern line 2>
  reason: <specific reason>
  help: <actionable suggestion>
```

- `source`, `reason`, and `help` are omitted when empty.
- `pattern` is included only when a diagnostic relates to a pattern. Each line
  is indented by four spaces, preserving relative indentation and internal blank
  lines after normalizing CRLF/CR to LF and ignoring one trailing line ending.
  An explicitly empty pattern still prints `pattern:`.
- For an anonymous `--pattern` rule, `source` is `--pattern` and the pattern
  text appears only in the `pattern` block.
- The formatter itself does not append a trailing newline; the output layer adds
  one when writing.
- Argparse diagnostics that already include `error:`, `Usage:`, and optional
  `tip:` keep their full layout. Scan warnings keep their `warning:` format.
- Human wording and optional detail lines may evolve and are not a
  machine-readable contract; use `--json` for stable parsing. Fatal diagnostics
  never appear in finding records and always go to stderr.

### Exit status summary

| Status | Category | Triggering conditions |
| ---: | --- | --- |
| `0` | Success | Help, successful `docs`, successful `dump` or `dump --exit-code` (including `--strict-check`), scans/lints with or without findings, and scans with recoverable parse or `#moongrep.skip` warnings. |
| `1` | `internal` | Damaged embedded builtin rule, unreachable command state, or any other unclassified internal error. |
| `2` | `usage` | Missing/unknown command, unknown option, missing option value, multiple scan roots, invalid/misplaced/duplicate `--guard`, conflicting `docs`/`dump` flags, unknown embedded doc name, or unknown `--disable` rule ID. |
| `3` | `dump_input` | Invalid MoonBit input to `dump` (lexical/parse diagnostics, recovery nodes, or `--impl` with zero or multiple top-level items). Checked before `--strict-check`. |
| `4` | `rule_source` | Missing, unreadable, or wrongly typed rule path; directory traversal or rule-file read failure; or a rule directory containing no `.yaml` / `.yml` files. |
| `5` | `rule_content` | Invalid YAML, schema/duplicate-ID errors, unsupported single-file `--rule` suffix, invalid pattern/guard compilation (including anonymous `--pattern`), or `dump --strict-check` pattern failures. (Damaged builtin rules use status `1`.) |
| `6` | `scan_input` | Missing scan root, directory traversal failure, or `.mbt` file read failure. (Source parse failures during scanning remain warnings with status `0`.) |
| `7` | `output` | Failure writing to stdout or stderr (including broken pipe). If writing an earlier failure diagnostic to stderr fails, status `7` takes precedence and output is not retried on stdout. Streamed findings already written are not withdrawn. |
| `8` | `taint_incomplete` | Incomplete taint analysis when `--strict-taint` is set (see below). |

### Incomplete taint analysis

`scan` and `lint` accept `--strict-taint` (disabled by default):

- Unsupported executable syntax, a nonconvergent taint SCC, or a relevant source
  block that fails to parse emits a `taint_incomplete` warning on stderr with
  the file, source range, affected rule IDs, and reason, and scanning continues.
- Unsupported functions and incomplete function/rule pairs emit no partial
  findings. Structural-only scans never prepare taint CFGs.
- In default mode, the command still exits `0` unless another error occurs.
- With `--strict-taint`, scanning finishes and the command exits with status
  `8`. In JSON mode, it also appends a final `error` record with
  `category: "taint_incomplete"` and `exit_code: 8`. Existing finding fields and
  coordinates are unaffected.
