# Ellipsis metavariables

The matching snapshots below print only the matched source to keep positive and
near-miss cases readable.

## Empty, single, and multiple items

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'inspect($$$args)' testdata/ellipsis/sample.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
inspect()
inspect(1)
inspect(1, content=\"1\")
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'anchored(prefix, $$$middle, suffix)' testdata/ellipsis/sample.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
anchored(prefix, suffix)
anchored(prefix, first, second, suffix)
```

## Backtracking and binding equality

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'split($$$left, marker, $$$right, marker)' testdata/ellipsis/bindings.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
split(a, marker, b, marker)
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'repeated([$$$items], [$$$items])' testdata/ellipsis/bindings.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
repeated([], [])
repeated([a, b], [a, b])
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'arguments_equal(left($$$args), right($$$args))' testdata/ellipsis/bindings.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
arguments_equal(left(1, label=2), right(1, label=2))
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'anonymous([$$$_], [$$$_])' testdata/ellipsis/bindings.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
anonymous([a], [b, c])
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'typed_anonymous([$$$(_:const)], [$$$(_:id)])' testdata/ellipsis/bindings.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
typed_anonymous([1, 2], [a, b])
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'propagated([$$$(items:const)], [$$$items])' testdata/ellipsis/bindings.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
propagated([1, 2], [1, 2])
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'restore($$$gap, $(value:exp), marker, $(value:exp))' testdata/ellipsis/bindings.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
restore(first, selected, marker, selected)
```

## Typed call arguments

Bare and `arg` ellipses accept every complete argument kind, while `exp`, `id`,
and `const` accept only compatible positional argument values.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'any_args($$$(args:arg))' testdata/ellipsis/arguments.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
any_args()
any_args(value, other)
any_args(value, label=other)
any_args(label~)
any_args(label?=other)
any_args(label?)
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'exp_args($$$(args:exp))' testdata/ellipsis/arguments.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
exp_args()
exp_args(value, other + 1)
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'id_args($$$(args:id))' testdata/ellipsis/arguments.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
id_args()
id_args(value, other)
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'const_args($$$(args:const))' testdata/ellipsis/arguments.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
const_args()
const_args(1, \"two\")
```

## Ordered AST list positions

The array fixture also contains a spread element; both the bare and `exp`
patterns below intentionally match only the regular-element array.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'tuple_expr(($$$(items:exp), tail))' testdata/ellipsis/ordered_lists.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
tuple_expr((first, second, tail))
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'if condition { $$$items; tail }' testdata/ellipsis/ordered_lists.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
if condition {\n    before()\n    middle()\n    tail\n  }
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'array_expr([$$$(items:exp)])' testdata/ellipsis/ordered_lists.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
array_expr([first, second])
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'array_expr([$$$items])' testdata/ellipsis/ordered_lists.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
array_expr([first, second])
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'match tuple_input { ($$$(items:pat), tail) => tuple_pattern }' testdata/ellipsis/ordered_lists.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
match tuple_input { (first, second, tail) => tuple_pattern }
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'match constructor_input { Some($$$(items:pat)) => constructor_pattern }' testdata/ellipsis/ordered_lists.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
match constructor_input { Some(first, second) => constructor_pattern }
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'match array_input { [$$$(items:pat)] => array_pattern }' testdata/ellipsis/ordered_lists.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
match array_input { [first, _, 1] => array_pattern }
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'match id_input { [$$$(items:id)] => id_patterns }' testdata/ellipsis/ordered_lists.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
match id_input { [first, second] => id_patterns }
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'match const_input { [$$$(items:const)] => const_patterns }' testdata/ellipsis/ordered_lists.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
match const_input { [1, \"two\"] => const_patterns }
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'let value : ($$$(Types:type), Bool) = input' testdata/ellipsis/ordered_lists.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
let value : (Int, String, Bool) = input
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'fn($$$(params:id)) { body }' testdata/ellipsis/ordered_lists.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
fn(\n    positional,\n    labelled~ : Int,\n    optional~ : Int = 1,\n    question? : String,\n  ) { body }
fn() { body }
```

## Rule contexts and prefiltering

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rules testdata/ellipsis/inside/rules testdata/ellipsis/inside/src
testdata/ellipsis/inside/src/sample.mbt:2:11-2:19
rule: ellipsis-inside
outer_loc: testdata/ellipsis/inside/src/sample.mbt:2:3-2:20
description:
  Reuse the surrounding argument prefix inside the target.
source:
1 | fn inside {
2 >   wrapper(target())
3 |   wrapper(a, b, target(a, b))
4 |   wrapper(a, b, target(a, other))

testdata/ellipsis/inside/src/sample.mbt:3:17-3:29
rule: ellipsis-inside
outer_loc: testdata/ellipsis/inside/src/sample.mbt:3:3-3:30
description:
  Reuse the surrounding argument prefix inside the target.
source:
1 | fn inside {
2 |   wrapper(target())
3 >   wrapper(a, b, target(a, b))
4 |   wrapper(a, b, target(a, other))
5 | }
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rules testdata/ellipsis/taint/rules testdata/ellipsis/taint/src
testdata/ellipsis/taint/src/sample.mbt:3:24-3:29
rule: ellipsis-taint
description:
  Variadic sink arguments preserve taint and variadic cleaners sanitize it.
source:
1 | fn taint {
2 |   let dirty = get_user_input()
3 >   sink(prefix, marker, dirty)
4 |   sink(prefix, one, two, marker, dirty, trailing)
5 |   sink(prefix, marker, clean(prefix, around, dirty, trailing), trailing)

testdata/ellipsis/taint/src/sample.mbt:4:34-4:39
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

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rules testdata/ellipsis/prefilter/rules testdata/ellipsis/prefilter/src
testdata/ellipsis/prefilter/src/sample.mbt:2:3-2:34
rule: ellipsis-prefilter
description:
  Keep literals adjacent to an ellipsis as prefilter anchors.
source:
1 | fn prefilter {
2 >   anchored(prefix, value, suffix)
3 |   anchored(other, value, suffix)
4 |   other(prefix, value, suffix)
```

## Validation errors

Ellipses must occupy a complete unnamed ordered-list item.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --pattern '$$$items' testdata/ellipsis/sample.mbt
$$$items: patterns[0].shape uses ellipsis metavar $$$items outside a complete ordered AST list item
[1]
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --pattern 'wrap($$$items + 1)' testdata/ellipsis/sample.mbt
wrap($$$items + 1): patterns[0].shape uses ellipsis metavar $$$items outside a complete ordered AST list item
[1]
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --pattern 'sink(label=$$$items)' testdata/ellipsis/sample.mbt
sink(label=$$$items): patterns[0].shape uses ellipsis metavar $$$items outside a complete ordered AST list item
[1]
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --pattern 'if condition { $$$items }' testdata/ellipsis/sample.mbt
if condition { $$$items }: patterns[0].shape uses ellipsis metavar $$$items outside a complete ordered AST list item
[1]
```

Malformed spellings and unsupported kinds are rejected.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --pattern 'inspect($$$)' testdata/ellipsis/sample.mbt
inspect($$$): patterns[0].shape has invalid metavar syntax $$; use explicit typed syntax like $(value:exp)
[1]
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --pattern 'inspect($$$(items))' testdata/ellipsis/sample.mbt
inspect($$$(items)): patterns[0].shape has invalid metavar syntax $$$(items); use explicit typed syntax like $(value:exp)
[1]
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --pattern 'inspect($$$(items:unknown))' testdata/ellipsis/sample.mbt
inspect($$$(items:unknown)): patterns[0].shape contains unsupported ellipsis metavar kind unknown
[1]
```

Typed ellipses must be compatible with their list slot.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --pattern 'sink($$$(items:type))' testdata/ellipsis/sample.mbt
sink($$$(items:type)): patterns[0].shape uses ellipsis kind type in an incompatible ordered-list item position
[1]
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --pattern 'fn($$$(items:exp)) { body }' testdata/ellipsis/sample.mbt
fn($$$(items:exp)) { body }: patterns[0].shape uses ellipsis kind exp in an incompatible ordered-list item position
[1]
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --pattern 'match input { [$$$(items:exp)] => body }' testdata/ellipsis/sample.mbt
match input { [$$$(items:exp)] => body }: patterns[0].shape uses ellipsis kind exp in an incompatible ordered-list item position
[1]
```

Names cannot mix capture forms, kinds, reserved names, or guards.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --pattern 'pair($items, [$$$items])' testdata/ellipsis/sample.mbt
pair($items, [$$$items]): patterns[0].shape cannot use items as both an ellipsis metavar and a single-node metavar
[1]
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --pattern 'pair([$$$(items:exp)], [$$$(items:id)])' testdata/ellipsis/sample.mbt
pair([$$$(items:exp)], [$$$(items:id)]): patterns[0].shape declares ellipsis metavar items as multiple metavar kinds
[1]
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --pattern 'inspect($$$__TARGET__)' testdata/ellipsis/sample.mbt
inspect($$$__TARGET__): patterns[0] cannot declare metavar __TARGET__ because it is reserved for inside-expr target traversal
[1]
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --pattern 'inspect($$$__SOURCE__)' testdata/ellipsis/sample.mbt
inspect($$$__SOURCE__): patterns[0] cannot declare metavar __SOURCE__ because it is reserved for taint source targets
[1]
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --pattern 'inspect($$$args)' --guard '{$args: ".+"}' testdata/ellipsis/sample.mbt
inspect($$$args): patterns[0].guard.$args cannot reference ellipsis metavar args
[1]
```

Inherited inside-context captures must remain ellipses with the same kind.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rule testdata/ellipsis/invalid/inside-kind.yaml testdata/ellipsis/sample.mbt
testdata/ellipsis/invalid/inside-kind.yaml: patterns[0] cannot use inherited inside-expr ellipsis metavar items with a different kind
[1]
```

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rule testdata/ellipsis/invalid/inside-single.yaml testdata/ellipsis/sample.mbt
testdata/ellipsis/invalid/inside-single.yaml: patterns[0] cannot use inherited inside-expr ellipsis metavar items as exp
[1]
```
