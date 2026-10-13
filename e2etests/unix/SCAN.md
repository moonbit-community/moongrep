## Directory scanning

```mooncram-import
grep : cli/grep@0.2.0
```

When no rule source option is present, `scan` loads rules from
`./.moongrep/rules`. The path is resolved from the current directory.

```mooncram moonbit-community/moongrep
$ set-current-working-directory ../testdata/default-rules
$ moongrep scan
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

```mooncram moonbit-community/moongrep
$ moongrep scan --verbose --rules ../rules/structural ../testdata/skip-dirs
../testdata/skip-dirs/hit.mbt:1:13-1:21
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

```mooncram moonbit-community/moongrep
$ moongrep scan --verbose --rules ../rules/structural --exclude ignored/ --exclude ./../testdata/exclude-dirs/generated/ --exclude excluded.mbt ../testdata/exclude-dirs
../testdata/exclude-dirs/hit.mbt:1:13-1:21
rule: example
description:
  Target call.
source:
1 > fn sample { target() }
```

## Deterministic streaming order

Sorted depth-first traversal writes the nested file before returning to the
next entry in the parent directory.

```mooncram moonbit-community/moongrep
$ moongrep scan --rules ../rules/structural ../testdata/stream-order
../testdata/stream-order/a/hit.mbt:2:3-2:11
rule: example
description:
  Target call.
source:
1 | fn nested {
2 >   target()
3 | }

../testdata/stream-order/a.mbt:2:3-2:11
rule: example
description:
  Target call.
source:
1 | fn flat {
2 >   target()
3 | }
```

## Taint loop fixpoint

A YAML taint rule still reports a sink when propagation needs more than six
abstract loop iterations.

```mooncram moonbit-community/moongrep
$ moongrep scan --rules ../testdata/taint-fixpoint/rules ../testdata/taint-fixpoint/src
../testdata/taint-fixpoint/src/hit.mbt:19:8-19:10
rule: taint-fixpoint
description:
  Taint crosses more than six loop iterations.
source:
17 |     x1 = x0
18 |   }
19 >   sink(x7)
20 | }
```

## Source-level structural suppression

A bare `#moongrep.skip` suppresses every structural rule in its function while
taint analysis still runs. A payload form does not suppress structural rules.
The fixture also combines `#moongrep.skip()` with a bare marker on one function;
that function stays structurally suppressed because the bare marker remains
effective. With warnings hidden, only the payload-only function, the unmarked
function, and the taint flow under a bare marker are reported.

```mooncram moonbit-community/moongrep
$ moongrep scan --rules ../testdata/skip-structural/rules ../testdata/skip-structural/src | grep -E '^(../testdata/|rule:)'
../testdata/skip-structural/src/hit.mbt:9:3-9:11
rule: structural
../testdata/skip-structural/src/hit.mbt:21:3-21:11
rule: structural
../testdata/skip-structural/src/hit.mbt:28:8-28:9
rule: taint
```

Every payload form in this fixture writes a source-rebased warning to standard
error because the enabled rules keep its source blocks relevant through the
prefilter. The command still exits successfully, and the empty-payload warning
is emitted even though the same function also has a valid bare marker. More
generally, the prefilter may discard an irrelevant file or source block before
parsing; payload forms in discarded source do not emit warnings.

```mooncram moonbit-community/moongrep
$ moongrep scan --rules ../testdata/skip-structural/rules ../testdata/skip-structural/src
@STDOUT (ignore)
@STDERR
warning: ../testdata/skip-structural/src/hit.mbt:7:1-7:22: #moongrep.skip does not accept a payload; use bare #moongrep.skip
warning: ../testdata/skip-structural/src/hit.mbt:13:1-13:17: #moongrep.skip does not accept a payload; use bare #moongrep.skip
```

With `--json`, the same warnings are typed records on standard error.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --rules ../testdata/skip-structural/rules ../testdata/skip-structural/src
@STDOUT (ignore)
@STDERR
{"type":"warning","category":"invalid_skip_payload","message":"../testdata/skip-structural/src/hit.mbt:7:1-7:22: #moongrep.skip does not accept a payload; use bare #moongrep.skip","file":"../testdata/skip-structural/src/hit.mbt","range":{"start":{"line":7,"column":1},"end":{"line":7,"column":22}}}
{"type":"warning","category":"invalid_skip_payload","message":"../testdata/skip-structural/src/hit.mbt:13:1-13:17: #moongrep.skip does not accept a payload; use bare #moongrep.skip","file":"../testdata/skip-structural/src/hit.mbt","range":{"start":{"line":13,"column":1},"end":{"line":13,"column":17}}}
```

## Parse warnings

Parse warnings are written to standard error even without `--verbose`. An
invalid MoonBit file is skipped, but it does not prevent matches from valid
files in the same directory from being reported on standard output.

```mooncram moonbit-community/moongrep
$ moongrep scan --rules ../rules/structural ../testdata/parse-warning
../testdata/parse-warning/hit.mbt:1:13-1:21
rule: example
description:
  Target call.
