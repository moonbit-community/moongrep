# Shared scan behavior

```mooncram-import
jq : cli/jq@0.2.1
wc : cli/wc@0.2.0
```

## Non-BMP source

Scanning a match whose range ends on a line containing non-BMP characters
completes successfully.

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern 'let $(name:id) = $(value:exp)' ../testdata/scan-non-bmp/tmp.mbt
@STDOUT (ignore)
@STDERR (ignore)
```

## Literal prefiltering

The structural rule's literal prefilter can discard an irrelevant malformed
file before parsing it. A normal human-readable scan then reports that there
were no matches.

```mooncram moonbit-community/moongrep
$ moongrep scan --rules ../rules/structural ../testdata/prefilter-irrelevant
no match hits
```

A general rule has no literal anchor with which to discard the malformed file.
The failed parse still produces no match. Its warning is written to standard
error, while the normal no-match summary is written to standard output.

```mooncram moonbit-community/moongrep
$ moongrep scan --rules ../rules/general ../testdata/prefilter-general
no match hits
```

## Continuation captures

A terminal named expression metavar captures the complete continuation even
when the owning statement is inside a nested block.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --pattern 'wrapper({ let item = source(); $(body:exp) })' ../testdata/continuation-regressions | jq -r '"\(.range.start.line):\(.range.start.column)-\(.range["end"].line):\(.range["end"].column)"'
2:3-6:5
```

A continuation pattern without an explicit block wrapper matches each empty,
single-expression, and multi-expression block once. Each range includes the
block braces.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --pattern 'let value = load(); $(body:exp)' ../testdata/continuation-regressions | jq -r '"\(.range.start.line):\(.range.start.column)-\(.range["end"].line):\(.range["end"].column)"'
10:11-10:33
14:11-17:4
21:11-25:4
```

A terminal ignore placeholder after a continuation-owning statement matches
the complete suffix without binding it. Empty, single-expression, and
multi-expression suffixes all match, and each range covers the complete
`wrapper` block expression.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --pattern 'wrapper({ let value = load(); $_ })' ../testdata/continuation-regressions | jq -r '"\(.range.start.line):\(.range.start.column)-\(.range["end"].line):\(.range["end"].column)"'
10:3-10:34
14:3-17:5
21:3-25:5
```

## Function body candidates

Function body braces are traversal containers rather than expression matches.
The JSON range and matched source for a broad expression pattern therefore
refer to the expression inside the body.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --pattern '$(root:exp)' ../testdata/body-candidates/function.mbt | jq -r '"\(.range.start.line):\(.range.start.column)-\(.range["end"].line):\(.range["end"].column) \(.matched_source | @json | .[1:-1])"'
3:3-3:13 f <| value
```

An explicit block shape does not match those function body braces.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --pattern '{ a; b }' ../testdata/body-candidates/function.mbt
```

The same shape does match a block written inside the body, and its JSON range
and matched source include the explicit braces.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --pattern '{ a; b }' ../testdata/body-candidates/explicit.mbt | jq -r '"\(.range.start.line):\(.range.start.column)-\(.range["end"].line):\(.range["end"].column) \(.matched_source | @json | .[1:-1])"'
3:3-3:11 { a; b }
```

## Constant source spelling

Constant equality preserves the spelling stored in the parser CST instead of
normalizing numeric values. A literal `1000` pattern therefore matches only the
identically spelled call; the equivalent `1_000` call is omitted.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --pattern 'literal(1000)' ../testdata/constant-spelling/sample.mbt | jq -r '.matched_source | @json | .[1:-1]'
literal(1000)
```

The same comparison applies when a named `const` metavariable is repeated.
Pairs with consistent spelling match, while `repeated(1000, 1_000)` does not.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --pattern 'repeated($(value:const), $(value:const))' ../testdata/constant-spelling/sample.mbt | jq -r '.matched_source | @json | .[1:-1]'
repeated(1000, 1000)
repeated(1_000, 1_000)
```

## Rule filtering

A disabled id must refer to a loaded rule. An unknown id is a command-line
error and returns exit status 2.

```mooncram moonbit-community/moongrep
$ moongrep scan --rules ../rules/prefilter --disable missing ../testdata/prefilter-impl
@STDOUT (ignore)
@STDERR
error: unknown rule id in --disable
  source: missing
  help: use the exact id of a loaded rule
[2]
```

## Nonmatching rules

A rule directory whose patterns do not match the source produces no hits.

```mooncram moonbit-community/moongrep
$ moongrep scan --rules ../rules/other ../testdata/custom-rules
no match hits
```

## Empty JSON output

JSON mode writes no summary record when there are no matches. The empty stream
therefore has a byte count of zero.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --rules ../rules/structural ../testdata/prefilter-irrelevant | wc -c
0
```

## Taint CST fields

Migrated CST fields preserve taint flows through foreach binders, `noraise`
cases, array reads and writes, and `if` else branches.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --rules ../rules/cst-regressions ../testdata/taint-cst-regressions | jq -r '.matched_source | @json | .[1:-1]'
item
result
values[0]
get_user_input()
get_user_input()
value
```

## Case-sensitive source suffix

The source suffix check is case-sensitive on every platform. An explicitly
selected `.MBT` file is not scanned as a lowercase `.mbt` source file.

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern 'target()' ../testdata/exclude-dirs/uppercase.MBT
no match hits
```
