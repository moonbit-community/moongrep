## Integration scenarios

An `inside-expr` rule first binds a local declaration and then searches the
remaining expression for the target call. The result reports the complete
declaration-plus-target outer expression as its match location.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rules testdata/inside-expr-target/rules testdata/inside-expr-target/src
testdata/inside-expr-target/src/hit.mbt:2:3-3:15
rule: example
description:
  Local println shadows the builtin.
source:
1 | fn sample {
2 >   let println = custom;
3 >   println("x")
4 | }
```

Ordered outer alternatives work for both expression and top-level contexts in
one rule set. Inner captures are shared across every alternative.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rules testdata/inside-alternatives/rules testdata/inside-alternatives/src
testdata/inside-alternatives/src/expr.mbt:2:3-2:32
rule: expr
description:
  Multiple expression contexts share one inner pattern.
source:
1 | fn sample {
2 >   wrapper(alpha, target(alpha));
3 |   container(beta, target(beta))
4 | }

testdata/inside-alternatives/src/expr.mbt:3:3-3:32
rule: expr
description:
  Multiple expression contexts share one inner pattern.
source:
1 | fn sample {
2 |   wrapper(alpha, target(alpha));
3 >   container(beta, target(beta))
4 | }

testdata/inside-alternatives/src/toplevel.mbt:2:3-2:15
rule: toplevel
description:
  Multiple top-level contexts share one inner pattern.
source:
1 | fn run {
2 >   consume(run)
3 | }
4 | let value = box(consume(value))

testdata/inside-alternatives/src/toplevel.mbt:4:17-4:31
rule: toplevel
description:
  Multiple top-level contexts share one inner pattern.
source:
2 |   consume(run)
3 | }
4 > let value = box(consume(value))
```

An HTML builder chain is a taint source whose result is stored in a local
variable and passed into the `attrs` argument of a sink. The reported range is
the tainted local use, confirming propagation through the assignment.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rules testdata/html-attrs-taint-sanitizer/rules testdata/html-attrs-taint-sanitizer/src
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

Positive structural patterns run before `patterns-not` at each candidate root.
Once the sink pattern matches, the negative pattern is skipped for that root,
so both sink calls are reported even when one contains the negative shape.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rules testdata/patterns-not-structural/rules testdata/patterns-not-structural/src
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

For `patterns-not` combined with `inside-expr`, the exclusion is evaluated
inside each wrapper. The wrapper around `safe()` is reported, while wrappers
containing `danger()` are omitted.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun "$TESTDIR"/../moongrep.wasm -- scan --rules testdata/patterns-not-inside/rules testdata/patterns-not-inside/src
testdata/patterns-not-inside/src/hit.mbt:2:3-2:18
rule: example
description:
  Wrapper payload without danger.
source:
1 | fn sample {
2 >   wrapper(safe());
3 |   wrapper(danger());
4 |   wrapper(holder(danger()))
```