source:
1 > fn sample { target() }
```

Discarding standard output from the same non-verbose scan exposes the parse
warning without enabling verbose traversal messages.

```mooncram moonbit-community/moongrep
$ moongrep scan --rules ../rules/structural ../testdata/parse-warning
@STDOUT (ignore)
@STDERR
warning: skipping ../testdata/parse-warning/bad.mbt: parse failed due to Unexpected end of file, missing simple expression here.
```

## Anonymous patterns

Expressions that occur only in an `if` else branch are traversed and matched.

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern '$(left:exp) + $(right:exp)' ../testdata/cst-else
../testdata/cst-else/hit.mbt:5:5-5:21
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

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern 'if $(condition:exp) { $(then:exp) } else { $(else:exp) }' ../testdata/cst-else
../testdata/cst-else/hit.mbt:2:3-6:4
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

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern 'for $item in $items { $body }' ../testdata/metavar-regressions
../testdata/metavar-regressions/hit.mbt:2:3-4:4
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


A repeated typed metavariable must bind to the same expression at every use.
This matches `make() + make()` but not the following expression with different
operands.

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern '$(value:exp) + $(value:exp)' ../testdata/metavar
../testdata/metavar/sample.mbt:2:3-2:18
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

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern '$value + $value' ../testdata/metavar
../testdata/metavar/sample.mbt:2:3-2:18
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

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern 'target()' ../testdata/cli-pattern
../testdata/cli-pattern/hit.mbt:2:3-2:11
rule: target()
description:
  Anonymous CLI pattern.
source:
1 | fn sample {
2 >   target()
3 | }
```


A guard pattern without an explicit body matches the guard header and ignores
the candidate continuation. The reported range still covers the complete
candidate guard expression, including the following call.

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern 'guard ready() else { fallback() }' ../testdata/guard-omitted-body
../testdata/guard-omitted-body/hit.mbt:2:3-3:18
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

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern '@pkg.name()' ../testdata/qualified-whitespace
../testdata/qualified-whitespace/hit.mbt:2:3-2:15
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

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern 'let value : @pkg.Type = input' ../testdata/qualified-whitespace
../testdata/qualified-whitespace/hit.mbt:6:3-6:33
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

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern '$(callee:id)($(value:const))' --guard '{$callee: "^@html\\.render$", $value: "raw"}' ../testdata/guard
../testdata/guard/hit.mbt:2:3-2:22
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

```mooncram moonbit-community/moongrep
$ moongrep scan --rules ../rules/prefilter ../testdata/prefilter-impl
../testdata/prefilter-impl/hits.mbt:2:3-2:11
rule: target
description:
  Target call.
source:
1 | fn first {
2 >   target()
3 | }
4 | ///|

../testdata/prefilter-impl/hits.mbt:6:3-6:10
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

```mooncram moonbit-community/moongrep
$ moongrep scan --rules ../rules/prefilter --disable target ../testdata/prefilter-impl
../testdata/prefilter-impl/hits.mbt:6:3-6:10
rule: other
description:
  Other call.
source:
4 | ///|
5 | fn second {
6 >   other()
7 | }
```


The selected rule directory controls scan behavior. The structural rule set
matches the target call in the custom fixture.

```mooncram moonbit-community/moongrep
$ moongrep scan --rules ../rules/structural ../testdata/custom-rules
../testdata/custom-rules/hit.mbt:1:13-1:21
rule: example
description:
  Target call.
source:
1 > fn sample { target() }
```


Guards stored in a YAML rule apply the same callee and value constraints as
guards supplied with an anonymous CLI pattern.

```mooncram moonbit-community/moongrep
$ moongrep scan --rules ../rules/guard ../testdata/guard
../testdata/guard/hit.mbt:2:3-2:22
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

```mooncram moonbit-community/moongrep
$ moongrep scan --json --rules ../rules/structural ../testdata/render-structural
{"type":"finding","file":"../testdata/render-structural/hit.mbt","rule_id":"example","description":"Target call.","range":{"start":{"line":3,"column":3},"end":{"line":3,"column":11}},"matched_source":"target()","source_context":[{"line":1,"text":"fn sample {","is_match":false},{"line":2,"text":"  before()","is_match":false},{"line":3,"text":"  target()","is_match":true},{"line":4,"text":"  after()","is_match":false},{"line":5,"text":"}","is_match":false}]}
```

Verbose traversal messages and parse warnings are written to stderr, so
discarding stderr leaves the JSON stream on stdout unchanged.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --verbose --rules ../rules/structural ../testdata/parse-warning
{"type":"finding","file":"../testdata/parse-warning/hit.mbt","rule_id":"example","description":"Target call.","range":{"start":{"line":1,"column":13},"end":{"line":1,"column":21}},"matched_source":"target()","source_context":[{"line":1,"text":"fn sample { target() }","is_match":true}]}
```

Conversely, discarding stdout exposes the stderr stream. Verbose mode records
rule loading, directory entry, and file order; the parse warning explains why
the malformed file was skipped.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --verbose --rules ../rules/structural ../testdata/parse-warning
@STDOUT (ignore)
@STDERR
{"type":"trace","event":"rule_loaded","rule_id":"example"}
{"type":"trace","event":"directory_entered","path":"../testdata/parse-warning"}
{"type":"trace","event":"file_started","path":"../testdata/parse-warning/bad.mbt"}
{"type":"warning","category":"parse","message":"skipping ../testdata/parse-warning/bad.mbt: parse failed due to Unexpected end of file, missing simple expression here.","file":"../testdata/parse-warning/bad.mbt","reason":"parse failed due to Unexpected end of file, missing simple expression here."}
{"type":"trace","event":"file_started","path":"../testdata/parse-warning/hit.mbt"}
```

The default renderer presents the same structural match as a readable
diagnostic with line numbers and surrounding source context.

```mooncram moonbit-community/moongrep
$ moongrep scan --rules ../rules/structural ../testdata/render-structural
../testdata/render-structural/hit.mbt:3:3-3:11
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

```mooncram moonbit-community/moongrep
$ moongrep scan --rules ../rules/taint ../testdata/taint
../testdata/taint/hit.mbt:4:8-4:9
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
