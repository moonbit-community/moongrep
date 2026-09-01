## Directory scanning

When no rule source option is present, `scan` loads rules from
`./.moongrep/rules`. The path is resolved from the current directory.

```mooncram
$ cd "$TESTDIR"/../../testdata/default-rules && moonrun "$TESTDIR"/../moongrep.wasm -- scan
./src/hit.mbt:1:13-1:21
rule: example
description:
  Target call.
source:
1 > fn sample { target() }
```

The scanner ignores common repository and build directories by default. The
fixture creates matching files under the hidden directories `.git`,
`.mooncakes`, and `.xx`, as well as `_build`, `node_modules`, and `target`, but
only the source file at the scan root is reported.

```mooncram
$ cd "$TESTDIR"/../.. && sh testdata/skip-dirs/run.sh "$TESTDIR"/../moongrep.wasm
testdata/skip-dirs/hit.mbt:1:13-1:21
rule: example
description:
  Target call.
source:
1 > fn sample { target() }
```

Files and directories can be excluded by name or by path. The repeated
`--exclude` options remove the `ignored` and `generated` subtrees and the
`excluded.mbt` file, leaving only the match in the root of the fixture. The scan
root may follow them.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --verbose --rules e2etests/rules/structural --exclude ignored/ --exclude ./testdata/exclude-dirs/generated/ --exclude excluded.mbt testdata/exclude-dirs
testdata/exclude-dirs/hit.mbt:1:13-1:21
rule: example
description:
  Target call.
source:
1 > fn sample { target() }
```

## Deterministic streaming order

Sorted depth-first traversal writes the nested file before returning to the
next entry in the parent directory.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rules e2etests/rules/structural testdata/stream-order
testdata/stream-order/a/hit.mbt:2:3-2:11
rule: example
description:
  Target call.
source:
1 | fn nested {
2 >   target()
3 | }

testdata/stream-order/a.mbt:2:3-2:11
rule: example
description:
  Target call.
source:
1 | fn flat {
2 >   target()
3 | }
```

## Non-BMP source

Scanning a match whose range ends on a line containing non-BMP characters
completes successfully.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --pattern 'let $(name:id) = $(value:exp)' testdata/scan-non-bmp/tmp.mbt > /dev/null
```

## Source-level structural suppression

A bare `#moongrep.skip` suppresses every structural rule in its function while
taint analysis still runs. A payload form does not suppress structural rules.
The fixture also combines `#moongrep.skip()` with a bare marker on one function;
that function stays structurally suppressed because the bare marker remains
effective. With warnings hidden, only the payload-only function, the unmarked
function, and the taint flow under a bare marker are reported.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rules testdata/skip-structural/rules testdata/skip-structural/src 2>/dev/null | grep -E '^(testdata/|rule:)'
testdata/skip-structural/src/hit.mbt:9:3-9:11
rule: structural
testdata/skip-structural/src/hit.mbt:21:3-21:11
rule: structural
testdata/skip-structural/src/hit.mbt:28:8-28:9
rule: taint
```

Every payload form in this fixture writes a source-rebased warning to standard
error because the enabled rules keep its source blocks relevant through the
prefilter. The command still exits successfully, and the empty-payload warning
is emitted even though the same function also has a valid bare marker. More
generally, the prefilter may discard an irrelevant file or source block before
parsing; payload forms in discarded source do not emit warnings.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rules testdata/skip-structural/rules testdata/skip-structural/src 2>&1 >/dev/null
warning: testdata/skip-structural/src/hit.mbt:7:1-7:22: #moongrep.skip does not accept a payload; use bare #moongrep.skip
warning: testdata/skip-structural/src/hit.mbt:13:1-13:17: #moongrep.skip does not accept a payload; use bare #moongrep.skip
```

With `--output-json`, the same warnings are typed records on standard error.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --output-json --rules testdata/skip-structural/rules testdata/skip-structural/src 2>&1 >/dev/null
{"type":"warning","category":"invalid_skip_payload","message":"testdata/skip-structural/src/hit.mbt:7:1-7:22: #moongrep.skip does not accept a payload; use bare #moongrep.skip","file":"testdata/skip-structural/src/hit.mbt","range":{"start":{"line":7,"column":1},"end":{"line":7,"column":22}}}
{"type":"warning","category":"invalid_skip_payload","message":"testdata/skip-structural/src/hit.mbt:13:1-13:17: #moongrep.skip does not accept a payload; use bare #moongrep.skip","file":"testdata/skip-structural/src/hit.mbt","range":{"start":{"line":13,"column":1},"end":{"line":13,"column":17}}}
```

## Parse warnings

Parse warnings are written to standard error even without `--verbose`. An
invalid MoonBit file is skipped, but it does not prevent matches from valid
files in the same directory from being reported on standard output.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rules e2etests/rules/structural testdata/parse-warning
testdata/parse-warning/hit.mbt:1:13-1:21
rule: example
description:
  Target call.
source:
1 > fn sample { target() }
```

