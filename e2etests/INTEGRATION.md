## Integration scenarios

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rules testdata/inside-expr-target/rules testdata/inside-expr-target/src
testdata/inside-expr-target/src/hit.mbt:3:3-3:15
rule: example
outer_loc: testdata/inside-expr-target/src/hit.mbt:2:3-3:15
description:
  Local println shadows the builtin.
source:
1 | fn sample {
2 |   let println = custom;
3 >   println("x")
4 | }
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rules testdata/html-attrs-taint-sanitizer/rules testdata/html-attrs-taint-sanitizer/src
testdata/html-attrs-taint-sanitizer/src/hit.mbt:3:30-3:35
rule: example
description:
  Attrs built with `inner_html(...)` carry raw DOM content.
source:
1 | fn hit(raw, child) {
2 |   let attrs = @html.Attrs::build().inner_html(raw);
3 >   @html.div(class="x", attrs=attrs, child)
4 | }
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rules testdata/patterns-not-structural/rules testdata/patterns-not-structural/src
testdata/patterns-not-structural/src/hit.mbt:2:3-2:12
rule: example
description:
  Sink call where positive match wins over patterns-not.
source:
1 | fn sample {
2 >   sink(raw);
3 |   sink(safe(raw))
4 | }

testdata/patterns-not-structural/src/hit.mbt:3:3-3:18
rule: example
description:
  Sink call where positive match wins over patterns-not.
source:
1 | fn sample {
2 |   sink(raw);
3 >   sink(safe(raw))
4 | }
5 | 
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rules testdata/patterns-not-inside/rules testdata/patterns-not-inside/src
testdata/patterns-not-inside/src/hit.mbt:2:3-2:18
rule: example
outer_loc: testdata/patterns-not-inside/src/hit.mbt:2:3-2:18
description:
  Wrapper payload without danger.
source:
1 | fn sample {
2 >   wrapper(safe());
3 |   wrapper(danger());
4 |   wrapper(holder(danger()))
```
