## Directory scanning

The scanner ignores common repository and build directories by default. The
fixture creates matching files under `.git`, `_build`, `.mooncakes`, and
`target`, but only the source file at the scan root is reported.

```mooncram
$ cd "$TESTDIR"/.. && sh testdata/skip-dirs/run.sh "$TESTDIR"/moongrep.wasm
testdata/skip-dirs/hit.mbt:1:13-1:21
rule: example
description:
  Target call.
source:
1 > fn sample { target() }
```

Additional directories can be excluded by name or by path. The two
`--exclude-dir` forms remove the `ignored` and `generated` subtrees, leaving
only the match in the root of the fixture.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --verbose --rules e2etests/rules/structural testdata/exclude-dirs --exclude-dir ignored/ ./testdata/exclude-dirs/generated/
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
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rules e2etests/rules/structural testdata/stream-order
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

## Parse warnings

Without verbose output, an invalid MoonBit file is skipped quietly and does
not prevent matches from valid files in the same directory from being
reported.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rules e2etests/rules/structural testdata/parse-warning
testdata/parse-warning/hit.mbt:1:13-1:21
rule: example
description:
  Target call.
source:
1 > fn sample { target() }
```

The structural rule's literal prefilter can discard an irrelevant malformed
file before parsing it. A normal human-readable scan then reports that there
were no matches.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rules e2etests/rules/structural testdata/prefilter-irrelevant
no match hits
```

A general rule has no literal anchor with which to discard the malformed file.
The failed parse still produces no match, and its warning remains hidden in
non-verbose mode.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rules e2etests/rules/general testdata/prefilter-general
no match hits
```

## Anonymous patterns

A repeated typed metavariable must bind to the same expression at every use.
This matches `make() + make()` but not the following expression with different
operands.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --pattern '$(value:exp) + $(value:exp)' testdata/metavar
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
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --pattern '$value + $value' testdata/metavar
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
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --pattern 'target()' testdata/cli-pattern
testdata/cli-pattern/hit.mbt:2:3-2:11
rule: target()
description:
  Anonymous CLI pattern.
source:
1 | fn sample {
2 >   target()
3 | }
```

Guards further restrict captured metavariables. Both the fully qualified
callee and the constant value must satisfy their regular expressions, so only
the raw HTML render call is reported.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --pattern '$(callee:id)($(value:const))' --guard '{$callee: "^@html\\.render$", $value: "raw"}' testdata/guard
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

## Rule filtering

Loading the prefilter rule directory runs both rules and reports their matches
in source order.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rules e2etests/rules/prefilter testdata/prefilter-impl
testdata/prefilter-impl/hits.mbt:2:3-2:11
rule: target
description:
  Target call.
source:
1 | fn first {
2 >   target()
3 | }
4 | 

testdata/prefilter-impl/hits.mbt:6:3-6:10
rule: other
description:
  Other call.
source:
4 | 
5 | fn second {
6 >   other()
7 | }
```

Excluding a loaded rule by id removes only that rule. The remaining rule still
scans the same source and reports its match.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rules e2etests/rules/prefilter testdata/prefilter-impl --exclude-rules target
testdata/prefilter-impl/hits.mbt:6:3-6:10
rule: other
description:
  Other call.
source:
4 | 
5 | fn second {
6 >   other()
7 | }
```

An excluded id must refer to a loaded rule. An unknown id is a command-line
error and returns exit status 2.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rules e2etests/rules/prefilter testdata/prefilter-impl --exclude-rules missing
unknown rule id in --exclude-rules: missing
[2]
```

The selected rule directory controls scan behavior. The structural rule set
matches the target call in the custom fixture.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rules e2etests/rules/structural testdata/custom-rules
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
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rules e2etests/rules/other testdata/custom-rules
no match hits
```

Guards stored in a YAML rule apply the same callee and value constraints as
guards supplied with an anonymous CLI pattern.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rules e2etests/rules/guard testdata/guard
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
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --rules e2etests/rules/structural testdata/render-structural
{"file":"testdata/render-structural/hit.mbt","rule_id":"example","description":"Target call.","range":{"start":{"line":3,"column":3},"end":{"line":3,"column":11}},"outer_range":null,"matched_source":"target()","source_context":[{"line":1,"text":"fn sample {","is_match":false},{"line":2,"text":"  before()","is_match":false},{"line":3,"text":"  target()","is_match":true},{"line":4,"text":"  after()","is_match":false},{"line":5,"text":"}","is_match":false}]}
```

Verbose traversal messages are written to stderr, so discarding stderr leaves
the JSON stream on stdout unchanged.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --verbose --rules e2etests/rules/structural testdata/parse-warning 2>/dev/null
{"file":"testdata/parse-warning/hit.mbt","rule_id":"example","description":"Target call.","range":{"start":{"line":1,"column":13},"end":{"line":1,"column":21}},"outer_range":null,"matched_source":"target()","source_context":[{"line":1,"text":"fn sample { target() }","is_match":true}]}
```

Conversely, discarding stdout exposes the verbose stderr stream. It records
rule loading, directory entry, file order, and the reason a malformed file was
skipped.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --verbose --rules e2etests/rules/structural testdata/parse-warning 2>&1 >/dev/null
moongrep scan: loaded rule example
moongrep scan: entering testdata/parse-warning
moongrep scan: file testdata/parse-warning/bad.mbt
warning: skipping testdata/parse-warning/bad.mbt: parse failed due to Unexpected end of file, missing simple expression here.
moongrep scan: file testdata/parse-warning/hit.mbt
```

JSON mode writes no summary record when there are no matches. The empty stream
therefore has a byte count of zero.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --rules e2etests/rules/structural testdata/prefilter-irrelevant | wc -c
0
```

The default renderer presents the same structural match as a readable
diagnostic with line numbers and surrounding source context.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rules e2etests/rules/structural testdata/render-structural
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
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rules e2etests/rules/taint testdata/taint
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
