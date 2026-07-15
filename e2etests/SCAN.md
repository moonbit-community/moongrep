## Directory scanning

```mooncram
$ cd "$TESTDIR"/.. && sh testdata/skip-dirs/run.sh "$TESTDIR"/moongrep.wasm
testdata/skip-dirs/hit.mbt:1:13-1:21
rule: example
description:
  Target call.
source:
1 > fn sample { target() }
```

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

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rules e2etests/rules/structural testdata/parse-warning
testdata/parse-warning/hit.mbt:1:13-1:21
rule: example
description:
  Target call.
source:
1 > fn sample { target() }
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rules e2etests/rules/structural testdata/prefilter-irrelevant
no match hits
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rules e2etests/rules/general testdata/prefilter-general
no match hits
```

## Anonymous patterns

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

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rules e2etests/rules/prefilter testdata/prefilter-impl --exclude-rules missing
unknown rule id in --exclude-rules: missing
[2]
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rules e2etests/rules/structural testdata/custom-rules
testdata/custom-rules/hit.mbt:1:13-1:21
rule: example
description:
  Target call.
source:
1 > fn sample { target() }
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rules e2etests/rules/other testdata/custom-rules
no match hits
```

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

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --rules e2etests/rules/structural testdata/render-structural
{"file":"testdata/render-structural/hit.mbt","rule_id":"example","description":"Target call.","range":{"start":{"line":3,"column":3},"end":{"line":3,"column":11}},"outer_range":null,"matched_source":"target()","source_context":[{"line":1,"text":"fn sample {","is_match":false},{"line":2,"text":"  before()","is_match":false},{"line":3,"text":"  target()","is_match":true},{"line":4,"text":"  after()","is_match":false},{"line":5,"text":"}","is_match":false}]}
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --verbose --rules e2etests/rules/structural testdata/parse-warning 2>/dev/null
{"file":"testdata/parse-warning/hit.mbt","rule_id":"example","description":"Target call.","range":{"start":{"line":1,"column":13},"end":{"line":1,"column":21}},"outer_range":null,"matched_source":"target()","source_context":[{"line":1,"text":"fn sample { target() }","is_match":true}]}
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --verbose --rules e2etests/rules/structural testdata/parse-warning 2>&1 >/dev/null
moongrep scan: loaded rule example
moongrep scan: entering testdata/parse-warning
moongrep scan: file testdata/parse-warning/bad.mbt
warning: skipping testdata/parse-warning/bad.mbt: parse failed due to Unexpected end of file, missing simple expression here.
moongrep scan: file testdata/parse-warning/hit.mbt
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --rules e2etests/rules/structural testdata/prefilter-irrelevant | wc -c
0
```

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
