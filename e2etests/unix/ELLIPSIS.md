# Ellipsis paths on Unix

## Rule contexts and prefiltering

An ellipsis captured by `then` can be reused by the target pattern. The
target matches when its arguments repeat the wrapper prefix, including the
empty prefix, and rejects a differing final argument.

```mooncram moonbit-community/moongrep
$ moongrep scan --rules ../testdata/ellipsis/inside/rules ../testdata/ellipsis/inside/src
../testdata/ellipsis/inside/src/sample.mbt:2:3-2:20
rule: ellipsis-inside
description:
  Reuse the surrounding argument prefix inside the target.
source:
1 | fn inside {
2 >   wrapper(target())
3 |   wrapper(a, b, target(a, b))
4 |   wrapper(a, b, target(a, other))

../testdata/ellipsis/inside/src/sample.mbt:3:3-3:30
rule: ellipsis-inside
description:
  Reuse the surrounding argument prefix inside the target.
source:
1 | fn inside {
2 |   wrapper(target())
3 >   wrapper(a, b, target(a, b))
4 |   wrapper(a, b, target(a, other))
5 | }
```

Taint rules can place ellipses around source and sink arguments. Both direct
dirty values reach the variadic sink, while a variadic sanitizer removes the
third candidate.

```mooncram moonbit-community/moongrep
$ moongrep scan --rules ../testdata/ellipsis/taint/rules ../testdata/ellipsis/taint/src
../testdata/ellipsis/taint/src/sample.mbt:3:24-3:29
rule: ellipsis-taint
description:
  Variadic sink arguments preserve taint and variadic cleaners sanitize it.
source:
1 | fn taint {
2 |   let dirty = get_user_input()
3 >   sink(prefix, marker, dirty)
4 |   sink(prefix, one, two, marker, dirty, trailing)
5 |   sink(prefix, marker, clean(prefix, around, dirty, trailing), trailing)

../testdata/ellipsis/taint/src/sample.mbt:4:34-4:39
rule: ellipsis-taint
description:
  Variadic sink arguments preserve taint and variadic cleaners sanitize it.
source:
2 |   let dirty = get_user_input()
3 |   sink(prefix, marker, dirty)
4 >   sink(prefix, one, two, marker, dirty, trailing)
5 |   sink(prefix, marker, clean(prefix, around, dirty, trailing), trailing)
6 | }
```

Literal items adjacent to an ellipsis remain useful prefilter anchors. They
select the call with the required prefix and suffix without admitting calls
whose callee or prefix differs.

```mooncram moonbit-community/moongrep
$ moongrep scan --rules ../testdata/ellipsis/prefilter/rules ../testdata/ellipsis/prefilter/src
../testdata/ellipsis/prefilter/src/sample.mbt:2:3-2:34
rule: ellipsis-prefilter
description:
  Keep literals adjacent to an ellipsis as prefilter anchors.
source:
1 | fn prefilter {
2 >   anchored(prefix, value, suffix)
3 |   anchored(other, value, suffix)
4 |   other(prefix, value, suffix)
```

## File-backed validation errors

A file-backed multiline shape is displayed separately from the rule source.
Its relative indentation is preserved without an extra line for the block
scalar's trailing newline.

```mooncram moonbit-community/moongrep
$ moongrep scan --rule ../testdata/ellipsis/invalid/shape.yaml ../testdata/ellipsis/sample.mbt
@STDOUT (ignore)
@STDERR
error: invalid rule
  source: ../testdata/ellipsis/invalid/shape.yaml
  pattern:
    wrap(
      $$$items + 1
    )
  reason: the pattern uses ellipsis metavar $$$items outside a complete ordered CST list item
  help: fix the rule and try again
[5]
```

Inherited inside-context captures must remain ellipses with the same kind.

Reusing an inherited ellipsis with a different typed kind would change its
capture contract and is rejected while loading the rule.

```mooncram moonbit-community/moongrep
$ moongrep scan --rule ../testdata/ellipsis/invalid/inside-kind.yaml ../testdata/ellipsis/sample.mbt
@STDOUT (ignore)
@STDERR
error: invalid rule
  source: ../testdata/ellipsis/invalid/inside-kind.yaml
  reason: patterns[0].then.patterns[0] cannot use inherited ancestor[0] ellipsis metavar items with a different kind
  help: fix the rule and try again
[5]
```

An inherited ellipsis also cannot be narrowed to a single-node metavariable in
the target pattern.

```mooncram moonbit-community/moongrep
$ moongrep scan --rule ../testdata/ellipsis/invalid/inside-single.yaml ../testdata/ellipsis/sample.mbt
@STDOUT (ignore)
@STDERR
error: invalid rule
  source: ../testdata/ellipsis/invalid/inside-single.yaml
  reason: patterns[0].then.patterns[0] cannot use inherited ancestor[0] ellipsis metavar items as exp
  help: fix the rule and try again
[5]
```