Discarding standard output from the same non-verbose scan exposes the parse
warning without enabling verbose traversal messages.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rules e2etests/rules/structural testdata/parse-warning 2>&1 >/dev/null
warning: skipping testdata/parse-warning/bad.mbt: parse failed due to Unexpected end of file, missing simple expression here.
```

The structural rule's literal prefilter can discard an irrelevant malformed
file before parsing it. A normal human-readable scan then reports that there
were no matches.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rules e2etests/rules/structural testdata/prefilter-irrelevant
no match hits
```

A general rule has no literal anchor with which to discard the malformed file.
The failed parse still produces no match. Its warning is written to standard
error, while the normal no-match summary is written to standard output.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rules e2etests/rules/general testdata/prefilter-general
no match hits
```

## Anonymous patterns

Expressions that occur only in an `if` else branch are traversed and matched.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --pattern '$(left:exp) + $(right:exp)' testdata/cst-else
testdata/cst-else/hit.mbt:5:5-5:21
rule: $(left:exp) + $(right:exp)
description:
  Anonymous CLI pattern.
source:
3 |     then_call()
4 |   } else {
5 >     left() + right()
6 |   }
7 | }
```

Keyword metavariable names remain placeholders instead of being parsed as
MoonBit keywords.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --pattern 'if $(condition:exp) { $(then:exp) } else { $(else:exp) }' testdata/cst-else
testdata/cst-else/hit.mbt:2:3-6:4
rule: if $(condition:exp) { $(then:exp) } else { $(else:exp) }
description:
  Anonymous CLI pattern.
source:
1 | fn sample {
2 >   if clean() {
3 >     then_call()
4 >   } else {
5 >     left() + right()
6 >   }
7 | }
```

Bare metavariables in foreach binder positions infer the identifier kind.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --pattern 'for $item in $items { $body }' testdata/metavar-regressions
testdata/metavar-regressions/hit.mbt:2:3-4:4
rule: for $item in $items { $body }
description:
  Anonymous CLI pattern.
source:
1 | fn sample {
2 >   for item in items {
3 >     body()
4 >   }
5 | }
```

A terminal named expression metavar captures the complete continuation even
when the owning statement is inside a nested block.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --output-json --pattern 'wrapper({ let item = source(); $(body:exp) })' testdata/continuation-regressions | sed -n 's/.*"range":{"start":{"line":\([0-9][0-9]*\),"column":\([0-9][0-9]*\)},"end":{"line":\([0-9][0-9]*\),"column":\([0-9][0-9]*\)}}.*/\1:\2-\3:\4/p'
2:3-6:5
```

A continuation pattern without an explicit block wrapper matches each empty,
single-expression, and multi-expression block once. Each range includes the
block braces.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --output-json --pattern 'let value = load(); $(body:exp)' testdata/continuation-regressions | sed -n 's/.*"range":{"start":{"line":\([0-9][0-9]*\),"column":\([0-9][0-9]*\)},"end":{"line":\([0-9][0-9]*\),"column":\([0-9][0-9]*\)}}.*/\1:\2-\3:\4/p'
10:11-10:33
14:11-17:4
21:11-25:4
```

A terminal ignore placeholder after a continuation-owning statement matches
the complete suffix without binding it. Empty, single-expression, and
multi-expression suffixes all match, and each range covers the complete
`wrapper` block expression.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --output-json --pattern 'wrapper({ let value = load(); $_ })' testdata/continuation-regressions | sed -n 's/.*"range":{"start":{"line":\([0-9][0-9]*\),"column":\([0-9][0-9]*\)},"end":{"line":\([0-9][0-9]*\),"column":\([0-9][0-9]*\)}}.*/\1:\2-\3:\4/p'
10:3-10:34
14:3-17:5
21:3-25:5
```

A repeated typed metavariable must bind to the same expression at every use.
This matches `make() + make()` but not the following expression with different
operands.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --pattern '$(value:exp) + $(value:exp)' testdata/metavar
testdata/metavar/sample.mbt:2:3-2:18
rule: $(value:exp) + $(value:exp)
description:
  Anonymous CLI pattern.
source:
1 | fn sample {
2 >   make() + make()
3 |   make() + other()
4 | }
```

The shorthand metavariable syntax has the same repeated-binding equality as
the explicit `exp` form.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --pattern '$value + $value' testdata/metavar
testdata/metavar/sample.mbt:2:3-2:18
rule: $value + $value
description:
  Anonymous CLI pattern.
source:
1 | fn sample {
2 >   make() + make()
3 |   make() + other()
4 | }
```

A complete structural pattern can be supplied directly on the command line.
Anonymous rules use the pattern text as their rule id and a standard
description in the result.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --pattern 'target()' testdata/cli-pattern
testdata/cli-pattern/hit.mbt:2:3-2:11
rule: target()
description:
  Anonymous CLI pattern.
source:
1 | fn sample {
2 >   target()
3 | }
```

Function body braces are traversal containers rather than expression matches.
The JSON range and matched source for a broad expression pattern therefore
refer to the expression inside the body.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --output-json --pattern '$(root:exp)' testdata/body-candidates/function.mbt | sed -n 's/.*"range":{"start":{"line":\([0-9][0-9]*\),"column":\([0-9][0-9]*\)},"end":{"line":\([0-9][0-9]*\),"column":\([0-9][0-9]*\)}}.*"matched_source":"\([^"]*\)".*/\1:\2-\3:\4 \5/p'
3:3-3:13 f <| value
```

An explicit block shape does not match those function body braces.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --output-json --pattern '{ a; b }' testdata/body-candidates/function.mbt
```

The same shape does match a block written inside the body, and its JSON range
and matched source include the explicit braces.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --output-json --pattern '{ a; b }' testdata/body-candidates/explicit.mbt | sed -n 's/.*"range":{"start":{"line":\([0-9][0-9]*\),"column":\([0-9][0-9]*\)},"end":{"line":\([0-9][0-9]*\),"column":\([0-9][0-9]*\)}}.*"matched_source":"\([^"]*\)".*/\1:\2-\3:\4 \5/p'
3:3-3:11 { a; b }
```

A guard pattern without an explicit body matches the guard header and ignores
the candidate continuation. The reported range still covers the complete
candidate guard expression, including the following call.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --pattern 'guard ready() else { fallback() }' testdata/guard-omitted-body
testdata/guard-omitted-body/hit.mbt:2:3-3:18
rule: guard ready() else { fallback() }
description:
  Anonymous CLI pattern.
source:
1 | fn sample {
2 >   guard ready() else { fallback() }
3 >   continue_work()
4 | }
```

Qualified call matching is independent of whitespace before the long
identifier dot. The source still matches the compact anonymous pattern.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --pattern '@pkg.name()' testdata/qualified-whitespace
testdata/qualified-whitespace/hit.mbt:2:3-2:15
rule: @pkg.name()
description:
  Anonymous CLI pattern.
source:
1 | fn called {
2 >   @pkg .name()
3 | }
4 | ///|
```

Qualified type matching follows the same rule, so source formatting cannot
cause the prefilter to discard the anonymous pattern before parsing.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --pattern 'let value : @pkg.Type = input' testdata/qualified-whitespace
testdata/qualified-whitespace/hit.mbt:6:3-6:33
rule: let value : @pkg.Type = input
description:
  Anonymous CLI pattern.
source:
4 | ///|
5 | fn typed {
6 >   let value : @pkg .Type = input
7 | }
```

Guards further restrict captured metavariables. Both the fully qualified
callee and the constant value must satisfy their regular expressions, so only
the raw HTML render call is reported.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --pattern '$(callee:id)($(value:const))' --guard '{$callee: "^@html\\.render$", $value: "raw"}' testdata/guard
testdata/guard/hit.mbt:2:3-2:22
rule: $(callee:id)($(value:const))
description:
  Anonymous CLI pattern.
source:
1 | fn sample {
2 >   @html.render("raw")
3 |   @html.render("safe")
4 |   render("raw")
```

## Constant source spelling

Constant equality preserves the spelling stored in the parser CST instead of
normalizing numeric values. A literal `1000` pattern therefore matches only the
identically spelled call; the equivalent `1_000` call is omitted.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --output-json --pattern 'literal(1000)' testdata/constant-spelling/sample.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
literal(1000)
```

The same comparison applies when a named `const` metavariable is repeated.
Pairs with consistent spelling match, while `repeated(1000, 1_000)` does not.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --output-json --pattern 'repeated($(value:const), $(value:const))' testdata/constant-spelling/sample.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
repeated(1000, 1000)
repeated(1_000, 1_000)
```

## Rule filtering

Loading the prefilter rule directory runs both rules and reports their matches
in source order.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rules e2etests/rules/prefilter testdata/prefilter-impl
testdata/prefilter-impl/hits.mbt:2:3-2:11
rule: target
description:
  Target call.
source:
1 | fn first {
2 >   target()
3 | }
4 | ///|

testdata/prefilter-impl/hits.mbt:6:3-6:10
rule: other
description:
  Other call.
source:
4 | ///|
5 | fn second {
6 >   other()
7 | }
```

Disabling a loaded rule by id removes only that rule. The remaining rule still
scans the same source and reports its match.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rules e2etests/rules/prefilter --disable target testdata/prefilter-impl
testdata/prefilter-impl/hits.mbt:6:3-6:10
rule: other
description:
  Other call.
source:
4 | ///|
5 | fn second {
6 >   other()
7 | }
```

A disabled id must refer to a loaded rule. An unknown id is a command-line
error and returns exit status 2.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rules e2etests/rules/prefilter --disable missing testdata/prefilter-impl 2>&1 >/dev/null
error: unknown rule id in --disable
  source: missing
  help: use the exact id of a loaded rule
[2]
```

The selected rule directory controls scan behavior. The structural rule set
matches the target call in the custom fixture.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rules e2etests/rules/structural testdata/custom-rules
testdata/custom-rules/hit.mbt:1:13-1:21
rule: example
description:
  Target call.
source:
1 > fn sample { target() }
```

Selecting a different rule directory for the same source produces no hits
when that directory's patterns do not match.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rules e2etests/rules/other testdata/custom-rules
no match hits
```

Guards stored in a YAML rule apply the same callee and value constraints as
guards supplied with an anonymous CLI pattern.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rules e2etests/rules/guard testdata/guard
testdata/guard/hit.mbt:2:3-2:22
rule: guarded-render
description:
  Guarded render call.
source:
1 | fn sample {
2 >   @html.render("raw")
3 |   @html.render("safe")
4 |   render("raw")
```

## Rendering

JSON output emits one complete record per match. The record includes the file,
rule metadata, exact ranges, matched source, and nearby source lines marked as
matched or unmatched.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --output-json --rules e2etests/rules/structural testdata/render-structural
{"type":"finding","file":"testdata/render-structural/hit.mbt","rule_id":"example","description":"Target call.","range":{"start":{"line":3,"column":3},"end":{"line":3,"column":11}},"matched_source":"target()","source_context":[{"line":1,"text":"fn sample {","is_match":false},{"line":2,"text":"  before()","is_match":false},{"line":3,"text":"  target()","is_match":true},{"line":4,"text":"  after()","is_match":false},{"line":5,"text":"}","is_match":false}]}
```

Verbose traversal messages and parse warnings are written to stderr, so
discarding stderr leaves the JSON stream on stdout unchanged.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --output-json --verbose --rules e2etests/rules/structural testdata/parse-warning 2>/dev/null
{"type":"finding","file":"testdata/parse-warning/hit.mbt","rule_id":"example","description":"Target call.","range":{"start":{"line":1,"column":13},"end":{"line":1,"column":21}},"matched_source":"target()","source_context":[{"line":1,"text":"fn sample { target() }","is_match":true}]}
```

Conversely, discarding stdout exposes the stderr stream. Verbose mode records
rule loading, directory entry, and file order; the parse warning explains why
the malformed file was skipped.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --output-json --verbose --rules e2etests/rules/structural testdata/parse-warning 2>&1 >/dev/null
{"type":"trace","event":"rule_loaded","rule_id":"example"}
{"type":"trace","event":"directory_entered","path":"testdata/parse-warning"}
{"type":"trace","event":"file_started","path":"testdata/parse-warning/bad.mbt"}
{"type":"warning","category":"parse","message":"skipping testdata/parse-warning/bad.mbt: parse failed due to Unexpected end of file, missing simple expression here.","file":"testdata/parse-warning/bad.mbt","reason":"parse failed due to Unexpected end of file, missing simple expression here."}
{"type":"trace","event":"file_started","path":"testdata/parse-warning/hit.mbt"}
```

JSON mode writes no summary record when there are no matches. The empty stream
therefore has a byte count of zero.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --output-json --rules e2etests/rules/structural testdata/prefilter-irrelevant | wc -c
0
```

The default renderer presents the same structural match as a readable
diagnostic with line numbers and surrounding source context.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rules e2etests/rules/structural testdata/render-structural
testdata/render-structural/hit.mbt:3:3-3:11
rule: example
description:
  Target call.
source:
1 | fn sample {
2 |   before()
3 >   target()
4 |   after()
5 | }
```

For a taint rule, the primary range identifies the source-derived expression
passed to the sink rather than the whole sink call. The human-readable context
still shows the surrounding data flow.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rules e2etests/rules/taint testdata/taint
testdata/taint/hit.mbt:4:8-4:9
rule: example
description:
  User input reaches sink.
source:
2 |   before()
3 |   let x = get_user_input()
4 >   sink(x)
5 |   after()
6 | }
```

Migrated CST fields preserve taint flows through foreach binders, `noraise`
cases, array reads and writes, and `if` else branches.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --output-json --rules e2etests/rules/cst-regressions testdata/taint-cst-regressions | sed -n 's/.*"matched_source":"\([^"]*\)".*/\1/p'
item
result
values[0]
get_user_input()
get_user_input()
value
```
